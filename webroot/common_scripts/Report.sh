#!/system/bin/sh

OUT_DIR="/sdcard"
OUT_FILE="$OUT_DIR/report.json"

# helpers
jescape() {
  echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_array() {
  awk '{printf "\"%s\",", $0}' | sed 's/,$//'
}

mask_fingerprint() {
    local FP

    # Get fingerprint from getprop first
    FP="$(getprop ro.build.fingerprint 2>/dev/null)"

    # Fallback to build.prop
    [ -z "$FP" ] && FP="$(grep -m1 '^ro.build.fingerprint=' /system/build.prop /vendor/build.prop 2>/dev/null | cut -d= -f2)"

    # Fallback to pseudo fingerprint
    [ -z "$FP" ] && FP="$(getprop ro.product.brand 2>/dev/null)/$(getprop ro.product.device 2>/dev/null)/$(getprop ro.build.version.release 2>/dev/null)"

    # Default if empty
    [ -z "$FP" ] && FP="unknown/unknown/unknown"

    # Remove leading/trailing slashes
    FP="${FP#/}"
    FP="${FP%/}"

    # Use parameter expansion instead of IFS read to avoid byte splitting
    local PREFIX="${FP%%/*}"      # first part
    local REST="${FP#*/}"
    PREFIX="${PREFIX}/"
    local SECOND="${REST%%/*}"    # second part
    PREFIX="${PREFIX}${SECOND}"

    # Last colon-separated part as tag
    local TAGS
    case "$FP" in
        *:*) TAGS="${FP##*:}" ;;
        *)   TAGS="unknown" ;;
    esac

    echo "${PREFIX}/***MASKED***/${TAGS}"
}

# root implementation
ROOT_IMPL="none"
[ -d /data/adb/ksu/bin ] && ROOT_IMPL="kernelsu"
[ -d /data/adb/ap/bin ] && ROOT_IMPL="apatch"
[ -d /data/adb/magisk ] && ROOT_IMPL="magisk"

# fingerprint
FP_RAW="$(getprop ro.build.fingerprint)"
FP_MASKED="$(mask_fingerprint "$FP_RAW")"

# kernel
KERNEL_NAME="$(uname -s)"
KERNEL_RELEASE="$(uname -r)"
KERNEL_VERSION="$(uname -v)"
KERNEL_FULL="$(uname -a)"
PROC_VERSION="$(cat /proc/version 2>/dev/null)"

# system state
SELINUX="$(getenforce 2>/dev/null)"
VB_STATE="$(getprop ro.boot.verifiedbootstate)"
VBMETA_STATE="$(getprop ro.boot.vbmeta.device_state)"
FLASH_LOCKED="$(getprop ro.boot.flash.locked)"
SECURE="$(getprop ro.secure)"
DEBUGGABLE="$(getprop ro.debuggable)"
QEMU="$(getprop ro.kernel.qemu)"

# play services / store
GMS_DUMP="$(dumpsys package com.google.android.gms 2>/dev/null)"
GMS_VNAME="$(echo "$GMS_DUMP" | grep versionName | head -n1 | cut -d= -f2)"
GMS_VCODE="$(echo "$GMS_DUMP" | grep versionCode | head -n1 | cut -d= -f2 | cut -d' ' -f1)"

PLAY_DUMP="$(dumpsys package com.android.vending 2>/dev/null)"
PLAY_VNAME="$(echo "$PLAY_DUMP" | grep versionName | head -n1 | cut -d= -f2)"
PLAY_VCODE="$(echo "$PLAY_DUMP" | grep versionCode | head -n1 | cut -d= -f2 | cut -d' ' -f1)"

# user apps
pm list packages -3 | cut -d: -f2 > "$OUT_DIR/user_apps.tmp"

# PIF
PIF_FILE="/data/adb/modules/playintegrityfix/custom.pif.prop"

# default: empty object, formatted
PIF_JSON="{
    }"

if [ -f "$PIF_FILE" ]; then
  PIF_JSON="$(
    awk -F= '
      BEGIN {
        print "{"
        first=1
      }

      $1=="=verboseLogs" ||
      $1=="spoofApps" ||
      $1=="spoofBuild" ||
      $1=="spoofProps" ||
      $1=="spoofProvider" ||
      $1=="spoofSignature" ||
      $1=="spoofVendingFinger" ||
      $1=="spoofPixel" ||
      $1=="spoofVendingSdk" {

        if (!first) printf ",\n"
        first=0
        printf "        \"%s\": \"%s\"", $1, $2
      }

      END {
        if (!first) print ""
        print "    }"
      }
    ' "$PIF_FILE"
  )"
fi

# magisk modules
MODULES_JSON=""
for m in /data/adb/modules/*; do
  PROP="$m/module.prop"
  [ -f "$PROP" ] || continue

  ID="$(grep '^id=' "$PROP" | cut -d= -f2)"
  NAME="$(grep '^name=' "$PROP" | cut -d= -f2)"
  VERSION="$(grep '^version=' "$PROP" | cut -d= -f2)"
  AUTHOR="$(grep '^author=' "$PROP" | cut -d= -f2)"

  MODULES_JSON="${MODULES_JSON}{
    \"id\":\"$(jescape "$ID")\",
    \"name\":\"$(jescape "$NAME")\",
    \"version\":\"$(jescape "$VERSION")\",
    \"author\":\"$(jescape "$AUTHOR")\"
  },"
done

MODULES_JSON="[${MODULES_JSON%,}]"

# JSON
{
echo "{"
echo "  \"timestamp\": \"$(date -Iseconds)\","

echo "  \"root\": {"
echo "    \"implementation\": \"$(jescape "$ROOT_IMPL")\""
echo "  },"

echo "  \"build\": {"
echo "    \"fingerprint\": \"$(jescape "$FP_MASKED")\","
echo "    \"tags\": \"$(jescape "$(getprop ro.build.tags)")\","
echo "    \"type\": \"$(jescape "$(getprop ro.build.type)")\""
echo "  },"

echo "  \"device\": {"
echo "    \"brand\": \"$(jescape "$(getprop ro.product.brand)")\","
echo "    \"manufacturer\": \"$(jescape "$(getprop ro.product.manufacturer)")\","
echo "    \"model\": \"$(jescape "$(getprop ro.product.model)")\","
echo "    \"device\": \"$(jescape "$(getprop ro.product.device)")\""
echo "  },"

echo "  \"android\": {"
echo "    \"version\": \"$(jescape "$(getprop ro.build.version.release)")\","
echo "    \"sdk\": \"$(jescape "$(getprop ro.build.version.sdk)")\","
echo "    \"security_patch\": \"$(jescape "$(getprop ro.build.version.security_patch)")\""
echo "  },"

echo "  \"kernel\": {"
echo "    \"name\": \"$(jescape "$KERNEL_NAME")\","
echo "    \"release\": \"$(jescape "$KERNEL_RELEASE")\","
echo "    \"version\": \"$(jescape "$KERNEL_VERSION")\","
echo "    \"full\": \"$(jescape "$KERNEL_FULL")\","
echo "    \"proc_version\": \"$(jescape "$PROC_VERSION")\""
echo "  },"

echo "  \"system_state\": {"
echo "    \"selinux\": \"$(jescape "$SELINUX")\","
echo "    \"verified_boot\": \"$(jescape "$VB_STATE")\","
echo "    \"vbmeta_state\": \"$(jescape "$VBMETA_STATE")\","
echo "    \"flash_locked\": \"$(jescape "$FLASH_LOCKED")\","
echo "    \"secure\": \"$(jescape "$SECURE")\","
echo "    \"debuggable\": \"$(jescape "$DEBUGGABLE")\","
echo "    \"kernel_qemu\": \"$(jescape "$QEMU")\""
echo "  },"

echo "  \"play\": {"
echo "    \"services\": {"
echo "      \"version_name\": \"$(jescape "$GMS_VNAME")\","
echo "      \"version_code\": \"$(jescape "$GMS_VCODE")\""
echo "    },"
echo "    \"store\": {"
echo "      \"version_name\": \"$(jescape "$PLAY_VNAME")\","
echo "      \"version_code\": \"$(jescape "$PLAY_VCODE")\""
echo "    }"
echo "  },"

echo "  \"playintegrityfix\": $PIF_JSON,"

echo "  \"modules\": $MODULES_JSON,"

echo "  \"user_apps\": [$(json_array < "$OUT_DIR/user_apps.tmp")]"

echo "}"
} > "$OUT_FILE"

rm -f "$OUT_DIR/user_apps.tmp"

echo
echo "======================================"
echo " Report generated successfully"
echo " $OUT_FILE"
echo "======================================"
