#!/system/bin/sh
MODPATH="${0%/*}"
. $MODPATH/common_func.sh

# Module path and file references
PIF="$MODPATH"
ROOT_SOL=$(detect_root_solution)
SCRIPT="$MODPATH/webroot/common_scripts/autopilot.sh"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
PROP="$PIF/system.prop"
PROP1="ro.crypto.state=encrypted"
PROP2="ro.build.tags=release-keys"
PROP3="ro.build.type=user"
LOG="$LOG_DIR/service.log"
LOG2="$LOG_DIR/encrypt.log"
#LOG3="$LOG_DIR/autopif.log"
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
sleep 120

# Spoof Encryption 
{
  echo "ENCRYPT CHECK ($(date))"

  if [ -f /data/adb/Box-Brain/encrypt ]; then
    if grep -qxF "$PROP1" "$PROP"; then
      echo "Prop already exists, no action needed"
    else
      echo "$PROP1" >> "$PROP"
      echo "Spoofed prop: $PROP1"
    fi
  else
    if grep -qxF "$PROP1" "$PROP"; then
      sed -i "\|^${PROP1}\$|d" "$PROP"
      echo "Removed line: $PROP1"
    else
      echo "Prop not present, no action needed"
    fi
  fi

  echo
} >> "$LOG2" 2>&1

# Spoof Tag 
{
  echo "TAG CHECK ($(date))"

  if [ -f /data/adb/Box-Brain/tag ]; then
    if grep -qxF "$PROP2" "$PROP"; then
      echo "Prop already exists, no action needed"
    else
      echo "$PROP2" >> "$PROP"
      echo "Spoofed prop: $PROP2"
    fi
  else
    if grep -qxF "$PROP2" "$PROP"; then
      sed -i "\|^${PROP2}\$|d" "$PROP"
      echo "Removed line: $PROP2"
    else
      echo "Prop not present, no action needed"
    fi
  fi

  echo
} >> "$LOG5" 2>&1

# Spoof Build 
{
  echo "BUILD CHECK ($(date))"

  if [ -f /data/adb/Box-Brain/build ]; then
    if grep -qxF "$PROP3" "$PROP"; then
      echo "Prop already exists, no action needed"
    else
      echo "$PROP3" >> "$PROP"
      echo "Spoofed prop: $PROP3"
    fi
  else
    if grep -qxF "$PROP3" "$PROP"; then
      sed -i "\|^${PROP3}\$|d" "$PROP"
      echo "Removed line: $PROP3"
    else
      echo "Prop not present, no action needed"
    fi
  fi

  echo
} >> "$LOG6" 2>&1

# Rename twrp folder to avoid root detection
{
  echo "TWRP/FOX RENAME ($(date))"
  echo
  [ -f /data/adb/Box-Brain/twrp ] && hide_recovery_folders
} >> "$LOG4" 2>&1

# Stop daemon if needed 
if [ -f "/data/adb/Box-Brain/rukja" ]; then
    exit 0
fi

# Restart daemon if dead
while true; do
    if [ -f "/data/adb/Box-Brain/autopilot" ]; then
        # Check heartbeat
        last=$(cat /data/adb/Box-Brain/daemon_heartbeat 2>/dev/null || echo "0")
        now=$(date +%s)
        
        # Dead if no heartbeat for 3+ minutes
        if [ $((now - last)) -gt 180 ]; then
            # Clean stale locks
            rm -rf /data/adb/Box-Brain/autorun.lockdir \
                   /data/adb/Box-Brain/.executing 2>/dev/null
            
            # Restart
            sh "$SCRIPT" >/dev/null 2>&1 &
        fi
    fi
    
    sleep 60
done
