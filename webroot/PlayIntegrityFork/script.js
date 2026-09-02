const PROP_CANDIDATES = [
  "/data/adb/modules/playintegrityfix/custom.pif.prop",
  "/data/adb/custom.pif.prop"
];

const KEYS = ["spoofBuild", "spoofProps", "spoofProvider", "spoofSignature", "spoofVendingFinger", "spoofVendingSdk", "spoofPixel"];
const ZYGISK_PATH = "/data/adb/modules/playintegrityfix/zygisk";

let propFile = null;
let zygiskExists = false;

function showToast(msg) {
  document.getElementById("toastText").textContent = msg;
  document.getElementById("toast").classList.add("show");
  clearTimeout(window._toastTimer);
  window._toastTimer = setTimeout(() => document.getElementById("toast").classList.remove("show"), 1400);
}

function showWarning(text) {
  const line = document.getElementById("warningLine");
  if (!text) {
    line.classList.remove("show");
    return;
  }
  document.getElementById("warningText").textContent = text;
  line.classList.add("show");
}

function setDisabled(key, disabled) {
  const input = document.getElementById(key);
  const row = document.getElementById("row-" + key);
  if (input) input.disabled = disabled;
  if (row) {
    row.style.opacity = disabled ? "0.4" : "1";
    row.style.pointerEvents = disabled ? "none" : "auto";
  }
}

function updateVisuals(key, isActive) {
  document.getElementById("row-" + key).classList.toggle("active", isActive);
  document.getElementById(key).checked = isActive;
}

async function toggle(key) {
  if (!propFile || !zygiskExists) {
    showWarning("zygiskless mode has been enabled");
    return;
  }
  const input = document.getElementById(key);
  if (input.disabled) return;

  const newVal = input.checked ? "0" : "1";
  input.checked = !input.checked;

  if (key === "spoofVendingSdk" && newVal === "1") {
    await writeKey(propFile, key, newVal);
    const others = KEYS.filter(k => k !== key && k !== "spoofBuild" && k !== "spoofProps");
    for (const k of others) {
      await writeKey(propFile, k, "0");
      updateVisuals(k, false);
    }
    showToast("A10 mode enabled, others disabled");
  } else {
    await writeKey(propFile, key, newVal);
    showToast(newVal === "1" ? "Enabled" : "Disabled");
  }

  await restartGMS();
  updateVisuals(key, newVal === "1");
}

async function sh(cmd) {
  try {
    if (typeof ksu?.exec === "function") {
      const maybe = ksu.exec(cmd);
      if (maybe && typeof maybe.then === "function") return (await maybe).toString().trim();
      if (typeof maybe === "string") return maybe.toString().trim();
      return await new Promise((resolve) => {
        const cb = `cb_${Date.now()}_${Math.random() * 10000 | 0}`;
        window[cb] = (code, stdout, stderr) => {
          delete window[cb];
          resolve(code === 0 ? (stdout || "").toString().trim() : ((stdout || "") + (stderr || "")).toString().trim());
        };
        ksu.exec(cmd, "{}", cb);
      });
    }
    return "";
  } catch (e) { return ""; }
}

async function findPropFile() {
  for (const p of PROP_CANDIDATES) {
    const out = await sh(`sh -c 'if [ -f "${p}" ]; then echo found; else echo missing; fi'`);
    if (out.trim() === "found") return p;
  }
  return null;
}

async function checkZygisk() {
  const out = await sh(`sh -c 'if [ -d "${ZYGISK_PATH}" ]; then echo exists; else echo missing; fi'`);
  return out.trim() === "exists";
}

async function hasAdvancedSettings(file) {
  if (!file) return false;
  const out = await sh(`sh -c 'grep -q "^spoofProvider=" "${file}" && echo 1 || echo 0'`);
  return out.trim() === "1";
}

async function readKey(file, key) {
  if (!file) return "";
  const cmd = `sh -c 'grep -m1 "^${key}=" "${file}" | cut -d"=" -f2- || echo ""'`;
  const out = await sh(cmd);
  return (out ?? "").toString().trim();
}

async function writeKey(file, key, value) {
  if (!file) return false;
  const cmd = `sh -c 'if grep -q "^${key}=" "${file}"; then sed -i "s/^${key}=.*/${key}=${value}/" "${file}"; else printf "\\n${key}=${value}\\n" >> "${file}"; fi'`;
  await sh(cmd);
  return true;
}

async function restartGMS() {
  await sh(`sh -c 'am force-stop com.google.android.gms.unstable 2>/dev/null || true; am force-stop com.android.vending 2>/dev/null || true'`);
}

async function restartServices() {
  await restartGMS();
  showToast("Services restarted");
}

async function init() {
  propFile = await findPropFile();
  zygiskExists = await checkZygisk();

  if (!zygiskExists) {
    showWarning("zygiskless mode has been enabled");
    KEYS.forEach(k => setDisabled(k, true));
    return;
  }

  if (!propFile) {
    showWarning("Change IntegrityBox profile first");
    KEYS.forEach(k => setDisabled(k, true));
    return;
  }

  const adv = await hasAdvancedSettings(propFile);
  if (!adv) {
    showWarning("Change your current profile brother");
    KEYS.forEach(k => setDisabled(k, true));
    return;
  }

  showWarning("");

  for (const key of KEYS) {
    const val = await readKey(propFile, key);
    updateVisuals(key, val === "1");
  }

  KEYS.forEach(key => {
    const input = document.getElementById(key);
    input.addEventListener("change", () => toggle(key));
  });
}

document.addEventListener("DOMContentLoaded", () => {
  init().catch(() => showWarning("Check KSU availability"));
});
