popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

if su -c "getprop persist.sys.pihooks.disable.gms_props >/dev/null 2>&1"; then
    popup"🎲 Disabling GMS spoofing prop..."
    su -c "setprop persist.sys.pihooks.disable.gms_props true"
fi

if su -c "getprop persist.sys.pihooks.disable.gms_key_attestation_block >/dev/null 2>&1"; then
    popup "🎲 Disabling GMS key attestation block..."
    su -c "setprop persist.sys.pihooks.disable.gms_key_attestation_block true"
fi
