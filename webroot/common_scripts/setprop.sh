popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

# Check if the properties exist before setting them
if getprop persist.sys.pihooks.disable.gms_props >/dev/null 2>&1; then
    popup "🎲 Disabled GMS spoofing prop"
    setprop persist.sys.pihooks.disable.gms_props true
fi

if getprop persist.sys.pihooks.disable.gms_key_attestation_block >/dev/null 2>&1; then
    popup "🎲 Disabled GMS key attestation block"
    setprop persist.sys.pihooks.disable.gms_key_attestation_block true
    su -c setprop persist.sys.pihooks.disable.gms_key_attestation_block true
fi