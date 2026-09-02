function popup(msg) {
  try {
    if (window.toast) return window.toast(String(msg));
    if (window.kernelsu?.toast) return window.kernelsu.toast(String(msg));
    if (window.ksu?.toast) return window.ksu.toast(String(msg));
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

const CACHE_KEY = "pif_cache_v1";
const CACHE_TIME = 24 * 60 * 60 * 1000; // 24h

const SEARCH_DIR = '/data/adb/modules/playintegrityfix/fingerprint';
const DEST = '/data/adb/modules/playintegrityfix/pixel.txt';
const rows = document.getElementById("rows");

async function sh(cmd) {
  try {
    if (typeof ksu?.exec === "function") {
      const out = ksu.exec(cmd);
      if (out?.then) return (await out).toString().trim();
      if (typeof out === "string") return out.trim();
      return await new Promise(res => {
        const cb = "cb_" + Date.now() + "_" + (Math.random() * 10000 | 0);
        window[cb] = (c, o, e) => { delete window[cb]; res((o || "") + (e || "")); };
        ksu.exec(cmd, "{}", cb);
      });
    }
  } catch (e) {}
  return "";
}

async function readKV(file, key) {
  return (await sh(`sh -c 'grep -m1 "^${key}=" "${file}" | cut -d"=" -f2- || true'`)).trim();
}
async function readExpiry(file) {
  return (await sh(`sh -c 'grep -m1 "^# *Estimated Expiry:" "${file}" | sed "s/^# *Estimated Expiry:[[:space:]]*//" || true'`)).trim();
}
async function findCandidates() {
  const out = await sh(`sh -c 'find "${SEARCH_DIR}" -maxdepth 1 -type f -name "*pixel.txt" -print0 | sort -z'`);
  if (!out) return [];
  return out.split("\0").filter(Boolean).map(x => x.trim());
}

function buildUI(metaList) {
  rows.innerHTML = "";
  const frag = document.createDocumentFragment();
  metaList.forEach((item, i) => {
    frag.appendChild(makeItem(i, item.file, item.meta));
  });
  rows.appendChild(frag);
}

function makeItem(index, file, meta) {
  const div = document.createElement("div");
  div.className = "item list-item";
  div.dataset.file = file;

  const num = document.createElement("div");
  num.className = "num";
  num.textContent = "#" + (index + 1);

  const info = document.createElement("div");
  info.className = "grow";

  const line = document.createElement("div");
  line.className = "line";
  line.innerHTML = `
    <div><strong>${meta.MODEL || "Unknown Model"}</strong><div class="small muted">${meta.DEVICE || "unknown"}</div></div>
    <div class="small muted">${meta.RELEASE ? ("Type: " + meta.RELEASE) : ""}</div>
  `;

  const metaRow = document.createElement("div");
  metaRow.className = "meta";
  metaRow.innerHTML = `
    <div>FP: ${meta.FINGERPRINT ? meta.FINGERPRINT.substring(0, 34) + "…" : "—"}</div>
    <div>Patch: ${meta.SECURITY_PATCH || "—"}</div>
    <div class="expiry" data-exp="${meta.ESTIMATED || ''}"></div>
  `;

  info.append(line, metaRow);
  div.append(num, info);

  div.onclick = async () => {
    document.querySelectorAll(".item").forEach(x => x.classList.remove("active"));
    div.classList.add("active");

    await sh(`cp -f "${file}" "${DEST}" && chmod 0644 "${DEST}"`);
    await sh(`am force-stop com.google.android.gms.unstable 2>/dev/null || true;
              am force-stop com.google.android.gms 2>/dev/null || true;
              am force-stop com.android.vending 2>/dev/null || true`);
    popup("Prop applied & GMS restarted");
  };

  setTimeout(() => {
    const expEl = div.querySelector('.expiry');
    if (expEl) {
      formatExpiry(expEl, expEl.dataset.exp);
    }
  }, 10);

  return div;
}

async function scanAndCache() {
  const files = await findCandidates();
  const metaList = [];

  for (const f of files) {
    const [MODEL, DEVICE, RELEASE, SECURITY_PATCH, FINGERPRINT, ESTIMATED] = await Promise.all([
      readKV(f, "MODEL"),
      readKV(f, "DEVICE"),
      readKV(f, "RELEASE"),
      readKV(f, "SECURITY_PATCH"),
      readKV(f, "FINGERPRINT"),
      readExpiry(f)
    ]);
    metaList.push({ file: f, meta: { MODEL, DEVICE, RELEASE, SECURITY_PATCH, FINGERPRINT, ESTIMATED } });
  }

  localStorage.setItem(CACHE_KEY, JSON.stringify({
    time: Date.now(),
    data: metaList
  }));

  return metaList;
}

function loadFromCache() {
  const raw = localStorage.getItem(CACHE_KEY);
  if (!raw) return null;
  try {
    const obj = JSON.parse(raw);
    if (Date.now() - obj.time > CACHE_TIME) return null;
    return obj.data;
  } catch {
    return null;
  }
}

function formatExpiry(el, dateStr) {
  if (!dateStr || !dateStr.trim()) {
    el.innerHTML = `<span class="chip chip-muted">N/A</span>`;
    return;
  }

  const expDate = new Date(dateStr);
  if (isNaN(expDate)) {
    el.innerHTML = `<span class="chip chip-ok">${dateStr}</span>`;
    return;
  }

  const now = new Date();
  const diffMs = expDate - now;
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (diffDays < 0) {
    el.innerHTML = `<span class="chip chip-err">Banned ${Math.abs(diffDays)} days ago</span>`;
    return;
  }

  if (diffDays <= 7) {
    el.innerHTML = `<span class="chip chip-warn">Expiring in ${diffDays} days</span>`;
    return;
  }

  el.innerHTML = `<span class="chip chip-ok">Expiring in ${diffDays} days</span>`;
}

async function init() {
  const cache = loadFromCache();
  if (cache) {
    buildUI(cache);
    return;
  }

  rows.innerHTML = `<div class="empty">Scanning…</div>`;
  const fresh = await scanAndCache();
  buildUI(fresh);
}

async function forceRefresh() {
  rows.innerHTML = `<div class="empty">Refreshing…</div>`;
  const fresh = await scanAndCache();
  buildUI(fresh);
  popup("List refreshed");
}

document.addEventListener("DOMContentLoaded", init);
