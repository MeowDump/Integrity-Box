PID_FILE="/data/adb/Box-Brain/AutoPilot/emergency-monitor.lock/pid"

if [ ! -f "$PID_FILE" ]; then
    echo "[ERROR] PID file not found."
    exit 1
fi

PID=$(cat "$PID_FILE" | tr -d '[:space:]')

if ! kill -0 "$PID" 2>/dev/null; then
    echo "[INFO] Process $PID is not running."
elif kill -9 "$PID" 2>/dev/null; then
    sleep 1
    if kill -0 "$PID" 2>/dev/null; then
        echo "[WARNING] Process $PID is still running."
    else
        echo "[SUCCESS] Process $PID killed successfully."
    fi
else
    echo "[ERROR] Failed to kill process $PID."
fi
