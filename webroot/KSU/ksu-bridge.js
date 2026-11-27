/**
 * Integrity Box - Web Bridge Shim (ksu-bridge.js)
 * Transparently bridges KernelSU/Magisk/APatch WebUI JavaScript API to local Root Shell CGI
 * Enhances standard browsers with native app names and app icon support
 */
(function() {
  'use strict';

  // 1. Token Management & Persistence
  var token = '';
  try {
    if (window.location.hash && window.location.hash.length > 1 && !window.location.hash.startsWith('#ib-iframe-')) {
      token = window.location.hash.replace(/^#/, '').trim();
      localStorage.setItem('ib_bridge_token', token);
      sessionStorage.setItem('ib_bridge_token', token);
    } else {
      token = localStorage.getItem('ib_bridge_token') || sessionStorage.getItem('ib_bridge_token') || '';
    }
  } catch(e) {
    console.warn('[IB Bridge] Storage error:', e);
  }

  // Inherit token from parent window if running inside an iframe
  if (!token && window.parent && window.parent !== window && window.parent.BRIDGE_TOKEN) {
    token = window.parent.BRIDGE_TOKEN;
  }

  window.BRIDGE_TOKEN = token;

  // 2. App Labels & Icon Interception Bridge
  if (!window.APP_LABELS) {
    if (window.parent && window.parent !== window && window.parent.APP_LABELS) {
      window.APP_LABELS = window.parent.APP_LABELS;
    } else if (window.top && window.top !== window && window.top.APP_LABELS) {
      window.APP_LABELS = window.top.APP_LABELS;
    } else {
      try {
        fetch('/KSU/app_labels.json')
          .then(function(r) { return r.json(); })
          .then(function(d) {
            window.APP_LABELS = d;
            fixAppDom();
          })
          .catch(function(){});
      } catch(e) {}
    }
  }

  // Property interceptor on cachedApps for TrickyStore / Bootloader Spoofer
  (function() {
    var _cachedApps = [];
    try {
      Object.defineProperty(window, 'cachedApps', {
        configurable: true,
        enumerable: true,
        get: function() { return _cachedApps; },
        set: function(apps) {
          if (Array.isArray(apps)) {
            var labels = window.APP_LABELS || (window.parent && window.parent.APP_LABELS) || {};
            apps.forEach(function(a) {
              if (a && a.pkg && (!a.label || a.label === a.pkg) && labels[a.pkg]) {
                a.label = labels[a.pkg];
              }
            });
          }
          _cachedApps = apps;
        }
      });
    } catch(e) {}
  })();

  // Icon URL rewrite helper (ksu://icon/<pkg> -> /icons/<pkg>.png)
  function rewriteIconUrl(url) {
    if (typeof url !== 'string') return url;
    if (url.indexOf('ksu://icon/') === 0) {
      var pkg = url.slice(11).trim();
      return '/icons/' + pkg + '.png';
    }
    return url;
  }

  try {
    var origSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value) {
      if ((name === 'src' || name === 'data-src') && typeof value === 'string' && value.indexOf('ksu://icon/') === 0) {
        value = rewriteIconUrl(value);
      }
      return origSetAttribute.call(this, name, value);
    };
  } catch(e) {}

  try {
    var desc = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
    if (desc && desc.set) {
      var origSrcSet = desc.set;
      Object.defineProperty(HTMLImageElement.prototype, 'src', {
        configurable: true,
        enumerable: true,
        get: desc.get,
        set: function(val) {
          return origSrcSet.call(this, rewriteIconUrl(val));
        }
      });
    }
  } catch(e) {}

  // Fallback for missing or unloaded icons
  document.addEventListener('error', function(evt) {
    var t = evt.target;
    if (t && t.tagName === 'IMG' && (t.classList.contains('app-icon') || (t.src && t.src.indexOf('/icons/') !== -1))) {
      t.onerror = null;
      t.src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 24 24" fill="%234da3ff"><path d="M17 1H7c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-2-2-2zm0 18H7V5h10v14z"/></svg>';
      t.style.opacity = '0.6';
    }
  }, true);

  // Active DOM scanner to fix icons and app label elements
  function fixAppDom() {
    try {
      var labels = window.APP_LABELS || (window.parent && window.parent.APP_LABELS) || {};

      // 1. Rewrite any ksu://icon/ images
      var imgs = document.querySelectorAll('img[src*="ksu://icon/"], img[data-src*="ksu://icon/"]');
      for (var i = 0; i < imgs.length; i++) {
        var img = imgs[i];
        var s = img.getAttribute('src');
        if (s && s.indexOf('ksu://icon/') === 0) img.src = rewriteIconUrl(s);
        var ds = img.getAttribute('data-src');
        if (ds && ds.indexOf('ksu://icon/') === 0) {
          img.setAttribute('data-src', rewriteIconUrl(ds));
          if (!img.src || img.src.indexOf('data:') === -1) img.src = rewriteIconUrl(ds);
        }
      }

      // 2. Fix app labels in .item rows
      if (labels && Object.keys(labels).length > 0) {
        var items = document.querySelectorAll('.item[data-pkg]');
        for (var j = 0; j < items.length; j++) {
          var it = items[j];
          var p = it.getAttribute('data-pkg');
          if (p && labels[p]) {
            var nameEl = it.querySelector('.name');
            if (nameEl && (nameEl.textContent === p || !nameEl.dataset.labeled)) {
              nameEl.textContent = labels[p];
              nameEl.dataset.labeled = '1';
              var pkgEl = it.querySelector('.pkg');
              if (!pkgEl && it.querySelector('.info')) {
                var pdiv = document.createElement('div');
                pdiv.className = 'pkg';
                pdiv.textContent = p;
                it.querySelector('.info').appendChild(pdiv);
              }
            }
          }
        }
      }
    } catch(e) {}
  }

  if (typeof MutationObserver !== 'undefined') {
    var domObs = new MutationObserver(function() { fixAppDom(); });
    domObs.observe(document.documentElement, { childList: true, subtree: true });
  }
  window.addEventListener('DOMContentLoaded', fixAppDom);

  // 3. Multi-Scope Callback Dispatcher
  function dispatchCallback(cbName, code, stdout, stderr) {
    if (!cbName) return false;
    if (typeof cbName === 'function') {
      try {
        cbName(code, stdout, stderr);
        return true;
      } catch(e) {
        return false;
      }
    }
    if (typeof cbName !== 'string') return false;
    var found = false;

    // Check current window
    try {
      if (typeof window[cbName] === 'function') {
        window[cbName](code, stdout, stderr);
        found = true;
      }
    } catch(e) {}

    // Check parent window
    try {
      if (window.parent && window.parent !== window && typeof window.parent[cbName] === 'function') {
        window.parent[cbName](code, stdout, stderr);
        found = true;
      }
    } catch(e) {}

    // Check top window
    try {
      if (window.top && window.top !== window && window.top !== window.parent && typeof window.top[cbName] === 'function') {
        window.top[cbName](code, stdout, stderr);
        found = true;
      }
    } catch(e) {}

    // Check any active iframe
    try {
      var iframes = document.querySelectorAll('iframe');
      for (var i = 0; i < iframes.length; i++) {
        var cw = iframes[i].contentWindow;
        if (cw && typeof cw[cbName] === 'function') {
          cw[cbName](code, stdout, stderr);
          found = true;
        }
      }
    } catch(e) {}

    return found;
  }

  // 4. Core Execution Engine
  function enhanceShellStdout(cmd, stdout) {
    if (typeof stdout !== 'string') return stdout;
    if (cmd.indexOf('pm list packages') !== -1 && (cmd.indexOf('echo "$pkg|$label"') !== -1 || cmd.indexOf('$pkg|$label') !== -1)) {
      var labels = window.APP_LABELS || (window.parent && window.parent.APP_LABELS) || {};
      if (Object.keys(labels).length > 0) {
        var lines = stdout.split('\n');
        var mod = false;
        for (var li = 0; li < lines.length; li++) {
          var line = lines[li];
          var pipeIdx = line.indexOf('|');
          if (pipeIdx > 0) {
            var pkgName = line.slice(0, pipeIdx).trim();
            if (labels[pkgName]) {
              lines[li] = pkgName + '|' + labels[pkgName];
              mod = true;
            }
          }
        }
        if (mod) return lines.join('\n');
      }
    }
    return stdout;
  }

  function executeSyncCmd(cmd, effectiveToken) {
    var url = '/cgi-bin/ibwb-exec';
    try {
      var xhr = new XMLHttpRequest();
      xhr.open('POST', url, false); // synchronous XHR for sync callers (Profile, Spoofing, PIF findPropFile)
      xhr.setRequestHeader('Content-Type', 'text/plain; charset=utf-8');
      if (effectiveToken) xhr.setRequestHeader('X-IB-Token', effectiveToken);
      xhr.send(cmd);
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          var data = JSON.parse(xhr.responseText);
          var out = (typeof data.stdout === 'string') ? data.stdout : '';
          if (data.stderr) console.warn('[IB Bridge] Shell stderr:', data.stderr);
          return enhanceShellStdout(cmd, out);
        } catch(e) {
          console.error('[IB Bridge] Invalid CGI response:', xhr.responseText);
          return '';
        }
      }
      console.error('[IB Bridge] Shell request rejected:', xhr.status, xhr.statusText, xhr.responseText);
    } catch(err) {
      console.error('[IB Bridge] Synchronous exec error:', err);
    }
    return '';
  }

  function executeBridgeCmd(cmd, env, callbackName) {
    // KernelSU-compatible overloads: exec(cmd, callback) and exec(cmd, env, callback).
    if (callbackName === undefined && (typeof env === 'function' || typeof env === 'string')) {
      callbackName = env;
      env = {};
    }
    if (!env || typeof env !== 'object') env = {};
    if (!cmd || typeof cmd !== 'string') {
      var err = new Error('Empty shell command');
      dispatchCallback(callbackName, 1, '', err.message);
      return callbackName ? Promise.reject(err) : '';
    }

    var effectiveToken = window.BRIDGE_TOKEN || localStorage.getItem('ib_bridge_token') || '';

    // If no callback is provided, preserve KernelSU's synchronous exec behaviour.
    if (!callbackName || (typeof callbackName !== 'string' && typeof callbackName !== 'function')) {
      if (!effectiveToken) {
        console.error('[IB Bridge] Missing session token. Reopen the WebUI using ib_webbridge.sh.');
        return '';
      }
      return executeSyncCmd(cmd, effectiveToken);
    }
    if (!effectiveToken) {
      var tokenError = new Error('Bridge token is missing. Reopen the WebUI using ib_webbridge.sh.');
      dispatchCallback(callbackName, 1, '', tokenError.message);
      return Promise.reject(tokenError);
    }

    var headers = {
      'Content-Type': 'text/plain; charset=utf-8',
      'X-IB-Token': effectiveToken
    };

    var url = '/cgi-bin/ibwb-exec';

    return fetch(url, {
      method: 'POST',
      headers: headers,
      body: cmd
    })
    .then(function(res) {
      if (!res.ok) {
        throw new Error('Bridge HTTP ' + res.status + ' ' + res.statusText);
      }
      return res.text();
    })
    .then(function(rawText) {
      var data;
      try {
        data = JSON.parse(rawText);
      } catch(parseErr) {
        console.warn('[IB Bridge] Raw response parsing:', parseErr, rawText);
        data = { code: 0, stdout: rawText, stderr: '' };
      }

      var code = (typeof data.code === 'number') ? data.code : 0;
      var stdout = (typeof data.stdout === 'string') ? data.stdout : '';
      var stderr = (typeof data.stderr === 'string') ? data.stderr : '';

      stdout = enhanceShellStdout(cmd, stdout);
      data.stdout = stdout;

      dispatchCallback(callbackName, code, stdout, stderr);

      var resObj = {
        errno: code,
        code: code,
        stdout: stdout,
        stderr: stderr,
        toString: function() { return stdout; },
        valueOf: function() { return stdout; }
      };

      return resObj;
    })
    .catch(function(err) {
      console.error('[IB Bridge] Exec failure:', err);
      dispatchCallback(callbackName, 1, '', err.message || 'Execution failed');
      throw err;
    });
  }

  // 5. Toast Helper
  function showToast(msg) {
    if (typeof window.popup === 'function') {
      try { window.popup(String(msg), 'info'); return; } catch(e) {}
    }
    if (window.parent && typeof window.parent.popup === 'function') {
      try { window.parent.popup(String(msg), 'info'); return; } catch(e) {}
    }
    var t = document.createElement('div');
    t.className = 'ib-bridge-toast';
    t.textContent = msg;
    t.style.position = 'fixed';
    t.style.bottom = '24px';
    t.style.left = '50%';
    t.style.transform = 'translateX(-50%)';
    t.style.background = 'rgba(20, 24, 38, 0.95)';
    t.style.border = '1px solid #4da3ff60';
    t.style.color = '#e6e6e6';
    t.style.padding = '8px 16px';
    t.style.borderRadius = '20px';
    t.style.fontSize = '13px';
    t.style.zIndex = '999999';
    t.style.boxShadow = '0 8px 24px rgba(0,0,0,0.5)';
    t.style.transition = 'opacity 0.3s ease';
    document.body.appendChild(t);
    setTimeout(function() {
      t.style.opacity = '0';
      setTimeout(function() { if (t.parentNode) t.parentNode.removeChild(t); }, 300);
    }, 2500);
  }

  // 6. Fullscreen Helper
  function handleFullScreen(enable) {
    if (enable) {
      if (document.documentElement.requestFullscreen) {
        document.documentElement.requestFullscreen().catch(function(){});
      }
    } else {
      if (document.exitFullscreen) {
        document.exitFullscreen().catch(function(){});
      }
    }
  }

  // 7. Global API Bridge Object
  var bridgeApi = {
    exec: executeBridgeCmd,
    toast: showToast,
    fullScreen: handleFullScreen
  };

  window.ksu = bridgeApi;
  window.kernelsu = bridgeApi;

  // Universal runShell implementation for standalone pages & iframes (e.g. KeyboxLoader)
  var universalRunShell = function(cmd) {
    return new Promise(function(resolve, reject) {
      executeBridgeCmd(cmd, "{}", function(code, stdout, stderr) {
        if (code === 0) {
          resolve(stdout || "");
        } else {
          if (stdout && stdout.trim().length > 0) {
            resolve(stdout);
          } else {
            reject(new Error(stderr || stdout || ("Command failed with code " + code)));
          }
        }
      }).catch(reject);
    });
  };

  window.runShell = universalRunShell;
  window.runShellFromIframe = universalRunShell;

  // Propagate to parent and top if embedded
  try {
    if (window.parent && window.parent !== window) {
      window.parent.ksu = bridgeApi;
      window.parent.kernelsu = bridgeApi;
      window.parent.runShell = universalRunShell;
      window.parent.runShellFromIframe = universalRunShell;
    }
    if (window.top && window.top !== window) {
      window.top.ksu = bridgeApi;
      window.top.kernelsu = bridgeApi;
      window.top.runShell = universalRunShell;
      window.top.runShellFromIframe = universalRunShell;
    }
  } catch(e) {}

  // Propagate downwards into child iframes as they load
  function injectChildIframes() {
    try {
      var iframes = document.querySelectorAll('iframe');
      for (var i = 0; i < iframes.length; i++) {
        var cw = iframes[i].contentWindow;
        if (cw) {
          if (!cw.ksu) cw.ksu = bridgeApi;
          if (!cw.kernelsu) cw.kernelsu = bridgeApi;
          if (!cw.runShell) cw.runShell = universalRunShell;
          if (!cw.runShellFromIframe) cw.runShellFromIframe = universalRunShell;
          if (window.APP_LABELS && !cw.APP_LABELS) {
            cw.APP_LABELS = window.APP_LABELS;
          }
        }
      }
    } catch(e) {}
  }

  injectChildIframes();
  window.addEventListener('DOMContentLoaded', injectChildIframes);
  setInterval(injectChildIframes, 800);

  // Diagnostic endpoint: useful when a browser can render the UI but root calls fail.
  window.IBBridgeCheck = function() {
    var effectiveToken = window.BRIDGE_TOKEN || localStorage.getItem('ib_bridge_token') || '';
    return fetch('/cgi-bin/ibwb-check', {
      method: 'GET',
      cache: 'no-store',
      headers: { 'X-IB-Token': effectiveToken }
    })
    .then(function(r) { return r.json().then(function(data) { return { httpStatus: r.status, data: data }; }); })
    .then(function(result) {
      console.info('[IB Bridge] Backend diagnostic:', result.data);
      if (!result.data || result.data.root !== true) {
        console.error('[IB Bridge] CGI is not running as root. Check BusyBox httpd -u root.');
      }
      return result;
    })
    .catch(function(err) {
      console.error('[IB Bridge] Backend diagnostic failed:', err);
      throw err;
    });
  };
  window.IBBridgeCheck();

  // 8. Session Heartbeat (keeps server alive while tab is open)
  var lastPing = Date.now();
  function sendHeartbeat() {
    var now = Date.now();
    if (now - lastPing < 25000) return;
    lastPing = now;
    var effectiveToken = window.BRIDGE_TOKEN || localStorage.getItem('ib_bridge_token') || '';
    fetch('/cgi-bin/ibwb-ping', {
      method: 'GET',
      headers: { 'X-IB-Token': effectiveToken }
    }).catch(function(){});
  }

  ['click', 'touchstart', 'scroll', 'keydown'].forEach(function(evt) {
    window.addEventListener(evt, sendHeartbeat, { passive: true });
  });
  setInterval(sendHeartbeat, 30000);

  console.log('[IB Bridge] Bridge v1.2 with App Labels & Icons initialized.');
})();
