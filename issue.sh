popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

nohup am start -a android.intent.action.VIEW -d https://t.me/TempMeow >/dev/null 2>&1 & 
popup "Report your problem here"

exit 0
