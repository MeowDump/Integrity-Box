MEOW() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

resetprop -p -d persist.sys.pihooks.disable.gms_props
resetprop -p -d persist.sys.pihooks.disable.gms_key_attestation_block
resetprop -p -d setprop persist.sys.pihooks.disable.gms_key_attestation_block
MEOW "Switched back to default settings"