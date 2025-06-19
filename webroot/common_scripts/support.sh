#!/system/bin/sh

popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

popup "This feature is under maintenance"
exit 0
