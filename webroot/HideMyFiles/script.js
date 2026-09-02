const SIZE_LIMIT_MB = 512;

const BASE = "/data/adb/Vault/.hidefiles";
const LOG = "/data/adb/Vault/webui.log";
const VAULT = "/data/adb/Vault";

let PREDEFINED = {
  MT2: "/sdcard/MT2", TWRP: "/sdcard/TWRP", Fox: "/sdcard/Fox",
  PBRP: "/sdcard/PBRP", Magisk: "/sdcard/Magisk", SHRP: "/sdcard/SHRP",
  Migrate: "/sdcard/Migrate", CustomROM: "/vendor/bin/install-recovery.sh",
  SwiftBackup: "/sdcard/SwiftBackup", AppManager: "/sdcard/AppManager",
  TMP: "/sdcard/InfinityResource", KernelSU: "/sdcard/.ksu", FolkPatch: "/sdcard/Download/FolkPatch",
  DataBackup: "/sdcard/DataBackup", OTA: "/system/addon.d"
};

let CUSTOM = {}, TARGETS = { ...PREDEFINED };
const sh = cmd => parent.runShellFromIframe(cmd);
const bar = document.getElementById("bar");
const list = document.getElementById("list");
const customPath = document.getElementById("customPath");

const exists = async p => (await sh(`[ -e "${p}" ] && echo 1 || echo 0`)).trim() == "1";

async function getSizeSafe(p) {
  return (await sh(`du -sh "${p}" 2>/dev/null | awk '{print $1}'`)).trim() || "0B";
}
function sizeToMB(s) {
  const v = parseFloat(s) || 0;
  if (s.endsWith("G")) return v * 1024;
  if (s.endsWith("M")) return v;
  if (s.endsWith("K")) return v / 1024;
  return 0;
}

async function loadConf(k) {
  try {
    const o = await sh(`. ${BASE}/${k}.conf 2>/dev/null; echo "$ENABLED|$MODE"`);
    const [e, m] = o.trim().split("|");
    return { e: e === "1", m: m || "move" };
  } catch { return { e: false, m: "move" } }
}
async function saveConf(k, e, m) {
  await sh(`mkdir -p ${BASE};
    echo "ENABLED=${e ? 1 : 0}" > ${BASE}/${k}.conf;
    echo "MODE=${m}" >> ${BASE}/${k}.conf`);
}

function popup(msg, type = "info") {
  try {
    if (window.toast) return window.toast(msg);
    if (window.kernelsu?.toast) return window.kernelsu.toast(msg);
    if (window.ksu?.toast) return window.ksu.toast(msg);
  } catch {}
  let t = document.querySelector(".toast");
  if (!t) {
    t = document.createElement("div");
    t.className = "toast";
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.classList.add("show");
  setTimeout(() => t.classList.remove("show"), 2500);
}

// Custom Paths Persistence
async function loadCustomPaths() {
  try {
    const out = await sh(`cat ${BASE}/custom.conf 2>/dev/null`);
    CUSTOM = {};
    out.trim().split("\n").forEach(line => {
      if (line) {
        const [name, path] = line.split("|");
        CUSTOM[name] = path;
      }
    });
    TARGETS = { ...PREDEFINED, ...CUSTOM };
  } catch {}
}

async function saveCustomPaths() {
  const lines = Object.entries(CUSTOM).map(([k, v]) => `${k}|${v}`);
  await sh(`mkdir -p ${BASE}; echo "${lines.join("\n")}" > ${BASE}/custom.conf`);
}

// Add Custom Path
async function addCustomPath() {
  const p = customPath.value.trim();
  if (!p) return;

  // Only allow /sdcard/ or /storage/emulated/0/
  if (!p.startsWith("/sdcard/") && !p.startsWith("/storage/emulated/0/")) {
    alert("Only paths under /sdcard/ or /storage/emulated/0/ are allowed");
    return;
  }

  // Check if path exists
  if (!(await exists(p))) {
    alert("Path does not exist");
    return;
  }

  const name = p.split("/").pop();
  CUSTOM[name] = p;
  TARGETS = { ...PREDEFINED, ...CUSTOM };
  await saveCustomPaths(); // persist
  customPath.value = "";
  render();
}

// Render
async function render() {
  list.innerHTML = "";
  for (const k in TARGETS) {
    const p = TARGETS[k];
    if (!await exists(p)) continue;

    const size = await getSizeSafe(p);
    const large = sizeToMB(size) > SIZE_LIMIT_MB;
    const recovery = p === "/vendor/bin/install-recovery.sh" || p === "/system/addon.d";
    const cfg = await loadConf(k);

    const el = document.createElement("div");
    el.className = "item list-item";
    el.innerHTML = `
      <div class="row">
        <div class="path mono grow">${p}</div>
        ${CUSTOM[k] ? `<button class="btn btn-danger btn-remove" title="Remove" style="min-height:34px;padding:0 12px">Remove</button>` : ""}
        <label class="switch"><input type="checkbox" class="t" ${cfg.e ? "checked" : ""}/><span class="track"></span></label>
      </div>

      <div class="meta">
        <span>Size: ${size}</span>
        ${large ? `<span class="chip chip-warn">Too big to spoof</span>` : ""}
        ${recovery ? `<span class="chip chip-err">Remove manually from recovery</span>` : ""}
      </div>

      <div class="mode">
        <button data-m="move" ${large || recovery ? "disabled" : ""}
          class="btn small-btn ${cfg.m === "move" && !large && !recovery ? "active" : ""}">Spoof</button>
        <button data-m="rename"
          class="btn small-btn ${cfg.m === "rename" || large || recovery ? "active" : ""}"
          ${recovery ? "disabled" : ""}>Mask</button>
      </div>
    `;

    const t = el.querySelector(".t");
    const btns = [...el.querySelectorAll(".mode button")];

    t.onchange = () => {
      saveConf(k, t.checked,
        btns.find(b => b.classList.contains("active"))?.dataset.m || "rename");
    };

    btns.forEach(b => {
      if (b.disabled) return;
      b.onclick = () => {
        btns.forEach(x => x.classList.remove("active"));
        b.classList.add("active");
        saveConf(k, t.checked, b.dataset.m);
      };
    });

    // Remove button for custom paths
    const rm = el.querySelector(".btn-remove");
    if (rm) {
      rm.onclick = async () => {
        delete CUSTOM[k];
        TARGETS = { ...PREDEFINED, ...CUSTOM };
        await saveCustomPaths();
        render();
      };
    }

    list.appendChild(el);
  }
}

// Run Cleaner
async function runCleaner() {
  const keys = Object.keys(TARGETS);
  let done = 0;
  await sh(`mkdir -p ${BASE}/.unhide ${VAULT}; echo "[$(date)] RUN" >> ${LOG}`);
  for (const k of keys) {
    const p = TARGETS[k];
    const conf = `${BASE}/${k}.conf`;
    await sh(`
      if [ ! -f "${conf}" ]; then echo "[SKIP] ${p} (no config)" >> ${LOG};
      else . "${conf}";
        if [ "$ENABLED" != "1" ]; then echo "[SKIP] ${p} (disabled)" >> ${LOG};
        elif [ ! -e "${p}" ]; then echo "[SKIP] ${p} (missing)" >> ${LOG};
        else TS=$(date +%s);
          if [ -d "${p}" ]; then [ -z "$(ls -A "${p}" 2>/dev/null)" ] && EMPTY=1 || EMPTY=0;
          else [ ! -s "${p}" ] && EMPTY=1 || EMPTY=0; fi;
          if [ "$EMPTY" = "1" ]; then
            mv "${p}" "${BASE}/.unhide/$(basename "${p}").$TS";
            echo "mv \"${BASE}/.unhide/$(basename "${p}").$TS\" \"${p}\"" >> ${BASE}/last_action.sh;
            echo "[EMPTY] ${p}" >> ${LOG};
          else
            if [ "$MODE" = "move" ]; then
              dst="${VAULT}/$(basename "${p}")"; [ -e "$dst" ] && dst="$dst.$TS"; mv "${p}" "$dst";
              echo "mv \"$dst\" \"${p}\"" >> ${BASE}/last_action.sh;
              echo "[MOVE] ${p} -> Vault" >> ${LOG};
            else
              newname=$(tr -dc a-zA-Z0-9 </dev/urandom | head -c12)
              mv "${p}" "${p}.$newname";
              echo "mv \"${p}.$newname\" \"${p}\"" >> ${BASE}/last_action.sh;
              echo "[RENAME] ${p}" >> ${LOG};
            fi
          fi
        fi
      fi
    `);
    done++;
    bar.style.width = Math.round(done / keys.length * 100) + "%";
  }
  render();
  popup("Cleaner completed", "success");
}

// Unhide
async function unhide() {
  await sh(`[ -f ${BASE}/last_action.sh ] && sh ${BASE}/last_action.sh`);
  await sh(`echo "[$(date)] UNHIDE" >> "${LOG}"`);
  bar.style.width = "0%";
  render();
  popup("Unhide completed!", "info");
}

// Load Custom Paths & Render
(async () => {
  await loadCustomPaths();
  render();
})();
