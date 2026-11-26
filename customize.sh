#!/system/bin/sh

MODDIR="${0%/*}"
FLAG="/data/adb/Box-Brain"
LOG_DIR="$FLAG/Integrity-Box-Logs"
INSTALL_LOG="$LOG_DIR/Installation.log"
LOG_FILE="$LOG_DIR/DeviceType.log"
SCRIPT="$MODPATH/webroot/common_scripts"
MEOW="/data/adb/modules/integrity-box"
SDK=$(getprop ro.system.build.version.sdk)
TRICKY="/data/adb/tricky_store"

mkdir -p "$FLAG" || true
mkdir -p "$FLAG/PIF" || true
mkdir -p "$LOG_DIR" || true
mkdir -p "$MEOW" || true
mkdir -p "$TRICKY" || true

touch "$FLAG/PIF/custom-pif"
touch "$FLAG/PIF/advanced"
touch "$FLAG/keyswitch"

debug() {
    echo "$1" | tee -a "$INSTALL_LOG"
}

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

setup_environment() {
    debug " ✦ Setting up Environment "
    debug " "
    chmod +x "$SCRIPT/key.sh"
    # The AutoPilot engine is an ARM64 binary: elsewhere it is removed, and the module's own scripts keep working
    # exactly as before (they hand over to the engine only when it is present).
    case "$(getprop ro.product.cpu.abi)" in
        arm64-v8a) chmod 755 "$SCRIPT/bin/box-autopilot" "$SCRIPT/ap2.sh" 2>/dev/null ;;
        *) rm -f "$SCRIPT/bin/box-autopilot" ;;
    esac
    sh "$SCRIPT/key.sh"
    debug " "
}

magisk_resetprop_rs() {
    local dir="$1"
    local arch fallback

    # Remove IB bundled Resetprop-RS binaries
    # if Magisk is not installed.
    if [ ! -f /data/adb/magisk/magisk ]; then
        rm -f "$dir"/resetprop-*
        return 0
    fi

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
        [ -f "$f" ] || continue

        local name
        name=$(basename "$f")

        case "$name" in
            "resetprop-${arch}"|"resetprop-${fallback}")
                chmod +x "$f"
                debug " ✔ Kept ${name}"
                ;;
            *)
                rm -f "$f"
                debug " ✗ Dropped ${name}"
                ;;
        esac
    done
}

manage_safemode() {
    local timeout_seconds=60 line
    
    ui_print "----------------------------------------"
    ui_print "        Safemode Configuration"
    ui_print "----------------------------------------"
    ui_print " "
    ui_print "  Safemode prevents certain custom ROM-specific"
    ui_print "  functions from running on stock ROMs. This is"
    ui_print "  intended to avoid potentially rare issues such as"
    ui_print "  bootloops or broken cameras on some devices"
    ui_print " "
    ui_print "  Safemode is enabled by default. Disabling it"
    ui_print "  can help improve Play Integrity results"
    ui_print " "
    ui_print "  You can always enable or disable it"
    ui_print "  later, manually through the WebUI"
    ui_print " "
    ui_print "  Volume Up   : Enable Safemode"
    ui_print "  Volume Down : Disable Safemode"
    ui_print "  No key press within 60 seconds: Enable by default"
    ui_print " "
    ui_print "  Press a volume key to make your choice..."
    ui_print " "
    ui_print "----------------------------------------"
    read -r -t "$timeout_seconds" line < <(getevent -ql | awk '/KEY_VOLUME/ {print; exit}')

    if [ $? -eq 142 ]; then
        debug " ✦ Timeout: enabling safemode by default"
        touch "$FLAG/safemode" 2>/dev/null
        return 0
    fi

    if echo "$line" | grep -q "KEY_VOLUMEUP"; then
        touch "$FLAG/safemode" 2>/dev/null
        debug " ✦ Volume Up pressed: safemode enabled"
    elif echo "$line" | grep -q "KEY_VOLUMEDOWN"; then
        rm -f "$FLAG/safemode" 2>/dev/null
        debug " ✦ Volume Down pressed: safemode disabled"
    else
        touch "$FLAG/safemode" 2>/dev/null
    fi
}

detect_rom() {
    local TS RESULT=0
    TS="$(date '+%Y-%m-%d %H:%M:%S')"

    > "$LOG_FILE" 2>/dev/null
    echo "ROM Detection Started - $TS" >> "$LOG_FILE" 2>/dev/null

    local props="
        ro.lineage.version
        ro.mod.version
        ro.custom.device
        sys.eliteprops.keybox
        sys.eliteprops.photos
        sys.eliteprops.pixelprops
        ro.lineage.build.version.plat.sdk
        ro.infinity.version
        ro.axion.version
        ro.crdroid.device
    "
    for prop in $props; do
        local val
        val=$(getprop "$prop" 2>/dev/null)
        if [ -n "$val" ]; then
            echo "$TS | Custom ROM detected via prop: $prop=$val" >> "$LOG_FILE" 2>/dev/null
            echo "Result: Custom ROM" >> "$LOG_FILE" 2>/dev/null
            echo "Detection Completed - $(date)" >> "$LOG_FILE" 2>/dev/null
            debug " ✦ ROM type: Custom ROM"
            #Disable built-in spoofing by default 
            touch "$FLAG/disablegms"
            touch "$FLAG/disablevending"
            return 1
        fi
    done

    local pkgs="
        org.lineageos.audiofx
        com.hentai.omaha
        com.nikgapps.overlay.gmscore
        com.android.axion.sandbox
        org.omnirom.omnijaws
        org.omnirom.omnistyle
        org.evolution.updater
        com.caf.fmradio
        org.lineageos.etar
        com.bitgapps.playstore.overlay
        co.aospa.sense.settings.overlay
        org.lineageos.aperture
        org.lineageos.aperture.frameworksbaseoverlay
        android.aosp.overlay
        lineageos.platform
        com.libremobileos.freeform
        org.calyxos.backup.contacts
        net.pixelos.ota
        org.clover.settings.overlay
        com.bootleggers.shishufied.clockfont.LowerAtmosphere
        com.goolag.pif
        com.rising.updater
        com.infinity.updater
    "
    for pkg in $pkgs; do
        if pm path "$pkg" >/dev/null 2>&1; then
            echo "$TS | Custom ROM detected via package: $pkg" >> "$LOG_FILE" 2>/dev/null
            echo "Result: Custom ROM" >> "$LOG_FILE" 2>/dev/null
            echo "Detection Completed - $(date)" >> "$LOG_FILE" 2>/dev/null
            debug " ✦ ROM type: Custom ROM"
            #Disable built-in spoofing by default 
            touch "$FLAG/disablegms"
            touch "$FLAG/disablevending"
            return 1
        fi
    done

    if getprop | grep -iq "lineage" 2>/dev/null; then
        echo "$TS | Custom ROM detected via getprop lineage" >> "$LOG_FILE" 2>/dev/null
        echo "Result: Custom ROM" >> "$LOG_FILE" 2>/dev/null
        echo "Detection Completed - $(date)" >> "$LOG_FILE" 2>/dev/null
        debug " ✦ ROM type: Custom ROM"
        #Disable built-in spoofing by default 
        touch "$FLAG/disablegms"
        touch "$FLAG/disablevending"
        return 1
    fi

    if [ -f /system/build.prop ] && grep -iq "lineage" /system/build.prop 2>/dev/null; then
        echo "$TS | Custom ROM detected via /system/build.prop" >> "$LOG_FILE" 2>/dev/null
        echo "Result: Custom ROM" >> "$LOG_FILE" 2>/dev/null
        echo "Detection Completed - $(date)" >> "$LOG_FILE" 2>/dev/null
        debug " ✦ ROM type: Custom ROM"
        #Disable built-in spoofing by default 
        touch "$FLAG/disablegms"
        touch "$FLAG/disablevending"
        return 1
    fi

    if [ -f /vendor/build.prop ] && grep -iq "lineage" /vendor/build.prop 2>/dev/null; then
        echo "$TS | Custom ROM detected via /vendor/build.prop" >> "$LOG_FILE" 2>/dev/null
        echo "Result: Custom ROM" >> "$LOG_FILE" 2>/dev/null
        echo "Detection Completed - $(date)" >> "$LOG_FILE" 2>/dev/null
        debug " ✦ ROM type: Custom ROM"
        #Disable built-in spoofing by default 
        touch "$FLAG/disablegms"
        touch "$FLAG/disablevending"
        return 1
    fi

    local sensitive_pkgs="
        com.samsung.android.app.updatecenter
        com.samsung.android.biometrics.app.setting
        com.samsung.android.game.gos
        com.sec.android.soagent
        com.xiaomi.account
        com.wssyncmldm
        com.oplus.ota
        com.xiaomi.misettings
        com.oplus.romupdate
    "
    local FOUND_SENSITIVE=0
    for pkg in $sensitive_pkgs; do
        if pm list packages -s 2>/dev/null | grep -q "^package:$pkg$"; then
            FOUND_SENSITIVE=1
            echo "$TS | PM_DETECTED | $pkg" >> "$LOG_FILE" 2>/dev/null
        elif find /system /product /system_ext /apex -type d -name "*$pkg*" 2>/dev/null | grep -q .; then
            FOUND_SENSITIVE=1
            echo "$TS | FS_DETECTED | $pkg" >> "$LOG_FILE" 2>/dev/null
        else
            echo "$TS | NOT_FOUND | $pkg" >> "$LOG_FILE" 2>/dev/null
        fi
    done

    if [ "$FOUND_SENSITIVE" -eq 1 ]; then
        touch "$FLAG/skip" 2>/dev/null
        debug " ✦ ROM type: Stock ROM"
        echo "$TS | ACTION | skip flag created (sensitive stock device)" >> "$LOG_FILE" 2>/dev/null
    fi

    echo "$TS | ACTION | safemode flag created" >> "$LOG_FILE" 2>/dev/null
    echo "Result: Stock ROM" >> "$LOG_FILE" 2>/dev/null
    echo "Detection Completed - $(date)" >> "$LOG_FILE" 2>/dev/null
    debug " ✦ ROM type: Stock ROM"
    manage_safemode
    return 0
}

set_integritybox_profile() {
    debug " ✦ Setting IntegrityBox Profile"
        if [ "$SDK" -ge 33 ]; then
            touch "$FLAG/pixelify"
        else
            touch "$FLAG/legacy"
        fi
}

boot_configuration() {
    debug " ✦ Fresh installation detected"
    debug " ✦ Enabling Boot Configuration UI"
    debug " ✦ Open WebUI after installation to"
    debug "   configure settings before rebooting"
    debug " "

    mkdir -p "$MEOW/webroot"
    cp "$MODPATH/toolkit/BootConfiguration/index.html" "$MEOW/webroot/index.html"
    chmod 644 "$MEOW/webroot/index.html"
}

cleanup() {
    chmod +x "$SCRIPT/cleanup.sh"
    sh "$SCRIPT/cleanup.sh"
}

prepare_directories() {
    debug " ✦ Preparing Required Directories  "
    [ ! -d "/data/adb/modules/integrity-box" ] && mkdir -p "/data/adb/modules/integrity-box"
    [ ! -f "$MODPATH/module.prop" ] && return 1
}

handle_module_props() {
    debug " ✦ Handling Module Properties "
    touch "$MEOW/update"
    cp "$MODPATH/module.prop" "$MEOW/module.prop" > /dev/null 2>&1
}

check_boot_hash() {
    debug " ✦ Creating Verified Boot Hash config"
    debug " "
    if [ ! -f "/data/adb/Box-Brain/hash.txt" ]; then
        touch "/data/adb/Box-Brain/hash.txt"
    fi
}

setup_blacklist() {
    if [ ! -f "$FLAG/blacklist.txt" ]; then
        cp "$MODPATH/toolkit/blacklist.txt" "$FLAG/blacklist.txt"
    fi
}

setup_status() {
    if [ ! -f "$FLAG/status.json" ]; then
        cp "$MODPATH/toolkit/status.json" "$FLAG/status.json"
    fi
}

release_source() {
    nohup am start -a android.intent.action.VIEW -d "https://t.me/MeowRedirect" > /dev/null 2>&1 &
}

enable_recommended_settings() {
    debug " ✦ Enabling Recommended Settings "
    touch "$FLAG/iframe_back_button"
    touch "$FLAG/noredirect"
    touch "$FLAG/ignore"
    touch "$FLAG/keyswitch"
    touch "$FLAG/wait"
    touch "$FLAG/autopilot"
    touch "$FLAG/force-reset"
    touch "$FLAG/PIF/skip_json"
    touch "$FLAG/PIF/skip_key"
    touch "$FLAG/PIF/advanced"
    touch "$FLAG/PIF/custom-pif"
}

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

install_module() {
    check_integrity
    prepare_directories
    handle_module_props
    check_boot_hash
    setup_environment
#    magisk_resetprop_rs "$MODPATH/resetprop-rs"
    cleanup
    setup_blacklist
    setup_status
    generate_hosts_block
}

chmod +x "$MODPATH/hello.sh"
sh "$MODPATH/hello.sh"

echo "
  ___     _                _ _        
 |_ _|_ _| |_ ___ __ _ _ _(_) |_ _  _ 
  | || ' \  _/ -_) _  | '_| |  _| || |
 |___|_||_\__\___\__, |_| |_|\__|\_, |
 | _ ) _____ __  |___/           |__/ 
 | _ \/ _ \ \ /                       
 |___/\___/_\_\                       
                                                
                                      
"

if [ -f "$MEOW/config.meow" ]; then
    cp "$MEOW/config.meow" "$MODPATH/config.meow"
elif [ ! -f "$MEOW/service.sh" ]; then
    cp "$MODPATH/toolkit/pixelify.prop" "$MODPATH/config.meow"
fi

if [ ! -f "$FLAG/integrity_box_ui_settings" ]; then
    cp "$MODPATH/toolkit/integrity_box_ui_settings" "$FLAG/integrity_box_ui_settings"
fi

[ -d "$TRICKY/keys" ] && rm -rf "$TRICKY/keys"
PATCH_DATE="$(cat "$FLAG/patch.txt" 2>/dev/null)"
# Same rule as patch_from_pif in common_func.sh (not sourced yet at this point): the fingerprint's patch wins
[ -z "$PATCH_DATE" ] && PATCH_DATE="$(sed -n 's/^SECURITY_PATCH=//p' "$MODPATH/config.meow" 2>/dev/null | head -n 1 | tr -d ' \t\r')"
case "$PATCH_DATE" in
    [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]) ;;
    *) PATCH_DATE="$(date '+%Y-%m-05')" ;;
esac
echo "all=$PATCH_DATE" > "$TRICKY/security_patch.txt"
 
install_module

# Fresh Installation 
if [ ! -f "$MEOW/service.sh" ]; then
    enable_recommended_settings
    set_integritybox_profile
    boot_configuration
    detect_rom
    release_source

    sed -i 's/^description=.*/description=> ᴄᴏɴꜰɪɢᴜʀᴇ ᴛʜᴇ ᴍᴏᴅᴜʟᴇ ʙᴇʜᴀᴠɪᴏᴜʀ ʙᴇꜰᴏʀᴇ ʀᴇʙᴏᴏᴛɪɴɢ ʙʏ ᴏᴘᴇɴɪɴɢ ᴛʜᴇ ᴡᴇʙᴜɪ/' "$MEOW/module.prop"
else
    sed -i 's/^description=.*/description=> If nobody was watching, nobody was judging, and nobody was there to applaud you, would your life still have a purpose?/' "$MODPATH/module.prop"
fi

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

PROP_FILE="/data/adb/modules/integrity-box/module.prop"
REQUIRED_LINE="support=https://t.me/MeowDump"
LOG_DIR="/data/adb/Box-Brain"

SERVICE_FILES="
/data/adb/service.d/shamiko.sh
/data/adb/service.d/prop.sh
/data/adb/service.d/hash.sh
/data/adb/service.d/lineage.sh
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

cat <<'EOF' > "$boot/lineage.sh"
#!/system/bin/sh

MODPATH="/data/adb/modules/integrity-box"
. $MODPATH/common_func.sh

# Module path and file references
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
PROP="/data/adb/modules/integrity-box/system.prop"

note() {
    TS="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$LOG_DIR" 2>/dev/null
    printf "%s | %s\n" "$TS" "$1" >> "$LOG_DIR/Lineage.log"
}

# Abort the script & delete flags wen safe mode is active 
if [ -f "/data/adb/Box-Brain/safemode" ]; then
    note "$(date '+%Y-%m-%d %H:%M:%S') : Safemode active, script aborted." >> "/data/adb/Box-Brain/Integrity-Box-Logs/safemode.log"
    safemode_flags
    exit 1
fi

# Exit if module is disabled 
if [ -f "/data/adb/modules/integrity-box/disable" ]; then
    note "Integrity Box is disabled, exiting..."
    exit 0
fi

# Module install path
export MODPATH="/data/adb/modules/integrity-box"

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

    # Convert Android getprop output from "[key]: [value]" to the
    # key=value syntax required by system.prop loaders.
    sed -i 's///g' "$TMP_PROP"
    sed -i -E 's/^\[([^]]+)\]: \[(.*)\]$/\1=\2/' "$TMP_PROP"
    sed -i -E '/^(init\.svc\.|init\.svc_debug_pid\.|ro\.boottime\.)/d' "$TMP_PROP"
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
        ro.modversion \
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

cat <<'EOF' > "$boot/hash.sh"
#!/system/bin/sh

HASH_FILE="/data/adb/Box-Brain/hash.txt"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/vbmeta.log"

mkdir -p "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

# Exit if module is disabled or safe mode is enabled 
if [ -f "/data/adb/modules/integrity-box/disable" ]; then
    log "Integrity Box is disabled, exiting..."
    exit 0
fi

if [ -f "/data/adb/Box-Brain/safemode" ]; then
    log "Safe mode is enabled"
    log "Skipping boot hash spoofing"
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

# Set static default props (preserve original avb_version if present)
"$RESETPROP" ro.boot.vbmeta.size "4096"
"$RESETPROP" ro.boot.vbmeta.hash_alg "sha256"
"$RESETPROP" ro.boot.vbmeta.device_state "locked"

ORIG_AVB=$(getprop ro.boot.vbmeta.avb_version)
if [ -z "$ORIG_AVB" ] || [ "$ORIG_AVB" = "2.0" ]; then
    "$RESETPROP" ro.boot.vbmeta.avb_version "1.3"
    log "Set VBMeta avb_version=1.3"
else
    log "Preserved native VBMeta avb_version=$ORIG_AVB"
fi

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

cat <<'EOF' > "$boot/prop.sh"
#!/system/bin/sh

# CONFIG
PATCH_FILE="/data/adb/Box-Brain/patch.txt"
FILE_PATH="/data/adb/tricky_store/security_patch.txt"
SKIP_FILE="/data/adb/Box-Brain/skip"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/prop_patch.log"
FALLBACK_DATE="2026-11-05"

writelog() {
    TS="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$LOG_DIR" 2>/dev/null
    printf "%s | %s\n" "$TS" "$1" >> "$LOG_FILE"
}

abort() {
    writelog "ERROR | $1"
    exit 1
}

# GET PATCH DATE
if [ -f "$PATCH_FILE" ]; then
    PATCH_DATE="$(tr -d ' \t\r\n' < "$PATCH_FILE")"
    PATCH_SOURCE="patch.txt"

elif [ -f "$FILE_PATH" ]; then
    PATCH_DATE="$(sed -n 's/^all=//p' "$FILE_PATH" | head -n 1 | tr -d ' \t\r\n')"
    PATCH_SOURCE="security_patch.txt"

else
    PATCH_DATE="$FALLBACK_DATE"
    PATCH_SOURCE="hardcoded fallback"
fi

# VALIDATE PATCH DATE
if ! echo "$PATCH_DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    abort "Invalid patch date from $PATCH_SOURCE"
fi

# SAFE MODE CHECK
if [ -f "/data/adb/Box-Brain/safemode" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') : Safemode active, script aborted." \
        >> "/data/adb/Box-Brain/Integrity-Box-Logs/safemode.log"
    safemode_flags
    exit 1
fi

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
writelog "Selected Patch Date: $PATCH_DATE (Source: $PATCH_SOURCE)"

# Exit if module is disabled
if [ -f "/data/adb/modules/integrity-box/disable" ]; then
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

##########################################
# adapted from Play Integrity Fork by @osm0sis
# source: https://github.com/osm0sis/PlayIntegrityFork
# license: GPL-3.0
##########################################

# Zygiskless installation 
if [ -d /sdcard/zygisk ] || [ -f /sdcard/zygisk ] || [ -f /data/adb/Box-Brain/zygisk ]; then
    debug " ✦ Proceeding Zygiskless Installation"
    debug " ✦ Disabled: Zygisk Attestation fallback"
    debug " ✦ Enabled:  Pixel Mode"
#    rm -rf "$FLAG/PIF/skip_json"
#    rm -rf "$FLAG/PIF/skip_key"
    sed -i 's/^description=.*/description=⏤͟͞𝗣𝗜𝗫𝗘𝗟 𝗠𝗢𝗗𝗘 🍋‍🟩 has been enabled, all zygisk related components has been removed/' "$MODPATH/module.prop"
    sed -i 's/^description=.*/description=⏤͟͞𝗣𝗜𝗫𝗘𝗟 𝗠𝗢𝗗𝗘 🍋‍🟩 has been enabled, all zygisk related components has been removed/' "$MEOW/module.prop"
    rm -rf $MODPATH/app_replace_list.txt \
        $MODPATH/autopif2.sh $MODPATH/classes.dex \
        $MODPATH/common_setup.sh $MODPATH/custom.app_replace_list.txt \
        $MODPATH/custom.pif.json \
        $MODPATH/legacy \
        $MODPATH/pif.json $MODPATH/config.meow $MODPATH/zygisk \
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
rm -f /data/data/com.google.android.gms/cache/config.meow /data/data/com.google.android.gms/config.meow \
    /data/data/com.google.android.gms/cache/pif.json /data/data/com.google.android.gms/pif.json

# Remove flag from /sdcard to avoid detection 
[ -f /sdcard/zygisk ] || [ -d /sdcard/zygisk ] && rm -rf /sdcard/zygisk

display_footer
exit 0

