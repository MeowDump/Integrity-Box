#!/system/bin/sh

CHECK_INTERVAL=900
TIMEOUT=15
RETRIES=3
LOG_MAX_BYTES=524288
MAX_LOGS=2
MODPATH=/data/adb/modules/integrity-box
BOX_BRAIN=/data/adb/Box-Brain
AP_DIR="$BOX_BRAIN/AutoPilot"
STATE_FILE="$AP_DIR/emergency_state"
AP_LOG="$AP_DIR/emergency-monitor.log"
LOCK_DIR="$AP_DIR/emergency-monitor.lock"
TMP_JSON="$AP_DIR/markers.tmp"
TMP_CANDIDATES="$AP_DIR/candidates.tmp"
RAW_BASE=https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/auto-pilot
API_URL=https://api.github.com/repos/MeowDump/Integrity-Box/contents/auto-pilot?ref=main

mkdir -p "$AP_DIR" 2>/dev/null || { /system/bin/log -t AutoPilot "ERROR: cannot create $AP_DIR" 2>/dev/null; exit 1; }
: >> "$AP_LOG" 2>/dev/null || { /system/bin/log -t AutoPilot "ERROR: cannot open $AP_LOG" 2>/dev/null; exit 1; }

rotate_autopilot_log() {
    size=$(wc -c < "$AP_LOG" 2>/dev/null | tr -d ' ')
    [ -n "$size" ] && [ "$size" -ge "$LOG_MAX_BYTES" ] || return 0
    rm -f "$AP_LOG.$MAX_LOGS"
    i=$((MAX_LOGS - 1))
    while [ "$i" -ge 1 ]; do
        [ -f "$AP_LOG.$i" ] && mv -f "$AP_LOG.$i" "$AP_LOG.$((i + 1))"
        i=$((i - 1))
    done
    mv -f "$AP_LOG" "$AP_LOG.1"
    : >> "$AP_LOG"
}

ap_log() {
    rotate_autopilot_log
    msg="$*"
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$msg" >> "$AP_LOG" 2>/dev/null || /system/bin/log -t AutoPilot "LOG WRITE FAILED: $msg" 2>/dev/null
    /system/bin/log -t AutoPilot "$msg" 2>/dev/null
}

if [ "${AUTOPILOT_CHILD:-0}" != 1 ]; then
    ap_log "Background launch requested; script=$0"
    nohup env AUTOPILOT_CHILD=1 sh "$0" >/dev/null 2>&1 &
    ap_log "Background process requested; child=$!"
    exit 0
fi

ap_log "Child initialization started; PID=$$; interval=${CHECK_INTERVAL}s"
COMMON_FUNC="$MODPATH/common_func.sh"
if [ ! -r "$COMMON_FUNC" ]; then ap_log "FATAL: common_func.sh unavailable: $COMMON_FUNC"; exit 1; fi
. "$COMMON_FUNC" || { ap_log "FATAL: common_func.sh sourcing failed"; exit 1; }
if ! command -v detect_downloader >/dev/null 2>&1; then ap_log "FATAL: detect_downloader missing"; exit 1; fi
if ! command -v wait_for_network >/dev/null 2>&1; then ap_log "FATAL: wait_for_network missing"; exit 1; fi
detect_downloader
ap_log "Common library sourced; DL_MODE=${DL_MODE:-unset}; DOWNLOADER=${DOWNLOADER:-unset}"
if [ -z "$DL_MODE" ] || [ -z "$DOWNLOADER" ]; then ap_log "FATAL: downloader detection failed"; exit 1; fi

cleanup() {
    ap_log "Termination signal received; cleanup started"
    rm -f "$TMP_JSON" "$TMP_CANDIDATES"
    if [ -f "$LOCK_DIR/pid" ] && [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then rm -f "$LOCK_DIR/pid"; rmdir "$LOCK_DIR" 2>/dev/null; fi
    ap_log "Cleanup complete; daemon exiting"
    exit 0
}
trap cleanup INT TERM HUP

if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid" || { ap_log "FATAL: failed writing PID lock"; exit 1; }
    ap_log "Lock acquired; PID=$$"
else
    old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then ap_log "Existing daemon detected PID=$old_pid; exiting"; exit 0; fi
    ap_log "Stale/malformed lock detected; attempting reclaim"
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || { ap_log "FATAL: lock reclaim failed"; exit 1; }
    mkdir "$LOCK_DIR" 2>/dev/null || { ap_log "FATAL: lock reacquisition failed"; exit 1; }
    printf '%s\n' "$$" > "$LOCK_DIR/pid" || { ap_log "FATAL: PID write failed after lock reclaim"; exit 1; }
    ap_log "Lock reclaimed; PID=$$"
fi

marker_value() {
    s="$1" n=0
    while [ -n "$s" ]; do
        c=$(printf '%s' "$s" | cut -c1)
        case "$c" in A) v=1;; B) v=2;; C) v=3;; D) v=4;; E) v=5;; F) v=6;; G) v=7;; H) v=8;; I) v=9;; J) v=10;; K) v=11;; L) v=12;; M) v=13;; N) v=14;; O) v=15;; P) v=16;; Q) v=17;; R) v=18;; S) v=19;; T) v=20;; U) v=21;; V) v=22;; W) v=23;; X) v=24;; Y) v=25;; Z) v=26;; *) return 1;; esac
        n=$((n * 26 + v)); s=$(printf '%s' "$s" | cut -c2-)
    done
    printf '%s' "$n"
}

http_get_to_file() {
    url="$1" outfile="$2" attempt=1
    while [ "$attempt" -le "$RETRIES" ]; do
        ap_log "HTTP fetch attempt=$attempt/$RETRIES url=$url"
        rm -f "$outfile"
        case "$DL_MODE" in
            curl) "$DOWNLOADER" -fsSL --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" -H 'Accept: application/vnd.github+json' "$url" -o "$outfile" >> "$AP_LOG" 2>&1; rc=$? ;;
            wget) "$DOWNLOADER" -q --timeout="$TIMEOUT" --tries=1 "$url" -O "$outfile" >> "$AP_LOG" 2>&1; rc=$? ;;
            busybox) "$DOWNLOADER" wget -q --timeout="$TIMEOUT" "$url" -O "$outfile" >> "$AP_LOG" 2>&1; rc=$? ;;
            toybox) toybox wget -q "$url" -O "$outfile" >> "$AP_LOG" 2>&1; rc=$? ;;
            *) ap_log "ERROR: unsupported DL_MODE=$DL_MODE"; return 1 ;;
        esac
        ap_log "HTTP fetch completed rc=$rc output_size=$(wc -c < "$outfile" 2>/dev/null | tr -d ' ')"
        [ "$rc" -eq 0 ] && [ -s "$outfile" ] && return 0
        attempt=$((attempt + 1)); [ "$attempt" -le "$RETRIES" ] && sleep 2
    done
    return 1
}

raw_verify() {
    marker="$1" url="$RAW_BASE/emergency_$marker"
    ap_log "Raw verification of marker=$marker url=$url"
    case "$DL_MODE" in
        curl)
            code=$("$DOWNLOADER" -sS -I -L --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" -o /dev/null -w '%{http_code}' "$url" 2>>"$AP_LOG")
            rc=$?; ap_log "Raw HEAD result marker=$marker HTTP=${code:-unknown} rc=$rc"
            [ "$rc" -eq 0 ] && [ "$code" = 200 ] ;;
        wget)
            "$DOWNLOADER" -q --spider --timeout="$TIMEOUT" --tries=1 "$url" >> "$AP_LOG" 2>&1; rc=$?; ap_log "Raw spider result marker=$marker rc=$rc"; [ "$rc" -eq 0 ] ;;
        busybox)
            "$DOWNLOADER" wget -q --spider --timeout="$TIMEOUT" "$url" >> "$AP_LOG" 2>&1; rc=$?; ap_log "Raw BusyBox spider result marker=$marker rc=$rc"; [ "$rc" -eq 0 ] ;;
        toybox)
            toybox wget -q --spider "$url" >> "$AP_LOG" 2>&1; rc=$?; ap_log "Raw Toybox spider result marker=$marker rc=$rc"; [ "$rc" -eq 0 ] ;;
    esac
}


report_optins() {
    action_flag="$BOX_BRAIN/auto-action"
    key_flag="$BOX_BRAIN/auto-key"
    action_script="$MODPATH/action.sh"
    key_script="$MODPATH/webroot/common_scripts/key.sh"

    if [ -e "$action_flag" ]; then
        ap_log "Opt-in detected: auto-action exists"
        if [ -f "$action_script" ]; then
            ap_log "Updating configuration via auto action"
            sh "$action_script"
        else
            ap_log "ERROR: action.sh missing; auto-action opt-in cannot be fulfilled"
        fi
    else
        ap_log "auto-action opt-in absent"
    fi

    if [ -e "$key_flag" ]; then
        ap_log "Opt-in detected: auto-key exists"
        if [ -f "$key_script" ]; then
            ap_log "Updating Keybox"
            sh "$key_script"
        else
            ap_log "ERROR: key.sh missing; auto-key opt-in cannot be fulfilled"
        fi
    else
        ap_log "auto-key opt-in absent"
    fi
}

get_remote_highest() {
    ap_log "Fetching GitHub directory listing for marker discovery"
    if ! http_get_to_file "$API_URL" "$TMP_JSON"; then ap_log "ERROR: directory listing request failed"; return 1; fi
    if ! grep -q '"name"' "$TMP_JSON"; then ap_log "ERROR: directory listing does not appear to be JSON"; return 1; fi
    grep -o '"name"[[:space:]]*:[[:space:]]*"emergency_[A-Z][A-Z]*"' "$TMP_JSON" 2>/dev/null | sed 's/.*"emergency_\([A-Z][A-Z]*\)"/\1/' > "$TMP_CANDIDATES"
    ap_log "Candidate marker filenames parsed; count=$(wc -l < "$TMP_CANDIDATES" | tr -d ' ')"
    highest="" highest_num=0
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        num=$(marker_value "$candidate") || { ap_log "Skipping malformed candidate=$candidate"; continue; }
        ap_log "Candidate=$candidate numeric=$num"
        if raw_verify "$candidate"; then
            ap_log "Candidate raw URL verified=$candidate"
            if [ "$num" -gt "$highest_num" ]; then highest="$candidate"; highest_num="$num"; ap_log "Highest marker updated=$highest numeric=$highest_num"; fi
        else
            ap_log "Candidate raw verification failed=$candidate"
        fi
    done < "$TMP_CANDIDATES"
    printf '%s' "$highest"
}

ap_log "Daemon started; PID=$$; interval=${CHECK_INTERVAL}s; raw_base=$RAW_BASE"
cycle=0
while :; do
    cycle=$((cycle + 1)); ap_log "========== Cycle $cycle begin =========="
    ap_log "Network wait starting; max=15s"
    if wait_for_network 15; then
        ap_log "Network wait succeeded"
        remote=$(get_remote_highest); scan_rc=$?
        local_marker=$(cat "$STATE_FILE" 2>/dev/null)
        ap_log "Scan result rc=$scan_rc local=${local_marker:-none} remote=${remote:-none}"
        if [ "$scan_rc" -eq 0 ] && [ -n "$remote" ]; then
            remote_num=$(marker_value "$remote" 2>/dev/null) || remote_num=0
            local_num=0; [ -n "$local_marker" ] && local_num=$(marker_value "$local_marker" 2>/dev/null || echo 0)
            ap_log "Comparison remote_numeric=$remote_num local_numeric=$local_num"
            if [ "$remote_num" -gt "$local_num" ]; then
                flag="$AP_DIR/Integrity-Box-emergency_$remote"
                ap_log "New marker detected; creating flag=$flag"
                if touch "$flag"; then
                    ap_log "Flag created successfully"
                    tmp_state="$STATE_FILE.tmp.$$"
                    if printf '%s\n' "$remote" > "$tmp_state" && mv -f "$tmp_state" "$STATE_FILE"; then ap_log "State updated to=$remote"; else rm -f "$tmp_state"; ap_log "ERROR: state update failed"; fi
                    ap_log "Marker notification recorded"
                    report_optins
                else ap_log "ERROR: flag creation failed for marker=$remote"; fi
            else ap_log "No marker ahead of stored state; no flag created"; fi
        elif [ "$scan_rc" -ne 0 ]; then ap_log "ERROR: scan failed; state unchanged"; else ap_log "No remote emergency markers listed"; fi
    else ap_log "Network wait failed; cycle skipped"; fi
    ap_log "========== Cycle $cycle complete; sleep=${CHECK_INTERVAL}s =========="
    sleep "$CHECK_INTERVAL"
done
