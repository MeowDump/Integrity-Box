#!/system/bin/sh
MODPATH="${0%/*}"
. $MODPATH/common_func.sh

boot="/data/adb/service.d"
placeholder="$MODPATH/webroot/common_scripts"
mkdir -p "/data/adb/Box-Brain/Integrity-Box-Logs"
mkdir -p "$boot"

# Handle Vending-specific prop
if [ -f "/data/adb/Box-Brain/enablevending" ]; then
    set_simpleprop persist.sys.pixelprops.vending true
fi

if [ -f "/data/adb/Box-Brain/disablevending" ]; then
    set_simpleprop persist.sys.pixelprops.vending false
fi

# Handle GMS-specific props
if [ -f "/data/adb/Box-Brain/enablegms" ]; then
    setprop persist.sys.pihooks.disable.gms_key_attestation_block false
    setprop persist.sys.pihooks.disable.gms_props false
    setprop persist.sys.pihooks.enabled_features 1
    setprop persist.sys.pihooks.disable 0
    setprop persist.sys.kihooks.disable 0
fi

if [ -f "/data/adb/Box-Brain/disablegms" ]; then
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
    "$boot/prop.sh" \
    "$boot/hash.sh" \
    "$boot/lineage.sh" \
    "$boot/package.sh" \
    "$boot/.box_cleanup.sh" \
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
    "$placeholder/kernel.sh" \
    "$placeholder/hma.sh"
do
    set_perm_if_needed "$_f" 755
done

##########################################
# adapted from Play Integrity Fork by @osm0sis
# source: https://github.com/osm0sis/PlayIntegrityFork
# license: GPL-3.0
##########################################

# First check if Magisk directory exists
if [ -d "/data/adb/magisk" ]; then
    echo "Magisk detected."

    if [ -d "$MODPATH/zygisk" ]; then
        if magisk --denylist status; then
            magisk --denylist rm com.google.android.gms
            magisk --denylist rm com.android.vending
        fi

        . "$MODPATH/common_setup.sh"
    else
        magisk --denylist add com.google.android.gms com.google.android.gms.unstable
        magisk --denylist add com.android.vending
    fi

else
    echo "Skipped denylist, Bro's not using Magisk"
fi

# Conditional early sensitive properties

# Samsung
$RESETPROP_RS --stealth ro.boot.warranty_bit 0
$RESETPROP_RS --stealth ro.vendor.boot.warranty_bit 0
$RESETPROP_RS --stealth ro.vendor.warranty_bit 0
$RESETPROP_RS --stealth ro.warranty_bit 0

# Realme
$RESETPROP_RS --stealth ro.boot.realmebootstate green

# OnePlus
$RESETPROP_RS --stealth ro.is_ever_orange 0

# Microsoft
for PROP in $($RESETPROP_RS | grep -oE 'ro.*.build.tags'); do
    $RESETPROP_RS --stealth "$PROP" release-keys
done

# Other
for PROP in $($RESETPROP_RS | grep -oE 'ro.*.build.type'); do
    $RESETPROP_RS --stealth "$PROP" user
done
$RESETPROP_RS --stealth ro.adb.secure 1
if ! $SKIPDELPROP; then
    $RESETPROP_RS --nuke ro.boot.verifiedbooterror
    $RESETPROP_RS --nuke ro.boot.verifyerrorpart
fi
$RESETPROP_RS --stealth ro.boot.veritymode.managed yes
$RESETPROP_RS --stealth ro.debuggable 0
$RESETPROP_RS --stealth ro.force.debuggable 0
$RESETPROP_RS --stealth ro.secure 1


# Hide custom ROM
if [ -f "/data/adb/Box-Brain/kernel" ]; then
   log "Detected kernel flag"
   sh "$placeholder/kernel.sh"
   log "kernel.sh executed successfully"
else
   log "kernel spoofer flag not found, skipping kernel.sh"
fi

exit 0