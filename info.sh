popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

nohup am start -a android.intent.action.VIEW -d https://github.com/MeowDump/Integrity-Box/blob/main/README.md >/dev/null 2>&1 & 
popup "Redirecting to Github"

exit 0
