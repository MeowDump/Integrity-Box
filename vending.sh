popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

su -c "pm clear com.android.vending"
su -c "pm clear com.google.android.gms"

popup " Open playstore & Check/FIX"
exit 0
