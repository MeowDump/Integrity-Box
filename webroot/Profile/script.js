const PXL_FILE = "/data/adb/Box-Brain/pixelify";
const ADV_FILE = "/data/adb/Box-Brain/advanced";
const LEGACY_FILE = "/data/adb/Box-Brain/legacy";
const WIPE_FILE = "/data/adb/Box-Brain/wipe";
const OSMOSIS = "/data/adb/modules/playintegrityfix/osm0sis.sh";

const COOLDOWN = 30000;
let lastSwitch = 0;

const profiles = [
  { name: "Pixelify", desc: "Pixel-style spoofing for Google Tensor devices", file: PXL_FILE },
  { name: "Supreme", desc: "Recommended for A13+ ROMs", file: ADV_FILE },
  { name: "Legacy", desc: "Recommended for A12 and below", file: LEGACY_FILE },
  { name: "Meta", desc: "Experimental feature (luck based)", file: WIPE_FILE }
];

function popup(msg, type = "info") {
  try {
    if (typeof window.toast === "function") { window.toast(String(msg)); return; }
    if (window.kernelsu && typeof window.kernelsu.toast === "function") { window.kernelsu.toast(String(msg)); return; }
    if (typeof ksu === "object" && typeof ksu.toast === "function") { ksu.toast(String(msg)); return; }
  } catch {}

  let t = document.querySelector(".toast");
  if (!t) {
    t = document.createElement("div");
    t.className = "toast";
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove("show"), 2500);
}

function showLoader(show, text = "Applying Profile...") {
  const loader = document.getElementById("loader");
  const loaderText = document.getElementById("loaderText");
  if (text) loaderText.textContent = text;
  loader.classList.toggle("show", show);
}

function sh(cmd) {
  try { return ksu.exec(cmd); } catch { return ""; }
}

async function getActive() {
  for (const p of profiles) {
    const r = sh(`test -f "${p.file}" && echo yes`);
    if (String(r).trim() === "yes") return p.file;
  }
  return null;
}

async function switchProfile(p) {
  if (Date.now() - lastSwitch < COOLDOWN) {
    popup("Please wait before switching again", "warn");
    return;
  }
  lastSwitch = Date.now();

  showLoader(true, `Activating ${p.name}...`);
  popup(`Applying ${p.name} profile...`, "info");

  requestAnimationFrame(() => {
    setTimeout(() => {

      sh(`
        rm -f "${PXL_FILE}" "${ADV_FILE}" "${LEGACY_FILE}" "${WIPE_FILE}" &&
        touch "${p.file}" &&
        chmod 0644 "${p.file}" &&
        sh "${OSMOSIS}" &&
        pkill -f com.google.android.gms &&
        pkill -f com.android.vending
      `);

      showLoader(false);
      popup(`${p.name} profile activated`, "success");
      render();

    }, 0);
  });
}

async function render() {
  const active = await getActive();
  const root = document.getElementById("profiles");
  root.innerHTML = "";

  profiles.forEach(p => {
    const d = document.createElement("div");
    const isActive = active === p.file;
    d.className = "item" + (isActive ? " active" : "");
    d.innerHTML = `
      <span class="check">✓</span>
      <span>${p.name}</span>
      <span class="muted small" style="font-weight:400">${p.desc}</span>
    `;
    d.onclick = () => switchProfile(p);
    root.appendChild(d);
  });
}

function clearData() {
  showLoader(true, "Clearing app data...");
  popup("Clearing Play Store & GMS data...", "info");

  requestAnimationFrame(() => {
    setTimeout(() => {
      try {
        sh(`pm clear com.android.vending && pm clear com.google.android.gms`);
        popup("Data cleared successfully", "success");
      } catch {
        popup("Command failed", "error");
      }
      showLoader(false);
    }, 0);
  });
}

function openAPKMirror() {
  sh(`nohup am start -a android.intent.action.VIEW -d "https://www.apkmirror.com/apk/google-inc/google-play-store/google-play-store-40-0-13-release/google-play-store-40-0-13-23-0-pr-612537281-android-apk-download/download/?key=11b745de637f14dc60ab90c02234ed466e71cdf3&forcebaseapk=true" > /dev/null 2>&1 &`);
  popup("Opening APK Mirror...", "info");
}

function showProfileInfo() {
  document.getElementById("infoModal").classList.add("show");
}

function hideProfileInfo(e) {
  if (e && e.target !== e.currentTarget && !(e.target.closest && e.target.closest(".btn"))) return;
  document.getElementById("infoModal").classList.remove("show");
}

document.addEventListener("DOMContentLoaded", render);
