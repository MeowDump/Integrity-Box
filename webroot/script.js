const MODDIR = "/data/adb/modules/integrity_box/webroot/common_scripts";
const PROP = `/data/adb/modules/integrity_box/module.prop`;

const modalBackdrop = document.getElementById("modal-backdrop");
const modalTitle = document.getElementById("modal-title");
const modalOutput = document.getElementById("modal-output");
const modalClose = document.getElementById("modal-close");

function runShell(command) {
  if (typeof ksu !== "object" || typeof ksu.exec !== "function") {
    return Promise.reject("KernelSU JavaScript API not available.");
  }
  const cb = `cb_${Date.now()}`;
  return new Promise((resolve, reject) => {
    window[cb] = (code, stdout, stderr) => {
      delete window[cb];
      code === 0 ? resolve(stdout) : reject(new Error(stderr || "Shell command failed"));
    };
    ksu.exec(command, "{}", cb);
  });
}

function popup(msg) {
  return runShell(`am start -a android.intent.action.MAIN -e mona "${msg}" -n meow.helper/.MainActivity`);
}

function openModal(title, content) {
  modalTitle.textContent = title;
  modalOutput.textContent = content || "Loading...";
  modalBackdrop.classList.remove("hidden");
}

function closeModal() {
  modalBackdrop.classList.add("hidden");
}

async function getModuleName() {
  try {
    const name = await runShell(`grep '^name=' ${PROP} | cut -d= -f2`);
    document.getElementById("module-name").textContent = name.trim();
    document.title = name.trim();
  } catch {
    document.getElementById("module-name").textContent = "integrity_box";
  }
}

async function updateDashboard() {
  const statusWhitelist = document.getElementById("status-whitelist");
  const statusGms = document.getElementById("status-gms");
  const statusSusfs = document.getElementById("status-susfs");

  try {
    await runShell("[ -f /data/adb/nohello/whitelist ] || [ -f /data/adb/shamiko/whitelist ]");
    statusWhitelist.textContent = "Enabled";
    statusWhitelist.className = "status-indicator enabled";
  } catch {
    statusWhitelist.textContent = "Disabled";
    statusWhitelist.className = "status-indicator disabled";
  }

  try {
    const gmsProp = await runShell("getprop persist.sys.pihooks.disable.gms_props");
    if (gmsProp.trim() === "true") {
      statusGms.textContent = "Disabled";
      statusGms.className = "status-indicator enabled";
    } else {
      statusGms.textContent = "Enabled";
      statusGms.className = "status-indicator disabled";
    }
  } catch {
    statusGms.textContent = "Unknown";
    statusGms.className = "status-indicator";
  }

  try {
    await runShell("[ -d /data/adb/modules/susfs4ksu ]");
    statusSusfs.textContent = "Detected";
    statusSusfs.className = "status-indicator enabled";
  } catch {
    statusSusfs.textContent = "Not Found";
    statusSusfs.className = "status-indicator disabled";
  }
}

document.addEventListener("DOMContentLoaded", () => {
  getModuleName();
  updateDashboard();

  document.querySelectorAll(".btn").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const script = btn.dataset.script;
      const type = btn.dataset.type;
      const command = `sh ${MODDIR}/${script}`;
      btn.classList.add("loading");
      try {
        if (type === "scanner") {
          const title = btn.innerText.trim();
          openModal(title, "Running scan...");
          const output = await runShell(command);
          modalOutput.textContent = output || "Script executed with no output.";
        } else {
          await runShell(command);
        }
      } catch (error) {
        if (type === "scanner") {
          modalOutput.textContent = `Error executing script:\n\n${error.message}`;
        } else {
          popup(`Error: ${error.message}`);
        }
      } finally {
        btn.classList.remove("loading");
        setTimeout(updateDashboard, 1000);
      }
    });
  });

  modalClose.addEventListener("click", closeModal);
  modalBackdrop.addEventListener("click", (e) => {
    if (e.target === modalBackdrop) closeModal();
  });

  const langDropdown = document.getElementById("lang-dropdown");
  langDropdown.addEventListener("change", async () => {
    const lang = langDropdown.value;
    document.documentElement.setAttribute("dir", lang === "ar" || lang === "ur" ? "rtl" : "ltr");

    try {
      const module = await import(`./lang/${lang}.js`);
      const { translations, buttonGroups, buttonOrder } = module;

      document.querySelectorAll(".group-title").forEach(title => {
        const originalKey = title.dataset.key || title.textContent;
        if (!title.dataset.key) title.dataset.key = originalKey;
        if (buttonGroups[originalKey] && buttonGroups[originalKey][lang]) {
          title.textContent = buttonGroups[originalKey][lang];
        }
      });

      const labels = translations[lang] || translations["en"];
      buttonOrder.forEach((scriptName, index) => {
        const btn = document.querySelector(`.btn[data-script='${scriptName}']`);
        if (btn) {
          const icon = btn.querySelector('.icon');
          const spinner = btn.querySelector('.spinner');
          const label = labels[index] || btn.textContent.trim();
          btn.innerHTML = '';
          if (icon) btn.appendChild(icon);
          btn.appendChild(document.createTextNode(label));
          if (spinner) btn.appendChild(spinner);
        }
      });
    } catch (e) {
      console.error("Failed to load language file", e);
    }
  });

  langDropdown.dispatchEvent(new Event("change"));

  const toggle = document.getElementById("theme-toggle");
  function applyTheme(theme) {
    if (theme === "light") {
      document.documentElement.classList.remove("dark");
      document.documentElement.classList.add("light");
      toggle.checked = false;
    } else {
      document.documentElement.classList.remove("light");
      document.documentElement.classList.add("dark");
      toggle.checked = true;
    }
  }

  const savedTheme = localStorage.getItem("theme") || "dark";
  applyTheme(savedTheme);

  toggle.addEventListener("change", () => {
    const newTheme = toggle.checked ? "dark" : "light";
    localStorage.setItem("theme", newTheme);
    applyTheme(newTheme);
  });
});