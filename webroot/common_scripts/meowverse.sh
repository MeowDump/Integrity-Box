popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

nohup am start -a android.intent.action.VIEW -d https://t.me/+bKUOLxF_K_IyNDY1 >/dev/null 2>&1 &
popup "Redirecting to ⏤͟͞𝗠𝗘𝗢𝗪 𝗩𝗘𝗥𝗦𝗘"
exit 0