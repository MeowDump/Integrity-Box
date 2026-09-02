const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
const today = new Date();
const todayY = today.getFullYear();
const todayM = today.getMonth() + 1;
const todayD = today.getDate();

let selMonth = null, selDate = null;

const monthScroll = document.getElementById("monthScroll");
const dateGrid = document.getElementById("dateGrid");
const previewDate = document.getElementById("previewDate");
const previewCard = document.getElementById("previewCard");
const statusText = document.getElementById("statusText");
const statusDot = document.getElementById("statusDot");

const PATCH_FILE = "/data/adb/tricky_store/security_patch.txt";
const CUSTOM_DIR = "/data/adb/Box-Brain/Custom-Patch";

function showToast(msg) {
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

async function sh(cmd) {
  try {
    if (typeof ksu?.exec === 'function') {
      const maybe = ksu.exec(cmd);
      if (maybe && typeof maybe.then === 'function') return (await maybe).toString().trim();
      if (typeof maybe === 'string') return maybe.toString().trim();
      return await new Promise((resolve) => {
        const cb = `cb_${Date.now()}_${Math.random() * 10000 | 0}`;
        window[cb] = (code, stdout, stderr) => {
          delete window[cb];
          resolve(code === 0 ? (stdout || '').toString().trim() : ((stdout || '') + (stderr || '')).toString().trim());
        };
        ksu.exec(cmd, "{}", cb);
      });
    }
    return '';
  } catch (e) { return '' }
}

function initMonths() {
  months.forEach((m, i) => {
    const el = document.createElement("div");
    el.className = "month-item";
    el.textContent = m;
    el.onclick = () => {
      selMonth = i + 1;
      [...monthScroll.children].forEach(x => x.classList.remove("active"));
      el.classList.add("active");
      refreshDates();
      updatePreview();
    };
    monthScroll.appendChild(el);
  });
}

function getDaysInMonth(month, year) {
  return new Date(year, month, 0).getDate();
}

function getFirstDayOfMonth(month, year) {
  return new Date(year, month - 1, 1).getDay();
}

function refreshDates() {
  dateGrid.innerHTML = "";
  if (!selMonth) return;

  const daysInMonth = getDaysInMonth(selMonth, 2026);
  const firstDay = getFirstDayOfMonth(selMonth, 2026);

  for (let i = 0; i < firstDay; i++) {
    const empty = document.createElement("div");
    empty.className = "date-item empty";
    dateGrid.appendChild(empty);
  }

  for (let d = 1; d <= daysInMonth; d++) {
    const el = document.createElement("div");
    el.className = "date-item";
    el.textContent = d;

    const isFuture = todayY === 2026 && (selMonth > todayM || (selMonth === todayM && d > todayD));
    if (isFuture) {
      el.classList.add("disabled");
    }

    el.onclick = () => {
      if (el.classList.contains("disabled")) {
        showToast("Future dates are not allowed");
        return;
      }
      selDate = d;
      [...dateGrid.children].forEach(x => x.classList.remove("active"));
      el.classList.add("active");
      updatePreview();
    };

    if (selDate === d && !isFuture) {
      el.classList.add("active");
    }

    dateGrid.appendChild(el);
  }
}

function updatePreview() {
  if (selMonth && selDate) {
    const mm = String(selMonth).padStart(2, "0");
    const dd = String(selDate).padStart(2, "0");
    previewDate.textContent = `2026-${mm}-${dd}`;
    previewCard.classList.add("active");
  } else {
    previewDate.textContent = "--/--";
    previewCard.classList.remove("active");
  }
}

function selectMonth(month) {
  selMonth = month;
  const items = monthScroll.children;
  for (let i = 0; i < items.length; i++) {
    items[i].classList.toggle("active", i + 1 === month);
  }
  refreshDates();
}

function selectDate(date) {
  selDate = date;
  const items = dateGrid.querySelectorAll(".date-item:not(.empty)");
  items.forEach((el) => {
    const d = parseInt(el.textContent);
    if (d === date && !el.classList.contains("disabled")) {
      el.classList.add("active");
    } else {
      el.classList.remove("active");
    }
  });
  updatePreview();
}

async function loadExistingDate() {
  statusText.textContent = "Reading patch file...";

  const out = await sh(`cat ${PATCH_FILE} 2>/dev/null || echo "FILE_NOT_FOUND"`);
  const output = out.trim();

  if (output === "FILE_NOT_FOUND" || !output) {
    statusText.textContent = "No existing patch found";
    statusDot.classList.add("warning");
    refreshDates();
    return;
  }

  const match = output.match(/all=(\d{4})-(\d{2})-(\d{2})/);
  if (match) {
    const year = parseInt(match[1]);
    const month = parseInt(match[2]);
    const day = parseInt(match[3]);

    if (year === 2026 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      selectMonth(month);
      setTimeout(() => {
        selectDate(day);
        statusText.textContent = `Loaded: ${match[1]}-${match[2]}-${match[3]}`;
        statusDot.classList.remove("warning");
      }, 100);
      return;
    }
  }

  statusText.textContent = "Invalid patch format";
  statusDot.classList.add("warning");
  refreshDates();
}

async function save() {
  if (!selMonth || !selDate) {
    showToast("Please select month and date");
    return;
  }
  if (todayY === 2026 && (selMonth > todayM || (selMonth === todayM && selDate > todayD))) {
    showToast("Future date blocked");
    return;
  }
  const mm = String(selMonth).padStart(2, "0");
  const dd = String(selDate).padStart(2, "0");
  const dateStr = `2026-${mm}-${dd}`;

  const cmd = `mkdir -p ${CUSTOM_DIR} && rm -f ${CUSTOM_DIR}/* && echo 'all=${dateStr}' > ${PATCH_FILE} && touch ${CUSTOM_DIR}/${dateStr}`;

  await sh(cmd);
  showToast(`Saved ${dateStr}`);
  statusText.textContent = `Active: ${dateStr}`;
  statusDot.classList.remove("warning");
}

document.addEventListener('DOMContentLoaded', () => {
  initMonths();
  loadExistingDate().catch(() => {
    statusText.textContent = "Failed to initialize";
    statusDot.classList.add("warning");
  });
});
