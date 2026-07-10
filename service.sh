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

# Boot-Phase Properties
# Wait for boot using resetprop-rs
###$RESETPROP_RS --wait sys.boot_completed 0
wait_for_boot

# •••• EARLY BOOT PROPS ••••

# Bootloader/VBMeta
$RESETPROP_RS --stealth "ro.boot.vbmeta.device_state" "locked"
$RESETPROP_RS --stealth "vendor.boot.vbmeta.device_state" "locked"
$RESETPROP_RS --stealth "ro.boot.verifiedbootstate" "green"
$RESETPROP_RS --stealth "vendor.boot.verifiedbootstate" "green"
$RESETPROP_RS --stealth "ro.boot.flash.locked" "1"
$RESETPROP_RS --stealth "ro.boot.veritymode" "enforcing"

# Warranty/Debug
$RESETPROP_RS --stealth "ro.boot.warranty_bit" "0"
$RESETPROP_RS --stealth "ro.warranty_bit" "0"
$RESETPROP_RS --stealth "ro.vendor.boot.warranty_bit" "0"
$RESETPROP_RS --stealth "ro.vendor.warranty_bit" "0"
$RESETPROP_RS --stealth "ro.debuggable" "0"
$RESETPROP_RS --stealth "ro.force.debuggable" "0"
$RESETPROP_RS --stealth "ro.secure" "1"
$RESETPROP_RS --stealth "ro.adb.secure" "1"
$RESETPROP_RS --stealth "sys.oem_unlock_allowed" "0"

# Build
$RESETPROP_RS --stealth "ro.build.type" "user"
$RESETPROP_RS --stealth "ro.build.tags" "release-keys"

# OEM-Specific
$RESETPROP_RS --stealth "ro.secureboot.lockstate" "locked"
$RESETPROP_RS --stealth "ro.boot.realmebootstate" "green"
$RESETPROP_RS --stealth "ro.boot.realme.lockstate" "1"

# Recovery Mode Hiding
$RESETPROP_RS --stealth "ro.bootmode" "unknown"
$RESETPROP_RS --stealth "ro.boot.bootmode" "unknown"
$RESETPROP_RS --stealth "vendor.boot.bootmode" "unknown"

# Other props
$RESETPROP_RS --stealth persist.sys.developer_options 0
$RESETPROP_RS --stealth persist.sys.dev_mode 0
$RESETPROP_RS --stealth persist.sys.debuggable 0
$RESETPROP_RS --stealth ro.oem_unlock_supported 0
$RESETPROP_RS --stealth ro.hardware.virtual_device 0

# SELinux
$RESETPROP_RS --stealth "ro.boot.selinux" "enforcing"
[ -f "$MODPATH/skipdelprop" ] || $RESETPROP_RS --nuke "ro.build.selinux"

# Compact arenas after early props
$RESETPROP_RS --compact

wait_for_boot

# Spoof Encryption 
{
  echo "ENCRYPT CHECK ($(date))"

  if [ -f $BOX/encrypt ]; then
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

  if [ -f $BOX/tag ]; then
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

  if [ -f $BOX/build ]; then
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
  [ -f $BOX/twrp ] && hide_recovery_folders
} >> "$LOG4" 2>&1

# Hide PIF
if [ -f "$BOX/hidehook" ]; then
   log "hidehook flag found, executing resetprop.sh..."
   sh "$SCRIPT/resetprop.sh"
   log "resetprop.sh executed successfully"
else
   log "hidehook flag not found, skipping resetprop.sh"
fi

# Hide custom ROM
if [ -f "$BOX/spoof-custom-rom-boot" ]; then
   log "spoof-custom-rom-boot flag found, executing prop.sh..."
   sh "$SCRIPT/prop.sh"
   log "prop.sh executed successfully"
else
   log "spoof-custom-rom-boot flag not found, skipping prop.sh"
fi

# Hide sus files
if [ -f "$BOX/nuke-sus-boot" ]; then
   log "nuke-sus-boot flag found, executing susfiles.sh..."
   sh "$SCRIPT/susfiles.sh"
   log "susfiles.sh executed successfully"
else
   log "nuke-sus-boot flag not found, skipping susfiles.sh"
fi

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

# Override lineage props
if [ -f "$BOX/spoof-los-boot" ]; then
   log "spoof-los-boot flag found, executing override_lineage.sh..."
   sh "$SCRIPT/override_lineage.sh"
   log "override_lineage.sh executed successfully"
else
   log "spoof-los-boot flag not found, skipping override_lineage.sh"
fi

# Nuke lineage props
if [ -f "$BOX/nuke-los-boot" ]; then
   log "nuke-los-boot flag found, executing force_override.sh..."
   sh "$SCRIPT/force_override.sh"
   log "force_override.sh executed successfully"
else
   log "nuke-los-boot flag not found, skipping force_override.sh"
fi
