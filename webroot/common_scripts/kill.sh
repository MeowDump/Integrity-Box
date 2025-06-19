#!/system/bin/sh

popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

kill_process() {
    TARGET="$1"
    PID=$(pidof "$TARGET")

    if [ -n "$PID" ]; then
        echo "- Found PID(s) for $TARGET: $PID"
        kill -9 $PID
        echo "- Killed $TARGET"
	   popup "Process killed successfully"
        echo "$TARGET process killed successfully"
    else
        echo "- $TARGET not running"
	   popup "Process not running"
    fi
}

# Kill Google Play Services (unstable)
kill_process "com.google.android.gms.unstable"

# Kill Google Play Store
kill_process "com.android.vending"