MEOW() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

nohup am start -a android.intent.action.VIEW -d https://android.googleapis.com/attestation/status >/dev/null 2>&1 &
MEOW "Redirecting to Google Revoked List"

exit 0