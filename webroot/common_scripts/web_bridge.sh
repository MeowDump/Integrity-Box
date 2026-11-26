#!/system/bin/sh

# Integrity Box browser WebUI bridge
ROOT=/dev/ibwb
STATE="$ROOT/.state"; TOKEN_FILE="$ROOT/.token"; PIDFILE="$ROOT/.pid"; WATCHFILE="$ROOT/.watch"
MAX_AGE=600; IDLE=600
if [ "$1" = --stop ]; then
  for f in "$ROOT/.watch" "$ROOT/.pid"; do
    [ -r "$f" ] || continue
    p=$(cat "$f" 2>/dev/null)
    case "$p" in ''|*[!0-9]*) continue;; esac
    if [ -r "/proc/$p/cmdline" ]; then
      c=$(tr '\000' ' ' < "/proc/$p/cmdline" 2>/dev/null)
      case "$c" in *"$ROOT"*|*ib_webbridge.sh*) kill "$p" 2>/dev/null;; esac
    fi
  done
  rm -rf "$ROOT"
  echo ' ✦ Integrity Box Web Bridge stopped.'
  exit 0
fi
if [ "$1" = --watchdog ]; then
  SERVER="$2"; PORT="$3"; DEADLINE="$4"
  while :; do
    sleep 30
    [ -r "$STATE" ] || break
    read P D A < "$STATE"
    NOW=$(date +%s)
    case "$P:$D:$A" in *[!0-9:]*|::*|*::*) break;; esac
    [ "$P" = "$PORT" ] && [ "$D" = "$DEADLINE" ] && [ "$NOW" -le "$D" ] && [ $((NOW-A)) -le "$IDLE" ] || break
    kill -0 "$SERVER" 2>/dev/null || break
  done
  kill "$SERVER" 2>/dev/null; sleep 1; kill -9 "$SERVER" 2>/dev/null
  rm -rf "$ROOT"
  exit 0
fi
say(){ echo "$*"; }
find_bb(){ for x in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /system/bin/busybox; do [ -x "$x" ] && { echo "$x"; return; }; done; command -v busybox 2>/dev/null; }
BB=$(find_bb); [ -n "$BB" ] || { say ' ✖ BusyBox not found.'; exit 1; }
[ "$(id -u 2>/dev/null)" = 0 ] || { say ' ✖ Run this script as root.'; exit 1; }

IB_ROOT=""
for d in "${0%/*}" /data/adb/modules/integrity_box /data/adb/modules/integrity-box /data/adb/modules/IntegrityBox; do
  [ -f "$d/webroot/index.html" ] && { IB_ROOT="$d"; break; }
done
[ -n "$IB_ROOT" ] || { say ' ✖ Integrity Box webroot/index.html was not found.'; exit 1; }
SRC="$IB_ROOT/webroot"

stop_pid(){ f="$1"; [ -r "$f" ] || return; p=$(cat "$f" 2>/dev/null); case "$p" in ''|*[!0-9]*) rm -f "$f"; return;; esac; if [ -r "/proc/$p/cmdline" ]; then c=$(tr '\000' ' ' < "/proc/$p/cmdline" 2>/dev/null); case "$c" in *"$ROOT"*|*ib_webbridge.sh*) kill "$p" 2>/dev/null; sleep 1; kill -9 "$p" 2>/dev/null;; esac; fi; rm -f "$f"; }
mkdir -p "$ROOT" || exit 1
stop_pid "$PIDFILE"; stop_pid "$WATCHFILE"
rm -rf "$ROOT"; mkdir -p "$ROOT/cgi-bin" || exit 1

# Never expose symlinks from the module's WebUI
if find "$SRC" -type l 2>/dev/null | grep -q .; then say ' ✖ WebUI contains symlinks; refusing to serve it.'; rm -rf "$ROOT"; exit 1; fi
cp -R "$SRC/." "$ROOT/" || { say ' ✖ Could not stage Integrity Box WebUI.'; rm -rf "$ROOT"; exit 1; }
if [ -d "$IB_ROOT/toolkit" ]; then
  if find "$IB_ROOT/toolkit" -type l 2>/dev/null | grep -q .; then say ' ✖ Toolkit contains symlinks; refusing to serve it.'; rm -rf "$ROOT"; exit 1; fi
  mkdir -p "$ROOT/toolkit"; cp -R "$IB_ROOT/toolkit/." "$ROOT/toolkit/" 2>/dev/null
fi

KSU_DIR="$ROOT/KSU"
[ -f "$KSU_DIR/ksu-bridge.js" ] && [ -f "$KSU_DIR/app_labels.json" ] || {
  say ' ✖ Missing webroot/KSU/ksu-bridge.js or webroot/KSU/app_labels.json.'
  say ' ✖ Place both files in the Integrity Box webroot/KSU directory.'
  rm -rf "$ROOT"
  exit 1
}

chmod 644 "$KSU_DIR/ksu-bridge.js" "$KSU_DIR/app_labels.json"

cat > "$ROOT/cgi-bin/ibwb-exec" <<'IBWB_EXEC_END'
#!/system/bin/sh
ROOT=/dev/ibwb
TOKEN_FILE="$ROOT/.token"
STATE_FILE="$ROOT/.state"
reply() {
  status="$1"; msg="$2"
  printf 'Status: %s\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'
  printf '{"code":1,"stdout":"","stderr":"%s"}\n' "$msg"
  exit 0
}
[ "$REQUEST_METHOD" = POST ] || reply '405 Method Not Allowed' 'POST required'
[ -r "$TOKEN_FILE" ] && [ -r "$STATE_FILE" ] || reply '403 Forbidden' 'Session unavailable'
EXPECTED=$(cat "$TOKEN_FILE" 2>/dev/null)
INCOMING=${HTTP_X_IB_TOKEN-}
[ "${#EXPECTED}" -eq 64 ] && [ -n "$INCOMING" ] && [ "$INCOMING" = "$EXPECTED" ] || reply '403 Forbidden' 'Invalid bridge token'

# BusyBox versions differ in CGI environment variables. Derive the port from Host.
case "$HTTP_HOST" in 127.0.0.1:[0-9]*) ;; *) reply '403 Forbidden' 'Invalid host' ;; esac
HOST_PORT=${HTTP_HOST##*:}
case "$HOST_PORT" in ''|*[!0-9]*) reply '403 Forbidden' 'Invalid host port' ;; esac
# Origin is normally present for browser POSTs. If present, it must match exactly.
[ -z "${HTTP_ORIGIN-}" ] || [ "$HTTP_ORIGIN" = "http://$HTTP_HOST" ] || reply '403 Forbidden' 'Invalid origin'

read SESSION_PORT DEADLINE LAST_ACTIVITY < "$STATE_FILE"
case "$SESSION_PORT:$DEADLINE:$LAST_ACTIVITY" in *[!0-9:]*|::*|*::*) reply '403 Forbidden' 'Invalid session state' ;; esac
NOW=$(date +%s)
[ "$SESSION_PORT" = "$HOST_PORT" ] && [ "$NOW" -le "$DEADLINE" ] && [ $((NOW-LAST_ACTIVITY)) -le 600 ] || reply '403 Forbidden' 'Session expired'

case "$CONTENT_LENGTH" in ''|*[!0-9]*) reply '411 Length Required' 'Content-Length required' ;; esac
[ "$CONTENT_LENGTH" -le 1048576 ] || reply '413 Payload Too Large' 'Command payload exceeds 1 MiB'

# Resolve basic utilities. The HTTP daemon is explicitly configured to run CGI as root.
BB=""
for candidate in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /system/bin/busybox; do
  if [ -x "$candidate" ]; then BB="$candidate"; break; fi
done
[ -n "$BB" ] || BB=$(command -v busybox 2>/dev/null)
[ -n "$BB" ] || reply '500 Internal Server Error' 'BusyBox unavailable'
[ "$(id -u 2>/dev/null)" = 0 ] || reply '500 Internal Server Error' 'CGI is not running as root; restart bridge with httpd -u root'

umask 077
TMP_DIR=$("$BB" mktemp -d /data/local/tmp/ibwb.XXXXXX 2>/dev/null)
[ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] || reply '500 Internal Server Error' 'Cannot create private temporary directory'
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
CMD_FILE="$TMP_DIR/cmd"
OUT_FILE="$TMP_DIR/out"
ERR_FILE="$TMP_DIR/err"
"$BB" head -c "$CONTENT_LENGTH" > "$CMD_FILE" 2>/dev/null || reply '400 Bad Request' 'Unable to read command body'
: > "$OUT_FILE"; : > "$ERR_FILE"
"$BB" sh "$CMD_FILE" > "$OUT_FILE" 2> "$ERR_FILE"
EXIT_CODE=$?

# Refresh idle time after the command completes.
STATE_TMP="$STATE_FILE.tmp.$$"
printf '%s %s %s\n' "$SESSION_PORT" "$DEADLINE" "$NOW" > "$STATE_TMP" && mv -f "$STATE_TMP" "$STATE_FILE"

json_escape_file() {
  "$BB" od -An -v -tu1 "$1" 2>/dev/null | LC_ALL=C "$BB" awk '{
    for (i=1; i<=NF; i++) {
      n=$i+0
      if (n==34 || n==92) printf "\\%c", n
      else if (n==8) printf "\\b"
      else if (n==9) printf "\\t"
      else if (n==10) printf "\\n"
      else if (n==12) printf "\\f"
      else if (n==13) printf "\\r"
      else if (n<32) printf "\\u%04x", n
      else printf "%c", n
    }
  }'
}
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store, no-cache, must-revalidate\r\nConnection: close\r\n\r\n'
printf '{"code":%s,"stdout":"' "$EXIT_CODE"
json_escape_file "$OUT_FILE"
printf '","stderr":"'
json_escape_file "$ERR_FILE"
printf '"}\n'
IBWB_EXEC_END
cat > "$ROOT/cgi-bin/ibwb-ping" <<'IBWB_PING_END'
#!/system/bin/sh
ROOT=/dev/ibwb
TOKEN=$(cat "$ROOT/.token" 2>/dev/null)
STATE="$ROOT/.state"
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'
[ "$REQUEST_METHOD" = GET ] && [ -n "$TOKEN" ] && [ "$HTTP_X_IB_TOKEN" = "$TOKEN" ] || { printf '{"status":"denied"}\n'; exit 0; }
case "$HTTP_HOST" in 127.0.0.1:[0-9]*) ;; *) printf '{"status":"denied"}\n'; exit 0 ;; esac
HOST_PORT=${HTTP_HOST##*:}
case "$HOST_PORT" in ''|*[!0-9]*) printf '{"status":"denied"}\n'; exit 0 ;; esac
[ -z "${HTTP_ORIGIN-}" ] || [ "$HTTP_ORIGIN" = "http://$HTTP_HOST" ] || { printf '{"status":"denied"}\n'; exit 0; }
[ -r "$STATE" ] || { printf '{"status":"inactive"}\n'; exit 0; }
read P D A < "$STATE"; NOW=$(date +%s)
case "$P:$D:$A" in *[!0-9:]*|::*|*::*) printf '{"status":"denied"}\n'; exit 0 ;; esac
[ "$P" = "$HOST_PORT" ] && [ "$NOW" -le "$D" ] && [ $((NOW-A)) -le 600 ] || { printf '{"status":"expired"}\n'; exit 0; }
X="$STATE.tmp.$$"
printf '%s %s %s\n' "$P" "$D" "$NOW" > "$X" && mv -f "$X" "$STATE"
printf '{"status":"alive"}\n'
IBWB_PING_END
cat > "$ROOT/cgi-bin/ibwb-check" <<'IBWB_CHECK_END'
#!/system/bin/sh
ROOT=/dev/ibwb
TOKEN=$(cat "$ROOT/.token" 2>/dev/null)
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'
[ "$REQUEST_METHOD" = GET ] && [ -n "$TOKEN" ] && [ "$HTTP_X_IB_TOKEN" = "$TOKEN" ] || { printf '{"ok":false,"error":"authentication failed"}\n'; exit 0; }
UID_NOW=$(id -u 2>/dev/null)
BB=""
for X in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /system/bin/busybox; do [ -x "$X" ] && { BB="$X"; break; }; done
[ -n "$BB" ] || BB=$(command -v busybox 2>/dev/null)
case "$HTTP_HOST" in 127.0.0.1:[0-9]*) PORT_NOW=${HTTP_HOST##*:} ;; *) PORT_NOW="" ;; esac
STATE_OK=0; TOKEN_OK=0
[ -r "$ROOT/.state" ] && STATE_OK=1
[ -r "$ROOT/.token" ] && TOKEN_OK=1
ROOT_OK=false; [ "$UID_NOW" = 0 ] && ROOT_OK=true
printf '{"ok":%s,"uid":"%s","root":%s,"host":"%s","origin":"%s","port":"%s","state":%s,"token":%s,"busybox":"%s"}\n' \
  "$ROOT_OK" "$UID_NOW" "$ROOT_OK" "$HTTP_HOST" "$HTTP_ORIGIN" "$PORT_NOW" "$STATE_OK" "$TOKEN_OK" "$BB"
IBWB_CHECK_END

chmod 755 "$ROOT/cgi-bin/ibwb-exec" "$ROOT/cgi-bin/ibwb-ping" "$ROOT/cgi-bin/ibwb-check"
# Inject only into the staged copy
find "$ROOT" -type f -name '*.html' 2>/dev/null | while IFS= read -r h; do
  if grep -qi '<head[^>]*>' "$h" 2>/dev/null; then
    sed -i 's|<head[^>]*>|&<script src="/KSU/ksu-bridge.js"></script>|I' "$h" 2>/dev/null
  elif grep -qi '<html[^>]*>' "$h" 2>/dev/null; then
    sed -i 's|<html[^>]*>|&<head><script src="/KSU/ksu-bridge.js"></script></head>|I' "$h" 2>/dev/null
  fi
done

# Cryptographically random per-session
[ -r /dev/urandom ] || { say ' ✖ Secure random source unavailable.'; rm -rf "$ROOT"; exit 1; }
TOKEN=$(od -An -N32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
[ "${#TOKEN}" -eq 64 ] || { say ' ✖ Token generation failed.'; rm -rf "$ROOT"; exit 1; }
printf '%s' "$TOKEN" > "$TOKEN_FILE"; chmod 600 "$TOKEN_FILE"

# Pick a free loopback port.
PORT=""; n=0
while [ "$n" -lt 40 ]; do
  v=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' '); case "$v" in ''|*[!0-9]*) v=$(date +%s);; esac
  p=$((14000 + v % 30000)); hx=$(printf '%04X' "$p")
  if ! grep -qi ":$hx " /proc/net/tcp /proc/net/tcp6 2>/dev/null; then PORT=$p; break; fi
  n=$((n+1))
done
[ -n "$PORT" ] || { say ' ✖ No free localhost port found.'; rm -rf "$ROOT"; exit 1; }
NOW=$(date +%s); DEADLINE=$((NOW+MAX_AGE)); printf '%s %s %s\n' "$PORT" "$DEADLINE" "$NOW" > "$STATE"
"$BB" httpd -f -u root -h "$ROOT" -p "127.0.0.1:$PORT" >/dev/null 2>&1 & SERVER=$!
printf '%s\n' "$SERVER" > "$PIDFILE"
sleep 1
if ! kill -0 "$SERVER" 2>/dev/null; then say ' ✖ Local HTTP server failed to start.'; rm -rf "$ROOT"; exit 1; fi

# Watchdog
"$0" --watchdog "$SERVER" "$PORT" "$DEADLINE" >/dev/null 2>&1 & WATCH=$!
printf '%s\n' "$WATCH" > "$WATCHFILE"
am start -a android.intent.action.VIEW -d "http://127.0.0.1:$PORT/#$TOKEN" >/dev/null 2>&1
say ' ✦ Integrity Box WebUI opened in your browser.'
say " ✦ http://127.0.0.1:$PORT/"
say ' ✦ Session limit: 10 minutes; idle timeout: 10 minutes.'
exit 0
