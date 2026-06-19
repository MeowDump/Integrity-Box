#!/system/bin/sh

# Module and log directory paths
MODDIR="${0%/*}"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
INSTALL_LOG="$LOG_DIR/Installation.log"
SCRIPT="$MODPATH/webroot/common_scripts"
MEOW="/data/adb/modules/playintegrityfix"
SRC="/data/adb/modules_update/playintegrityfix/module.prop"
SDK=$(getprop ro.system.build.version.sdk)
DEST="$MEOW/module.prop"
FLAG="/data/adb/Box-Brain"
TIMEOUT=15

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR" || true
mkdir -p "$MEOW"

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
                abort " ✘ Module integrity check failed!"
            fi
        else
            abort " ✘ Missing verification script!"
        fi
    fi
}

rom_type() {
    # use getprop grep
    if getprop | grep -iq "lineage"; then
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

# Clean up old logs and files
cleanup() {
    chmod +x "$SCRIPT/cleanup.sh"
    sh "$SCRIPT/cleanup.sh"
}

# Clean up old logs and files
butter_chicken() {
    chmod +x "$MODPATH/consent.sh"
    sh "$MODPATH/consent.sh"
}

setup_keybox() {
  local BASE="$1"
  [ -z "$BASE" ] && return 0

  local SRC="$BASE/keybox"
  local DST="/data/adb/tricky_store"

  # Ensure destination directory exists
  [ -d "$DST" ] || {
    mkdir -p "$DST" || return 1
    chmod 700 "$DST"
  }

  for f in keybox2.xml keybox3.xml; do
    [ -f "$DST/$f" ] && continue
    [ -f "$SRC/$f" ] || continue
    cp "$SRC/$f" "$DST/$f" || continue
    chmod 600 "$DST/$f"
    chown root:root "$DST/$f" 2>/dev/null
  done
}

# Create necessary directories if missing
prepare_directories() {
    debug " ✦ Preparing Required Directories  "
    [ ! -d "/data/adb/modules/playintegrityfix" ] && mkdir -p "/data/adb/modules/playintegrityfix"
    [ ! -f "$SRC" ] && return 1
}

# Handle module prop file
handle_module_props() {
    debug " ✦ Handling Module Properties "
    touch "$MEOW/update"
    cp "$SRC" "$DEST"
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
    debug " ✦ Enabling Recommended Settings "
    touch "$FLAG/iframe_back_button"
    touch "$FLAG/migrate_force"
    touch "$FLAG/run_migrate"
    touch "$FLAG/noredirect"
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
}

# Main installation flow
install_module() {
    check_integrity
    prepare_directories
    handle_module_props
    setup_environment
    hizru
    cleanup
    check_boot_hash
    setup_keybox "$MODPATH"
    enable_recommended_settings
    butter_chicken
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
if [ -f "/data/adb/modules/playintegrityfix/pixel.txt" ]; then
    cp "/data/adb/modules/playintegrityfix/pixel.txt" "$MODPATH/pixel.txt"
elif [ ! -f "/data/adb/modules/playintegrityfix/service.sh" ]; then
    cp "$MODPATH/fingerprint/pixel.txt" "$MODPATH/pixel.txt"
fi

# Quote of the day 
cat <<EOF > $LOG_DIR/.verify
hash
EOF

# remove old module id to avoid conflict
if [ -d /data/adb/modules/playintegrity ]; then
    touch "/data/adb/modules/playintegrity/remove"
fi

# Detect ROM
if rom_type; then
    debug " ✦ ROM type: CUSTOM ROM"
else
    touch "$FLAG/safemode"
fi

# Write security patch file if missing 
if [ ! -f /data/adb/tricky_store/security_patch.txt ]; then
cat <<EOF > /data/adb/tricky_store/security_patch.txt
all=2026-06-01
EOF
fi

# Start the installation process
install_module

#[ ! -f "$FLAG/consent" ] && butter_chicken

debug " ✦ Setting IntegrityBox Profile"
# Only set profile on fresh installation 
if [ ! -f "/data/adb/modules/playintegrityfix/service.sh" ]; then
    if [ "$SDK" -ge 33 ]; then
        touch "$FLAG/pixelify"
    else
        touch "$FLAG/legacy"
    fi
fi

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
if [ -f "$MEOW/action.sh" ] && [ -d "$MEOW/webroot" ]; then
    mv "$MEOW/action.sh" "$MEOW/action.sh.bak"
    mv "$MEOW/webroot" "$MEOW/webui"
    sed -i 's/^description=.*/description=> 𝚁𝚎𝚋𝚘𝚘𝚝 𝚢𝚘𝚞𝚛 𝚙𝚑𝚘𝚗𝚎 𝚝𝚘 𝚞𝚜𝚎 𝚖𝚎 🪷🦢/' "$MEOW/module.prop"
fi

display_footer
