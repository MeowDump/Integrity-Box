const MODDIR = `/data/adb/modules/playintegrityfix/webroot/common_scripts`;
const PROP = `/data/adb/modules/playintegrityfix/module.prop`;
const BOXBRAIN = `/data/adb/Box-Brain`;

const messageMap = {
  "user": { start: "Blacklist Unnecessary Apps", type: "info" },
  "pixel": { start: "Spoof your device to app", type: "info" },
  "piffork": { start: "All changes will be applied immediately", type: "info" },
  "propspoofer": { start: "These will be applied till reboot", type: "info" },
  "flags": { start: "These require Reboot / Action", type: "info" },
  "profile": { start: "Good Luck old friend 🌚", type: "info" },
  "ctrl": { start: "For those using ROM inbuilt spoofing", type: "info" },
  "support": { start: "Become a Supporter", type: "info" },
  "report": { start: "What's wrong buddy?", type: "info" },
  "assistant": { start: "Let me guide you to the right path", type: "info" },
  "status": { start: "Informs you about keybox & fingerprint validity", type: "info" },
  "repair": { success: "These don't require a reboot", type: "info" },
  "spoofing": { start: "These are for custom ROM users", type: "info" },
  "pilot": { start: "Updates keybox & fp automatically whether a new key is available", type: "info" },
  "downloader": { start: "Some useful stuff you may need", type: "info" },
  "hide": { start: "This will hide basic sus paths", type: "info" },
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
  const colors = { error:"#f44336", success:"#4caf50", info:"#1565c0", warn:"#ff8f00" };
  const bg = colors[type] || "#0099FF";
  Object.assign(n.style, {
    position:"fixed",top:"-70px",left:"50%",transform:"translateX(-50%)",
    background:bg,color:"#fff",padding:"0.8rem 1.2rem",borderRadius:"8px",
    boxShadow:"0 6px 18px rgba(0,0,0,0.35)",fontWeight:"600",zIndex:"99999",
    transition:"top 0.36s,opacity 0.36s",opacity:"0"
  });
  document.body.appendChild(n);
  requestAnimationFrame(()=>{ n.style.top="20px"; n.style.opacity="1"; });
  setTimeout(()=>{ n.style.top="-70px"; n.style.opacity="0"; setTimeout(()=>n.remove(),420); },2500);
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
    position: "fixed",
    top: "0",
    left: "0",
    width: "100vw",
    height: "100vh",
    border: "none",
    zIndex: 9998,
    background: "black"
  });

  document.body.appendChild(iframe);

  const isRight = config.gestureRight;
  const edgeWidth = "30px";
  
  const edge = document.createElement("div");
  Object.assign(edge.style, {
    position: "fixed",
    top: "0",
    [isRight ? "right" : "left"]: "0",
    width: edgeWidth,
    height: "100vh",
    zIndex: "99999999",
    background: "transparent",
    pointerEvents: "auto",
    touchAction: "none"
  });

  document.body.appendChild(edge);

  let backBtn = null;
  if (config.backButton) {
    backBtn = document.createElement("div");
    backBtn.innerHTML = "←";
    Object.assign(backBtn.style, {
      position: "fixed",
      top: "20px",
      [isRight ? "left" : "right"]: "20px",
      width: "44px",
      height: "44px",
      borderRadius: "50%",
      background: "rgba(30,30,30,0.8)",
      backdropFilter: "blur(10px)",
      color: "#fff",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: "24px",
      fontWeight: "bold",
      zIndex: "99999999",
      cursor: "pointer",
      pointerEvents: "auto",
      border: "1px solid rgba(255,255,255,0.1)",
      boxShadow: "0 4px 12px rgba(0,0,0,0.4)",
      transition: "transform 0.2s ease, background 0.2s ease"
    });
    
    backBtn.addEventListener("click", () => {
      closeIframe();
    });
    
    backBtn.addEventListener("touchstart", () => {
      backBtn.style.transform = "scale(0.95)";
      backBtn.style.background = "rgba(50,50,50,0.9)";
    });
    
    backBtn.addEventListener("touchend", () => {
      backBtn.style.transform = "scale(1)";
      backBtn.style.background = "rgba(30,30,30,0.8)";
    });
    
    document.body.appendChild(backBtn);
  }

  let startX = 0;
  let startTime = 0;

  const onStart = (e) => {
    const t = e.touches?.[0] || e;
    startX = t.clientX;
    startTime = Date.now();
  };

  const onEnd = (e) => {
    const t = e.changedTouches?.[0] || e;
    const diff = isRight ? startX - t.clientX : t.clientX - startX;
    const dt = Date.now() - startTime;
    const swipe = diff > 40 && dt < 300;

    if (swipe || Math.abs(diff) < 10) {
      closeIframe();
    }
  };

  const closeIframe = () => {
    iframe.remove();
    edge.remove();
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
    if (text.includes('🟢🟢🟢')) return { status: 'STRONG', label: 'Strong' };
    if (text.includes('🟢🟢🔴')) return { status: 'DEVICE', label: 'Device' };
    if (text.includes('🔴🔴🔴')) return { status: 'BANNED', label: 'Banned' };
    return { status: 'UNKNOWN', label: 'Unknown' };
  } catch (e) {
    return { status: 'OFFLINE', label: 'Offline' };
  }
}

async function updateDashboard() {
  const statusItems = {
    "status-selinux": "getenforce || echo Unknown",
    "status-target": "[ -f /data/adb/tricky_store/target.txt ] && grep -cve '^$' /data/adb/tricky_store/target.txt || echo 0",
    "status-pixel": "[ -f /data/adb/modules/playintegrityfix/custom.pif.prop ] && awk -F= '/^MODEL=/{print $2}' /data/adb/modules/playintegrityfix/custom.pif.prop || echo None",
    "status-patch": "getprop ro.build.version.security_patch || echo Unknown",
    "status-integrity": "__FETCH_KEYBOX__",
    "status-profile": `if [ -f ${BOXBRAIN}/advanced ]; then echo 'Supreme'; elif [ -f ${BOXBRAIN}/pixelify ]; then echo 'Pixelify'; elif [ -f ${BOXBRAIN}/legacy ]; then echo 'Legacy'; elif [ -f ${BOXBRAIN}/wipe ]; then echo 'Meta'; else echo 'None'; fi`,

    "status-LineageProp": `
      if [ -f ${BOXBRAIN}/safemode ]; then
        echo OTA
      elif getprop | grep -iq 'lineage'; then
        echo FOUND
      else
        echo NONE
      fi
    `
  };
  
  const expiryEl = document.getElementById("status-expiry");
  if (expiryEl) {
    try {
      const file = "/data/adb/modules/playintegrityfix/custom.pif.prop";
      const exp = await readExpiry(file);

      if (!exp) {
        expiryEl.textContent = "Unknown";
        expiryEl.className = "chip disabled";
      } else {
        const expDate = new Date(exp.trim().replace(/[^0-9-]/g, "") + "T00:00:00");
        if (isNaN(expDate.getTime())) {
          expiryEl.textContent = "Unknown";
          expiryEl.className = "chip disabled";
        } else {
          const now = new Date();
          const diff = Math.max(0, Math.floor((expDate - now) / 86400000));

          if (diff < 3) {
            expiryEl.className = "chip disabled";
          } else if (diff < 7) {
            expiryEl.className = "chip aqua";
          } else {
            expiryEl.className = "chip enabled";
          }
          expiryEl.textContent = `${diff} days`;
        }
      }
    } catch {
      expiryEl.textContent = "Unknown";
      expiryEl.className = "chip disabled";
    }
  }

  for (const [id, cmd] of Object.entries(statusItems)) {
    const el = document.getElementById(id);
    if (!el) continue;

    if (id === "status-integrity") {
      try {
        const result = await fetchKeyboxStatus();
        el.textContent = result.label;
        if (result.status === 'STRONG') {
          el.className = "chip play";
        } else if (result.status === 'DEVICE') {
          el.className = "chip play";
        } else if (result.status === 'BANNED') {
          el.className = "chip disabled";
        } else {
          el.className = "chip disabled";
        }
      } catch {
        el.textContent = "Offline";
        el.className = "chip disabled";
      }
      continue;
    }
  try {
    let out = (await runShell(cmd)).trim();
    if (!out) out = "Unknown";

    switch (id) {

        case "status-profile":
          el.textContent = out;
          el.className = "chip play";
          break;

        case "status-selinux":
          el.textContent = out;
          el.className = `chip ${
            out === "Enforcing" ? "play" : out === "Permissive" ? "disabled" : "aqua"
          }`;
          break;

        case "status-target":
          const count = parseInt(out) || 0;
          el.textContent = `${out} apps`;
          el.className = `chip ${count === 0 || count > 50 ? "disabled" : "enabled"}`;
          break;
          
        case "status-pixel":
        case "status-patch":
          el.textContent = out;
          el.className = "chip enabled";
          break;

        case "status-LineageProp":
          if (out === "OTA") {
            el.textContent = "OTA";
          } else if (out === "FOUND") {
            el.textContent = "90% Spoofed";
          } else {
            el.textContent = "Spoofed";
          }
          el.className = "chip play";
          break;

        default:
          el.textContent = out;
          el.className = `chip ${out === "Unknown" ? "disabled" : "aqua"}`;
      }
    } catch {
      el.textContent = "Unknown";
      el.className = "chip disabled";
    }
  }
}

function attachButtonListeners() {
  const btns = Array.from(document.querySelectorAll(".btn"));
  
  btns.forEach(btn => {
    if (btn._attached) return;
    btn._attached = true;
    
    btn.addEventListener("click", async () => {
      const script = btn.dataset.script;
      const type = btn.dataset.type;

      btn.classList.add("loading");

      try {
        if (["hash","user","flags","repair","profile","pixel","hide",
             "support","report","assistant","pilot","spoofing","ctrl","piffork","propspoofer","downloader"].includes(type)) {

          const pathMap = {
            ctrl:"./Control/index.html",
            hash:"./BootHash/index.html",
            flags:"./Flags/index.html",
            piffork:"./PlayIntegrityFork/index.html",
            propspoofer:"./PropSpoofer/index.html",
            support:"./Support/index.html",
            report:"./Report/index.html",
            user:"./TrickyStore/index.html",
            pixel:"./Pixel/index.html",
            hide:"./HideMyFiles/index.html",
            profile:"./Profile/index.html",
            assistant:"./Assistant/index.html",
            repair:"./RepairMode/index.html",
            pilot:"./Pilot/index.html",
            spoofing:"./Spoofing/index.html",
            downloader:"./Downloader/index.html"
          };

          const toastKey = (type || script || "").trim().replace(/\.sh$/, "");
          const msg = messageMap[toastKey];

          if (msg?.start) {
            popup(msg.start, msg.type);
          } else {
            popup("Opening…", "info");
          }

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
        popup(`Error: ${e.message}`, "error");
      } finally {
        btn.classList.remove("loading");
        setTimeout(updateDashboard, 500);
      }
    });
  });
}

document.addEventListener("DOMContentLoaded", () => {
  enableFullScreen();
  attachButtonListeners();
  updateDashboard();
  if (document.fonts && document.fonts.check("16px 'Material Symbols Outlined'")) {
    document.documentElement.classList.add("fonts-loaded");
  } else if (document.fonts) {
    document.fonts.load("16px 'Material Symbols Outlined'").then(() => {
      if (document.fonts.check("16px 'Material Symbols Outlined'"))
        document.documentElement.classList.add("fonts-loaded");
    }).catch(() => {});
  }
});
