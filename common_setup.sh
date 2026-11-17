
# Skip on pixel mode
if [ -e "/sdcard/zygisk" ] || [ -e "/data/adb/Box-Brain/zygisk" ]; then
    return 0
fi

if ! $SKIPPERSISTPROP; then
    # Work around custom ROM PropImitationHooks conflict when their persist props don't exist
    if [ -n "$(resetprop ro.aospa.version)" -o -n "$(resetprop net.pixelos.version)" -o -n "$(resetprop ro.afterlife.version)" -o -f /data/system/gms_certified_props.json ]; then
        for PROP in persist.sys.pihooks.first_api_level persist.sys.pihooks.security_patch; do
            resetprop | grep -q "\[$PROP\]" || persistprop "$PROP" ""
        done
    fi

    # Work around supported custom ROM PropImitationHooks/PixelPropsUtils (and hybrids) conflict when spoofProvider is disabled
    if resetprop | grep -qE "persist.sys.pihooks|persist.sys.entryhooks|persist.sys.spoof|persist.sys.pixelprops|persist.sys.pp" || [ -f /data/system/gms_certified_props.json ]; then
        persistprop persist.sys.pihooks.disable.gms_props true
        persistprop persist.sys.pihooks.disable.gms_key_attestation_block true
        persistprop persist.sys.entryhooks_enabled false
        persistprop persist.sys.spoof.gms false
        persistprop persist.sys.pixelprops.gms false
        persistprop persist.sys.pixelprops.gapps false
        persistprop persist.sys.pixelprops.google false
        persistprop persist.sys.pixelprops.pi false
        persistprop persist.sys.pp.gms false
        persistprop persist.sys.pp.finsky false
    fi
fi
