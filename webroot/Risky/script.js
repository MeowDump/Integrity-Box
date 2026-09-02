const runBtn = document.getElementById("run-btn");
const clearBtn = document.getElementById("clear-log");
const outputLog = document.getElementById("output-log");
const progress = document.getElementById("progress");
const progressDetail = document.getElementById("progress-detail");
const stats = document.getElementById("stats");
const totalCountEl = document.getElementById("total-count");
const riskyCountEl = document.getElementById("risky-count");
const spoofedCountEl = document.getElementById("spoofed-count");

let scannedApps = 0;
let detectedRisky = 0;
let detectedSpoofed = 0;

function showSnackbar(msg, type="info") {
  try {
    if (typeof window.toast === "function") { window.toast(String(msg)); return; }
    if (window.kernelsu && typeof window.kernelsu.toast === "function") { window.kernelsu.toast(String(msg)); return; }
    if (typeof ksu === "object" && typeof ksu.toast === "function") { ksu.toast(String(msg)); return; }
  } catch {}

  const n = document.createElement("div");
  n.className = "toast";
  n.textContent = msg;
  document.body.appendChild(n);
  requestAnimationFrame(()=>n.classList.add("show"));
  setTimeout(()=>{ n.classList.remove("show"); setTimeout(()=>n.remove(),300); },2500);
}

function updateStats() {
  totalCountEl.textContent = scannedApps;
  riskyCountEl.textContent = detectedRisky;
  spoofedCountEl.textContent = detectedSpoofed;
}

function addStatusCard(name, pkg, status) {
  const card = document.createElement("div");
  card.className = "status-card";

  const statusClass = status.toLowerCase();

  const iconUrl = `ksu://icon/${pkg}`;

  card.innerHTML = `
    <img class="app-icon" src="${iconUrl}" alt="${escapeHtml(name)}" onerror="this.style.display='none';">
    <div class="status-content">
      <div class="status-name">${escapeHtml(name)}</div>
      <div class="status-pkg">${escapeHtml(pkg)}</div>
    </div>
    <div class="chip ${statusClass}">${status}</div>
  `;

  outputLog.appendChild(card);
  outputLog.scrollTop = outputLog.scrollHeight;

  if (status === 'RISKY') detectedRisky++;
  if (status === 'SPOOFED') detectedSpoofed++;

  updateStats();
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

function setEmptyState() {
  outputLog.innerHTML = `
    <div class="log-empty">
      <div>Ready to scan<br>Tap "Run Scan" to begin</div>
    </div>
  `;
  stats.style.display = 'none';
  scannedApps = 0;
  detectedRisky = 0;
  detectedSpoofed = 0;
}

async function safeRun(cmd, timeout = 1000) {
  if (!window.parent.runShellFromIframe) return "";
  return Promise.race([
    window.parent.runShellFromIframe(cmd).catch(() => ""),
    new Promise(res => setTimeout(() => res(""), timeout))
  ]);
}

async function detectApps() {
  outputLog.innerHTML = '';
  stats.style.display = 'flex';
  progress.style.display = 'flex';
  runBtn.disabled = true;
  runBtn.classList.add('loading');

  scannedApps = 0;
  detectedRisky = 0;
  detectedSpoofed = 0;
  updateStats();

  showSnackbar("Starting security scan...", 'security');

  const riskyApps = [
    "com.rifsxd.ksunext:KernelSU_Next",
    "me.weishu.kernelsu:KernelSU",
    "com.google.android.hmal:Hide_My_Applist",
    "com.reveny.vbmetafix.service:VBmeta_Fixer",
    "me.twrp.twrpapp:TWRP",
    "com.termux:Termux",
    "bin.mt.plus:MT_Manager",
    "org.swiftapps.swiftbackup:Swift_Backup",
    "ru.mike.updatelocker:Update_Locker",
    "com.coderstory.toolkit:Core_Patch",
    "ru.maximoff.apktool:APK_ToolM",
    "io.github.muntashirakon.AppManager.debug:App_Manager",
    "io.github.a13e300.ksuwebui:KSU_WebUI",
    "com.slash.batterychargelimit:Battery_Charging_Limit",
    "io.github.vvb2060.keyattestation:Key_Attestation",
    "io.github.qwq233.keyattestation:Key_Attestation",
    "io.github.muntashirakon.AppManager:App_Manager",
    "io.github.vvb2060.mahoshojo:Momo",
    "com.reveny.nativecheck:Native_Detector",
    "icu.nullptr.nativetest:NativeTest",
    "io.github.huskydg.memorydetector:Memory_Detector",
    "org.akanework.checker:Checker",
    "icu.nullptr.applistdetector:Applist_Detector",
    "io.github.rabehx.securify:Securify",
    "krypton.tbsafetychecker:TB_Checker",
    "me.garfieldhan.holmes:Holmes",
    "com.byxiaorun.detector:Ruru",
    "com.kimchangyoun.rootbeerFresh.sample:Root_Beer",
    "com.dergoogler.mmrl.wx:WebUI_X",
    "wu.keyChain.test:TS_Detector",
    "com.dergoogler.mmrl:MMRL"
  ];

  try {
    let installedPackages = (await safeRun("pm list packages")).split("\n").map(l => l.replace("package:", "").trim()).filter(p => p);
    let userApps = (await safeRun("pm list packages -3")).split("\n").map(l => l.replace("package:", "").trim()).filter(p => p);

    const totalToScan = installedPackages.length + userApps.length;

    progressDetail.textContent = `Found ${installedPackages.length} installed packages, ${userApps.length} user apps`;

    for (const entry of riskyApps) {
      const [pkg, name] = entry.split(":");
      if (installedPackages.includes(pkg)) {
        addStatusCard(name, pkg, "RISKY");
      }
      scannedApps++;
      if (scannedApps % 10 === 0) {
        progressDetail.textContent = `Checking risky apps... (${scannedApps}/${totalToScan})`;
        updateStats();
      }
    }

    for (const pkg of userApps) {
      try {
        const version = (await safeRun(`dumpsys package ${pkg} | grep -m1 versionName`)).trim();
        if (version.toLowerCase().includes("spoofed")) {
          const displayName = pkg.split('.').pop().replace(/_/g, ' ').replace(/([A-Z])/g, ' $1').trim();
          addStatusCard(displayName || pkg, pkg, "SPOOFED");
        }
      } catch {}

      scannedApps++;
      if (scannedApps % 5 === 0) {
        progressDetail.textContent = `Analyzing user apps... (${scannedApps}/${totalToScan})`;
        updateStats();
      }

      await new Promise(r => setTimeout(r, 30));
    }

    updateStats();

    if (outputLog.children.length === 0) {
      addStatusCard("System Secure", "No suspicious applications detected", "SAFE");
    }

    showSnackbar(`Scan completed: ${scannedApps} apps checked`, 'check_circle');
  } catch (error) {
    showSnackbar("Scan failed: " + error.message, 'error');
  } finally {
    progress.style.display = 'none';
    runBtn.disabled = false;
    runBtn.classList.remove('loading');
  }
}

runBtn.addEventListener("click", detectApps);
clearBtn.addEventListener("click", () => {
  setEmptyState();
  showSnackbar("Log cleared", 'delete');
});
