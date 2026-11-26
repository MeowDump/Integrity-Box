#!/system/bin/sh

CHECK_INTERVAL=900
GITHUB="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/auto-pilot"
GITHUB_LATEST="$GITHUB/latest"
GITHUB_API="https://api.github.com/repos/MeowDump/Integrity-Box/contents/auto-pilot"
BOX_BRAIN="/data/adb/Box-Brain"
MODPATH="/data/adb/modules/integrity-box"

mkdir -p "$BOX_BRAIN/Integrity-Box-Logs" 2>/dev/null
LOG_FILE="$BOX_BRAIN/Integrity-Box-Logs/autorun.log"

log "••••••• AUTORUN START PID: $$ •••••••"

if [ -f "$MODPATH/common_func.sh" ]; then
    . "$MODPATH/common_func.sh"
    log "common_func.sh loaded"
else
    log "FATAL: common_func.sh missing"
    exit 1
fi

writelog() {
    if [[ -z "${_LOG_FILE_INITIALIZED:-}" ]]; then
        : > "$LOG_FILE"
        _LOG_FILE_INITIALIZED=1
    fi

    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    /system/bin/log -t PATCH_OVERRIDE "$1"
}

if [ ! -f "$BOX_BRAIN/autopilot" ]; then
    log "autopilot disabled, exit"
    exit 0
fi

LOCK_DIR="$BOX_BRAIN/autorun.lockdir"

claim_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo $$ > "$LOCK_DIR/pid"
        return 0
    fi
    return 1
}

if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
    log "Lock acquired (fresh)"
else
    log "Lock exists, checking stale..."
    if [ -f "$LOCK_DIR/pid" ]; then
        old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null | tr -dc '0-9')
        if [ -n "$old_pid" ] && [ -d "/proc/$old_pid" ]; then
            if [ -r "/proc/$old_pid/cmdline" ] && grep -q "autorun" "/proc/$old_pid/cmdline" 2>/dev/null; then
                last_beat=$(cat "$BOX_BRAIN/daemon_heartbeat" 2>/dev/null | tr -dc '0-9')
                now=$(date +%s)
                diff=$((now - ${last_beat:-0}))
                if [ "$diff" -lt 180 ]; then
                    log "Already running (PID $old_pid, ${diff}s ago)"
                    exit 0
                else
                    log "Killing stale PID $old_pid"
                    kill -9 "$old_pid" 2>/dev/null
                    sleep 1
                    claim_lock || { log "Cannot claim lock"; exit 1; }
                    log "Lock acquired (stale reclaimed)"
                fi
            else
                claim_lock || { log "Cannot claim lock"; exit 1; }
                log "Lock acquired (foreign process)"
            fi
        else
            claim_lock || { log "Cannot claim lock"; exit 1; }
            log "Lock acquired (dead process)"
        fi
    else
        claim_lock || { log "Cannot claim lock"; exit 1; }
        log "Lock acquired (no pid file)"
    fi
fi

cleanup() {
    log "Stopping daemon"
    rm -rf "$LOCK_DIR" "$BOX_BRAIN/.executing" 2>/dev/null
    exit 0
}

trap cleanup 15 2 1 0 2>/dev/null || true

wakelock_acquire() {
    [ -w "/sys/power/wake_lock" ] && printf "integrity_autorun" > /sys/power/wake_lock 2>/dev/null
}

wakelock_release() {
    [ -w "/sys/power/wake_unlock" ] && printf "integrity_autorun" > /sys/power/wake_unlock 2>/dev/null
}

name_is_newer() {
    # Exit 0 when marker $1 is newer than $2. A longer marker is always newer
    # (AA > Z); at equal length the letters are compared. Without this rule a
    # plain string compare makes "Z" beat "AA".
    local cand="$1"
    local cur="$2"
    case "$cand" in
        [A-Z] | [A-Z][A-Z] | [A-Z][A-Z][A-Z]) : ;;
        *) return 1 ;;
    esac
    [ -z "$cur" ] && return 0
    if [ ${#cand} -ne ${#cur} ]; then
        [ ${#cand} -gt ${#cur} ]
        return $?
    fi
    [ "$cand" \> "$cur" ]
}

get_local_highest() {
    highest=""
    for f in "$BOX_BRAIN"/emergency_[A-Z]*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        letter=${name#emergency_}
        if name_is_newer "$letter" "$highest"; then
            highest="$letter"
        fi
    done
    printf '%s' "$highest"
}

get_script() {
    if [ -f "$BOX_BRAIN/run_action" ] && [ -f "$MODPATH/action.sh" ]; then
        printf '%s' "$MODPATH/action.sh"
    elif [ -f "$MODPATH/webroot/common_scripts/key.sh" ]; then
        printf '%s' "$MODPATH/webroot/common_scripts/key.sh"
    else
        printf ''
    fi
}

check_github() {
    local letter="$1"
    if ! type detect_downloader >/dev/null 2>&1; then
        log "WARNING: detect_downloader not found"
        return 1
    fi
    detect_downloader
    if [ "$DL_MODE" = "curl" ]; then
        code=$(curl -s -I --max-time 15 -o /dev/null -w "%{http_code}" "$GITHUB/emergency_$letter" 2>/dev/null)
        [ "$code" = "200" ]
    elif [ "$DL_MODE" = "wget" ]; then
        wget -q --spider --timeout=15 --tries=1 "$GITHUB/emergency_$letter" 2>/dev/null
    else
        # busybox and toybox wget have no portable --spider, so download and
        # throw the body away. Without this fallback the sweep stayed mute on
        # those devices and reported "Remote: none" forever.
        fetch_text "$GITHUB/emergency_$letter" >/dev/null 2>&1
    fi
}

fetch_text() {
    # GET an URL and write the body on stdout.
    local url="$1"
    [ -n "$url" ] || return 1
    type detect_downloader >/dev/null 2>&1 || return 1
    detect_downloader
    case "$DL_MODE" in
        curl)    curl -fLsS --connect-timeout 15 --max-time 20 "$url" 2>/dev/null ;;
        wget)    wget -q --timeout=15 --tries=1 -O - "$url" 2>/dev/null ;;
        busybox) "$DOWNLOADER" wget -q -T 15 -O - "$url" 2>/dev/null ;;
        toybox)  toybox wget -T 15 -O - "$url" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

normalize_marker() {
    # Accepts "AD", "AD\n" or "emergency_AD" and prints the canonical marker.
    local marker
    marker=$(printf '%s' "$1" | head -n1 | tr -d ' \t\r\n' | sed -e 's/^[Ee][Mm][Ee][Rr][Gg][Ee][Nn][Cc][Yy]_//')
    case "$marker" in
        [A-Z] | [A-Z][A-Z] | [A-Z][A-Z][A-Z])
            printf '%s' "$marker"
            return 0
            ;;
    esac
    return 1
}

get_remote_highest_from_latest() {
    # One CDN request: auto-pilot/latest holds the marker currently in use.
    local raw
    raw=$(fetch_text "$GITHUB_LATEST") || return 1
    [ -n "$raw" ] || return 1
    normalize_marker "$raw"
}

get_remote_highest_from_api() {
    # One request: directory listing of auto-pilot, highest emergency_* entry.
    local raw cand highest
    raw=$(fetch_text "$GITHUB_API") || return 1
    [ -n "$raw" ] || return 1
    highest=""
    for cand in $(printf '%s' "$raw" \
        | tr ',' '\n' \
        | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"emergency_\([A-Za-z]*\)".*/\1/p' \
        | tr 'a-z' 'A-Z' | sort -u); do
        if name_is_newer "$cand" "$highest"; then
            highest="$cand"
        fi
    done
    [ -n "$highest" ] || return 1
    printf '%s' "$highest"
}

sweep_tier_reverse() {
    # $1 = tier prefix ("" then "A" then "B"). Probes Z down to A and returns
    # the first hit, which is the highest marker of that tier.
    local prefix="$1" sym
    for sym in Z Y X W V U T S R Q P O N M L K J I H G F E D C B A; do
        if check_github "${prefix}${sym}"; then
            printf '%s' "${prefix}${sym}"
            return 0
        fi
    done
    return 1
}

get_remote_highest_by_sweep() {
    # Last resort, needs no index file to exist.
    local marker
    marker=$(sweep_tier_reverse "B") \
        || marker=$(sweep_tier_reverse "A") \
        || marker=$(sweep_tier_reverse "") \
        || marker=""
    # normalize_marker drops any stray message that leaked on stdout while
    # sweeping, so a marker always reaches the caller.
    normalize_marker "$marker" || printf ''
}

get_remote_highest() {
    # The first two paths cost one request each; the sweep only runs when
    # neither latest nor the API answers. Logs go to stderr so they cannot
    # pollute the stdout this function returns to its caller.
    local marker
    marker=$(get_remote_highest_from_latest)
    if [ -n "$marker" ]; then
        log "Remote $marker (latest index)" >&2
        printf '%s' "$marker"
        return 0
    fi
    marker=$(get_remote_highest_from_api)
    if [ -n "$marker" ]; then
        log "Remote $marker (GitHub API)" >&2
        printf '%s' "$marker"
        return 0
    fi
    log "latest/API unavailable, sweeping emergency files" >&2
    get_remote_highest_by_sweep
}

execute() {
    letter="$1"
    if [ -f "$BOX_BRAIN/.executing" ]; then
        log "Skip: already executing"
        return 1
    fi
    touch "$BOX_BRAIN/.executing"
    script=$(get_script)
    if [ -z "$script" ]; then
        log "ERROR: no script found"
        rm -f "$BOX_BRAIN/.executing"
        return 1
    fi
    log "EXECUTE: emergency_$letter -> $script"
    wakelock_acquire
    [ -x "$script" ] || chmod +x "$script" 2>/dev/null
    if type timeout >/dev/null 2>&1; then
        timeout 120 "$script" >> "$LOG_FILE" 2>&1
        code=$?
    else
        "$script" >> "$LOG_FILE" 2>&1 &
        pid=$!
        ( sleep 120; kill "$pid" 2>/dev/null ) &
        wait "$pid" 2>/dev/null
        code=$?
    fi
    wakelock_release
    log "EXIT: $code"
    if [ "$code" -eq 0 ]; then
        touch "$BOX_BRAIN/emergency_$letter"
        log "MARKED: $letter done"
    fi
    rm -f "$BOX_BRAIN/.executing"
    return "$code"
}

log "Entering loop (interval: ${CHECK_INTERVAL}s)"

iteration=0
while true; do
    iteration=$((iteration + 1))
    now=$(date +%s)
    printf '%s' "$now" > "$BOX_BRAIN/daemon_heartbeat"
    if [ -f "$LOCK_DIR/pid" ]; then
        owner=$(cat "$LOCK_DIR/pid" 2>/dev/null | tr -dc '0-9')
        if [ "$owner" != "$$" ]; then
            log "Lost lock (owner: $owner), exit"
            exit 1
        fi
    else
        log "Lock lost, exit"
        exit 1
    fi
    log "--- Cycle #$iteration ---"
    if type wait_for_network >/dev/null 2>&1; then
        if wait_for_network 15; then
            local_max=$(get_local_highest)
            remote_max=$(get_remote_highest)
            printf '%s' "$now" > "$BOX_BRAIN/last_github_check"
            log "Local: ${local_max:-none}, Remote: ${remote_max:-none}"
            if [ -n "$remote_max" ]; then
                if [ "$remote_max" = "$local_max" ]; then
                    log "Remote = Local, no action"
                elif [ -f "$BOX_BRAIN/emergency_$remote_max" ]; then
                    log "Remote $remote_max already done"
                else
                    execute "$remote_max"
                fi
            else
                log "No remote emergency"
            fi
        else
            log "Network unavailable"
        fi
    else
        log "WARNING: wait_for_network not found"
    fi
    remaining=$CHECK_INTERVAL
    while [ "$remaining" -gt 0 ]; do
        chunk=60
        [ "$remaining" -lt "$chunk" ] && chunk=$remaining
        sleep "$chunk"
        remaining=$((remaining - chunk))
        date +%s > "$BOX_BRAIN/daemon_heartbeat"
        if [ ! -f "$BOX_BRAIN/autopilot" ]; then
            log "Autopilot disabled, stop"
            cleanup
        fi
    done
done
