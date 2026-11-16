#!/system/bin/sh
MODPATH="${0%/*}"
. $MODPATH/common_func.sh

BOX="/data/adb/Box-Brain"
boot="/data/adb/service.d"
backend="$MODPATH/webroot/common_scripts"
mkdir -p "$BOX/Integrity-Box-Logs"

# Verify backend perms
for _f in \
    "$MODPATH/webroot/Canary.sh" \
    "$MODPATH/resetprop-rs/resetprop-x86_64" \
    "$MODPATH/resetprop-rs/resetprop-x86" \
    "$MODPATH/resetprop-rs/resetprop-armeabi-v7a" \
    "$MODPATH/resetprop-rs/resetprop-arm64-v8a" \
    "$boot/prop.sh" \
    "$boot/hash.sh" \
    "$boot/lineage.sh" \
    "$boot/.box_cleanup.sh" \
    "$backend/teesim.sh" \
    "$backend/susfiles.sh" \
    "$backend/web_bridge.sh" \
    "$backend/autopilot.sh" \
    "$backend/multiroot.sh" \
    "$backend/custom_pif.sh" \
    "$backend/spectre.sh" \
    "$backend/resetprop.sh" \
    "$backend/Report.sh" \
    "$backend/status.sh" \
    "$backend/force_override.sh" \
    "$backend/override_lineage.sh" \
    "$backend/keymint.sh" \
    "$backend/hehe.sh" \
    "$backend/zygisk.sh" \
    "$backend/extract_boot.sh"
do
    make_exec "$_f" || true
done

# Skip disabling built-in spoofing when zygiskless mode is enabled 
if [ -f "$BOX/zygisk" ]; then
    [ -f "$BOX/disablegms" ] && rm -f "$BOX/disablegms"
    [ -f "$BOX/disablevending" ] && rm -f "$BOX/disablevending"
fi

# Handle Vending-specific prop
if [ -f "$BOX/enablevending" ]; then
    check_and_set_prop -f persist.sys.pixelprops.vending true
fi

if [ -f "$BOX/disablevending" ]; then
    check_and_set_prop -f persist.sys.pixelprops.vending false
fi

# Handle GMS-specific props
if [ -f "$BOX/enablegms" ]; then
    check_and_set_prop -f persist.sys.pihooks.disable.gms_key_attestation_block false
    check_and_set_prop -f persist.sys.pihooks.disable.gms_props false
    check_and_set_prop -f persist.sys.pihooks.enabled_features 1
    check_and_set_prop -f persist.sys.pihooks.disable 0
    check_and_set_prop -f persist.sys.kihooks.disable 0
fi

if [ -f "$BOX/disablegms" ]; then
    check_and_set_prop -f persist.sys.pihooks.disable.gms_key_attestation_block true
    check_and_set_prop -f persist.sys.pihooks.disable.gms_props true
    check_and_set_prop -f persist.sys.pihooks.enabled_features 0
    check_and_set_prop -f persist.sys.pihooks.disable 1
    check_and_set_prop -f persist.sys.kihooks.disable 1
fi

# Conditional early sensitive properties
check_and_set_prop ro.boot.warranty_bit 0
check_and_set_prop ro.vendor.boot.warranty_bit 0
check_and_set_prop ro.vendor.warranty_bit 0
check_and_set_prop ro.warranty_bit 0
check_and_set_prop ro.boot.realmebootstate green
check_and_set_prop ro.is_ever_orange 0
check_and_set_prop ro.adb.secure 1
check_and_set_prop ro.boot.veritymode.managed yes
check_and_set_prop ro.debuggable 0
check_and_set_prop ro.force.debuggable 0
check_and_set_prop ro.secure 1
delprop_if_exist ro.boot.verifiedbooterror
delprop_if_exist ro.boot.verifyerrorpart

for PROP in $(resetprop | grep -oE 'ro.*.build.tags'); do
    check_and_set_prop $PROP release-keys
done

for PROP in $(resetprop | grep -oE 'ro.*.build.type'); do
    check_and_set_prop $PROP user
done

# Fix multiple root implementation conflicts 
count=0

[ -e "$BOX/ROOT/apatch" ] && count=$((count + 1))
[ -e "$BOX/ROOT/magisk" ] && count=$((count + 1))
[ -e "$BOX/ROOT/kernelsu" ] && count=$((count + 1))

if [ "$count" -eq 1 ]; then
    sh "$backend/multiroot.sh"
fi

# Handle denylist for magisk users
if [ -d "/data/adb/magisk" ]; then
    echo "Magisk detected."

    if [ -d "$MODPATH/zygisk" ]; then
        # Remove Play Services and Play Store from Magisk DenyList when set to Enforce in normal mode
        if magisk --denylist status; then
            magisk --denylist rm com.google.android.gms
            magisk --denylist rm com.android.vending
        fi

        # Run common tasks for installation and boot-time
        . "$MODPATH/common_setup.sh"
    else
        # Add Play Services DroidGuard and Play Store processes to Magisk DenyList for better results in zygiskless mode
        magisk --denylist add com.google.android.gms com.google.android.gms.unstable
        magisk --denylist add com.android.vending
    fi

else
    echo "Skipped denylist, Bro's not using Magisk"
fi

exit 0
