popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

nohup am start -a android.intent.action.VIEW -d https://t.me/MeowDump >/dev/null 2>&1 &
popup "Redirecting to 𝗠𝗘𝗢𝗪 𝗗𝗨𝗠𝗣"
exit 0