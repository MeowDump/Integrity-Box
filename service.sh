#!/system/bin/sh
MODPATH="${0%/*}"
. $MODPATH/common_func.sh

# Module path and file references
PIF="/data/adb/modules/playintegrityfix"
SCRIPT="$MODPATH/webroot/common_scripts"
BOX="/data/adb/Box-Brain"
LOG_DIR="$BOX/Integrity-Box-Logs"
PROP="$PIF/system.prop"
PROP1="ro.crypto.state=encrypted"
PROP2="ro.build.tags=release-keys"
PROP3="ro.build.type=user"
LOG="$LOG_DIR/service.log"
LOG2="$LOG_DIR/encrypt.log"
LOG4="$LOG_DIR/twrp.log"
LOG5="$LOG_DIR/tag.log"
LOG6="$LOG_DIR/build.log"

# Log folder
mkdir -p "$LOG_DIR"

# Logger function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG"
}

setup_resetprop

# Boot-Phase Properties
# Wait for boot (Magisk/KSU/APatch with resetprop only)
case "$ROOT_SOL" in
    magisk|kernelsu|apatch) $PROP_WAIT sys.boot_completed 0 ;;
esac

# •••• EARLY BOOT PROPS ••••

# Bootloader/VBMeta
resetprop_if_diff "ro.boot.vbmeta.device_state" "locked"
resetprop_if_diff "vendor.boot.vbmeta.device_state" "locked"
resetprop_if_diff "ro.boot.verifiedbootstate" "green"
resetprop_if_diff "vendor.boot.verifiedbootstate" "green"
resetprop_if_diff "ro.boot.flash.locked" "1"
resetprop_if_diff "ro.boot.veritymode" "enforcing"

# Warranty/Debug
resetprop_if_diff "ro.boot.warranty_bit" "0"
resetprop_if_diff "ro.warranty_bit" "0"
resetprop_if_diff "ro.vendor.boot.warranty_bit" "0"
resetprop_if_diff "ro.vendor.warranty_bit" "0"
resetprop_if_diff "ro.debuggable" "0"
resetprop_if_diff "ro.force.debuggable" "0"
resetprop_if_diff "ro.secure" "1"
resetprop_if_diff "ro.adb.secure" "1"
resetprop_if_diff "sys.oem_unlock_allowed" "0"

# Build
resetprop_if_diff "ro.build.type" "user"
resetprop_if_diff "ro.build.tags" "release-keys"

# OEM-Specific
resetprop_if_diff "ro.secureboot.lockstate" "locked"  # MIUI
resetprop_if_diff "ro.boot.realmebootstate" "green"   # Realme
resetprop_if_diff "ro.boot.realme.lockstate" "1"       # Realme

# Recovery Mode Hiding
resetprop_if_match "ro.bootmode" "recovery" "unknown"
resetprop_if_match "ro.boot.bootmode" "recovery" "unknown"
resetprop_if_match "vendor.boot.bootmode" "recovery" "unknown"

# USB/ADB
# Reset system properties if mismatch
#[ -n "$(resetprop sys.usb.adb.disabled)" ] && [ "$(resetprop sys.usb.adb.disabled)" != "1" ] && resetprop sys.usb.adb.disabled 1
#[ -n "$(resetprop service.adb.root)" ] && [ "$(resetprop service.adb.root)" != "0" ] && resetprop service.adb.root 0

# Other props use normal function
resetprop_if_diff persist.sys.developer_options 0
resetprop_if_diff persist.sys.dev_mode 0
resetprop_if_diff persist.sys.debuggable 0
resetprop_if_diff ro.oem_unlock_supported 0
resetprop_if_diff ro.hardware.virtual_device 0

# SELinux
resetprop_if_diff "ro.boot.selinux" "enforcing"
[ "$ROOT_SOL" = "magisk" ] && ! [ -f "$MODPATH/skipdelprop" ] && delprop_if_exist "ro.build.selinux"

# Fix SELinux permissions if permissive
#if [ "$(cat /sys/fs/selinux/enforce 2>/dev/null)" = "0" ]; then
#    chmod 640 /sys/fs/selinux/enforce 2>/dev/null
#    chmod 440 /sys/fs/selinux/policy 2>/dev/null
#fi

# Run compact after early props if supported
run_compact
wait_for_boot

# Toggle a system.prop spoof line
spoof_prop_line() {
  local FLAG="$1"
  local LINE="$2"
  local HEADER="$3"

  echo "$HEADER CHECK ($(date))"

  if [ -f "$BOX/$FLAG" ]; then
    if grep -qxF "$LINE" "$PROP"; then
      echo "Prop already exists, no action needed"
    else
      echo "$LINE" >> "$PROP"
      echo "Spoofed prop: $LINE"
    fi
  else
    if grep -qxF "$LINE" "$PROP"; then
      sed -i "\|^${LINE}\$|d" "$PROP"
      echo "Removed line: $LINE"
    else
      echo "Prop not present, no action needed"
    fi
  fi

  echo
}

# Spoof Encryption / Tag / Build
spoof_prop_line "encrypt" "$PROP1" "ENCRYPT" >> "$LOG2" 2>&1
spoof_prop_line "tag"     "$PROP2" "TAG"     >> "$LOG5" 2>&1
spoof_prop_line "build"   "$PROP3" "BUILD"   >> "$LOG6" 2>&1

# Rename twrp folder to avoid root detection
{
  echo "TWRP/FOX RENAME ($(date))"
  echo
  [ -f "$BOX/twrp" ] && hide_recovery_folders
} >> "$LOG4" 2>&1

# Run a flag-triggered script
run_flagged_script() {
  local FLAG="$1"
  local SCRIPT_NAME="$2"

  if [ -f "$BOX/$FLAG" ]; then
    log "$FLAG flag found, executing $SCRIPT_NAME..."
    sh "$SCRIPT/$SCRIPT_NAME"
    log "$SCRIPT_NAME executed successfully"
  else
    log "$FLAG flag not found, skipping $SCRIPT_NAME"
  fi
}

run_flagged_script "hidehook"            "resetprop.sh"
run_flagged_script "spoof-custom-rom-boot" "prop.sh"
run_flagged_script "nuke-sus-boot"       "susfiles.sh"
run_flagged_script "spoof-los-boot"      "override_lineage.sh"
run_flagged_script "nuke-los-boot"       "force_override.sh"

# Spoof selinux status
if [ -f "$BOX/spoof-selinux-boot" ]; then
    log "spoof-selinux-boot flag found"
    if [ "$(getenforce)" != "Enforcing" ]; then
        log "Current SELinux status: $(getenforce), changing to enforcing"
        setenforce 1
        log "SELinux status spoofed to enforcing"
    else
        log "SELinux already enforcing, no change needed"
    fi
else
    log "spoof-selinux-boot flag not found, skipping"
fi

# Stop daemon if needed
if [ -f "$BOX/rukja" ]; then
    exit 0
fi

# Daemon watchdog
if [ -f "$BOX/autopilot" ]; then
    (
        while true; do
            last=$(cat "$BOX/daemon_heartbeat" 2>/dev/null || echo "0")
            now=$(date +%s)

            if [ $((now - last)) -gt 180 ]; then
                rm -rf "$BOX/autorun.lockdir" "$BOX/.executing" 2>/dev/null
                sh "$SCRIPT/autopilot.sh" >/dev/null 2>&1 &
            fi

            sleep 60
        done
    ) &
fi
