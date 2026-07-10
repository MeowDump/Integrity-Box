#!/system/bin/sh

# Module and log directory paths
MODDIR="${0%/*}"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
INSTALL_LOG="$LOG_DIR/Installation.log"
SCRIPT="$MODPATH/webroot/common_scripts"
MEOW="/data/adb/modules/playintegrityfix"
SDK=$(getprop ro.system.build.version.sdk)
FLAG="/data/adb/Box-Brain"
TRICKY="/data/adb/tricky_store"
TIMEOUT=15

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR" || true
mkdir -p "$MEOW"
mkdir -p "$TRICKY"

# Support Hot Installation
#export MODULE_HOT_INSTALL_REQUEST="true"

# Set-up Resetprop-rs 
cleanup_resetprop_binaries() {
    local dir="$1"
    local arch fallback

    case "$(getprop ro.product.cpu.abi)" in
        arm64-v8a)
            arch="arm64-v8a"
            fallback="armeabi-v7a"
            ;;
        armeabi-v7a)
            arch="armeabi-v7a"
            fallback=""
            ;;
        x86_64)
            arch="x86_64"
            fallback="x86"
            ;;
        x86)
            arch="x86"
            fallback=""
            ;;
        *)
            arch="arm64-v8a"
            fallback="armeabi-v7a"
            ;;
    esac

    debug " ✦ Configuring Resetprop-RS"

    for f in "$dir"/resetprop-*; do
        local name
        name=$(basename "$f")
        case "$name" in
            "resetprop-${arch}"|\
            "resetprop-${fallback}")
                chmod +x "$f"
                debug " ✔ Kept ${name}"
                ;;
            *)
                rm -f "$f"
                debug " ✗  Removed ${name}"
                ;;
        esac
    done
}

# Logger
debug() {
    echo "$1" | tee -a "$INSTALL_LOG"
}

# Verify module integrity
check_integrity() {
    debug "========================================="
    debug "          Integrity Box Installer    "
    debug "========================================="
    debug " ✦ Verifying Module Integrity    "
    
    if [ -n "$ZIPFILE" ] && [ -f "$ZIPFILE" ]; then
        if [ -f "$MODPATH/verify.sh" ]; then
            if sh "$MODPATH/verify.sh"; then
                debug " ✦ Module integrity verified." > /dev/null 2>&1
            else
                debug " ✘ Module integrity check failed!"
                exit 1
            fi
        else
            debug " ✘ Missing verification script!"
            exit 1
        fi
    fi
}

rom_type() {
    # use getprop grep
    if getprop | grep -iq "lineage"; then
        return 0
    fi
    
    # read system build.prop
    if [ -f /system/build.prop ] && grep -iq "lineage" /system/build.prop; then
        return 0
    fi
    
    # read vendor build.prop
    if [ -f /vendor/build.prop ] && grep -iq "lineage" /vendor/build.prop; then
        return 0
    fi
    
    return 1
}

# Setup environment and permissions
setup_environment() {
    debug " ✦ Setting up Environment "
    chmod +x "$SCRIPT/key.sh"
    sh "$SCRIPT/key.sh"
}

hizru() {
    FLAG="/data/adb/Box-Brain"
    FLAG_FILE="$FLAG/skip"
    LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
    LOG_FILE="$LOG_DIR/skip.log"

    mkdir -p "$FLAG" "$LOG_DIR"

    PKGS="com.samsung.android.app.updatecenter com.samsung.android.biometrics.app.setting com.samsung.android.game.gos com.sec.android.soagent com.xiaomi.account com.wssyncmldm com.oplus.ota com.xiaomi.misettings com.oplus.romupdate"
    FOUND=0
    TS="$(date '+%Y-%m-%d %H:%M:%S')"

    for pkg in $PKGS; do
        if pm list packages -s 2>/dev/null | grep -q "^package:$pkg$"; then
            FOUND=1
            echo "$TS | PM_DETECTED | $pkg" >> "$LOG_FILE"
        elif find /system /product /system_ext /apex -type d -name "*$pkg*" 2>/dev/null | grep -q .; then
            FOUND=1
            echo "$TS | FS_DETECTED | $pkg" >> "$LOG_FILE"
        else
            echo "$TS | NOT_FOUND | $pkg" >> "$LOG_FILE"
        fi
    done

    if [ "$FOUND" -eq 1 ]; then
        touch "$FLAG_FILE"
        echo "$TS | ACTION | skip flag created" >> "$LOG_FILE"
        return 0
    fi

    echo "$TS | ACTION | no skip required" >> "$LOG_FILE"
    return 1
}

detect_rom() {
    if rom_type; then
        debug " ✦ ROM type: Custom ROM"
    else
        debug " ✦ ROM type: Stock / Spoofed"
        if [ ! -f "$MEOW/service.sh" ]; then
            touch "$FLAG/safemode"
        fi
    fi
}

set_integritybox_profile() {
    debug " ✦ Setting IntegrityBox Profile"
        if [ "$SDK" -ge 33 ]; then
            touch "$FLAG/pixelify"
        else
            touch "$FLAG/legacy"
        fi
}

# Clean up old logs and files
cleanup() {
    chmod +x "$SCRIPT/cleanup.sh"
    sh "$SCRIPT/cleanup.sh"
}

# Create necessary directories if missing
prepare_directories() {
    debug " ✦ Preparing Required Directories  "
    [ ! -d "/data/adb/modules/playintegrityfix" ] && mkdir -p "/data/adb/modules/playintegrityfix"
    [ ! -f "$MODPATH/module.prop" ] && return 1
}

# Handle module prop file
handle_module_props() {
    debug " ✦ Handling Module Properties "
    touch "$MEOW/update"
    cp "$MODPATH/module.prop" "$MEOW/module.prop"
}

# Verify boot hash file
check_boot_hash() {
    debug " ✦ Creating Verified Boot Hash config     "
    if [ ! -f "/data/adb/Box-Brain/hash.txt" ]; then
        touch "/data/adb/Box-Brain/hash.txt"
    fi
}

# Release the source
release_source() {
    [ -f "/data/adb/Box-Brain/noredirect" ] && return 0
    nohup am start -a android.intent.action.VIEW -d "https://t.me/MeowRedirect" > /dev/null 2>&1 &
}

# Enable recommended settings
enable_recommended_settings() {
    if [ ! -f "$MEOW/service.sh" ]; then
        debug " ✦ Enabling Recommended Settings "
        touch "$FLAG/iframe_back_button"
        touch "$FLAG/migrate_force"
        touch "$FLAG/run_migrate"
        touch "$FLAG/noredirect"
        touch "$FLAG/ignore"
        touch "$FLAG/rukja"
    fi
}

# Final footer message
display_footer() {
    debug "_________________________________________"
    debug " "
    debug "             Installation Completed "
    debug "    This module was released by 𝗠𝗘𝗢𝗪 𝗗𝗨𝗠𝗣"
    debug " "
    debug " "
    debug " "
    debug " "
    debug " "
    debug " "
}

# Main installation flow
install_module() {
#    check_integrity
    prepare_directories
    handle_module_props
    set_integritybox_profile
    setup_environment
    cleanup_resetprop_binaries "$MODPATH/resetprop-rs"
    hizru
    cleanup
    check_boot_hash
    enable_recommended_settings
    detect_rom
    release_source
}

echo "
  ___     _                _ _        
 |_ _|_ _| |_ ___ __ _ _ _(_) |_ _  _ 
  | || ' \  _/ -_) _  | '_| |  _| || |
 |___|_||_\__\___\__, |_| |_|\__|\_, |
 | _ ) _____ __  |___/           |__/ 
 | _ \/ _ \ \ /                       
 |___/\___/_\_\                       
                                                
                                      
  
"

# Set fingerprint on installation 
if [ -f "$MEOW/custom.pif.prop" ]; then
    cp "$MEOW/custom.pif.prop" "$MODPATH/custom.pif.prop"
elif [ ! -f "$MEOW/service.sh" ]; then
    if [ "$SDK" -le 31 ]; then
        cp "$MODPATH/toolkit/legacy.prop" "$MODPATH/custom.pif.prop"
    else
        cp "$MODPATH/toolkit/pixelify.prop" "$MODPATH/custom.pif.prop"
    fi
fi

# Quote of the day 
cat <<EOF > $LOG_DIR/.verify
DreamsWithoutDisciplineAreMerelyWishesThatFadeWithTheMorningLight
EOF

# remove old module id to avoid conflict
if [ -d /data/adb/modules/playintegrity ]; then
    touch "/data/adb/modules/playintegrity/remove"
fi

# Write security patch file if missing 
if [ ! -f $TRICKY/security_patch.txt ]; then
cat <<EOF > $TRICKY/security_patch.txt
all=2026-07-05
EOF
fi

# Start the installation process
install_module

# Create scripts 
boot="/data/adb/service.d"
placeholder="$MODPATH/webroot/common_scripts"
mkdir -p "$boot"

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

###if [ ! -f "$boot/lineage.sh" ]; then
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

# Abort the script & delete flags when safe mode is active 
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

NO_LINEAGE_FLAG="/data/adb/Box-Brain/NoLineageProp"
NODEBUG_FLAG="/data/adb/Box-Brain/nodebug"
TAG_FLAG="/data/adb/Box-Brain/tag"

TMP_PROP="$MODPATH/tmp.prop"
SYSTEM_PROP="$MODPATH/system.prop"
> "$TMP_PROP"

# Build summary of active flags
FLAGS_ACTIVE=""
[ -f "$NO_LINEAGE_FLAG" ] && FLAGS_ACTIVE="$FLAGS_ACTIVE NoLineageProp"
[ -f "$NODEBUG_FLAG" ] && FLAGS_ACTIVE="$FLAGS_ACTIVE nodebug"
[ -f "$TAG_FLAG" ] && FLAGS_ACTIVE="$FLAGS_ACTIVE tag"

if [ -n "$FLAGS_ACTIVE" ]; then
    note "Prop sanitization flags active: $FLAGS_ACTIVE"
    note "Preparing temporary prop file..."
    $RESETPROP_RS | grep "userdebug" >> "$TMP_PROP"
    $RESETPROP_RS | grep "test-keys" >> "$TMP_PROP"
    $RESETPROP_RS | grep "lineage_" >> "$TMP_PROP"

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
        $RESETPROP_RS --nuke "$prop"
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

    note "Applying props via resetprop-rs..."
    $RESETPROP_RS --file "$SYSTEM_PROP"
    note "Prop sanitization applied from system.prop"
fi

# Explicit fingerprint sanitization
if [ -f "$NODEBUG_FLAG" ] || [ -f "$TAG_FLAG" ]; then
    fp=$($RESETPROP_RS ro.build.fingerprint)
    fp_clean="$fp"

    [ -f "$NODEBUG_FLAG" ] && fp_clean=${fp_clean/userdebug/user}
    [ -f "$TAG_FLAG" ] && {
        fp_clean=${fp_clean/test-keys/release-keys}
        fp_clean=${fp_clean/dev-keys/release-keys}
    }

    if [ "$fp" != "$fp_clean" ]; then
        $RESETPROP_RS --stealth ro.build.fingerprint "$fp_clean"
        [ -f "$NODEBUG_FLAG" ] && $RESETPROP_RS --stealth ro.build.type "user"
        [ -f "$TAG_FLAG" ] && $RESETPROP_RS --stealth ro.build.tags "release-keys"
        note "Fingerprint sanitized to $fp_clean"
    else
        note "Fingerprint already clean. No changes applied."
    fi
fi
EOF
###fi

###if [ ! -f "$boot/hash.sh" ]; then
cat <<'EOF' > "$boot/hash.sh"
#!/system/bin/sh

HASH_FILE="/data/adb/Box-Brain/hash.txt"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/vbmeta.log"
RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-arm64-v8a"

# Fallback binary detection
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-armeabi-v7a"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86_64"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86"

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

# Verify resetprop-rs binary
if [ ! -x "$RESETPROP_RS" ]; then
  log "ERROR: resetprop-rs binary not found or not executable. Exiting."
  exit 0
fi

log "Using resetprop-rs: $RESETPROP_RS"

# Always set static default props 
$RESETPROP_RS --stealth ro.boot.vbmeta.size "4096"
$RESETPROP_RS --stealth ro.boot.vbmeta.hash_alg "sha256"
$RESETPROP_RS --stealth ro.boot.vbmeta.avb_version "2.0"
$RESETPROP_RS --stealth ro.boot.vbmeta.device_state "locked"
log "Set static VBMeta props: size=4096, hash_alg=sha256, avb_version=2.0, device_state=locked"

# Handle hash
if [ ! -s "$HASH_FILE" ]; then
  log "Hash file missing or empty : clearing vbmeta.digest"
  $RESETPROP_RS --nuke ro.boot.vbmeta.digest
  exit 0
fi

# Extract hash
DIGEST=$(tr -cd '0-9a-fA-F' < "$HASH_FILE")

if [ -z "$DIGEST" ]; then
  log "Hash file contained no valid hex. Clearing vbmeta.digest."
  $RESETPROP_RS --nuke ro.boot.vbmeta.digest
  exit 0
fi

if [ "${#DIGEST}" -ne 64 ]; then
  log "Invalid hash length (${#DIGEST}). Expected 64 (SHA-256). Clearing vbmeta.digest."
  $RESETPROP_RS --nuke ro.boot.vbmeta.digest
  exit 0
fi

# Set digest if valid
$RESETPROP_RS --stealth ro.boot.vbmeta.digest "$DIGEST"
log "Set ro.boot.vbmeta.digest = $DIGEST"
log " "

exit 0
EOF
###fi

if [ ! -f "$placeholder/july2" ]; then
touch "$placeholder/july2"
cat <<'EOF' > "$boot/prop.sh"
#!/system/bin/sh

# CONFIG
PATCH_DATE="2026-07-05"
FILE_PATH="/data/adb/tricky_store/security_patch.txt"
SKIP_FILE="/data/adb/Box-Brain/skip"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/prop_patch.log"
RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-arm64-v8a"

# Fallback binary detection
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-armeabi-v7a"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86_64"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86"

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

# RESETPROP-RS CHECK
if [ ! -x "$RESETPROP_RS" ]; then
    abort "resetprop-rs binary not found or not executable at $RESETPROP_RS"
fi

# PROP SET FUNCTION
setprop_safe() {
    PROP=$1
    VALUE=$2
    CURRENT=$($RESETPROP_RS "$PROP")

    if [ "$CURRENT" = "$VALUE" ]; then
        writelog "✔ $PROP already set to $VALUE"
        return
    fi

    if $RESETPROP_RS --stealth "$PROP" "$VALUE"; then
        writelog "✔ Stealth set $PROP to $VALUE (was: $CURRENT)"
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
BUILD_VAL=$($RESETPROP_RS ro.build.version.security_patch)
VENDOR_VAL=$($RESETPROP_RS ro.vendor.build.security_patch)

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

# A message for y'all 
sed -i 's/^description=.*/description=> Passing integrity checks means nothing if you’re missing life./' "$MEOW/module.prop"

##########################################
# adapted from Play Integrity Fork by @osm0sis
# source: https://github.com/osm0sis/PlayIntegrityFork
# license: GPL-3.0
##########################################

# Zygiskless installation 
if [ -e /sdcard/zygisk ] || [ -f /data/adb/Box-Brain/zygisk ]; then
    debug " ✦ Proceeding Zygiskless Installation"
    debug " ✦ Disabled: Zygisk Attestation fallback"
    debug " ✦ Enabled:  Pixel Mode"
    touch "$FLAG/zygisk"
    touch "$FLAG/keybox"
    touch "$FLAG/json"
    sed -i 's/^description=.*/description=Pixel Mode 🌱 has been enabled, all zygisk related components has been disabled/' "$MODPATH/module.prop"
    rm -rf $MODPATH/app_replace_list.txt \
        $MODPATH/autopif2.sh $MODPATH/classes.dex \
        $MODPATH/common_setup.sh $MODPATH/custom.app_replace_list.txt \
        $MODPATH/custom.pif.json \
        $MODPATH/example.pif.prop \
        $MODPATH/pif.json $MODPATH/pif.prop $MODPATH/zygisk \
        $MEOW/custom.app_replace_list.txt \
        $MEOW/custom.pif.json \
        $MEOW/skippersistprop \
        $MEOW/system
fi

# Copy any disabled app files to updated module
if [ -d $MEOW/system ]; then
    debug " ✦ Restoring disabled ROM apps configuration"
    cp -afL $MEOW/system $MODPATH
fi

# Warn if potentially conflicting modules are installed
if [ -d /data/adb/modules/MagiskHidePropsConf ]; then
    debug " ✦ MagiskHidePropsConfig (MHPC) module may cause issues with PIF"
    debug " ✦ Kindly disable or remove it"
fi

# Run common tasks for installation and boot-time
if [ -d "$MODPATH/zygisk" ]; then
    . $MODPATH/common_func.sh
    . $MODPATH/common_setup.sh
fi

# Clean up any leftover files from previous deprecated methods
rm -f /data/data/com.google.android.gms/cache/pif.prop /data/data/com.google.android.gms/pif.prop \
    /data/data/com.google.android.gms/cache/pif.json /data/data/com.google.android.gms/pif.json

# Remove flag from /sdcard to avoid detection 
[ -f /sdcard/zygisk ] || [ -d /sdcard/zygisk ] && rm -rf /sdcard/zygisk

# Hide Action & WebUI after update to enforce reboot.
# Some users flash (update) the module, skip rebooting, and still expect it to work.
# Then they report "bugs" that were already fixed in newer releases,
# while insisting they're on the latest version.
# If you didn't reboot, you're not actually running the update. 🙂
#if [ -f "$MEOW/action.sh" ] && [ -d "$MEOW/webroot" ]; then
#    mv "$MEOW/action.sh" "$MEOW/action.sh.bak"
#    mv "$MEOW/webroot" "$MEOW/webui"
#    sed -i 's/^description=.*/description=> 𝚁𝚎𝚋𝚘𝚘𝚝 𝚢𝚘𝚞𝚛 𝚙𝚑𝚘𝚗𝚎 𝚝𝚘 𝚞𝚜𝚎 𝚖𝚎 🪷🦢/' "$MEOW/module.prop"
#fi

display_footer
exit 0
