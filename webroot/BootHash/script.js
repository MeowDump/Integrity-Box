const DEST = "/data/adb/Box-Brain/hash.txt";
const input = document.getElementById("new-hash");
const savedEl = document.getElementById("savedHash");
const applyBtn = document.getElementById("apply");
const resetBtn = document.getElementById("reset");
const rebootBtn = document.getElementById("reboot");

function popup(msg, type = "info") {
  try {
    if (window.toast) return window.toast(msg);
    if (window.kernelsu?.toast) return window.kernelsu.toast(msg);
    if (window.ksu?.toast) return window.ksu.toast(msg);
  } catch (e) {}
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

function getExec() {
  if (window.ksu?.exec) return window.ksu.exec.bind(window.ksu);
  if (window.kernelsu?.exec) return window.kernelsu.exec.bind(window.kernelsu);
  if (typeof window.exec === "function") return window.exec;
  return null;
}

function runCmd(cmd) {
  const exec = getExec();
  if (!exec) return Promise.reject(new Error("No exec bridge"));

  try {
    if (exec.length >= 3) {
      return new Promise((resolve, reject) => {
        const id = "__cb" + Date.now();
        window[id] = (code, stdout, stderr) => {
          delete window[id];
          if (+code === 0) resolve(stdout || "");
          else reject(new Error(stderr || stdout || "shell error"));
        };
        exec(cmd, "{}", id);
      });
    }

    const out = exec(cmd);
    if (out?.then) return out.then(r => r.stdout || r);
    return Promise.resolve(out?.stdout || out || "");
  } catch (e) {
    return Promise.reject(e);
  }
}

async function readSaved() {
  try {
    const txt = await runCmd(`cat '${DEST}' || true`);
    const t = txt.trim();
    savedEl.textContent = t || "Config is empty ";
  } catch (e) {
    savedEl.textContent = "Config is empty ";
  }
}

async function writeFile(v) {
  const safe = v.replace(/'/g, "'\"'\"'");
  return runCmd(`printf "%s" '${safe}' > '${DEST}' && sync`);
}

async function removeFile() {
  return runCmd(`rm -f '${DEST}'`);
}

function validate(v) {
  if (!v) return { ok: false, why: "Empty" };
  if (/[^A-Za-z0-9]/.test(v)) return { ok: false, why: "Only A–Z and 0–9 allowed" };
  if (v.length < 12) return { ok: false, why: "Too short" };
  if (v.length > 4096) return { ok: false, why: "Too long" };
  return { ok: true };
}

applyBtn.onclick = async () => {
  const v = input.value.trim();
  const check = validate(v);
  if (!check.ok) return popup(check.why, "error");
  applyBtn.disabled = true;
  applyBtn.classList.add("loading");
  try {
    await writeFile(v);
    popup("Boot hash applied", "success");
    readSaved();
  } catch (e) { popup(e.message, "error"); }
  applyBtn.classList.remove("loading");
  applyBtn.disabled = false;
};

resetBtn.onclick = async () => {
  try {
    await removeFile();
    savedEl.textContent = "Config is empty ";
    popup("Boot hash removed", "info");
  } catch (e) { popup(e.message, "error"); }
};

rebootBtn.onclick = async () => {
  try {
    await runCmd("reboot");
    popup("Rebooting…");
  } catch (e) { popup(e.message, "error"); }
};

readSaved();
