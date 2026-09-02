#!/usr/bin/env python3
"""
Integrity-Box WebUI preview server.

Serves webroot/ at http://localhost:8000 with a MOCKED ksu.exec bridge so every
page renders and interacts on a desktop browser. Shell commands are faked:
file-existence checks read a mirror directory (/tmp/ib-preview-fs), everything
else returns canned plausible output. No device needed.

Usage:  python3 tests/preview_server.py [port]
Open:   http://localhost:8000/
"""

import http.server
import json
import os
import re
import socketserver
import sys
import threading
import time
import urllib.parse

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "webroot")
FS_MIRROR = "/tmp/ib-preview-fs"  # flag files / data-adb mirror
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000

os.makedirs(FS_MIRROR, exist_ok=True)
os.makedirs(os.path.join(FS_MIRROR, "data/adb/Box-Brain"), exist_ok=True)
os.makedirs(os.path.join(FS_MIRROR, "data/adb/modules/playintegrityfix"), exist_ok=True)

# --------------------------------------------------------------------- mock sh
def mock_shell(cmd):
    cmd = cmd.strip()

    def exists(p):
        if p.startswith("/data/adb") or p.startswith("/sdcard"):
            mirror = FS_MIRROR + p
            return os.path.exists(mirror)
        return False

    def read(p):
        mirror = FS_MIRROR + p if p.startswith("/data/adb") or p.startswith("/sdcard") else p
        try:
            with open(mirror) as f:
                return f.read()
        except OSError:
            return None

    # [ -f path ] && echo 1 || echo 0
    m = re.match(r"\[\s*-f\s+(\S+)\s*\]\s*&&\s*echo\s+1\s*\|\|\s*echo\s+0", cmd)
    if m:
        return "1" if exists(m.group(1).strip('"')) else "0"

    # [ -f path ] && cat path || echo ''   (and similar)
    m = re.match(r"\[\s*-f\s+(\S+)\s*\]\s*&&\s*cat\s+(\S+)", cmd)
    if m:
        data = read(m.group(1).strip('"'))
        return data if data is not None else ""

    # pm list packages
    if cmd.startswith("pm list packages") or cmd.startswith("cmd package list"):
        return "\n".join([
            "package:com.android.vending",
            "package:com.google.android.gms",
            "package:com.google.android.gsf",
            "package:org.mozilla.firefox",
            "package:com.spotify.music",
            "package:com.discord",
            "package:com.whatsapp",
        ])

    # getprop
    if cmd.startswith("getprop"):
        if "security_patch" in cmd:
            return "2026-08-05"
        if "ro.product.system.brand" in cmd or "ro.product.brand" in cmd:
            return "google"
        if "sys.boot_completed" in cmd:
            return "1"
        return ""

    # getenforce
    if cmd.startswith("getenforce"):
        return "Enforcing"

    # dumpsys package version
    if cmd.startswith("dumpsys package"):
        return "versionName=42.0.0\nversionCode=42000000"

    # grep -m1 '^MODEL=' custom.pif.prop style reads
    m = re.search(r"grep\s+-m1\s+\S+\s+(\S+)", cmd)
    if m and "grep" in cmd:
        data = read("/data/adb/modules/playintegrityfix/custom.pif.prop")
        if data:
            for line in data.splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    if k == "MODEL":
                        return v
        return "Pixel 9 Pro"

    # generic cat
    m = re.match(r"cat\s+(\S+)", cmd)
    if m:
        data = read(m.group(1).strip('"').strip("'"))
        return data if data is not None else ""

    # mkdir/touch/rm/sed/echo writes — apply to mirror
    if cmd.startswith(("touch ", "mkdir -p ", "mkdir ")) or " > " in cmd or " >> " in cmd or cmd.startswith(("rm ", "rm -f ", "rm -rf ")):
        try:
            for part in re.finditer(r"(?:touch|mkdir(?:\s+-p)?)\s+(\S+)", cmd):
                p = part.group(1).strip('"').strip("'")
                if p.startswith(("/data/adb", "/sdcard")):
                    mp = FS_MIRROR + p
                    os.makedirs(os.path.dirname(mp), exist_ok=True)
                    if part.group(0).startswith("touch"):
                        open(mp, "a").close()
                    else:
                        os.makedirs(mp, exist_ok=True)
            for part in re.finditer(r"rm\s+(?:-f\s+|-rf\s+|)(\S+)", cmd):
                p = part.group(1).strip('"').strip("'")
                if p.startswith(("/data/adb", "/sdcard")) and p != "/data/adb":
                    import shutil
                    shutil.rmtree(FS_MIRROR + p, ignore_errors=True)
                    try:
                        os.remove(FS_MIRROR + p)
                    except OSError:
                        pass
            m = re.search(r"echo\s+(.+?)\s*>\s*(\S+)", cmd)
            if m:
                p = m.group(2).strip('"').strip("'")
                if p.startswith(("/data/adb", "/sdcard")):
                    mp = FS_MIRROR + p
                    os.makedirs(os.path.dirname(mp), exist_ok=True)
                    with open(mp, "w") as f:
                        f.write(m.group(1).strip('"'))
        except Exception:
            pass
        return ""

    # reboot / am start / settings — just succeed silently
    if cmd.startswith(("am ", "settings ", "su ", "nohup ", "sh ", "reboot", "pkill", "kill")):
        return ""

    return ""


# ---------------------------------------------------------------------- server
class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def log_message(self, fmt, *args):
        pass  # quiet

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


class KSUInjector(threading.Thread):
    """Nothing to inject server-side; the bridge mock lives in the served
    preview.html wrapper (iframe) — kept simple: pages call ksu.exec which
    preview.html defines before loading the real page."""


PREVIEW_WRAPPER = """<!doctype html>
<html><head><meta charset="utf-8"><title>Integrity Box — Preview</title>
<style>
body{margin:0;font-family:system-ui;background:#0d0e14;color:#e7e9ee;display:flex;flex-direction:column;height:100vh}
header{padding:10px 16px;font-size:13px;color:#8b93a7;border-bottom:1px solid #22252f;background:#14161e;display:flex;gap:14px;align-items:center}
header b{color:#e7e9ee}
select{background:#22252f;color:#e7e9ee;border:1px solid #333847;border-radius:6px;padding:4px 8px;font-size:13px}
iframe{flex:1;border:0;width:100%;background:#15171f}
</style></head><body>
<header><b>Integrity Box WebUI preview</b>
<span>ksu.exec is mocked — shell output is fake</span>
<select id="nav"></select>
</header>
<iframe id="frame" src="index.html"></iframe>
<script>
// ---- mock KSU bridge + toast ------------------------------------------
let CB = 0;
window.ksu = {
  exec: function(cmd, _, cb) {
    const id = (typeof cb === "function") ? ("mock_cb_" + (++CB)) : cb;
    if (typeof cb !== "function" && cb) { window[cb] = (c,o,e)=>{}; }
    const t = this;
    fetch("/__exec?cmd=" + encodeURIComponent(cmd))
      .then(r => r.text())
      .then(out => {
        if (typeof cb === "function") cb(0, out, "");
        else if (window[cb]) window[cb](0, out, "");
      })
      .catch(() => { if (typeof cb === "function") cb(1, "", "mock error"); });
    return "";
  },
  toast: function(m) { console.log("[toast] " + m); }
};
window.toast = (m) => console.log("[toast] " + m);

// ---- page selector -----------------------------------------------------
const PAGES = ["", "About/", "Assistant/", "BeastMode/", "BootHash/", "Certified/",
  "Control/", "CustomPIF/", "Downloader/", "Flags/", "HideMyFiles/",
  "KeyboxLoader/", "Patch/", "Pilot/", "Pixel/", "PlayIntegrityFork/",
  "Profile/", "PropSpoofer/", "Report/", "Risky/", "Spoofing/", "Status/",
  "Support/", "TEEsimulator/", "TrickyStore/"];
const nav = document.getElementById("nav");
PAGES.forEach(p => {
  const o = document.createElement("option");
  o.value = p || "index.html";
  o.textContent = p ? p.replace("/","") : "Dashboard";
  nav.appendChild(o);
});
nav.onchange = () => document.getElementById("frame").src = nav.value;
</script></body></html>
"""


# Demo translation packs — the real packs are runtime-provisioned (empty
# TRANSLATIONS/ in-repo, filled by UpdateTranslation.sh). The preview
# synthesizes a few languages so the language dropdown visibly works.
DEMO_I18N = {
    "es": {
        "Play Integrity Box": "Play Integrity Box",
        "Hated By Many, Defeated By None": "Odiado por muchos, derrotado por nadie",
        "Integrity Hub": "Centro de Integridad",
        "Spoofing Hub": "Centro de Suplantación",
        "Meow Hub": "Centro Meow",
        "Community & Support": "Comunidad y Soporte",
        "Manage Targets": "Gestionar objetivos",
        "Repair Mode": "Modo reparación",
        "Module Settings": "Ajustes del módulo",
        "Set Profile": "Elegir perfil",
        "Per App Spoofing": "Suplantación por app",
        "Play Integrity": "Play Integrity",
        "Prop Spoofing": "Suplantación de props",
        "ROM Spoofing": "Suplantación de ROM",
        "Auto Pilot": "Piloto automático",
        "Advanced Mode": "Modo avanzado",
        "Fix Boot Hash": "Arreglar hash de arranque",
        "Hide Sus Files": "Ocultar archivos sospechosos",
        "Report a Problem": "Informar de un problema",
        "Ask Assistant": "Preguntar al asistente",
        "Support the Developer": "Apoyar al desarrollador",
        "Downloader": "Descargador",
    },
    "hi": {
        "Play Integrity Box": "Play Integrity Box",
        "Hated By Many, Defeated By None": "कईयों द्वारा नफ़रत, किसी द्वारा पराजित नहीं",
        "Integrity Hub": "Integrity Hub",
        "Spoofing Hub": "Spoofing Hub",
        "Meow Hub": "Meow Hub",
        "Community & Support": "कम्युनिटी और सपोर्ट",
        "Manage Targets": "Targets संभालें",
        "Repair Mode": "Repair Mode",
        "Module Settings": "Module Settings",
        "Set Profile": "Profile चुनें",
        "Per App Spoofing": "Per App Spoofing",
        "Report a Problem": "समस्या बताएं",
        "Ask Assistant": "Assistant से पूछें",
        "Support the Developer": "Developer को सपोर्ट करें",
        "Downloader": "Downloader",
    },
    "ru": {
        "Play Integrity Box": "Play Integrity Box",
        "Hated By Many, Defeated By None": "Ненавидим многими, не побеждён никем",
        "Integrity Hub": "Центр Integrity",
        "Spoofing Hub": "Центр подмены",
        "Meow Hub": "Центр Meow",
        "Community & Support": "Сообщество и поддержка",
        "Manage Targets": "Управление целями",
        "Repair Mode": "Режим ремонта",
        "Module Settings": "Настройки модуля",
        "Set Profile": "Выбрать профиль",
        "Per App Spoofing": "Подмена по приложениям",
        "Prop Spoofing": "Подмена свойств",
        "ROM Spoofing": "Подмена ROM",
        "Auto Pilot": "Автопилот",
        "Advanced Mode": "Расширенный режим",
        "Report a Problem": "Сообщить о проблеме",
        "Ask Assistant": "Спросить ассистента",
        "Support the Developer": "Поддержать разработчика",
        "Downloader": "Загрузчик",
    },
}

def synth_lang_js(lang):
    """Build a translation pack in the same shape the pages expect:
    it must define window.i18nBoot() which the page calls after load."""
    dictionary = DEMO_I18N.get(lang, {})
    payload = json.dumps(dictionary, ensure_ascii=False)
    return f"""/* Preview demo pack for '{lang}' (real packs are runtime-provisioned) */
window.IB_TRANSLATIONS = {payload};
window.i18nBoot = function () {{
  var T = window.IB_TRANSLATIONS || {{}};
  function apply(root) {{
    if (!root) return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    var node;
    while ((node = walker.nextNode())) {{
      var raw = node.nodeValue.trim();
      if (T[raw]) node.nodeValue = node.nodeValue.replace(raw, T[raw]);
    }}
  }}
  apply(document.body);
  setTimeout(function () {{
    var frame = document.getElementById('active-iframe');
    if (frame && frame.contentWindow && frame.contentWindow.document)
      apply(frame.contentWindow.document.body);
  }}, 300);
}};
i18nBoot();
"""


class PreviewHandler(Handler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/__exec":
            q = urllib.parse.parse_qs(parsed.query)
            cmd = q.get("cmd", [""])[0]
            out = mock_shell(cmd)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(out.encode())
            return
        if parsed.path == "/" or parsed.path == "/preview.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(PREVIEW_WRAPPER.encode())
            return
        # Preview-only translation packs: TRANSLATIONS/ is empty in-repo
        # (real packs are downloaded at runtime by UpdateTranslation.sh).
        # The preview synthesizes meow.js + demo languages so the language
        # dropdown is visibly testable.
        if parsed.path in ("/TRANSLATIONS/meow.js",):
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript")
            self.end_headers()
            self.wfile.write(b"/* preview stub: real meow.js is runtime-provisioned */\n"
                             b"window.i18nBoot = window.i18nBoot || function() {};\n")
            return
        m = re.match(r"^/TRANSLATIONS/([a-zA-Z_]+)\.js$", parsed.path)
        if m:
            lang = m.group(1)
            body = synth_lang_js(lang).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()


socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), PreviewHandler) as httpd:
    print(f"Preview server running: http://localhost:{PORT}/")
    print(f"  webroot: {os.path.abspath(ROOT)}")
    print(f"  mocked fs: {FS_MIRROR} (flag files persist between runs)")
    print("  Ctrl+C to stop")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
