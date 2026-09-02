const LOGFILE = "/data/adb/Box-Brain/Integrity-Box-Logs/keybox_scan.log";
const RUNNER = "/data/adb/modules/playintegrityfix/webroot/common_scripts/run_scan.sh";
const DEST = "/data/adb/tricky_store";

let slot = 1;
let allFiles = [];
let isScanning = false;

function runShell(cmd) {
  return new Promise((res, rej) => {
    if (window.parent && window.parent.runShellFromIframe) {
      window.parent.runShellFromIframe(cmd).then(res).catch(rej);
    } else {
      rej("Shell unavailable");
    }
  });
}

function showToast(msg, type = "info") {
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
  setTimeout(() => t.classList.remove("show"), 2500);
}

async function scan() {
  if (isScanning) return;
  isScanning = true;

  const btn = document.getElementById("refreshBtn");
  const list = document.getElementById("fileList");

  btn.classList.add("loading");
  list.innerHTML = '<div class="scanning"><span class="spinner"></span><span>Scanning...</span></div>';

  try {
    await runShell(`rm -f ${LOGFILE}`);
    await runShell(`sh -c 'sh ${RUNNER} &'`);
  } catch {}

  let found = false;
  const start = Date.now();
  const poll = setInterval(async () => {
    try {
      const cur = await runShell(`cat ${LOGFILE}`);
      if (cur && cur.trim().length > 0) {
        found = true;
        clearInterval(poll);
        parseFiles(cur);
      }
    } catch (e) {
      // poll target not ready yet — keep waiting until timeout
    }

    if (Date.now() - start > 10000) {
      clearInterval(poll);
      if (!found) renderEmpty();
    }
  }, 400);

  btn.classList.remove("loading");
  isScanning = false;
}

function parseFiles(out) {
  allFiles = out.split("\n").filter(Boolean).map(l => {
    const [ts, size, path] = l.split("|");
    return { ts: +ts, size: +size, path, name: path.split("/").pop() };
  });
  render();
}

function render() {
  const list = document.getElementById("fileList");
  if (allFiles.length === 0) {
    renderEmpty();
    return;
  }

  list.innerHTML = allFiles.map(f => `
    <div class="file-item list-item" onclick="loadFile('${f.path}')">
      <div class="grow">
        <div class="file-name">${f.name}</div>
        <div class="file-meta">${(f.size / 1024).toFixed(1)} KB • ${new Date(f.ts * 1000).toLocaleDateString()}</div>
      </div>
      <div class="file-load">Load</div>
    </div>
  `).join('');
}

function renderEmpty() {
  document.getElementById("fileList").innerHTML = `
    <div class="empty">No keybox files found</div>
  `;
}

async function loadFile(path) {
  const names = ["", "keybox.xml", "keybox2.xml", "keybox3.xml"];
  try {
    await runShell(`
      mkdir -p ${DEST} &&
      cp -f "${path}" ${DEST}/${names[slot]} &&
      chmod 644 ${DEST}/${names[slot]}
    `);
    showToast(`Loaded to Slot ${slot}`, "success");
  } catch {
    showToast("Failed to load", "error");
  }
}

document.querySelectorAll(".slot").forEach(s => {
  s.onclick = () => {
    document.querySelectorAll(".slot").forEach(x => x.classList.remove("active"));
    s.classList.add("active");
    slot = +s.dataset.slot;
  };
});

document.getElementById("refreshBtn").onclick = scan;
