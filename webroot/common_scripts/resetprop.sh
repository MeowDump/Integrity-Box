popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

su -c "resetprop -p -d persist.sys.pihooks.disable.gms_props"
su -c "resetprop -p -d persist.sys.pihooks.disable.gms_key_attestation_block"

popup "Switched back to default settings"
