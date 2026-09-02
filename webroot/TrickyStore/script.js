const TARGET_FILE = "/data/adb/tricky_store/target.txt";
const BLACK_FILE = "/data/adb/Box-Brain/blacklist.txt";
const BACKUP_FILE = "/sdcard/Download/blacklist_backup.txt.bak";

function runShell(cmd, cb) {
  if (window.parent?.runShellFromIframe) {
    window.parent.runShellFromIframe(cmd).then(out => cb?.(0, out, "")).catch(err => cb?.(1, "", err));
  } else if (window.ksu?.exec) {
    const id = "cb_" + Date.now() + "_" + Math.floor(Math.random() * 9999);
    window[id] = (code, stdout, stderr) => { try { delete window[id] } catch (e) {}; cb?.(code, stdout || "", stderr || ""); };
    ksu.exec(cmd, "{}", id);
  } else cb?.(1, "", "ksu/runShell not found");
}

function esc(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

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

function readLines(path, cb) {
  runShell(`if [ -f ${esc(path)} ]; then cat ${esc(path)}; fi`, (c, o) => cb((o || "").split("\n").map(l => l.trim()).filter(l => l)));
}

function writeLines(path, lines, cb) {
  const args = lines.map(l => esc(l)).join(" ");
  runShell(`mkdir -p $(dirname ${esc(path)}) && printf "%s\\n" ${args} > ${esc(path)}`, c => cb?.(c === 0));
}

function normalizeTargets(lines) { return lines.map(l => l.endsWith("!") ? l.slice(0, -1) : l); }

let cachedApps = [];
function fetchInstalled(cb) {
  runShell("pm list packages -3 -f", (c, out) => {
    if (!out) return cb([]);
    const apps = out.trim().split("\n").map(l => {
      const m = l.match(/package:(.+)=(.+)$/);
      return m ? { pkg: m[2], apk: m[1], label: m[2] } : null;
    }).filter(Boolean);
    cb(apps);
  });
}

function buildList() {
  readLines(TARGET_FILE, tLines => {
    readLines(BLACK_FILE, bLines => {
      const targets = normalizeTargets(tLines), blacks = bLines;
      fetchInstalled(apps => {
        cachedApps = apps;
        render(apps, targets, blacks);
      });
    });
  });
}

function render(apps, targets, blacks) {
  const q = (document.getElementById("search").value || "").toLowerCase();
  const list = document.getElementById("list");
  list.innerHTML = "";
  apps.forEach(a => {
    if (q && !a.pkg.toLowerCase().includes(q) && !a.label.toLowerCase().includes(q)) return;
    const isTarget = targets.includes(a.pkg);
    const isBlack = blacks.includes(a.pkg);
    const item = document.createElement("div");
    item.className = "item" + (isBlack ? " blacklisted" : "");
    item.innerHTML = `
      <img class="app-icon" data-src="ksu://icon/${a.pkg}" alt="">

      <div class="info">
        <div class="name">${a.label}</div>
      </div>

      <div class="actions">
        <div class="item-toggle ${isTarget ? 'active' : ''} ${isBlack ? 'disabled' : ''}"
             data-pkg="${a.pkg}"></div>

        <button class="icon-btn black ${isBlack ? 'blacklisted' : ''}" data-pkg="${a.pkg}" title="Blacklist">${isBlack ? "Unblock" : "Block"}</button>
      </div>
    `;
    list.appendChild(item);
  });
  attachListeners();
  loadIcons();
}

function attachListeners() {
  document.querySelectorAll(".toggle, .item-toggle").forEach(btn => {
    btn.onclick = () => {
      if (btn.classList.contains("disabled")) { popup("Package is blacklisted", true); return; }
      const pkg = btn.getAttribute("data-pkg");
      readLines(TARGET_FILE, lines => {
        let normalized = normalizeTargets(lines);
        if (btn.classList.contains("active")) normalized = normalized.filter(p => p !== pkg);
        else if (!normalized.includes(pkg)) normalized.push(pkg);
        writeLines(TARGET_FILE, normalized, ok => {
          popup(ok ? (btn.classList.contains("active") ? "Removed from targets" : "Added to targets") : "Write failed", !ok);
          buildList();
        });
      });
    };
  });

  document.querySelectorAll(".icon-btn.black").forEach(b => {
    b.onclick = () => {
      const pkg = b.getAttribute("data-pkg");
      readLines(BLACK_FILE, bLines => {
        readLines(TARGET_FILE, tLines => {
          let newBlacks = bLines;
          let newTargets = normalizeTargets(tLines);
          const isAdding = !newBlacks.includes(pkg);

          if (isAdding) {
            newBlacks.push(pkg);
            newTargets = newTargets.filter(p => p !== pkg);
          } else {
            newBlacks = newBlacks.filter(p => p !== pkg);
          }

          writeLines(BLACK_FILE, newBlacks, ok => {
            if (ok && isAdding) {
              writeLines(TARGET_FILE, newTargets, ok2 => {
                popup(ok2 ? "Blacklisted & removed from targets" : "Blacklist updated, target removal failed", !ok2);
                buildList();
              });
            } else {
              popup(ok ? (isAdding ? "Blacklisted" : "Removed from blacklist") : "Write failed", !ok);
              buildList();
            }
          });
        });
      });
    };
  });
}

function selectAllBlacklist() {
  readLines(BLACK_FILE, bLines => {
    readLines(TARGET_FILE, tLines => {
      let newBlacks = [...bLines];
      let newTargets = normalizeTargets(tLines);
      let addedCount = 0;

      cachedApps.forEach(app => {
        if (!newBlacks.includes(app.pkg)) {
          newBlacks.push(app.pkg);
          newTargets = newTargets.filter(p => p !== app.pkg);
          addedCount++;
        }
      });

      if (addedCount === 0) {
        popup("All apps already blacklisted", "info");
        return;
      }

      writeLines(BLACK_FILE, newBlacks, ok => {
        if (ok) {
          writeLines(TARGET_FILE, newTargets, ok2 => {
            popup(ok2 ? `Blacklisted ${addedCount} apps` : "Blacklist updated, target removal failed", !ok2);
            buildList();
          });
        } else {
          popup("Failed to update blacklist", true);
        }
      });
    });
  });
}

document.getElementById("search").addEventListener("input", buildList);

function loadIcons() {
  const imgs = document.querySelectorAll("img.app-icon[data-src]");

  if (!("IntersectionObserver" in window)) {
    imgs.forEach(img => {
      img.src = img.dataset.src;
    });
    return;
  }

  const obs = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      const img = e.target;
      img.src = img.dataset.src;
      img.onload = () => {};
      img.onerror = () => img.style.display = "none";
      obs.unobserve(img);
    });
  }, { rootMargin: "50px" });

  imgs.forEach(img => obs.observe(img));
}

function backupTargets() {
  readLines(BLACK_FILE, lines => {
    writeLines(BACKUP_FILE, lines, ok => popup(ok ? "Backup saved to Download" : "Backup failed", !ok));
  });
}

function restoreTargets() {
  readLines(BACKUP_FILE, lines => {
    writeLines(BLACK_FILE, lines, ok => {
      popup(ok ? "Restored from backup" : "Restore failed", !ok);
      buildList();
    });
  });
}

async function init() {
  runShell(`mkdir -p $(dirname ${esc(TARGET_FILE)}) && touch ${esc(TARGET_FILE)} && mkdir -p $(dirname ${esc(BLACK_FILE)}) && touch ${esc(BLACK_FILE)}`, () => buildList());
}

init();
