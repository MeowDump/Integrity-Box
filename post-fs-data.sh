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

# Handle Vending-specific prop
if [ -f "$BOX/enablevending" ]; then
    set_simpleprop persist.sys.pixelprops.vending true
fi

if [ -f "$BOX/disablevending" ]; then
    set_simpleprop persist.sys.pixelprops.vending false
fi

# Handle GMS-specific props
if [ -f "$BOX/enablegms" ]; then
    setprop persist.sys.pihooks.disable.gms_key_attestation_block false
    setprop persist.sys.pihooks.disable.gms_props false
    setprop persist.sys.pihooks.enabled_features 1
    setprop persist.sys.pihooks.disable 0
    setprop persist.sys.kihooks.disable 0
fi

if [ -f "$BOX/disablegms" ]; then
    setprop persist.sys.pihooks.disable.gms_key_attestation_block true
    setprop persist.sys.pihooks.disable.gms_props true
    setprop persist.sys.pihooks.enabled_features 0
    setprop persist.sys.pihooks.disable 1
    setprop persist.sys.kihooks.disable 1
fi

# Create all placeholder files only if they don't exist
for file in kill aosp patch xml tee user hma ulock stop start nogms lineage selinux hide resetprop faq nuke zygisknext yesgms; do
    [ -f "$placeholder/$file" ] || touch "$placeholder/$file"
done

# Verify backend perms
for _f in \
    "$MODPATH/webroot/UpdateTranslation.sh" \
    "$boot/prop.sh" \
    "$boot/hash.sh" \
    "$boot/lineage.sh" \
    "$boot/.box_cleanup.sh" \
    "$placeholder/teesim.sh" \
    "$placeholder/autopilot.sh" \
    "$placeholder/target.sh" \
    "$placeholder/gms.sh" \
    "$placeholder/webui.sh" \
    "$placeholder/run_scan.sh" \
    "$placeholder/scan_keybox.sh" \
    "$placeholder/resetprop.sh" \
    "$placeholder/Report.sh" \
    "$placeholder/force_override.sh" \
    "$placeholder/override_lineage.sh" \
    "$placeholder/keymint.sh" \
    "$placeholder/hma.sh"
do
    set_perm_if_needed "$_f" 755
done

if [ -e "$BOX/ota" ]; then
    rm -f "$MODPATH/system.prop"
    rm -f "$BOX/NoLineageProp"
    rm -rf "$BOX/override"
    rm -rf "$BOX/ota"
    touch "$BOX/safemode"
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
resetprop_if_diff ro.boot.warranty_bit 0
resetprop_if_diff ro.vendor.boot.warranty_bit 0
resetprop_if_diff ro.vendor.warranty_bit 0
resetprop_if_diff ro.warranty_bit 0

# Realme
resetprop_if_diff ro.boot.realmebootstate green

# OnePlus
resetprop_if_diff ro.is_ever_orange 0

# Microsoft
for PROP in $(resetprop | grep -oE 'ro.*.build.tags'); do
    resetprop_if_diff $PROP release-keys
done

# Other
for PROP in $(resetprop | grep -oE 'ro.*.build.type'); do
    resetprop_if_diff $PROP user
done
resetprop_if_diff ro.adb.secure 1
if ! $SKIPDELPROP; then
    delprop_if_exist ro.boot.verifiedbooterror
    delprop_if_exist ro.boot.verifyerrorpart
fi
resetprop_if_diff ro.boot.veritymode.managed yes
resetprop_if_diff ro.debuggable 0
resetprop_if_diff ro.force.debuggable 0
resetprop_if_diff ro.secure 1

exit 0
