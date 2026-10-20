#!/system/bin/sh
# IntegrityBox Device Report Generator
# Output: /sdcard/MeowLog

#set -e

STAMP=$(date +%Y%m%d-%H%M%S)
TMP_DIR="/data/local/tmp/ib-report-$$"
OUT_DIR="$TMP_DIR/report"
OUT_FILE="/sdcard/MeowLog/IntegrityBox-report-$STAMP.tar.gz"
BOX_DIR="/data/adb/Box-Brain"
PIF_FILE="/data/adb/modules/playintegrityfix/custom.pif.prop"

mkdir -p "/sdcard/MeowLog"
mkdir -p "$OUT_DIR"

# Helpers
jescape() {
  echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_array() {
  awk '{printf "\"%s\",", $0}' | sed 's/,$//'
}

flag_status() {
  if [ -f "$BOX_DIR/$1" ]; then echo "true"; else echo "false"; fi
}

mask_fingerprint() {
    local FP
    FP="$(getprop ro.build.fingerprint 2>/dev/null)"
    [ -z "$FP" ] && FP="$(grep -m1 '^ro.build.fingerprint=' /system/build.prop /vendor/build.prop 2>/dev/null | cut -d= -f2)"
    [ -z "$FP" ] && FP="$(getprop ro.product.brand 2>/dev/null)/$(getprop ro.product.device 2>/dev/null)/$(getprop ro.build.version.release 2>/dev/null)"
    [ -z "$FP" ] && FP="unknown/unknown/unknown"
    FP="${FP#/}"
    FP="${FP%/}"
    local PREFIX="${FP%%/*}"
    local REST="${FP#*/}"
    PREFIX="${PREFIX}/"
    local SECOND="${REST%%/*}"
    PREFIX="${PREFIX}${SECOND}"
    local TAGS
    if [[ "$FP" == *:* ]]; then
        TAGS="${FP##*:}"
    else
        TAGS="unknown"
    fi
    echo "${PREFIX}/***MASKED***/${TAGS}"
}

# Collect Data

# Root
ROOT_IMPL="none"
[ -d /data/adb/ksu/bin ] && ROOT_IMPL="kernelsu"
[ -d /data/adb/ap/bin ] && ROOT_IMPL="apatch"
[ -d /data/adb/magisk ] && ROOT_IMPL="magisk"

# Build
FP_RAW="$(getprop ro.build.fingerprint)"
FP_MASKED="$(mask_fingerprint "$FP_RAW")"
BUILD_TAGS="$(getprop ro.build.tags 2>/dev/null || echo "N/A")"
BUILD_TYPE="$(getprop ro.build.type 2>/dev/null || echo "N/A")"

# Device
BRAND="$(getprop ro.product.brand 2>/dev/null || echo "N/A")"
MANUFACTURER="$(getprop ro.product.manufacturer 2>/dev/null || echo "N/A")"
MODEL="$(getprop ro.product.model 2>/dev/null || echo "N/A")"
DEVICE="$(getprop ro.product.device 2>/dev/null || echo "N/A")"

# Android
ANDROID_VER="$(getprop ro.build.version.release 2>/dev/null || echo "N/A")"
SDK="$(getprop ro.build.version.sdk 2>/dev/null || echo "N/A")"
SECURITY_PATCH="$(getprop ro.build.version.security_patch 2>/dev/null || echo "N/A")"

# Kernel
KERNEL_NAME="$(uname -s)"
KERNEL_RELEASE="$(uname -r)"
KERNEL_VERSION="$(uname -v)"
KERNEL_FULL="$(uname -a)"
PROC_VERSION="$(cat /proc/version 2>/dev/null || echo "N/A")"

# System State
SELINUX="$(getenforce 2>/dev/null || echo "unknown")"
VB_STATE="$(getprop ro.boot.verifiedbootstate 2>/dev/null || echo "unknown")"
VBMETA_STATE="$(getprop ro.boot.vbmeta.device_state 2>/dev/null || echo "unknown")"
FLASH_LOCKED="$(getprop ro.boot.flash.locked 2>/dev/null || echo "unknown")"
SECURE="$(getprop ro.secure 2>/dev/null || echo "unknown")"
DEBUGGABLE="$(getprop ro.debuggable 2>/dev/null || echo "unknown")"
QEMU="$(getprop ro.kernel.qemu 2>/dev/null || echo "N/A")"
[ -z "$QEMU" ] && QEMU="N/A"

# Play Services / Store
GMS_DUMP="$(dumpsys package com.google.android.gms 2>/dev/null)"
GMS_VNAME="$(echo "$GMS_DUMP" | grep versionName | head -n1 | cut -d= -f2 || echo "N/A")"
GMS_VCODE="$(echo "$GMS_DUMP" | grep versionCode | head -n1 | cut -d= -f2 | cut -d' ' -f1 || echo "N/A")"

PLAY_DUMP="$(dumpsys package com.android.vending 2>/dev/null)"
PLAY_VNAME="$(echo "$PLAY_DUMP" | grep versionName | head -n1 | cut -d= -f2 || echo "N/A")"
PLAY_VCODE="$(echo "$PLAY_DUMP" | grep versionCode | head -n1 | cut -d= -f2 | cut -d' ' -f1 || echo "N/A")"

# Apps
USER_APPS_FILE="$TMP_DIR/.user_apps.tmp"
SYSTEM_APPS_FILE="$TMP_DIR/.system_apps.tmp"
pm list packages -3 2>/dev/null | cut -d: -f2 > "$USER_APPS_FILE" || true
pm list packages -s 2>/dev/null | cut -d: -f2 > "$SYSTEM_APPS_FILE" || true

# PIF
PIF_JSON="{ }"
if [ -f "$PIF_FILE" ]; then
  PIF_JSON="$(
    awk -F= '
      BEGIN { print "{"; first=1 }
      $1=="verboseLogs" || $1=="spoofApps" || $1=="spoofBuild" || $1=="spoofProps" || $1=="spoofProvider" || $1=="spoofSignature" || $1=="spoofVendingFinger" || $1=="spoofPixel" || $1=="spoofVendingSdk" {
        if (!first) printf ",\n"
        first=0
        printf "  \"%s\": \"%s\"", $1, $2
      }
      END { if (!first) print ""; print "}" }
    ' "$PIF_FILE"
  )"
fi

# Modules
MODULES_FILE="$OUT_DIR/modules.json"
{
echo "["
FIRST=1
for m in /data/adb/modules/*; do
  [ -d "$m" ] || continue
  PROP="$m/module.prop"
  [ -f "$PROP" ] || continue

  ID="$(grep '^id=' "$PROP" | cut -d= -f2 || echo "")"
  NAME="$(grep '^name=' "$PROP" | cut -d= -f2 || echo "")"
  VERSION="$(grep '^version=' "$PROP" | cut -d= -f2 || echo "")"
  AUTHOR="$(grep '^author=' "$PROP" | cut -d= -f2 || echo "")"

  [ "$FIRST" -eq 0 ] && echo ","
  FIRST=0
  echo "  {"
  echo "    \"id\": \"$(jescape "$ID")\","
  echo "    \"name\": \"$(jescape "$NAME")\","
  echo "    \"version\": \"$(jescape "$VERSION")\","
  echo "    \"author\": \"$(jescape "$AUTHOR")\""
  echo -n "  }"
done
echo ""
echo "]"
} > "$MODULES_FILE"

# Write Individual JSON Files

# meta.json
{
echo "{"
echo "  \"generator\": \"IntegrityBox Report\","
echo "  \"version\": \"1.0\","
echo "  \"timestamp\": \"$(date -Iseconds)\""
echo "}"
} > "$OUT_DIR/meta.json"

# root.json
{
echo "{"
echo "  \"implementation\": \"$(jescape "$ROOT_IMPL")\""
echo "}"
} > "$OUT_DIR/root.json"

# build.json
{
echo "{"
echo "  \"fingerprint_raw\": \"$(jescape "$FP_RAW")\","
echo "  \"fingerprint_masked\": \"$(jescape "$FP_MASKED")\","
echo "  \"tags\": \"$(jescape "$BUILD_TAGS")\","
echo "  \"type\": \"$(jescape "$BUILD_TYPE")\""
echo "}"
} > "$OUT_DIR/build.json"

# device.json
{
echo "{"
echo "  \"brand\": \"$(jescape "$BRAND")\","
echo "  \"manufacturer\": \"$(jescape "$MANUFACTURER")\","
echo "  \"model\": \"$(jescape "$MODEL")\","
echo "  \"device\": \"$(jescape "$DEVICE")\""
echo "}"
} > "$OUT_DIR/device.json"

# android.json
{
echo "{"
echo "  \"version\": \"$(jescape "$ANDROID_VER")\","
echo "  \"sdk\": \"$(jescape "$SDK")\","
echo "  \"security_patch\": \"$(jescape "$SECURITY_PATCH")\""
echo "}"
} > "$OUT_DIR/android.json"

# kernel.json
{
echo "{"
echo "  \"name\": \"$(jescape "$KERNEL_NAME")\","
echo "  \"release\": \"$(jescape "$KERNEL_RELEASE")\","
echo "  \"version\": \"$(jescape "$KERNEL_VERSION")\","
echo "  \"full\": \"$(jescape "$KERNEL_FULL")\","
echo "  \"proc_version\": \"$(jescape "$PROC_VERSION")\""
echo "}"
} > "$OUT_DIR/kernel.json"

# system_state.json
{
echo "{"
echo "  \"selinux\": \"$(jescape "$SELINUX")\","
echo "  \"verified_boot\": \"$(jescape "$VB_STATE")\","
echo "  \"vbmeta_state\": \"$(jescape "$VBMETA_STATE")\","
echo "  \"flash_locked\": \"$(jescape "$FLASH_LOCKED")\","
echo "  \"secure\": \"$(jescape "$SECURE")\","
echo "  \"debuggable\": \"$(jescape "$DEBUGGABLE")\","
echo "  \"kernel_qemu\": \"$(jescape "$QEMU")\""
echo "}"
} > "$OUT_DIR/system_state.json"

# play.json
{
echo "{"
echo "  \"services\": {"
echo "    \"version_name\": \"$(jescape "$GMS_VNAME")\","
echo "    \"version_code\": \"$(jescape "$GMS_VCODE")\""
echo "  },"
echo "  \"store\": {"
echo "    \"version_name\": \"$(jescape "$PLAY_VNAME")\","
echo "    \"version_code\": \"$(jescape "$PLAY_VCODE")\""
echo "  }"
echo "}"
} > "$OUT_DIR/play.json"

# integritybox.json
echo "$PIF_JSON" > "$OUT_DIR/integritybox.json"

# apps_user.json
{
echo "{"
echo "  \"count\": $(wc -l < "$USER_APPS_FILE" | tr -d ' '),"
echo "  \"packages\": [$(cat "$USER_APPS_FILE" | json_array)]"
echo "}"
} > "$OUT_DIR/apps_user.json"

# apps_system.json
{
echo "{"
echo "  \"count\": $(wc -l < "$SYSTEM_APPS_FILE" | tr -d ' '),"
echo "  \"packages\": [$(cat "$SYSTEM_APPS_FILE" | json_array)]"
echo "}"
} > "$OUT_DIR/apps_system.json"

# flags.json
{
echo "{"
echo "  \"action_exec\": { \"name\": \"Auto Run\", \"enabled\": $(flag_status "action_exec") },"
echo "  \"boot\": {"
echo "    \"spoof-los-boot\": { \"name\": \"Hide Lineage\", \"enabled\": $(flag_status "spoof-los-boot") },"
echo "    \"nuke-los-boot\": { \"name\": \"Nuke Lineage\", \"enabled\": $(flag_status "nuke-los-boot") },"
echo "    \"spoof-custom-rom-boot\": { \"name\": \"Hide Custom ROM\", \"enabled\": $(flag_status "spoof-custom-rom-boot") },"
echo "    \"nuke-sus-boot\": { \"name\": \"Hide SUS Files\", \"enabled\": $(flag_status "nuke-sus-boot") }"
echo "  },"
echo "  \"reboot\": {"
echo "    \"NoLineageProp\": { \"name\": \"Spoof Lineage Props\", \"enabled\": $(flag_status "NoLineageProp") },"
echo "    \"nodebug\": { \"name\": \"Debug Fingerprint\", \"enabled\": $(flag_status "nodebug") },"
echo "    \"build\": { \"name\": \"Debug Build\", \"enabled\": $(flag_status "build") },"
echo "    \"tag\": { \"name\": \"Build Tag\", \"enabled\": $(flag_status "tag") },"
echo "    \"encrypt\": { \"name\": \"Spoof Encryption\", \"enabled\": $(flag_status "encrypt") },"
echo "    \"twrp\": { \"name\": \"Hide Recovery\", \"enabled\": $(flag_status "twrp") },"
echo "    \"skip\": { \"name\": \"Skip System Patch\", \"enabled\": $(flag_status "skip") },"
echo "    \"spoof-selinux-boot\": { \"name\": \"Spoof SELinux\", \"enabled\": $(flag_status "spoof-selinux-boot") },"
echo "    \"hidehook\": { \"name\": \"Hide PIF Detection\", \"enabled\": $(flag_status "hidehook") },"
echo "    \"safemode\": { \"name\": \"Safe Mode\", \"enabled\": $(flag_status "safemode") }"
echo "  },"
echo "  \"action\": {"
echo "    \"lsposed\": { \"name\": \"Clear LSposed\", \"enabled\": $(flag_status "lsposed") },"
echo "    \"gapps\": { \"name\": \"Clear Gapps Logs\", \"enabled\": $(flag_status "gapps") },"
echo "    \"root\": { \"name\": \"Clear Module Logs\", \"enabled\": $(flag_status "root") },"
echo "    \"ota\": { \"name\": \"OTA Fix\", \"enabled\": $(flag_status "ota") }"
echo "  },"
echo "  \"general\": {"
echo "    \"keymint\": { \"name\": \"Update OMK build\", \"enabled\": $(flag_status "keymint") },"
echo "    \"teesim\": { \"name\": \"Skip TEEsim\", \"enabled\": $(flag_status "teesim") },"
echo "    \"iframe_gesture_right\": { \"name\": \"Right Gestures\", \"enabled\": $(flag_status "iframe_gesture_right") },"
echo "    \"iframe_back_button\": { \"name\": \"Floating Back\", \"enabled\": $(flag_status "iframe_back_button") },"
echo "    \"keyswitch\": { \"name\": \"DNS Poisoning\", \"enabled\": $(flag_status "keyswitch") },"
echo "    \"noredirect\": { \"name\": \"No Redirect\", \"enabled\": $(flag_status "noredirect") }"
echo "  },"
echo "  \"kernel\": {"
echo "    \"buildtime\": { \"name\": \"Spoof Build Time\", \"enabled\": $(flag_status "buildtime") },"
echo "    \"customkernel\": { \"name\": \"Hide Custom Kernel\", \"enabled\": $(flag_status "customkernel") },"
echo "    \"emoji\": { \"name\": \"No Gore\", \"enabled\": $(flag_status "emoji") },"
echo "    \"chinese\": { \"name\": \"Made in China\", \"enabled\": $(flag_status "chinese") },"
echo "    \"telegram\": { \"name\": \"No Telegram\", \"enabled\": $(flag_status "telegram") },"
echo "    \"mention\": { \"name\": \"No Mention Tags\", \"enabled\": $(flag_status "mention") },"
echo "    \"cmdline\": { \"name\": \"Spoof CMDline\", \"enabled\": $(flag_status "cmdline") },"
echo "    \"board\": { \"name\": \"Spoof Kernel\", \"enabled\": $(flag_status "board") },"
echo "    \"scanall\": { \"name\": \"All of Above\", \"enabled\": $(flag_status "scanall") }"
echo "  }"
echo "}"
} > "$OUT_DIR/flags.json"

# Debug Logs

# getprop dump
getprop > "$OUT_DIR/getprop.txt" 2>/dev/null || true

# logcat
logcat -b all -d -f "$OUT_DIR/logcat.log" 2>/dev/null || true

# dmesg
dmesg > "$OUT_DIR/dmesg.log" 2>/dev/null || true

# KernelSU logs
for f in /data/adb/ksu/log/* /data/adb/ap/log/*; do
  [ -f "$f" ] && cp "$f" "$OUT_DIR/" 2>/dev/null || true
done

# Magisk logs
[ -f /cache/magisk.log ] && cp /cache/magisk.log "$OUT_DIR/" 2>/dev/null || true
[ -f /data/adb/magisk.log ] && cp /data/adb/magisk.log "$OUT_DIR/" 2>/dev/null || true

# tombstones & dropbox
if [ -d /data/tombstones ]; then
  mkdir -p "$OUT_DIR/tombstones"
  ls -t /data/tombstones | head -n 20 | while read f; do
    cp "/data/tombstones/$f" "$OUT_DIR/tombstones/" 2>/dev/null || true
  done
fi

if [ -d /data/system/dropbox ]; then
  mkdir -p "$OUT_DIR/dropbox"
  ls -t /data/system/dropbox | head -n 20 | while read f; do
    cp "/data/system/dropbox/$f" "$OUT_DIR/dropbox/" 2>/dev/null || true
  done
fi

# pstore
if [ -d /sys/fs/pstore ]; then
  mkdir -p "$OUT_DIR/pstore"
  cp /sys/fs/pstore/* "$OUT_DIR/pstore/" 2>/dev/null || true
fi

# Box-Brain copy
if [ -d "$BOX_DIR" ]; then
  cp -r "$BOX_DIR" "$OUT_DIR/"
else
  mkdir -p "$OUT_DIR/Box-Brain"
  echo "Box-Brain directory not found" > "$OUT_DIR/Box-Brain/README.txt"
fi

# Cleanup temp files
rm -f "$USER_APPS_FILE" "$SYSTEM_APPS_FILE"

# Compress with tar.gz
/system/bin/tar -czf "$OUT_FILE" -C "$TMP_DIR" report
rm -rf "$TMP_DIR"

echo ""
echo "========================================"
echo "  Report generated successfully"
echo "  $OUT_FILE"
echo "========================================"
