const CONFIG = {
  keyboxUrl: 'https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/keybox/key-status',
  fingerprintPath: '/data/adb/modules/playintegrityfix/pixel.txt',
  teePath: '/data/adb/tricky_store/tee_status',
  keyboxLocalPath: '/data/adb/tricky_store/keybox.xml'
};

const infoTexts = {
  verdicts: `<strong>About Verdicts</strong><br><br>
    These results represent <strong>keybox validity</strong> indicating whether the current keybox meets integrity requirements or not. These indicators does not represents your device Play Integrity API request results<br><br>
    <span class="chip chip-ok">MEETS_STRONG_INTEGRITY</span> Keybox is valid<br><br>
    <span class="chip chip-warn">MEETS_DEVICE_INTEGRITY</span> Keybox is soft banned<br><br>
    <span class="chip chip-err">BASIC / NO_INTEGRITY</span> Keybox is revoked`,
  fingerprint: `<strong>Device Fingerprint</strong><br><br>
    Spoofs your device identity to match a certified device profile.<br><br>
    <strong>Validity Period</strong> - Estimated expiry calculated from canary release dates. Once expired, integrity checks will fail.<br><br>
    Config: <code>pixel.txt</code>`
};

const DOM = {};

function cacheDOM() {
  const ids = [
    'netStatusDot', 'netStatusText', 'offlineBanner', 'verdictSectionHeader',
    'keyboxPanel', 'vStrong', 'vDevice', 'vBasic', 'keyboxUpdated',
    'fpManufacturer', 'fpModel', 'fpDevice', 'fpRelease', 'fpFingerprint',
    'fpSecurityPatch', 'fpSdk', 'validityRange', 'expiryDays', 'expiryBar',
    'fpCreated', 'fpModified', 'daysLeft', 'selinuxStatus', 'playStoreVer',
    'playServicesVer', 'teePanel', 'teeTitle', 'teeDesc', 'teeBadge',
    'lastKeyboxSync', 'lastFpRead', 'refreshBtn', 'refreshText',
    'infoModal', 'modalTitle', 'modalText'
  ];
  ids.forEach(id => DOM[id] = document.getElementById(id));
}

async function exec(cmd) {
  return new Promise((resolve, reject) => {
    if (window.parent && window.parent.runShellFromIframe) {
      window.parent.runShellFromIframe(cmd).then(resolve).catch(reject);
      return;
    }
    if (typeof ksu !== 'undefined' && ksu.exec) {
      const cb = 'cb_' + Date.now();
      window[cb] = (code, stdout, stderr) => {
        delete window[cb];
        code === 0 ? resolve(stdout.trim()) : reject(stderr || stdout);
      };
      ksu.exec(cmd, '{}', cb);
    } else {
      reject(new Error('KSU API not available'));
    }
  });
}

async function checkInternet() {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3000);
    await fetch('https://www.google.com/favicon.ico', {
      mode: 'no-cors',
      cache: 'no-store',
      signal: controller.signal
    });
    clearTimeout(timeout);
    return true;
  } catch {
    return false;
  }
}

async function fetchKeyboxStatus() {
  const response = await fetch(CONFIG.keyboxUrl, { cache: 'no-store' });
  if (!response.ok) throw new Error('HTTP ' + response.status);
  const text = await response.text();
  if (text.includes('🟢🟢🟢')) return 'STRONG';
  if (text.includes('🟢🟢🔴')) return 'DEVICE';
  if (text.includes('🔴🔴🔴')) return 'BANNED';
  return 'UNKNOWN';
}

async function getFileStats(path) {
  try {
    const result = await exec(`stat -c '%Y %W %y' "${path}" 2>/dev/null || echo "0 0 0"`);
    const parts = result.split(' ');
    if (parts.length >= 3 && parts[0] !== '0') {
      const modified = parseInt(parts[0]) * 1000;
      const created = parts[1] !== '0' ? parseInt(parts[1]) * 1000 : modified;
      return { modified, created };
    }
  } catch (e) {}
  return null;
}

async function parseFingerprint() {
  try {
    const content = await exec(`cat "${CONFIG.fingerprintPath}" 2>/dev/null || echo ""`);
    if (!content) return null;

    const lines = content.split('\n');
    const data = {};

    lines.forEach(line => {
      if (line.includes('=') && !line.startsWith('#')) {
        const [key, ...valParts] = line.split('=');
        if (key && valParts.length > 0) {
          data[key.trim()] = valParts.join('=').trim();
        }
      }
      if (line.includes('Released On')) {
        const match = line.match(/Released On:\s*(\d{4}-\d{2}-\d{2})/);
        if (match) data.releasedOn = match[1];
      }
      if (line.includes('Estimated Expiry')) {
        const match = line.match(/Estimated Expiry:\s*(\d{4}-\d{2}-\d{2})/);
        if (match) data.estimatedExpiry = match[1];
      }
    });

    const stats = await getFileStats(CONFIG.fingerprintPath);
    if (stats) {
      data.fileCreated = stats.created;
      data.fileModified = stats.modified;
    }

    return data;
  } catch (e) {
    return null;
  }
}

async function parseTEE() {
  try {
    const content = await exec(`cat "${CONFIG.teePath}" 2>/dev/null || echo ""`);
    return {
      exists: true,
      broken: content.includes('teeBroken=true'),
      content: content
    };
  } catch (e) {
    return null;
  }
}

async function getPlayStoreVersion() {
  try {
    return await exec("dumpsys package com.android.vending | grep versionName | head -n1 | awk -F'=' '{print $2}' | cut -d'-' -f1 | cut -d' ' -f1");
  } catch (e) {
    return 'Unknown';
  }
}

async function getPlayServicesVersion() {
  try {
    return await exec("dumpsys package com.google.android.gms | grep versionName | head -n1 | awk -F'=' '{print $2}' | cut -d'-' -f1 | cut -d' ' -f1");
  } catch (e) {
    return 'Unknown';
  }
}

async function getSELinuxStatus() {
  try {
    return await exec("getenforce");
  } catch (e) {
    return 'Unknown';
  }
}

function formatDateShort(date) {
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function formatDateFull(date) {
  return date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}

function updateVerdicts(status) {
  const items = [
    { id: 'vStrong', name: 'Strong', desc: 'Hardware attestation' },
    { id: 'vDevice', name: 'Device', desc: 'Play Protect certified' },
    { id: 'vBasic', name: 'Basic', desc: 'System compatibility' }
  ];

  const stateMap = {
    'STRONG': ['pass', 'pass', 'pass'],
    'DEVICE': ['fail', 'pass', 'pass'],
    'BASIC': ['fail', 'fail', 'pass'],
    'BANNED': ['fail', 'fail', 'fail'],
    'UNKNOWN': ['fail', 'fail', 'fail']
  };

  const statusMap = {
    'pass': ['Pass', 'chip-ok'],
    'fail': ['Failed', 'chip-err'],
    'warn': ['Limited', 'chip-warn']
  };

  const states_arr = stateMap[status] || stateMap['UNKNOWN'];

  items.forEach((item, i) => {
    const el = DOM[item.id];
    const state = states_arr[i];
    const pill = el.querySelector('.chip');
    pill.textContent = statusMap[state][0] || 'Unknown';
    pill.className = 'chip ' + statusMap[state][1];
  });
}

function updateFingerprint(fp) {
  if (!fp) return;

  DOM.fpManufacturer.textContent = fp.MANUFACTURER || '-';
  DOM.fpModel.textContent = fp.MODEL || '-';
  DOM.fpDevice.textContent = fp.DEVICE || '-';
  DOM.fpRelease.textContent = fp.RELEASE || '-';
  DOM.fpFingerprint.textContent = fp.FINGERPRINT || '-';
  DOM.fpSecurityPatch.textContent = fp.SECURITY_PATCH || '-';
  DOM.fpSdk.textContent = fp.DEVICE_INITIAL_SDK_INT || fp['*.api_level'] || '-';

  const expiry = fp.estimatedExpiry || '2026-03-26';
  const released = fp.releasedOn || '2026-02-12';
  const today = new Date();
  const expiryDate = new Date(expiry);
  const releasedDate = new Date(released);

  const totalDays = Math.ceil((expiryDate - releasedDate) / (1000 * 60 * 60 * 24));
  const daysLeft = Math.ceil((expiryDate - today) / (1000 * 60 * 60 * 24));
  const percent = Math.max(0, Math.min(100, (daysLeft / totalDays) * 100));

  const daysEl = DOM.expiryDays;
  daysEl.textContent = daysLeft > 0 ? daysLeft + 'd' : 'EXP';
  daysEl.className = 'validity-days ' + (daysLeft < 7 ? 'critical' : daysLeft < 14 ? 'warning' : '');

  const bar = DOM.expiryBar;
  bar.style.width = percent + '%';
  bar.className = 'progress-bar ' + (daysLeft < 7 ? 'critical' : daysLeft < 14 ? 'warning' : '');

  DOM.validityRange.textContent = formatDateShort(releasedDate) + ' - ' + formatDateShort(expiryDate);

  if (fp.fileCreated) {
    DOM.fpCreated.textContent = 'Created: ' + formatDateFull(new Date(fp.fileCreated));
  } else if (fp.releasedOn) {
    DOM.fpCreated.textContent = 'Created: ' + formatDateFull(new Date(fp.releasedOn));
  }

  if (fp.fileModified) {
    const modDate = new Date(fp.fileModified);
    DOM.fpModified.textContent = 'Modified: ' + formatDateFull(modDate);
    DOM.lastFpRead.textContent = modDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  DOM.daysLeft.textContent = daysLeft > 0 ? daysLeft : '0';
}

function updateTEE(tee) {
  if (tee === null || tee === undefined) {
    DOM.teePanel.classList.add('hidden');
    return;
  }

  DOM.teePanel.classList.remove('hidden');
  const panel = DOM.teePanel;
  const title = DOM.teeTitle;
  const desc = DOM.teeDesc;
  const badge = DOM.teeBadge;

  if (tee.broken) {
    panel.className = 'tee-card broken';
    title.textContent = 'TEE Broken';
    desc.textContent = 'Not a problem';
    badge.textContent = 'its ok bro';
    badge.className = 'chip chip-warn';
  } else {
    panel.className = 'tee-card healthy';
    title.textContent = 'TEE Healthy';
    desc.textContent = 'Environment secure';
    badge.textContent = 'Secure';
    badge.className = 'chip chip-ok';
  }
}

async function updateSystemInfo() {
  const selinux = await getSELinuxStatus();
  const selBadge = DOM.selinuxStatus;
  selBadge.textContent = selinux === 'Enforcing' ? 'OK' : 'OFF';
  selBadge.className = 'chip ' + (selinux === 'Enforcing' ? 'chip-ok' : 'chip-warn');

  DOM.playStoreVer.textContent = await getPlayStoreVersion();
  DOM.playServicesVer.textContent = await getPlayServicesVersion();
}

async function init() {
  const btn = DOM.refreshBtn;
  btn.disabled = true;
  btn.classList.add('loading');
  DOM.refreshText.textContent = 'Loading...';

  const hasInternet = await checkInternet();

  if (hasInternet) {
    DOM.netStatusDot.className = 'status-indicator';
    DOM.netStatusText.textContent = 'Online';
    DOM.offlineBanner.classList.remove('show');
    DOM.keyboxPanel.classList.remove('hidden');
    DOM.verdictSectionHeader.classList.remove('hidden');

    try {
      const keyboxStatus = await fetchKeyboxStatus();
      updateVerdicts(keyboxStatus);
      DOM.lastKeyboxSync.textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

      const keyboxStats = await getFileStats(CONFIG.keyboxLocalPath);
      if (keyboxStats) {
        DOM.keyboxUpdated.textContent = 'Updated ' + formatDateShort(new Date(keyboxStats.modified));
      } else {
        DOM.keyboxUpdated.textContent = 'Updated ' + formatDateShort(new Date());
      }
    } catch (e) {
      updateVerdicts('UNKNOWN');
      DOM.keyboxUpdated.textContent = 'Sync failed';
    }
  } else {
    DOM.netStatusDot.className = 'status-indicator offline';
    DOM.netStatusText.textContent = 'Offline';
    DOM.offlineBanner.classList.add('show');
    DOM.keyboxPanel.classList.add('hidden');
    DOM.verdictSectionHeader.classList.add('hidden');
  }

  const fp = await parseFingerprint();
  if (fp) updateFingerprint(fp);

  const tee = await parseTEE();
  updateTEE(tee);

  await updateSystemInfo();

  btn.disabled = false;
  btn.classList.remove('loading');
  DOM.refreshText.textContent = 'Refresh';
}

function showInfo(type) {
  DOM.modalTitle.textContent = type === 'verdicts' ? 'Integrity Verdicts' : 'Device Fingerprint';
  DOM.modalText.innerHTML = infoTexts[type];
  DOM.infoModal.classList.add('active');
}

function hideModal() {
  DOM.infoModal.classList.remove('active');
}

document.addEventListener('DOMContentLoaded', () => {
  cacheDOM();
  init();
});
