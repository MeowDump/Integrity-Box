#!/system/bin/sh

LOG="/data/adb/Box-Brain/PID.log"
AUTOPILOT_FLAG="/data/adb/Box-Brain/autopilot"
AUTOPILOT_PID="/data/adb/Box-Brain/AutoPilot/emergency-monitor.lock/pid"
TRICKYBOX_PID="/data/adb/Box-Brain/TrickyBox/.service.lock/pid"

mkdir -p "${LOG%/*}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

kill_process() {
    PID_FILE="$1"
    PROCESS_NAME="$2"

    if [ ! -f "$PID_FILE" ]; then
        log "[INFO] $PROCESS_NAME PID file not found: $PID_FILE"
        return 1
    fi

    PID=$(tr -d '[:space:]' < "$PID_FILE")

    case "$PID" in
        ''|*[!0-9]*)
            log "[ERROR] Invalid PID in $PID_FILE"
            return 1
            ;;
    esac

    if ! kill -0 "$PID" 2>/dev/null; then
        log "[INFO] $PROCESS_NAME process $PID is not running."
        return 1
    fi

    log "[INFO] Attempting to kill $PROCESS_NAME process $PID."

    if kill -9 "$PID" 2>/dev/null; then
        sleep 1

        if kill -0 "$PID" 2>/dev/null; then
            log "[WARNING] $PROCESS_NAME process $PID is still running."
        else
            log "[SUCCESS] $PROCESS_NAME process $PID killed successfully."
        fi
    else
        log "[ERROR] Failed to kill $PROCESS_NAME process $PID."
        return 1
    fi
}

# AutoPilot disabled: kill AutoPilot process and exit
if [ ! -f "$AUTOPILOT_FLAG" ]; then
    log "[INFO] AutoPilot flag is absent. Managing AutoPilot PID."

    kill_process "$AUTOPILOT_PID" "AutoPilot"

    log "[INFO] Exiting."
    exit 0
fi

# AutoPilot enabled: skip AutoPilot PID and manage TrickyBox
log "[INFO] AutoPilot is enabled. Skipping AutoPilot PID."
log "[INFO] Managing TrickyBox PID."

kill_process "$TRICKYBOX_PID" "TrickyBox"

log "[INFO] Exiting."
exit 0
