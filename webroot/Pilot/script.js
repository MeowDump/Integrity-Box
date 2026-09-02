const AUTOPILOT_FLAG = '/data/adb/Box-Brain/autopilot';
const RUN_ACTION = '/data/adb/Box-Brain/run_action';
const EMERGENCY_DIR = '/data/adb/Box-Brain';
const DAEMON_SCRIPT = '/data/adb/modules/playintegrityfix/webroot/common_scripts/autopilot.sh';

function runShell(cmd, cb) {
  const k = window.parent?.ksu || window.ksu;
  if (!k || !k.exec) {
    popup('KernelSU API not available', 'error');
    if (cb) cb('');
    return;
  }
  const id = 'cb_' + Date.now();
  let done = false;
  const timeout = setTimeout(function() {
    if (done) return;
    done = true;
    delete (window.parent || window)[id];
    if (cb) cb('');
  }, 3000);
  (window.parent || window)[id] = function() {
    if (done) return;
    done = true;
    clearTimeout(timeout);
    delete (window.parent || window)[id];
    const result = arguments.length === 1 ? arguments[0] : arguments[1] || '';
    if (cb) cb(result);
  };
  k.exec('sh -c \'' + cmd.replace(/'/g, '\'\\\'\'') + '\'', '{}', id);
}

function popup(msg, type="info") {
  try {
    if (typeof window.toast === "function") { window.toast(String(msg)); return; }
    if (window.kernelsu && typeof window.kernelsu.toast === "function") { window.kernelsu.toast(String(msg)); return; }
    if (typeof ksu === "object" && typeof ksu.toast === "function") { ksu.toast(String(msg)); return; }
  } catch {}

  const n = document.createElement("div");
  n.className = "toast";
  n.textContent = msg;
  document.body.appendChild(n);
  requestAnimationFrame(()=>n.classList.add("show"));
  setTimeout(()=>{ n.classList.remove("show"); setTimeout(()=>n.remove(),300); },2800);
}

function showLoader(show, text = "Processing..."){
  const loader = document.getElementById("loader");
  const loaderText = loader.querySelector(".loader-text");
  if(text) loaderText.textContent = text;

  if(show){
    loader.classList.add("show");
  } else {
    loader.classList.remove("show");
  }
}

function timeAgo(timestamp) {
  if (!timestamp || timestamp === "0") return "Never";

  const now = Math.floor(Date.now() / 1000);
  const diff = now - parseInt(timestamp);

  if (diff < 0) return "Just now";
  if (diff < 60) return diff + " seconds ago";
  if (diff < 3600) return Math.floor(diff / 60) + " minutes ago";
  if (diff < 86400) return Math.floor(diff / 3600) + " hours ago";
  if (diff < 604800) return Math.floor(diff / 86400) + " days ago";
  if (diff < 2592000) return Math.floor(diff / 604800) + " weeks ago";
  if (diff < 31536000) return Math.floor(diff / 2592000) + " months ago";
  return Math.floor(diff / 31536000) + " years ago";
}

function formatExactTime(timestamp) {
  if (!timestamp || timestamp === "0") return "--";
  const date = new Date(parseInt(timestamp) * 1000);
  return date.toLocaleString();
}

function getHeartbeatStatus(timestamp) {
  if (!timestamp || timestamp === "0") return { status: 'dead', text: 'Not running' };
  const now = Math.floor(Date.now() / 1000);
  const diff = now - parseInt(timestamp);

  if (diff < 120) return { status: 'active', text: 'Healthy' };
  if (diff < 300) return { status: 'stale', text: 'Slow response' };
  return { status: 'dead', text: 'Not responding' };
}

function getHighestEmergencyFlag(cb) {
  runShell('ls ' + EMERGENCY_DIR + '/emergency_[A-Z]* 2>/dev/null | sed "s/.*emergency_//" | sort -V | tail -1', function(result) {
    const flag = result.trim();
    if (flag && flag.match(/^[A-Z]+$/)) {
      cb(flag);
    } else {
      cb(null);
    }
  });
}

function updateEmergencyUI(flag) {
  const badge = document.getElementById('emergencyBadge');
  const text = document.getElementById('emergencyText');
  if (flag) {
    text.textContent = flag;
    badge.className = 'chip chip-warn';
  } else {
    text.textContent = 'None';
    badge.className = 'chip chip-muted';
  }
}

function updateAutopilotUI(enabled) {
  document.getElementById('autopilotToggle').checked = enabled;
  const subtitle = document.getElementById('statusSubtitle');
  subtitle.textContent = enabled ? 'Active and running' : 'Disabled';
}

function updateModeUI(mode) {
  const fullBtn = document.getElementById('fullMode');
  const keyboxBtn = document.getElementById('keyboxMode');
  const descTitle = document.getElementById('modeDescTitle');
  const descText = document.getElementById('modeDescText');

  if (mode === 'full') {
    fullBtn.classList.add('active');
    keyboxBtn.classList.remove('active');
    descTitle.textContent = 'Xtreme Mode Active';
    descText.textContent = 'Executes complete automation: Keybox injection, fingerprint spoofing, target configuration, and system patching.';
  } else {
    fullBtn.classList.remove('active');
    keyboxBtn.classList.add('active');
    descTitle.textContent = 'Keybox Only Mode';
    descText.textContent = 'Performs single keybox injection only. Minimal footprint for attestation bypass.';
  }
}

function updateHeartbeatUI(timestamp) {
  const subtitle = document.getElementById('heartbeatSubtitle');
  const timeEl = document.getElementById('heartbeatTime');
  const chip = document.getElementById('heartbeatChip');

  const status = getHeartbeatStatus(timestamp);

  subtitle.textContent = status.text;
  timeEl.textContent = timeAgo(timestamp) + ' • ' + formatExactTime(timestamp);

  chip.textContent = status.text;
  if (status.status === 'active') {
    chip.className = 'chip chip-ok';
  } else if (status.status === 'stale') {
    chip.className = 'chip chip-warn';
  } else {
    chip.className = 'chip chip-err';
  }
}

function updateGithubUI(timestamp) {
  const subtitle = document.getElementById('githubSubtitle');
  const timeEl = document.getElementById('githubTime');

  if (!timestamp || timestamp === "0") {
    subtitle.textContent = 'Not checked yet';
    timeEl.textContent = '--';
    return;
  }

  subtitle.textContent = 'Last checked';
  timeEl.textContent = timeAgo(timestamp) + ' • ' + formatExactTime(timestamp);
}

function checkAutopilot() {
  runShell('[ -f ' + AUTOPILOT_FLAG + ' ] && echo "1" || echo "0"', function(result) {
    updateAutopilotUI(result.trim() === '1');
  });
}

function checkMode() {
  runShell('[ -f ' + RUN_ACTION + ' ] && echo "1" || echo "0"', function(result) {
    updateModeUI(result.trim() === '1' ? 'full' : 'keybox');
  });
}

function checkEmergency() {
  getHighestEmergencyFlag(function(flag) {
    updateEmergencyUI(flag);
  });
}

function checkTimestamps() {
  runShell('cat /data/adb/Box-Brain/daemon_heartbeat 2>/dev/null || echo "0"', function(beat) {
    updateHeartbeatUI(beat.trim());
  });

  runShell('cat /data/adb/Box-Brain/last_github_check 2>/dev/null || echo "0"', function(check) {
    updateGithubUI(check.trim());
  });
}

function toggleAutopilot() {
  const enabled = document.getElementById('autopilotToggle').checked;
  showLoader(true, enabled ? 'Enabling...' : 'Disabling...');
  if (enabled) {
    runShell('mkdir -p /data/adb/Box-Brain && touch ' + AUTOPILOT_FLAG, function() {
      runShell('sh ' + DAEMON_SCRIPT + ' &', function() {
        showLoader(false);
        popup('AutoPilot enabled', 'success');
        updateAutopilotUI(true);
        setTimeout(checkTimestamps, 1000);
      });
    });
  } else {
    runShell('rm -f ' + AUTOPILOT_FLAG, function() {
      showLoader(false);
      popup('AutoPilot disabled', 'info');
      updateAutopilotUI(false);
    });
  }
}

function setMode(mode) {
  const currentIsFull = document.getElementById('fullMode').classList.contains('active');
  const targetIsFull = mode === 'full';
  if (currentIsFull === targetIsFull) return;

  showLoader(true, 'Switching mode...');
  if (targetIsFull) {
    runShell('touch ' + RUN_ACTION, function() {
      showLoader(false);
      popup('Xtreme Mode activated', 'success');
      updateModeUI('full');
    });
  } else {
    runShell('rm -f ' + RUN_ACTION, function() {
      showLoader(false);
      popup('Keybox Only mode activated', 'success');
      updateModeUI('keybox');
    });
  }
}

document.addEventListener('DOMContentLoaded', function() {
  checkAutopilot();
  checkMode();
  checkEmergency();
  checkTimestamps();

  setInterval(checkTimestamps, 30000);
  setInterval(checkEmergency, 60000);
});
