const btn = document.getElementById("clean");
const status = document.getElementById("status");

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
  setTimeout(() => t.classList.remove("show"), 2500);
}

function runShell(cmd) {
  return new Promise((res, rej) => {
    if (!window.ksu?.exec) return rej(new Error("KSU unavailable"));
    const cb = "cb_" + Date.now();
    window[cb] = (code, out, err) => {
      delete window[cb];
      code === 0 ? res(out) : rej(new Error(err || out));
    };
    window.ksu.exec(cmd, "{}", cb);
  });
}

btn.onclick = async () => {
  btn.disabled = true;
  btn.classList.add("loading");
  status.style.display = "block";
  status.textContent = "Clearing Play Store & GMS data…";

  try {
    await runShell("pm clear com.android.vending && pm clear com.google.android.gms");
    status.textContent = "Done. Sign back into your Google account.";
    popup("Go, login your account", "success");
  } catch (e) {
    status.textContent = "Command failed.";
    popup("Command failed", "error");
  }

  btn.classList.remove("loading");
  setTimeout(() => { btn.disabled = false; }, 60000);
};
