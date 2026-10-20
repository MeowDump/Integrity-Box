#!/system/bin/sh

FLAG="/data/adb/modules/playintegrityfix/stop"
LOG="/data/adb/Box-Brain/Integrity-Box-Logs/zygisk.log"

log() {
    if [[ -z "${_LOG_INITIALIZED:-}" ]]; then
        : > "$LOG"
        _LOG_INITIALIZED=1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

run_cmd() {
    log "CMD: $*"
    "$@" >> "$LOG" 2>&1
    RET=$?
    log "EXIT: $RET"
    return $RET
}

log "PIF controller started"
log "Flag: $FLAG"

# Read state controlled by WebUI
if [ -f "$FLAG" ]; then
    STATE="PAUSED"
    log "Flag exists"
else
    STATE="RESUMED"
    log "Flag does not exist"
fi

log "Current state: $STATE"

# Find all GMS PIDs
log "Scanning GMS processes"

GMS_PIDS="$(ps -A 2>/dev/null | awk '$NF ~ /^com\.google\.android\.gms(:.*)?$/ {print $2}')"

if [ -n "$GMS_PIDS" ]; then
    log "GMS PIDs found: $GMS_PIDS"

    for PID in $GMS_PIDS; do
        PROC="$(ps -A 2>/dev/null | awk -v pid="$PID" '$2 == pid {print $NF; exit}')"

        if [ -n "$PROC" ]; then
            log "Killing GMS: PID=$PID PROCESS=$PROC"
        else
            log "Killing GMS: PID=$PID"
        fi

        run_cmd kill -9 "$PID"
    done
else
    log "No GMS processes found"
fi

# Find all Play Store PIDs
log "Scanning Vending processes"

VENDING_PIDS="$(ps -A 2>/dev/null | awk '$NF ~ /^com\.android\.vending(:.*)?$/ {print $2}')"

if [ -n "$VENDING_PIDS" ]; then
    log "Vending PIDs found: $VENDING_PIDS"

    for PID in $VENDING_PIDS; do
        PROC="$(ps -A 2>/dev/null | awk -v pid="$PID" '$2 == pid {print $NF; exit}')"

        if [ -n "$PROC" ]; then
            log "Killing Vending: PID=$PID PROCESS=$PROC"
        else
            log "Killing Vending: PID=$PID"
        fi

        run_cmd kill -9 "$PID"
    done
else
    log "No Vending processes found"
fi

# Verify remaining processes
sleep 1

REMAINING_GMS="$(ps -A 2>/dev/null | awk '$NF ~ /^com\.google\.android\.gms(:.*)?$/ {print $2 ":" $NF}')"
REMAINING_VENDING="$(ps -A 2>/dev/null | awk '$NF ~ /^com\.android\.vending(:.*)?$/ {print $2 ":" $NF}')"

if [ -n "$REMAINING_GMS" ]; then
    log "GMS processes after kill:"
    echo "$REMAINING_GMS" >> "$LOG"
else
    log "No GMS processes remaining after kill"
fi

if [ -n "$REMAINING_VENDING" ]; then
    log "Vending processes after kill:"
    echo "$REMAINING_VENDING" >> "$LOG"
else
    log "No Vending processes remaining after kill"
fi

# Final flag state
if [ -f "$FLAG" ]; then
    log "Final state: PAUSED"
else
    log "Final state: RESUMED"
fi

log "PIF controller finished"
log " "
log " "
