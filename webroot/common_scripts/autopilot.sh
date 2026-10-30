#!/system/bin/sh
# shellcheck disable=SC3043,SC2034,SC1091,SC2329
# ==============================================================================
# Integrity Box - Ultra-Efficient Autopilot Daemon (v46+)
# Non-Intrusive Scheduler, Little-Core Isolation, Multi-Tier Dynamic Cascade
# ==============================================================================

BASE_INTERVAL=3600
current_interval=$BASE_INTERVAL
network_fail_count=0
GRACE_DELAY=25
BOX_BRAIN="/data/adb/Box-Brain"
MODPATH="/data/adb/modules/playintegrityfix"
TRICKY_STORE="/data/adb/tricky_store"
KEYBOX="$TRICKY_STORE/keybox.xml"
ANCHOR_SERIAL="afb1549906c27a84eda46f24813fbfa0"

mkdir -p "$BOX_BRAIN/Integrity-Box-Logs" 2>/dev/null
AUTOLOG_FILE="$BOX_BRAIN/Integrity-Box-Logs/autorun.log"

# Universal background process isolation:
# 1. Native AOSP background cgroup (configured by vendor specifically for energy-efficient cores on any SoC)
if [ -d "/dev/cpuset/background" ]; then
    echo $$ > /dev/cpuset/background/tasks 2>/dev/null || true
elif [ -d "/dev/cpuset/system-background" ]; then
    echo $$ > /dev/cpuset/system-background/tasks 2>/dev/null || true
fi

# 2. Lower CPU scheduling priority (CFS/EAS scheduler favors low-power LITTLE cores)
renice -n 15 -p $$ 2>/dev/null || true

if [ -f "$MODPATH/common_func.sh" ]; then
    . "$MODPATH/common_func.sh"
fi

autolog() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$AUTOLOG_FILE"
}

update_heartbeat() {
    now=$(date +%s)
    printf '%s' "$now" > "$RAM_RUN/daemon_heartbeat" 2>/dev/null
}

autolog "••••••• ECO-AUTORUN DAEMON START PID: $$ •••••••"

RAM_RUN="/dev/.box_brain"
mkdir -p "$RAM_RUN" 2>/dev/null
LOCK_DIR="$RAM_RUN/autorun.lockdir"
# Maintain zero-wear symlink for backward compatibility with service.sh watchdog
ln -sf "$RAM_RUN/daemon_heartbeat" "$BOX_BRAIN/daemon_heartbeat" 2>/dev/null || true

claim_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        return 0
    fi
    return 1
}

if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
    autolog "Lock acquired (fresh)"
else
    autolog "Lock exists, checking stale..."
    if [ -f "$LOCK_DIR/pid" ]; then
        old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null | tr -dc '0-9')
        if [ -n "$old_pid" ] && [ -d "/proc/$old_pid" ]; then
            if [ -r "/proc/$old_pid/cmdline" ] && grep -q "autopilot" "/proc/$old_pid/cmdline" 2>/dev/null; then
                last_beat=$(cat "$RAM_RUN/daemon_heartbeat" 2>/dev/null | tr -dc '0-9')
                now=$(date +%s)
                diff=$((now - ${last_beat:-0}))
                if [ "$diff" -lt 300 ]; then
                    autolog "Already running (PID $old_pid, ${diff}s ago)"
                    exit 0
                else
                    autolog "Killing stale PID $old_pid (no heartbeat for ${diff}s)"
                    kill -9 "$old_pid" 2>/dev/null
                    sleep 1
                    claim_lock || { autolog "Cannot claim lock"; exit 1; }
                    autolog "Lock acquired (stale reclaimed)"
                fi
            else
                claim_lock || { autolog "Cannot claim lock"; exit 1; }
                autolog "Lock acquired (foreign process)"
            fi
        else
            claim_lock || { autolog "Cannot claim lock"; exit 1; }
            autolog "Lock acquired (dead process)"
        fi
    else
        claim_lock || { autolog "Cannot claim lock"; exit 1; }
        autolog "Lock acquired (no pid file)"
    fi
fi

cleanup() {
    autolog "Stopping daemon"
    rm -rf "$LOCK_DIR" "$BOX_BRAIN/.executing" 2>/dev/null
    exit 0
}

trap cleanup 15 2 1 0 2>/dev/null || true

is_charging() {
    local status
    status=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "Discharging")
    [ "$status" = "Charging" ] || [ "$status" = "Full" ]
}

is_screen_on() {
    local bright
    bright=$(cat /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || echo 0)
    [ "$bright" -gt 0 ]
}

is_battery_sufficient() {
    local cap
    cap=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 100)
    [ "$cap" -ge 15 ] || is_charging
}

has_network_route() {
    ip route get 1.1.1.1 >/dev/null 2>&1
}

parse_epoch() {
    raw="$1"
    [ -n "$raw" ] || { printf '%s' "0"; return; }
    yy=$(printf '%s' "$raw" | cut -c 1-2)
    mm=$(printf '%s' "$raw" | cut -c 3-4)
    dd=$(printf '%s' "$raw" | cut -c 5-6)
    hh=$(printf '%s' "$raw" | cut -c 7-8)
    min=$(printf '%s' "$raw" | cut -c 9-10)
    ss=$(printf '%s' "$raw" | cut -c 11-12)
    date -u -d "20${yy}-${mm}-${dd} ${hh}:${min}:${ss}" +%s 2>/dev/null || printf '%s' "0"
}

get_local_serial() {
    [ -s "$KEYBOX" ] || { echo ""; return; }
    local cert_b64
    cert_b64=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$KEYBOX" | head -n 35 | grep -v 'CERTIFICATE' | tr -d ' \n\r\t')
    [ -n "$cert_b64" ] || { echo ""; return; }
    printf '%s' "$cert_b64" | base64 -d 2>/dev/null | strings | grep -oE '[0-9a-f]{32}' | head -n 1
}

is_key_healthy() {
    [ -s "$KEYBOX" ] || return 1
    
    local cert_b64 strings_out dates not_before_raw not_after_raw start_epoch end_epoch now_epoch remaining_hours serial
    cert_b64=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$KEYBOX" | head -n 35 | grep -v 'CERTIFICATE' | tr -d ' \n\r\t')
    [ -n "$cert_b64" ] || return 1
    
    strings_out=$(printf '%s' "$cert_b64" | base64 -d 2>/dev/null | strings)
    serial=$(printf '%s\n' "$strings_out" | grep -oE '[0-9a-f]{32}' | head -n 1)

    # If emergency anchor (Megatron2) is installed, signal code 4 to seek upgrade to 2-check key
    if [ "$serial" = "$ANCHOR_SERIAL" ]; then
        return 4
    fi

    dates=$(printf '%s\n' "$strings_out" | grep -oE '[0-9]{12}Z')
    not_before_raw=$(printf '%s\n' "$dates" | head -n 1)
    not_after_raw=$(printf '%s\n' "$dates" | tail -n 1)
    
    [ -n "$not_before_raw" ] && [ -n "$not_after_raw" ] || return 1
    
    start_epoch=$(parse_epoch "$not_before_raw")
    end_epoch=$(parse_epoch "$not_after_raw")
    now_epoch=$(date +%s)
    
    if [ "$now_epoch" -lt "$start_epoch" ] || [ "$now_epoch" -gt "$end_epoch" ]; then
        autolog "WARN: Local key certificate is invalid/expired ($not_before_raw to $not_after_raw)"
        return 2
    fi
    
    remaining_hours=$(( (end_epoch - now_epoch) / 3600 ))
    if [ "$remaining_hours" -le 24 ]; then
        autolog "NOTICE: Local key certificate expires soon (${remaining_hours}h remaining <= 24h threshold)"
        return 3
    fi
    
    return 0
}

is_key_healthy_2check() {
    local code
    is_key_healthy >/dev/null 2>&1
    code=$?
    [ "$code" -eq 0 ]
}

try_spectre() {
    local spectre_script="$MODPATH/webroot/common_scripts/spectre.sh"
    [ -f "$spectre_script" ] || return 1
    autolog "EXECUTE [Spectre Live Catalog]: ($spectre_script)"
    sh "$spectre_script" >> "$AUTOLOG_FILE" 2>&1
    local code=$?
    if [ "$code" -eq 0 ] && is_key_healthy_2check; then
        autolog "SUCCESS: Installed active 2-check key from live catalog (Spectre)!"
        return 0
    fi
    autolog "NOTICE: Spectre did not provide a 2-check key (code: $code)."
    return 1
}

try_megatron() {
    local key_script="$MODPATH/webroot/common_scripts/key.sh"
    [ -f "$key_script" ] || return 1
    autolog "EXECUTE [Integrity Box Megatron]: ($key_script Megatron)"
    sh "$key_script" Megatron >> "$AUTOLOG_FILE" 2>&1
    local code=$?
    if [ "$code" -eq 0 ] && is_key_healthy_2check; then
        autolog "SUCCESS: Installed active 2-check key from Integrity Box mirror (Megatron)!"
        return 0
    fi
    autolog "NOTICE: Integrity Box Megatron did not provide a 2-check key (code: $code)."
    return 1
}

deploy_anchor_if_needed() {
    local cur_serial key_script
    cur_serial=$(get_local_serial)
    if [ "$cur_serial" = "$ANCHOR_SERIAL" ]; then
        autolog "STATUS: Already running Emergency Anchor (Megatron2). Basic integrity preserved."
        return 0
    fi
    
    autolog "EMERGENCY SAFETY NET: No 2-check keys available across any repository. Deploying Megatron2 (valid until 2032)..."
    key_script="$MODPATH/webroot/common_scripts/key.sh"
    if [ -f "$key_script" ]; then
        sh "$key_script" Megatron2 >> "$AUTOLOG_FILE" 2>&1
        autolog "SAFETY NET DEPLOYED: Megatron2 active. Basic integrity and Keystore2 protected from crash."
    fi
}

execute_update() {
    if [ -f "$BOX_BRAIN/.executing" ]; then
        autolog "Skip: update already executing"
        return 1
    fi
    touch "$BOX_BRAIN/.executing"
    
    local success_2check=0
    local skip_default=0
    [ -f "$BOX_BRAIN/disable-default-source" ] && skip_default=1

    if [ "$skip_default" -eq 1 ]; then
        autolog "PROFILE: 'Skip Integrity Box' is ACTIVE in UI."
        autolog "  -> Priority 1: Dynamic Catalog (Spectre / TAKR / Lei Jun / Yuri)"
        autolog "  -> Priority 2 (Fallback): Integrity Box Official (key.sh Megatron)"
        autolog "  -> Priority 3 (Safety Net): Emergency Anchor (Megatron2)"

        if try_spectre; then
            success_2check=1
        elif try_megatron; then
            success_2check=1
        fi
    else
        autolog "PROFILE: 'Skip Integrity Box' is OFF (Default Mode)."
        autolog "  -> Priority 1: Integrity Box Official (key.sh Megatron)"
        autolog "  -> Priority 2 (Fallback): Dynamic Catalog (Spectre / TAKR / Lei Jun / Yuri)"
        autolog "  -> Priority 3 (Safety Net): Emergency Anchor (Megatron2)"

        if try_megatron; then
            success_2check=1
        elif try_spectre; then
            success_2check=1
        fi
    fi

    # If all 2-check sources failed across all repositories:
    if [ "$success_2check" -ne 1 ]; then
        deploy_anchor_if_needed
    fi

    rm -f "$BOX_BRAIN/.executing"
    [ "$success_2check" -eq 1 ] && return 0 || return 1
}

autolog "Entering Eco Autopilot Loop (Base Interval: ${BASE_INTERVAL}s, Grace Delay: ${GRACE_DELAY}s)"

iteration=0
last_cycle_time=0
was_screen_on_last=0

while true; do
    if [ ! -f "$BOX_BRAIN/autopilot" ]; then
        autolog "Autopilot disabled by user flag, stopping daemon."
        cleanup
    fi

    now=$(date +%s)
    update_heartbeat

    if [ -f "$LOCK_DIR/pid" ]; then
        owner=$(cat "$LOCK_DIR/pid" 2>/dev/null | tr -dc '0-9')
        if [ "$owner" != "$$" ]; then
            autolog "Lost lock (owner: $owner), exit"
            exit 1
        fi
    else
        autolog "Lock lost, exit"
        exit 1
    fi

    screen_now=0
    is_screen_on && screen_now=1

    # Detect user screen activation (transition 0 -> 1)
    if [ "$was_screen_on_last" -eq 0 ] && [ "$screen_now" -eq 1 ]; then
        screen_turned_on_time=$now
    fi
    was_screen_on_last=$screen_now

    # Determine if system is ready for maintenance
    elapsed=$((now - last_cycle_time))
    ready_for_check=0

    if [ "$last_cycle_time" -eq 0 ]; then
        ready_for_check=1
    elif [ "$elapsed" -ge "$current_interval" ]; then
        if is_charging; then
            ready_for_check=1
        elif [ "$screen_now" -eq 1 ]; then
            awake_duration=$((now - ${screen_turned_on_time:-$now}))
            if [ "$awake_duration" -ge "$GRACE_DELAY" ]; then
                ready_for_check=1
            fi
        fi
    fi

    if [ "$ready_for_check" -eq 1 ]; then
        iteration=$((iteration + 1))
        last_cycle_time=$now
        autolog "--- Eco Cycle #$iteration ---"

        health_code=0
        is_key_healthy
        health_code=$?

        if [ "$health_code" -eq 0 ]; then
            cert_b64=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$KEYBOX" | head -n 35 | grep -v 'CERTIFICATE' | tr -d ' \n\r\t')
            strings_out=$(printf '%s' "$cert_b64" | base64 -d 2>/dev/null | strings)
            dates=$(printf '%s\n' "$strings_out" | grep -oE '[0-9]{12}Z')
            not_after_raw=$(printf '%s\n' "$dates" | tail -n 1)
            end_epoch=$(parse_epoch "$not_after_raw")
            rem_h=$(( (end_epoch - now) / 3600 ))
            autolog "Local keybox healthy and active (2 checks, ${rem_h}h remaining until $not_after_raw). Skipping network operations."
        elif [ "$health_code" -eq 4 ]; then
            autolog "NOTICE: Emergency anchor (Megatron2) is active (1 check). Seeking upgrade to 2-check key..."
            if ! is_battery_sufficient; then
                autolog "Battery too low (<15%), deferring upgrade check until charging."
            elif ! has_network_route; then
                autolog "Network route unavailable, will retry next cycle."
            else
                execute_update
            fi
        else
            autolog "Local key requires refresh or renewal (status code: $health_code)."
            if ! is_battery_sufficient; then
                autolog "Battery too low (<15%), deferring update until charging."
            elif ! has_network_route; then
                autolog "Network route unavailable, will retry next cycle."
            else
                execute_update
            fi
        fi
    fi

    # Small sleep chunk: maintains heartbeat and checks screen transition
    sleep 30
done
