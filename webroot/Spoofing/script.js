const BASE_DIR = "/data/adb/Box-Brain";
const FILES = {
  enablegms: `${BASE_DIR}/enablegms`,
  disablegms: `${BASE_DIR}/disablegms`,
  enablevending: `${BASE_DIR}/enablevending`,
  disablevending: `${BASE_DIR}/disablevending`
};

const CONFLICTS = {
  enablegms: ["disablegms"],
  disablegms: ["enablegms"],
  enablevending: ["disablevending"],
  disablevending: ["enablevending"]
};

const COOLDOWN = 1000;
let lastSwitch = 0;

const options = [
  {
    id: "enablegms",
    name: "Enable Device Spoofing",
    desc: "Resume ROM's inbuilt spoofing",
    group: "gms"
  },
  {
    id: "disablegms",
    name: "Disable Device Spoofing",
    desc: "Pause ROM's inbuilt spoofing",
    group: "gms"
  },
  {
    id: "enablevending",
    name: "Enable Play Store Spoofing",
    desc: "Resume ROM's inbuilt vending spoofing",
    group: "vending"
  },
  {
    id: "disablevending",
    name: "Disable Play Store Spoofing",
    desc: "Pause ROM's inbuilt vending spoofing",
    group: "vending"
  }
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

function showLoader(show, text = "Applying changes...") {
  const loader = document.getElementById("loader");
  const loaderText = document.getElementById("loaderText");
  if (text) loaderText.textContent = text;
  loader.classList.toggle("show", show);
}

function sh(cmd) {
  try { return ksu.exec(cmd); } catch { return ""; }
}

async function getActiveFiles() {
  const active = [];
  for (const key in FILES) {
    const exists = sh(`test -f "${FILES[key]}" && echo yes`).trim() === "yes";
    if (exists) active.push(key);
  }
  return active;
}

async function validateFiles() {
  const active = await getActiveFiles();
  if (active.length > 2) {
    showLoader(true, "Resetting configuration...");
    for (const key in FILES) {
      sh(`rm -f "${FILES[key]}"`);
    }
    popup("Too many options selected. All settings cleared.", "error");
    showLoader(false);
    return [];
  }
  return active;
}

function getConflictingOptions(activeFiles, optionId) {
  const conflicts = [];
  const optionGroup = options.find(o => o.id === optionId).group;

  for (const active of activeFiles) {
    const activeOption = options.find(o => o.id === active);
    if (activeOption.group === optionGroup && active !== optionId) {
      conflicts.push(active);
    }
  }

  return conflicts;
}

async function toggleOption(optionId) {
  if (Date.now() - lastSwitch < COOLDOWN) {
    popup("Please wait before switching again", "error");
    return;
  }
  lastSwitch = Date.now();

  const activeFiles = await getActiveFiles();
  const isCurrentlyActive = activeFiles.includes(optionId);

  if (!isCurrentlyActive) {
    const conflicts = getConflictingOptions(activeFiles, optionId);
    if (conflicts.length > 0) {
      popup("Cannot select opposite option. Deselect conflicting option first.", "error");
      return;
    }

    if (activeFiles.length >= 2) {
      popup("Maximum 2 options allowed. Deselect one first.", "error");
      return;
    }
  }

  showLoader(true, isCurrentlyActive ? "Disabling..." : "Enabling...");
  popup(`${isCurrentlyActive ? '👎' : '👍'} ${options.find(o => o.id === optionId).name}...`, "info");

  requestAnimationFrame(() => {
    setTimeout(() => {
      try {
        if (isCurrentlyActive) {
          sh(`rm -f "${FILES[optionId]}"`);
          popup("Reboot to apply changes", "success");
        } else {
          sh(`touch "${FILES[optionId]}" && chmod 0644 "${FILES[optionId]}"`);
          popup("Reboot to apply changes", "success");
        }
      } catch (e) {
        popup("Failed to apply changes", "error");
      }

      showLoader(false);
      render();
    }, 0);
  });
}

function showRebootModal() {
  document.getElementById("rebootModal").classList.add("show");
}

function closeRebootModal() {
  document.getElementById("rebootModal").classList.remove("show");
}

function confirmReboot() {
  closeRebootModal();
  showLoader(true, "Rebooting...");
  popup("Rebooting device...", "info");

  requestAnimationFrame(() => {
    setTimeout(() => {
      try {
        sh("reboot");
      } catch (e) {
        popup("Reboot command failed", "error");
        showLoader(false);
      }
    }, 1000);
  });
}

async function render() {
  await validateFiles();
  const activeFiles = await getActiveFiles();
  const root = document.getElementById("profiles");
  root.innerHTML = "";

  options.forEach(opt => {
    const isActive = activeFiles.includes(opt.id);
    const conflicts = getConflictingOptions(activeFiles, opt.id);
    const isDisabled = !isActive && conflicts.length > 0;

    const d = document.createElement("div");
    d.className = "item" + (isActive ? " active" : "") + (isDisabled ? " disabled-option" : "");
    d.innerHTML = `
      <div class="title"><span class="check">✓</span>${opt.name}</div>
      <div class="subtitle">${opt.desc}${isDisabled ? ' • Conflict with selected option' : ''}</div>
    `;

    if (!isDisabled) {
      d.onclick = () => toggleOption(opt.id);
    }

    root.appendChild(d);
  });
}

document.addEventListener("DOMContentLoaded", render);
