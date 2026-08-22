const MODDIR = `/data/adb/modules/playintegrityfix/webroot/common_scripts`;
const PROP = `/data/adb/modules/playintegrityfix/module.prop`;
const BOXBRAIN = `/data/adb/Box-Brain`;

const modalBackdrop = document.getElementById("modal-backdrop");
const modalTitle = document.getElementById("modal-title");
const modalOutput = document.getElementById("modal-output");
const modalClose = document.getElementById("modal-close");

const messageMap = {
  "kill": { success: "DroidGuard has been restarted", type: "info" },
  "user": { start: "Blacklist Unnecessary Apps", type: "info" },
  "stop": { success: "Switched to Blacklist Mode", type: "info" },
  "start": { success: "Switched to Whitelist Mode", type: "info" },
  "xml": { start: "Scanning xml files..", type: "info" },
  "pixel": { start: "Spoof your device to app", type: "info" },
  "patch": { start: "Opening configuration..", type: "info" },
  "aosp": { success: "Switched to AOSP Keybox", type: "info" },
  "resetprop.sh": { success: "Done, Reopen detector to check", type: "info" },
  "selinux": { success: "Spoofed to Enforcing", type: "info" },
  "piffork": { start: "All changes will be applied immediately", type: "info" },
  "propspoofer": { start: "These will be applied till reboot", type: "info" },
  "nogms": { success: "Reboot to apply changes", type: "info" },
  "yesgms": { start: "Reboot to apply changes", type: "info" },
  "key.sh": { success: "Keybox has been updated", type: "info" },
  "flags": { start: "These requires Reboot / Action", type: "info" },
  "profile": { start: "Good Luck old friend", type: "info" },
  "ctrl": { start: "For those using ROM inbuilt spoofing", type: "info" },
  "force_override.sh": { start: "Done", type: "info" },
  "pif": { start: "You can update fingerprint without internet", type: "info" },
  "vending": { start: "This will clear data of Play Services & Store", type: "info" },
  "zygisknext": { start: "Whatever you say cutie", type: "info" },
  "cache": { start: "This will delete temporary unnecessary files", type: "info" },
  "hide": { start: "This will hide basic sus paths", type: "info" },
  "scanner": { start: " Click on Run Scan", success: "Detection Complete", type: "info" },
  "support": { start: "Become a Supporter", type: "info" },
  "report": { start: "What's wrong buddy?", type: "info" },
  "assistant": { start: "Let me guide you to the right path", type: "info" },
  "status": { start: "Informs you about keybox & fingerprint validity", type: "info" },
  "hma.sh": { success: "Done", type: "info" },
  "ulock": { success: "Done", type: "info" },
  "faq": { start: "Coming Soon", type: "info" },
  "nuke": { start: "Coming Soon", type: "info" },
  "repair": { success: "These doesn't require reboot", type: "info" },
  "spoofing": { start: "These are for custom ROM users", type: "info" },
  "pilot": { start: "Updates keybox & fp automatically whether a new key is available", type: "info" },
  "downloader": { start: "Some useful stuff you may need", type: "info" },
  "hash": { start: "Paste your boot hash buddy", success: "Boot hash operation complete", type: "success" }
};

function popup(msg, type="info") {
  try {
    if (typeof window.toast === "function") { window.toast(String(msg)); return; }
    if (window.kernelsu && typeof window.kernelsu.toast === "function") { window.kernelsu.toast(String(msg)); return; }
    if (typeof ksu === "object" && typeof ksu.toast === "function") { ksu.toast(String(msg)); return; }
  } catch {}

  const n = document.createElement("div");
  n.className = "webui-popup";
  n.textContent = msg;
  const colors = { error: "#ff4757", success: "#00ff88", info: "#4da3ff", warn: "#ffaa4d" };
  const bg = colors[type] || "#4da3ff";
  const textColor = type === "success" ? "#0a1f0f" : "#fff";
  Object.assign(n.style, { background: bg + "dd", color: textColor });
  document.body.appendChild(n);
  requestAnimationFrame(() => { n.style.top = "24px"; n.style.opacity = "1"; });
  setTimeout(() => {
    n.style.top = "-100px"; n.style.opacity = "0";
    setTimeout(() => n.remove(), 400);
  }, 2800);
}

async function runShell(cmd) {
  if (!cmd || typeof ksu?.exec !== "function") throw new Error("KSU API unavailable");
  return new Promise((res, rej) => {
    const cb = `cb_${Date.now()}_${Math.random()*10000|0}`;
    window[cb] = (code, stdout, stderr) => {
      delete window[cb];
      code === 0 ? res((stdout||"").replace(/\r/g,"")) : rej(new Error(stderr||stdout||"Shell failed"));
    };
    ksu.exec(cmd, "{}", cb);
  });
}

function enableFullScreen() {
  try {
    if (window.kernelsu?.fullScreen) return window.kernelsu.fullScreen(true);
    if (window.fullScreen) return window.fullScreen(true);
    if (ksu?.fullScreen) return ksu.fullScreen(true);
    document.documentElement.requestFullscreen?.().catch(()=>{});
  } catch {}
}

async function checkGestureConfig() {
  try {
    const rightGesture = await runShell(`[ -f ${BOXBRAIN}/iframe_gesture_right ] && echo "1" || echo "0"`);
    const backButton = await runShell(`[ -f ${BOXBRAIN}/iframe_back_button ] && echo "1" || echo "0"`);
    return {
      gestureRight: rightGesture.trim() === "1",
      backButton: backButton.trim() === "1"
    };
  } catch {
    return { gestureRight: false, backButton: false };
  }
}

function openIframe(url) {
  if (document.getElementById("active-iframe")) return;
  const config = { gestureRight: false, backButton: false };
  checkGestureConfig().then(cfg => {
    Object.assign(config, cfg);
    createIframeUI(url, config);
  }).catch(() => {
    createIframeUI(url, config);
  });
}

function createIframeUI(url, config) {
  const iframe = document.createElement("iframe");
  iframe.src = url;
  iframe.id = "active-iframe";
  Object.assign(iframe.style, {
    position: "fixed", top: "0", left: "0",
    width: "100vw", height: "100vh",
    border: "none", zIndex: 9998, background: "#060913"
  });
  document.body.appendChild(iframe);

  const isRight = config.gestureRight;
  const edge = document.createElement("div");
  Object.assign(edge.style, {
    position: "fixed", top: "0",
    [isRight ? "right" : "left"]: "0",
    width: "36px", height: "100vh",
    zIndex: "99999999", background: "transparent",
    pointerEvents: "auto", touchAction: "none"
  });
  document.body.appendChild(edge);

  let backBtn = null;
  if (config.backButton) {
    backBtn = document.createElement("div");
    backBtn.className = "iframe-back-btn";
    backBtn.innerHTML = "&#8592;";
    backBtn.style[isRight ? "left" : "right"] = "18px";
    backBtn.addEventListener("click", () => closeIframe());
    backBtn.addEventListener("touchstart", () => { backBtn.style.transform = "scale(0.9)"; });
    backBtn.addEventListener("touchend", () => { backBtn.style.transform = "scale(1)"; });
    document.body.appendChild(backBtn);
  }

  let startX = 0, startTime = 0;
  const onStart = (e) => {
    const t = e.touches?.[0] || e;
    startX = t.clientX; startTime = Date.now();
  };
  const onEnd = (e) => {
    const t = e.changedTouches?.[0] || e;
    const diff = isRight ? startX - t.clientX : t.clientX - startX;
    const dt = Date.now() - startTime;
    if ((diff > 40 && dt < 300) || Math.abs(diff) < 10) closeIframe();
  };
  const closeIframe = () => {
    iframe.remove(); edge.remove();
    if (backBtn) backBtn.remove();
  };
  edge.addEventListener("touchstart", onStart, { passive: true });
  edge.addEventListener("touchend", onEnd);
  edge.addEventListener("mousedown", onStart);
  edge.addEventListener("mouseup", onEnd);
}

window.runShellFromIframe = async function (cmd) {
  return await runShell(cmd);
};

async function readExpiry(file){
  return (await runShell(
    `grep -i 'Estimated Expiry' "${file}" 2>/dev/null | head -n1 | cut -d':' -f2-`
  )).trim();
}

async function fetchKeyboxStatus() {
  const url = "https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/keybox/key-status";
  try {
    const response = await fetch(url, { cache: 'no-store' });
    if (!response.ok) throw new Error('HTTP ' + response.status);
    const text = await response.text();
    if (text.includes('\uD83D\uDFE2\uD83D\uDFE2\uD83D\uDFE2')) return { status: 'STRONG', label: 'Strong' };
    if (text.includes('\uD83D\uDFE2\uD83D\uDFE2\uD83D\uDD34')) return { status: 'DEVICE', label: 'Device' };
    if (text.includes('\uD83D\uDD34\uD83D\uDD34\uD83D\uDD34')) return { status: 'BANNED', label: 'Banned' };
    return { status: 'UNKNOWN', label: 'Unknown' };
  } catch (e) {
    return { status: 'OFFLINE', label: 'Offline' };
  }
}

function setStatus(id, text) {
  const valEl = document.getElementById("status-" + id);
  if (valEl) valEl.textContent = text;
}

function setPillClass(id, className) {
  const el = document.getElementById("status-" + id);
  if (!el) return;
  el.className = "status-pill " + className;
}

async function updateDashboard() {
  const expiryEl = document.getElementById("status-expiry");
  if (expiryEl) {
    try {
      const file = "/data/adb/modules/playintegrityfix/custom.pif.prop";
      const exp = await readExpiry(file);
      if (!exp) {
        setStatus("expiry", "Unknown");
        setPillClass("expiry", "blue");
      } else {
        const expDate = new Date(exp.trim().replace(/[^0-9-]/g, "") + "T00:00:00");
        if (isNaN(expDate.getTime())) {
          setStatus("expiry", "Unknown");
          setPillClass("expiry", "blue");
        } else {
          const now = new Date();
          const diff = Math.max(0, Math.floor((expDate - now) / 86400000));
          setStatus("expiry", diff + " days");
          if (diff > 30) setPillClass("expiry", "green");
          else if (diff > 7) setPillClass("expiry", "blue");
          else setPillClass("expiry", "orange");
        }
      }
    } catch {
      setStatus("expiry", "Unknown");
      setPillClass("expiry", "blue");
    }
  }

  const statusItems = {
    "selinux": "getenforce || echo Unknown",
    "target": "[ -f /data/adb/tricky_store/target.txt ] && grep -cve '^$' /data/adb/tricky_store/target.txt || echo 0",
    "pixel": "[ -f /data/adb/modules/playintegrityfix/custom.pif.prop ] && awk -F= '/^MODEL=/{print $2}' /data/adb/modules/playintegrityfix/custom.pif.prop || echo None",
    "patch": "getprop ro.build.version.security_patch || echo Unknown",
    "profile": `if [ -f ${BOXBRAIN}/advanced ]; then echo 'Supreme'; elif [ -f ${BOXBRAIN}/pixelify ]; then echo 'Pixelify'; elif [ -f ${BOXBRAIN}/legacy ]; then echo 'Legacy'; elif [ -f ${BOXBRAIN}/wipe ]; then echo 'Meta'; else echo 'None'; fi`,
    "LineageProp": `
      if [ -f ${BOXBRAIN}/safemode ]; then
        echo OTA
      elif getprop | grep -iq 'lineage'; then
        echo FOUND
      else
        echo NONE
      fi
    `
  };

  const purpleIds = ["integrity", "profile", "LineageProp", "selinux"];
  const blueIds = ["pixel", "expiry", "patch", "target"];

  for (const [id, cmd] of Object.entries(statusItems)) {
    const valEl = document.getElementById("status-" + id);
    if (!valEl) continue;

    try {
      let out = (await runShell(cmd)).trim();
      if (!out) out = "Unknown";
      setStatus(id, out);
      if (purpleIds.includes(id)) setPillClass(id, "purple");
      else if (blueIds.includes(id)) setPillClass(id, "blue");
    } catch {
      setStatus(id, "Unknown");
      if (purpleIds.includes(id)) setPillClass(id, "purple");
      else if (blueIds.includes(id)) setPillClass(id, "blue");
    }
  }

  try {
    const result = await fetchKeyboxStatus();
    setStatus("integrity", result.label);
    if (result.status === 'STRONG') setPillClass("integrity", "green");
    else if (result.status === 'BANNED') setPillClass("integrity", "red");
    else if (result.status === 'DEVICE') setPillClass("integrity", "orange");
    else setPillClass("integrity", "purple");
  } catch {
    setStatus("integrity", "Offline");
    setPillClass("integrity", "purple");
  }
}

function attachButtonListeners() {
  const btns = Array.from(document.querySelectorAll(".list-row:not(.list-row-static)"));
  btns.forEach(btn => {
    if (btn._attached) return;
    btn._attached = true;
    btn.addEventListener("click", async () => {
      const script = btn.dataset.script;
      const type = btn.dataset.type;

      btn.style.pointerEvents = "none";
      btn.style.opacity = "0.5";

      try {
        if (["scanner","hash","user","flags","cache","nuke","piffork","propspoofer","pif","vending","downloader","keymint",
             "support","report","profile","assistant","repair","pilot","faq","spoofing","status","tee","xml","pixel","hide","patch","ctrl"].includes(type)) {

          const pathMap = {
            ctrl: "./Control/index.html",
            hash: "./BootHash/index.html",
            flags: "./Flags/index.html",
            piffork: "./PlayIntegrityFork/index.html",
            propspoofer: "./PropSpoofer/index.html",
            support: "./Support/index.html",
            report: "./Report/index.html",
            user: "./TrickyStore/index.html",
            pixel: "./Pixel/index.html",
            hide: "./HideMyFiles/index.html",
            profile: "./Profile/index.html",
            assistant: "./Assistant/index.html",
            repair: "./RepairMode/index.html",
            pilot: "./Pilot/index.html",
            spoofing: "./Spoofing/index.html",
            downloader: "./Downloader/index.html"
          };

          const toastKey = (type || script || "").trim().replace(/\.sh$/, "");
          const msg = messageMap[toastKey];
          popup(msg?.start || "Opening...", msg?.type || "info");
          return openIframe(pathMap[type]);
        }

        if (script) {
          if (messageMap[script]?.start)
            popup(messageMap[script].start, messageMap[script].type);
          await runShell(`sh ${MODDIR}/${script}`);
          if (messageMap[script]?.success)
            popup(messageMap[script].success, messageMap[script].type);
        }
      } catch (e) {
        popup("Error: " + e.message, "error");
      } finally {
        btn.style.pointerEvents = "";
        btn.style.opacity = "";
        setTimeout(updateDashboard, 500);
      }
    });
  });
}

function initDashboardCollapse() {
  const dashboard = document.getElementById("dashboard");
  const toggle = document.getElementById("collapse-toggle");
  if (!toggle || !dashboard) return;

  toggle.addEventListener("click", () => {
    dashboard.classList.toggle("collapsed");
  });
}

function initTabs() {
  const navItems = document.querySelectorAll(".nav-item");
  const panels = document.querySelectorAll(".tab-panel");
  const tabs = Array.from(navItems).map(n => n.dataset.tab);
  let currentIndex = 0;

  function switchTab(index) {
    if (index < 0 || index >= tabs.length) return;
    const direction = index > currentIndex ? "right" : "left";
    const currentPanel = document.getElementById("tab-" + tabs[currentIndex]);
    const nextPanel = document.getElementById("tab-" + tabs[index]);

    currentPanel.classList.remove("active");
    currentPanel.classList.add(direction === "right" ? "exit-left" : "exit-right");

    nextPanel.classList.remove("exit-left", "exit-right");
    nextPanel.classList.add("active", direction === "right" ? "enter-right" : "enter-left");

    requestAnimationFrame(() => {
      nextPanel.classList.remove("enter-right", "enter-left");
    });

    navItems.forEach(n => n.classList.remove("active"));
    navItems[index].classList.add("active");
    currentIndex = index;
  }

  navItems.forEach((item, idx) => {
    item.addEventListener("click", () => switchTab(idx));
  });

  let touchStartX = 0;
  let touchStartY = 0;
  let touchStartTime = 0;

  const app = document.querySelector(".app");
  app.addEventListener("touchstart", (e) => {
    const t = e.touches[0];
    touchStartX = t.clientX;
    touchStartY = t.clientY;
    touchStartTime = Date.now();
  }, { passive: true });

  app.addEventListener("touchend", (e) => {
    const t = e.changedTouches[0];
    const dx = t.clientX - touchStartX;
    const dy = t.clientY - touchStartY;
    const dt = Date.now() - touchStartTime;

    if (Math.abs(dx) < 50 || Math.abs(dy) > Math.abs(dx) * 1.5 || dt > 350) return;

    if (dx < 0 && currentIndex < tabs.length - 1) {
      switchTab(currentIndex + 1);
    } else if (dx > 0 && currentIndex > 0) {
      switchTab(currentIndex - 1);
    }
  }, { passive: true });
}

function initModal() {
  modalClose.addEventListener("click", () => {
    modalBackdrop.classList.add("hidden");
  });
  modalBackdrop.addEventListener("click", (e) => {
    if (e.target === modalBackdrop) modalBackdrop.classList.add("hidden");
  });
}

function hideIntro() {
  const intro = document.getElementById("intro-overlay");
  if (intro) {
    setTimeout(() => {
      intro.classList.add("hidden");
      setTimeout(() => intro.remove(), 800);
    }, 1200);
  }
}

document.addEventListener("DOMContentLoaded", () => {
  enableFullScreen();
  initDashboardCollapse();
  initTabs();
  attachButtonListeners();
  initModal();
  hideIntro();
  updateDashboard();
});
