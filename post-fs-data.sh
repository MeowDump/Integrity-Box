#!/system/bin/sh
MODPATH="${0%/*}"
. $MODPATH/common_func.sh

boot="/data/adb/service.d"
placeholder="$MODPATH/webroot/common_scripts"
mkdir -p "/data/adb/Box-Brain/Integrity-Box-Logs"
mkdir -p "$boot"

# Grant perms 
if [ -f "$placeholder/autopilot.sh" ]; then
    chmod 755 "$placeholder/autopilot.sh"
fi

# Handle Vending-specific prop
if [ -f "/data/adb/Box-Brain/enablevending" ]; then
    set_simpleprop persist.sys.pixelprops.vending true
fi

if [ -f "/data/adb/Box-Brain/disablevending" ]; then
    set_simpleprop persist.sys.pixelprops.vending false
fi

# Handle GMS-specific props
if [ -f "/data/adb/Box-Brain/enablegms" ]; then
    resetprop -n persist.sys.pihooks.disable.gms_key_attestation_block false
    resetprop -n persist.sys.pihooks.disable.gms_props false
    resetprop -n persist.sys.pihooks.enabled_features 1
    resetprop -n persist.sys.pihooks.disable 0
    resetprop -n persist.sys.kihooks.disable 0
fi

if [ -f "/data/adb/Box-Brain/disablegms" ]; then
    resetprop -n persist.sys.pihooks.disable.gms_key_attestation_block true
    resetprop -n persist.sys.pihooks.disable.gms_props true
    resetprop -n persist.sys.pihooks.enabled_features 0
    resetprop -n persist.sys.pihooks.disable 1
    resetprop -n persist.sys.kihooks.disable 1
fi

cat <<'EOF' > "$boot/.box_cleanup.sh"
#!/system/bin/sh

# This script cleans up leftover files after module ID change.
#
# IntegrityBox and PIF now replace each other to avoid conflicts.
# If a user flashes PIF over IntegrityBox, leftover IntegrityBox files may remain.
# This script deletes those leftover files and folders, and then deletes itself. 
# It only runs if IntegrityBox is not installed

PROP_FILE="/data/adb/modules/playintegrityfix/module.prop"
REQUIRED_LINE="support=https://t.me/MeowDump"
LOG_DIR="/data/adb/Box-Brain"

SERVICE_FILES="
/data/adb/service.d/shamiko.sh
/data/adb/service.d/prop.sh
/data/adb/service.d/hash.sh
/data/adb/service.d/lineage.sh
/data/adb/service.d/package.sh
"

# Check if the prop file exists and contains the required line
if [ ! -f "$PROP_FILE" ] || ! grep -Fq "$REQUIRED_LINE" "$PROP_FILE"; then
    # Delete leftover files if they exist
    for file in $SERVICE_FILES; do
        [ -e "$file" ] && rm -rf "$file"
    done

    # Delete Box-Brain folder if it exists
    [ -d "$LOG_DIR" ] && rm -rf "$LOG_DIR"

    # Delete this script itself
    rm -f "$0"
fi
EOF

# Create all placeholder files only if they don't exist
for file in kill aosp patch xml tee user hma ulock stop start nogms lineage selinux hide resetprop faq nuke zygisknext yesgms; do
    [ -f "$placeholder/$file" ] || touch "$placeholder/$file"
done

if [ ! -f "$boot/package.sh" ]; then
cat <<'EOF' > "$boot/package.sh"
#!/system/bin/sh

# Check if required module folders exist
# These modules add system app package names to target.txt which ruins keybox & increases battery drain
MODULE1="/data/adb/modules/.TA_utl"
MODULE2="/data/adb/modules/tsupport-advance"
MODULE3="/data/adb/modules/Yurikey"
MODULE4="/data/adb/modules/tricky_store/webroot"

# Paths
IGNORE_FLAG="/data/adb/Box-Brain/ignore"
TARGET_FILE="/data/adb/tricky_store/target.txt"
SCRIPT="/data/adb/modules/playintegrityfix/webroot/common_scripts/target.sh"
LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/target.log"

if [ ! -d "$MODULE1" ] && [ ! -d "$MODULE2" ] && [ ! -d "$MODULE3" ] && [ ! -d "$MODULE4" ]; then
    exit 0
fi

# Check ignore flag
if [ -f "$IGNORE_FLAG" ]; then
    log "Ignore flag found, exiting"
    exit 0
fi

# Create log directory if needed
mkdir -p "$(dirname "$LOG_FILE")"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to check and execute
execute_if_needed() {
    if [ -f "$TARGET_FILE" ]; then
        line_count=$(wc -l < "$TARGET_FILE")
        log "Target.txt has $line_count packages"
        if [ "$line_count" -gt 150 ]; then
            log "Line count exceeds 150, executing cleanup script"
            if [ -f "$SCRIPT" ]; then
                sh "$SCRIPT"
                log "Script executed with exit code $?"
            else
                log "Script not found: $SCRIPT"
            fi
        fi
    else
        log "Target file not found: $TARGET_FILE"
    fi
}

# Initial check
log "••• Service started •••"

# Exit if module is disabled 
if [ -f "/data/adb/modules/playintegrityfix/disable" ]; then
    log "Integrity Box is disabled, exiting..."
    exit 0
fi

execute_if_needed

# Monitor in background
while true; do
    sleep 30
    if [ -f "$IGNORE_FLAG" ]; then
        log "Ignore flag detected during monitoring, stopping"
        exit 0
    fi
    execute_if_needed
done
EOF
fi

if [ ! -f "$boot/lineage.sh" ]; then
cat <<'EOF' > "$boot/lineage.sh"
#!/system/bin/sh

MODPATH="/data/adb/modules/playintegrityfix"
. $MODPATH/common_func.sh

# Module path and file references
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
PROP="/data/adb/modules/playintegrityfix/system.prop"

note() {
    TS="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$LOG_DIR" 2>/dev/null
    printf "%s | %s\n" "$TS" "$1" >> "$LOG_DIR/Lineage.log"
}

# Abort the script & delete flags wen safe mode is active 
if [ -f "/data/adb/Box-Brain/safemode" ]; then
    note "$(date '+%Y-%m-%d %H:%M:%S') : Safemode active, script aborted." >> "/data/adb/Box-Brain/Integrity-Box-Logs/safemode.log"
    rm -rf "/data/adb/Box-Brain/NoLineageProp"
    rm -rf "/data/adb/Box-Brain/nodebug"
    rm -rf "/data/adb/Box-Brain/tag"
    exit 1
fi

# Exit if module is disabled 
if [ -f "/data/adb/modules/playintegrityfix/disable" ]; then
    note "Integrity Box is disabled, exiting..."
    exit 0
fi

# Module install path
export MODPATH="/data/adb/modules/playintegrityfix"

NO_LINEAGE_FLAG="/data/adb/Box-Brain/NoLineageProp"
NODEBUG_FLAG="/data/adb/Box-Brain/nodebug"
TAG_FLAG="/data/adb/Box-Brain/tag"

TMP_PROP="$MODPATH/tmp.prop"
SYSTEM_PROP="$MODPATH/system.prop"
> "$TMP_PROP" # clear old temp file

# Build summary of active flags
FLAGS_ACTIVE=""
[ -f "$NO_LINEAGE_FLAG" ] && FLAGS_ACTIVE="$FLAGS_ACTIVE NoLineageProp"
[ -f "$NODEBUG_FLAG" ] && FLAGS_ACTIVE="$FLAGS_ACTIVE nodebug"
[ -f "$TAG_FLAG" ] && FLAGS_ACTIVE="$FLAGS_ACTIVE tag"

if [ -n "$FLAGS_ACTIVE" ]; then
    note "Prop sanitization flags active: $FLAGS_ACTIVE"
    note "Preparing temporary prop file..."
    getprop | grep "userdebug" >> "$TMP_PROP"
    getprop | grep "test-keys" >> "$TMP_PROP"
    getprop | grep "lineage_" >> "$TMP_PROP"

    # Basic cleanup
    sed -i 's///g' "$TMP_PROP"
    sed -i 's/: /=/g' "$TMP_PROP"
else
    note "No prop sanitization flags found. Skipping."
fi

# LineageOS cleanup
if [ -f "$NO_LINEAGE_FLAG" ]; then
    note "NoLineageProp flag detected. Deleting LineageOS props..."
    for prop in \
        ro.lineage.build.version \
        ro.lineage.build.version.plat.rev \
        ro.lineage.build.version.plat.sdk \
        ro.lineage.device \
        ro.lineage.display.version \
        ro.lineage.releasetype \
        ro.lineage.version \
        ro.lineagelegal.url; do
        resetprop --delete "$prop"
    done
    sed -i 's/lineage_//g' "$TMP_PROP"
    note "LineageOS props sanitized."
fi

# userdebug to user
if [ -f "$NODEBUG_FLAG" ]; then
    if grep -q "userdebug" "$TMP_PROP"; then
        sed -i 's/userdebug/user/g' "$TMP_PROP"
    fi
    note "userdebug to user sanitization applied."
fi

# test-keys to release-keys
if [ -f "$TAG_FLAG" ]; then
    if grep -q "test-keys" "$TMP_PROP"; then
        sed -i 's/test-keys/release-keys/g' "$TMP_PROP"
    fi
    note "test-keys to release-keys sanitization applied."
fi

# Finalize system.prop
if [ -s "$TMP_PROP" ]; then
    note "Sorting and creating final system.prop..."
    sort -u "$TMP_PROP" > "$SYSTEM_PROP"
    rm -f "$TMP_PROP"
    note "system.prop created at $SYSTEM_PROP."

    note "Waiting 30 seconds before applying props..."
    sleep 30

    note "Applying props via resetprop..."
    resetprop -n --file "$SYSTEM_PROP"
    note "Prop sanitization applied from system.prop"
fi

# Explicit fingerprint sanitization
if [ -f "$NODEBUG_FLAG" ] || [ -f "$TAG_FLAG" ]; then
    fp=$(getprop ro.build.fingerprint)
    fp_clean="$fp"

    [ -f "$NODEBUG_FLAG" ] && fp_clean=${fp_clean/userdebug/user}
    [ -f "$TAG_FLAG" ] && {
        fp_clean=${fp_clean/test-keys/release-keys}
        fp_clean=${fp_clean/dev-keys/release-keys}
    }

    if [ "$fp" != "$fp_clean" ]; then
        resetprop ro.build.fingerprint "$fp_clean"
        [ -f "$NODEBUG_FLAG" ] && resetprop ro.build.type "user"
        [ -f "$TAG_FLAG" ] && resetprop ro.build.tags "release-keys"
        note "Fingerprint sanitized to $fp_clean"
    else
        note "Fingerprint already clean. No changes applied."
    fi
fi
EOF
fi

if [ ! -f "$boot/hash.sh" ]; then
cat <<'EOF' > "$boot/hash.sh"
#!/system/bin/sh

HASH_FILE="/data/adb/Box-Brain/hash.txt"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/vbmeta.log"

mkdir -p "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

# Exit if module is disabled 
if [ -f "/data/adb/modules/playintegrityfix/disable" ]; then
    log "Integrity Box is disabled, exiting..."
    exit 0
fi

log " "
log "Script started"

# Find resetprop
RESETPROP=""
for RP in \
  /sbin/resetprop \
  /system/bin/resetprop \
  /system/xbin/resetprop \
  /data/adb/magisk/resetprop \
  /data/adb/ksu/bin/resetprop \
  $(command -v resetprop 2>/dev/null)
do
  if [ -x "$RP" ]; then
    RESETPROP="$RP"
    break
  fi
done

if [ -z "$RESETPROP" ]; then
  log "ERROR: resetprop binary not found. Exiting."
  exit 0
fi

log "Using resetprop: $RESETPROP"

# Always set static default props
"$RESETPROP" ro.boot.vbmeta.size "4096"
"$RESETPROP" ro.boot.vbmeta.hash_alg "sha256"
"$RESETPROP" ro.boot.vbmeta.avb_version "2.0"
"$RESETPROP" ro.boot.vbmeta.device_state "locked"
log "Set static VBMeta props: size=4096, hash_alg=sha256, avb_version=2.0, device_state=locked"

# Handle hash
if [ ! -s "$HASH_FILE" ]; then
  log "Hash file missing or empty : clearing vbmeta.digest"
  "$RESETPROP" --delete ro.boot.vbmeta.digest
  exit 0
fi

# Extract hash
DIGEST=$(tr -cd '0-9a-fA-F' < "$HASH_FILE")

if [ -z "$DIGEST" ]; then
  log "Hash file contained no valid hex. Clearing vbmeta.digest."
  "$RESETPROP" --delete ro.boot.vbmeta.digest
  exit 0
fi

if [ "${#DIGEST}" -ne 64 ]; then
  log "Invalid hash length (${#DIGEST}). Expected 64 (SHA-256). Clearing vbmeta.digest."
  "$RESETPROP" --delete ro.boot.vbmeta.digest
  exit 0
fi

# Set digest if valid
"$RESETPROP" ro.boot.vbmeta.digest "$DIGEST"
log "Set ro.boot.vbmeta.digest = $DIGEST"
log " "

exit 0
EOF
fi

if [ ! -f "$placeholder/june" ]; then
touch "$placeholder/june"
cat <<'EOF' > "$boot/prop.sh"
#!/system/bin/sh

# CONFIG
PATCH_DATE="2026-06-01"
FILE_PATH="/data/adb/tricky_store/security_patch.txt"
SKIP_FILE="/data/adb/Box-Brain/skip"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/prop_patch.log"

writelog() {
    TS="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$LOG_DIR" 2>/dev/null
    printf "%s | %s\n" "$TS" "$1" >> "$LOG_FILE"
}

abort() {
    writelog "ERROR | $1"
    exit 1
}

# SAFE MODE CHECK
#if [ -f "/data/adb/Box-Brain/safemode" ]; then
#    echo "$(date '+%Y-%m-%d %H:%M:%S') : Safemode active, script aborted." \
#        >> "/data/adb/Box-Brain/Integrity-Box-Logs/safemode.log"
#    exit 1
#fi

# RESETPROP CHECK
if ! command -v resetprop >/dev/null 2>&1; then
    abort "resetprop not found, cannot continue"
fi

# PROP SET FUNCTION
setprop_safe() {
    PROP=$1
    VALUE=$2
    CURRENT=$(getprop "$PROP")

    if [ "$CURRENT" = "$VALUE" ]; then
        writelog "✔ $PROP already set to $VALUE"
        return
    fi

    if resetprop "$PROP" "$VALUE"; then
        writelog "✔ Set $PROP to $VALUE (was: $CURRENT)"
    else
        writelog "❌ Failed to set $PROP (current: $CURRENT)"
    fi
}

# START LOG
writelog "•••••• Starting Security Patch Override ••••••"

# Exit if module is disabled 
if [ -f "/data/adb/modules/playintegrityfix/disable" ]; then
    writelog "Integrity Box is disabled, exiting..."
    exit 0
fi

# SAVE PATCH DATE
mkdir -p "/data/adb/tricky_store"
echo "all=$PATCH_DATE" > "$FILE_PATH" 2>>"$LOG_FILE"

# APPLY SYSTEM+VENDOR SECURITY PATCH
if [ -f "$SKIP_FILE" ]; then
    writelog "⚠ Sensitive device detected, skipping ro.vendor.build.security_patch"
else
    setprop_safe ro.vendor.build.security_patch "$PATCH_DATE"
    setprop_safe ro.build.version.security_patch "$PATCH_DATE"
fi

# FINAL VERIFICATION
BUILD_VAL=$(getprop ro.build.version.security_patch)
VENDOR_VAL=$(getprop ro.vendor.build.security_patch)

if [ -f "$SKIP_FILE" ]; then
    writelog "⚠ Sensitive device detected, Vendor patch override intentionally skipped"
else
    writelog "Vendor Patch Applied: $VENDOR_VAL"
    writelog "System Patch Applied: $BUILD_VAL"
fi

writelog "•••••• Script Finished Successfully ••••••"
exit 0
EOF
fi

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
