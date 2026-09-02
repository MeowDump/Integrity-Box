var DOWNLOADS = [
  { id: "zn", name: "Zygisk Next", desc: "Dr-TSNG / v1.4.4", type: "zip", url: "https://github.com/Dr-TSNG/ZygiskNext/releases/download/v1.4.4/Zygisk-Next-1.4.4-831-98fd9c6-release.zip", filename: "ZygiskNext.zip" },
  { id: "ts", name: "TrickyStore", desc: "5ec1cff / v1.4.1", type: "zip", url: "https://github.com/5ec1cff/TrickyStore/releases/download/1.4.1/Tricky-Store-v1.4.1-245-72b2e84-release.zip", filename: "TrickyStore.zip" },
  { id: "hma2", name: "HMA-OSS", desc: "frknkrc44 / oss-164", type: "zip", url: "https://github.com/frknkrc44/HMA-OSS/releases/download/oss-164/HMA-OSS-ZYGISK-oss-164-release.zip", filename: "HMA_OOS.zip" },
  { id: "nhl", name: "NoHello", desc: "MhmRdd / v1.8.3", type: "kpm", url: "https://github.com/MeowDump/TG2Git/releases/download/TG2Git/Nohello-v1.8.3.7-102-ab38e9c-release.kpm", filename: "NoHello.kpm" },
  { id: "nh", name: "NoHello", desc: "MhmRdd / v1.8.2", type: "kpm", url: "https://github.com/MeowDump/TG2Git/releases/download/TG2Git/Nohello-v1.8.2-48-f824968-release.kpm", filename: "NoHello-old.kpm" },
  { id: "sh", name: "SeLinuxHook", desc: "Admirepowered / 1.1.6.1", type: "kpm", url: "https://github.com/MeowDump/TG2Git/releases/download/TG2Git/selinux_hook_1.1.6.1.kpm", filename: "SeLinuxHook.kpm" },
  { id: "hma", name: "HMA Config", desc: "MeowDump / config.json", type: "json", url: "https://github.com/MeowDump/Integrity-Box/releases/download/v39/v8-HMA-OOS-config.json", filename: "HMA_Config.json" },
  { id: "ka", name: "KeyAttestation", desc: "qwq233 / v1.8.4", type: "apk", url: "https://github.com/qwq233/KeyAttestation/releases/download/1.8.4/key-attestation-v1.8.4-release.apk", filename: "KeyAttestation.apk" },
  { id: "ul", name: "UpdateLocker", desc: "ru.mike / v1.4.3", type: "apk", url: "https://github.com/Xposed-Modules-Repo/ru.mike.updatelocker/releases/download/20-1.4.3/updatelocker_v1.4.3_icon.apk", filename: "UpdateLocker.apk" },
  { id: "rp", name: "Reverse Pixelify", desc: "uragiristereo / v1.0", type: "apk", url: "https://github.com/uragiristereo/Reverse_Pixelify/releases/download/v1.0/Reverse_Pixelify_v1.0.apk", filename: "Disable_ROM_spoofing_lsposed.apk" },
  { id: "kw", name: "KSU WebUI", desc: "MeowDump / v2", type: "apk", url: "https://github.com/MeowDump/KsuWebUIStandalone/releases/download/v2/v2-Meow-KsuWebUI.apk", filename: "WebUI.apk" },
  { id: "cp", name: "CorePatch", desc: "LSPosed / N-1.0", type: "apk", url: "https://github.com/LSPosed/CorePatch/releases/download/N-1.0/app-release.apk", filename: "Downgrade_Playstore.apk" },
  { id: "th", name: "Thor", desc: "trinadhthatakula / v1.93.2", type: "apk", url: "https://github.com/trinadhthatakula/Thor/releases/download/v1.93.2-dev-106/foss-release.apk", filename: "Installation_Spoofer.apk" },
  { id: "ma", name: "MeowAssistant", desc: "MeowDump / v1", type: "apk", url: "https://github.com/MeowDump/MeowAssistant/releases/download/v1/v1-MeowTile.apk", filename: "Meow_QS_Tile.apk" },
  { id: "af", name: "AndroidFaker", desc: "Android1500 / v2.0.0-beta", type: "apk", url: "https://github.com/Android1500/AndroidFaker/releases/download/v2.0.0-beta-9-6/AF-v2.0.0-beta-9-6.apk", filename: "Android_Faker.apk" }
];

var FLAG_DIR = "/data/adb/Box-Brain/MeowDownloader";
var LOG_FILE = "/data/adb/Box-Brain/Integrity-Box-Logs/IntegrityDownloader.log";
var OUT_DIR = "/sdcard/Download/IntegrityModules";

var listEl = document.getElementById("list");
var statusArea = document.getElementById("statusArea");
var statusList = document.getElementById("statusList");
var dlBtn = document.getElementById("dlBtn");

function log(msg) {
  var el = document.getElementById("debugLog");
  var line = document.createElement("div");
  line.textContent = msg;
  el.appendChild(line);
  el.scrollTop = el.scrollHeight;
}

function sh(cmd) {
  try { return ksu.exec(cmd); } catch (e) { log("SH_ERR: " + (e.message || e)); return ""; }
}

function showToast(msg) {
  log("TOAST: " + msg);
  var t = document.querySelector(".toast");
  if (!t) {
    t = document.createElement("div");
    t.className = "toast";
    document.body.appendChild(t);
  }
  if (typeof window.toast === "function") { window.toast(msg); return; }
  if (window.kernelsu && typeof window.kernelsu.toast === "function") { window.kernelsu.toast(msg); return; }
  t.textContent = msg;
  t.classList.add("show");
  setTimeout(function() { t.classList.remove("show"); }, 3000);
}

function renderList() {
  var html = "";
  for (var i = 0; i < DOWNLOADS.length; i++) {
    var item = DOWNLOADS[i];
    html += '<div class="item list-item" id="item-' + item.id + '">' +
      '<div class="grow">' +
        '<div class="item-name">' + item.name + '</div>' +
        '<div class="item-desc">' + item.desc + '</div>' +
      '</div>' +
      '<div class="item-badge type-' + item.type + '">' + item.type + '</div>' +
      '<label class="switch" id="toggle-' + item.id + '" onclick="manualToggle(\'' + item.id + '\')">' +
        '<input type="checkbox" class="t"/><span class="track"></span>' +
      '</label>' +
    '</div>';
  }
  listEl.innerHTML = html;
}

function manualToggle(id) {
  var toggle = document.getElementById("toggle-" + id);
  var input = toggle.querySelector(".t");
  var isOn = input.checked;
  if (isOn) {
    input.checked = false;
    sh('rm -f "' + FLAG_DIR + '/' + id + '"');
    log("Toggle OFF: " + id);
  } else {
    input.checked = true;
    sh('mkdir -p "' + FLAG_DIR + '"');
    sh('touch "' + FLAG_DIR + '/' + id + '"');
    log("Selected: " + id);
  }
}

function selectAll() {
  sh('mkdir -p "' + FLAG_DIR + '"');
  for (var i = 0; i < DOWNLOADS.length; i++) {
    var id = DOWNLOADS[i].id;
    var toggle = document.getElementById("toggle-" + id);
    if (toggle && !toggle.querySelector(".t").checked) {
      toggle.querySelector(".t").checked = true;
      sh('touch "' + FLAG_DIR + '/' + id + '"');
    }
  }
  log("Select All");
}

function deselectAll() {
  sh('rm -rf "' + FLAG_DIR + '"');
  for (var i = 0; i < DOWNLOADS.length; i++) {
    var toggle = document.getElementById("toggle-" + DOWNLOADS[i].id);
    if (toggle) toggle.querySelector(".t").checked = false;
  }
  statusArea.style.display = "none";
  statusList.innerHTML = "";
  log("Deselect All");
}

function updateStatus(id, state, text) {
  var el = document.getElementById("st-" + id);
  if (!el) {
    var item = null;
    for (var i = 0; i < DOWNLOADS.length; i++) {
      if (DOWNLOADS[i].id === id) { item = DOWNLOADS[i]; break; }
    }
    el = document.createElement("div");
    el.id = "st-" + id;
    el.className = "status-item";
    el.innerHTML = '<div class="status-dot pending" id="dot-' + id + '"></div><div class="status-name">' + (item ? item.name : id) + '</div><div class="status-text" id="txt-' + id + '">Pending</div>';
    statusList.appendChild(el);
  }
  document.getElementById("dot-" + id).className = "status-dot " + state;
  document.getElementById("txt-" + id).textContent = text;
}

function getSelectedIds() {
  var ids = [];
  for (var i = 0; i < DOWNLOADS.length; i++) {
    var toggle = document.getElementById("toggle-" + DOWNLOADS[i].id);
    if (toggle && toggle.querySelector(".t").checked) {
      ids.push(DOWNLOADS[i].id);
    }
  }
  return ids;
}

function findItem(id) {
  for (var i = 0; i < DOWNLOADS.length; i++) {
    if (DOWNLOADS[i].id === id) return DOWNLOADS[i];
  }
  return null;
}

function buildDownloadCmd(item) {
  return 'OUT="' + OUT_DIR + '"; mkdir -p "$OUT"; DL=""; ' +
    'command -v curl >/dev/null 2>&1 && DL="curl"; ' +
    '[ -z "$DL" ] && command -v wget >/dev/null 2>&1 && DL="wget"; ' +
    '[ -z "$DL" ] && [ -x /data/adb/magisk/busybox ] && DL="bb"; ' +
    '[ -z "$DL" ] && [ -x /data/adb/ksu/bin/busybox ] && DL="bb"; ' +
    '[ -z "$DL" ] && toybox wget --help >/dev/null 2>&1 && DL="toybox"; ' +
    'if [ -z "$DL" ]; then echo "NO_DL"; exit 1; fi; ' +
    'tmp="$OUT/' + item.filename + '.tmp"; rm -f "$tmp"; ok=0; ' +
    'for i in 1 2 3; do ' +
      'if [ "$DL" = "curl" ]; then curl -L --fail --connect-timeout 10 --max-time 120 -o "$tmp" "' + item.url + '" 2>/dev/null; ' +
      'elif [ "$DL" = "wget" ]; then wget --no-check-certificate -O "$tmp" "' + item.url + '" 2>/dev/null; ' +
      'elif [ "$DL" = "bb" ]; then /data/adb/magisk/busybox wget --no-check-certificate -O "$tmp" "' + item.url + '" 2>/dev/null || /data/adb/ksu/bin/busybox wget --no-check-certificate -O "$tmp" "' + item.url + '" 2>/dev/null; ' +
      'elif [ "$DL" = "toybox" ]; then toybox wget -O "$tmp" "' + item.url + '" 2>/dev/null; ' +
      'fi; ' +
      'if [ -s "$tmp" ]; then mv "$tmp" "$OUT/' + item.filename + '"; echo "OK"; ok=1; break; fi; ' +
      'rm -f "$tmp"; sleep 1; ' +
    'done; ' +
    'if [ "$ok" = "0" ]; then echo "FAIL"; fi';
}

function startDownload() {
  log("Preparing Download...");
  var selectedIds = getSelectedIds();
  log("Selected: " + selectedIds.join(", "));

  if (selectedIds.length === 0) {
    showToast("Nothing selected");
    return;
  }

  dlBtn.disabled = true;
  dlBtn.classList.add("loading");
  statusArea.style.display = "block";
  statusList.innerHTML = "";

  for (var i = 0; i < selectedIds.length; i++) {
    updateStatus(selectedIds[i], "pending", "Queued");
  }

  sh('mkdir -p "' + OUT_DIR + '"');
  sh('rm -f "' + LOG_FILE + '"');
  sh('echo "START" > "' + LOG_FILE + '"');

  downloadNext(selectedIds, 0);
}

function downloadNext(ids, index) {
  if (index >= ids.length) {
    var dots = statusList.querySelectorAll(".status-dot");
    var done = 0, fail = 0;
    for (var i = 0; i < dots.length; i++) {
      var cls = dots[i].className;
      if (cls.indexOf("done") !== -1) done++;
      else if (cls.indexOf("fail") !== -1) fail++;
    }
    showToast("Finished: " + done + " OK, " + fail + " failed");
    dlBtn.disabled = false;
    dlBtn.classList.remove("loading");
    sh('rm -f "' + FLAG_DIR + '"/*');
    for (var i = 0; i < DOWNLOADS.length; i++) {
      var toggle = document.getElementById("toggle-" + DOWNLOADS[i].id);
      if (toggle) toggle.querySelector(".t").checked = false;
    }
    return;
  }

  var item = findItem(ids[index]);
  if (!item) {
    downloadNext(ids, index + 1);
    return;
  }

  updateStatus(item.id, "running", "Downloading...");
  log("Starting: " + item.name);

  var cmd = buildDownloadCmd(item);

  requestAnimationFrame(function() {
    setTimeout(function() {
      log("Exec: " + item.name);
      var result = sh(cmd);
      var out = String(result || "").trim();
      log("Result [" + item.name + "]: " + out);

      sh('echo "' + item.name + ':' + out + '" >> "' + LOG_FILE + '"');

      if (out === "OK") {
        updateStatus(item.id, "done", "Complete");
        showToast(item.name + " done");
      } else if (out === "NO_DL") {
        updateStatus(item.id, "fail", "No downloader");
        showToast("No curl/wget found!");
      } else {
        updateStatus(item.id, "fail", "Failed");
      }

      downloadNext(ids, index + 1);
    }, 50);
  });
}

renderList();
