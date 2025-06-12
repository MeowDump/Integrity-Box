#!/system/bin/sh

# Define popup
popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

# Check for Magisk presence
is_magisk() {
    [ -d /data/adb/magisk ] || getprop | grep -q 'magisk'
}

# Module path and file references
MCTRL="${0%/*}"
SHAMIKO_WHITELIST="/data/adb/shamiko/whitelist"
NOHELLO_DIR="/data/adb/nohello"
NOHELLO_WHITELIST="$NOHELLO_DIR/whitelist"

# Initial states
shamiko_prev=""
nohello_prev=""

# Loop to monitor toggle state
while true; do
  if [ -f /sdcard/stop ]; then
    popup "Stop file found. Exiting background loop."
    break
  fi
  
  if [ ! -e "${MCTRL}/disable" ] && [ ! -e "${MCTRL}/remove" ]; then
    if is_magisk && [ ! -f /sdcard/stop ]; then

      if [ ! -f "$SHAMIKO_WHITELIST" ]; then
        touch "$SHAMIKO_WHITELIST"
      fi

      if [ -d "$NOHELLO_DIR" ] && [ ! -f "$NOHELLO_WHITELIST" ]; then
        touch "$NOHELLO_WHITELIST"
      fi

      # Show popup if Shamiko just got activated
      if [ "$shamiko_prev" != "on" ] && [ -f "$SHAMIKO_WHITELIST" ]; then
        popup "Shamiko Whitelist Mode Activated.✅"
        shamiko_prev="on"
      fi

      # Show popup if NoHello just got activated
      if [ "$nohello_prev" != "on" ] && [ -f "$NOHELLO_WHITELIST" ]; then
        popup "NoHello Whitelist Mode Activated.✅"
        nohello_prev="on"
      fi

    fi
  else
    if [ -f "$SHAMIKO_WHITELIST" ]; then
      rm -f "$SHAMIKO_WHITELIST"
      popup "Shamiko Blacklist Mode Activated.❌"
      shamiko_prev="off"
    fi

    if [ -f "$NOHELLO_WHITELIST" ]; then
      rm -f "$NOHELLO_WHITELIST"
      popup "NoHello Blacklist Mode Activated.❌"
      nohello_prev="off"
    fi
  fi
  sleep 4
done &

# Module install path
export MODPATH="/data/adb/modules/integrity_box"

# Remove LineageOS props (by @ez-me)
resetprop --delete ro.lineage.build.version
resetprop --delete ro.lineage.build.version.plat.rev
resetprop --delete ro.lineage.build.version.plat.sdk
resetprop --delete ro.lineage.device
resetprop --delete ro.lineage.display.version
resetprop --delete ro.lineage.releasetype
resetprop --delete ro.lineage.version
resetprop --delete ro.lineagelegal.url

# Create system.prop from build info
getprop | grep "userdebug" >> "$MODPATH/tmp.prop"
getprop | grep "test-keys" >> "$MODPATH/tmp.prop"
getprop | grep "lineage_"  >> "$MODPATH/tmp.prop"

sed -i 's///g'  "$MODPATH/tmp.prop"
sed -i 's/: /=/g' "$MODPATH/tmp.prop"
sed -i 's/userdebug/user/g' "$MODPATH/tmp.prop"
sed -i 's/test-keys/release-keys/g' "$MODPATH/tmp.prop"
sed -i 's/lineage_//g' "$MODPATH/tmp.prop"

sort -u "$MODPATH/tmp.prop" > "$MODPATH/system.prop"
rm -f "$MODPATH/tmp.prop"

sleep 30
resetprop -n --file "$MODPATH/system.prop"

# Hide unlocked bootloader
sleep 5
resetprop ro.boot.vbmeta.device_state locked
resetprop ro.boot.verifiedbootstate green
resetprop ro.boot.flash.locked 1
resetprop ro.boot.veritymode enforcing
resetprop vendor.boot.vbmeta.device_state locked
resetprop vendor.boot.verifiedbootstate green
resetprop ro.secureboot.lockstate locked
resetprop ro.boot.realmebootstate green
resetprop ro.boot.realme.lockstate 1
resetprop ro.bootmode unknown
resetprop ro.boot.bootmode unknown
resetprop vendor.boot.bootmode unknown
