#!/system/bin/sh
MODPATH="${0%/*}"
. $MODPATH/common_func.sh

BOX="/data/adb/Box-Brain"
boot="/data/adb/service.d"
placeholder="$MODPATH/webroot/common_scripts"
mkdir -p "$BOX/Integrity-Box-Logs"
mkdir -p "$boot"

# Grant perms 
if [ -f "$placeholder/autopilot.sh" ]; then
    chmod 755 "$placeholder/autopilot.sh"
fi

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

# Create all placeholder files only if they don't exist
for file in kill aosp patch xml tee user hma ulock stop start nogms lineage selinux hide resetprop faq nuke zygisknext yesgms; do
    [ -f "$placeholder/$file" ] || touch "$placeholder/$file"
done

# Verify backend perms
for _f in \
    "$MODPATH/webroot/Canary.sh" \
    "$boot/prop.sh" \
    "$boot/hash.sh" \
    "$boot/lineage.sh" \
    "$boot/.box_cleanup.sh" \
    "$placeholder/teesim.sh" \
    "$placeholder/scan_keybox.sh" \
    "$placeholder/susfiles.sh" \
    "$placeholder/autopilot.sh" \
    "$placeholder/target.sh" \
    "$placeholder/multiroot.sh" \
    "$placeholder/gms.sh" \
    "$placeholder/spectre.sh" \
    "$placeholder/resetprop.sh" \
    "$placeholder/Report.sh" \
    "$placeholder/force_override.sh" \
    "$placeholder/override_lineage.sh" \
    "$placeholder/keymint.sh" \
    "$placeholder/hehe.sh" \
    "$placeholder/zygisk.sh" \
    "$placeholder/extract_boot.sh"
do
    make_exec "$_f"
done

# Fix multiple root implementation warning 
count=0

[ -e "$BOX/ROOT/apatch" ] && count=$((count + 1))
[ -e "$BOX/ROOT/magisk" ] && count=$((count + 1))
[ -e "$BOX/ROOT/kernelsu" ] && count=$((count + 1))

if [ "$count" -eq 1 ]; then
    sh "$placeholder/multiroot.sh"
fi

##########################################
# adapted from Play Integrity Fork by @osm0sis
# source: https://github.com/osm0sis/PlayIntegrityFork
# license: GPL-3.0
##########################################

# First check if Magisk directory exists
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
        # Add Play Services DroidGuard and Play Store processes to Magisk DenyList for better results in scripts-only mode
        magisk --denylist add com.google.android.gms com.google.android.gms.unstable
        magisk --denylist add com.android.vending
    fi

else
    echo "Skipped denylist, Bro's not using Magisk"
fi

# Conditional early sensitive properties

# Samsung
check_and_set_prop ro.boot.warranty_bit 0
check_and_set_prop ro.vendor.boot.warranty_bit 0
check_and_set_prop ro.vendor.warranty_bit 0
check_and_set_prop ro.warranty_bit 0

# Realme
check_and_set_prop ro.boot.realmebootstate green

# OnePlus
check_and_set_prop ro.is_ever_orange 0

# Microsoft
for PROP in $(resetprop | grep -oE 'ro.*.build.tags'); do
    check_and_set_prop $PROP release-keys
done

# Other
for PROP in $(resetprop | grep -oE 'ro.*.build.type'); do
    check_and_set_prop $PROP user
done
check_and_set_prop ro.adb.secure 1
delprop_if_exist ro.boot.verifiedbooterror
delprop_if_exist ro.boot.verifyerrorpart
check_and_set_prop ro.boot.veritymode.managed yes
check_and_set_prop ro.debuggable 0
check_and_set_prop ro.force.debuggable 0
check_and_set_prop ro.secure 1

exit 0
