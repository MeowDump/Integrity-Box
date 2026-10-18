#!/system/bin/sh
# Pixel Canary pif.prop generator script by osm0sis @ xda-developers

# This file is primarily adapted from PlayIntegrityFork
# Original repository: https://github.com/osm0sis/PlayIntegrityFork
#
# Minor modifications by: https://github.com/MeowDump
#
# Copyright (C) 2026 Original author of PlayIntegrityFork (https://github.com/osm0sis)
#
# Licensed under GNU GPL‑3.0 ~ see LICENSE file for details.

until [ -z "$1" ]; do
  case "$1" in
    -h|--help|help) echo "sh autopif4.sh [-a|-s] [-m]"; exit 0;;
    -a|--advanced|advanced) ARGS="-a"; shift;;
    -s|--strong|strong) FORCE_STRONG=1; shift;;
    -m|--match|match) FORCE_MATCH=1; shift;;
    *) break;;
  esac;
done;

case "$0" in
  *.sh) DIR="$0";;
  *) DIR="$(lsof -p $$ 2>/dev/null | grep -o '/.*autopif4.sh$')";;
esac;
DIR=$(dirname "$(readlink -f "$DIR")");

item() { printf ' ✦ %s\n' "$*"; }
die() { printf ' ✖ %s\n' "$*" >&2; exit 1; }
die_bb() { die "$*, install busybox"; }
warn() { printf ' 😭 %s\n' "$*" >&2; }


# Download fallback
DOWNLOAD_SWITCH="/data/adb/Box-Brain/keyswitch"
fetch_file() {
  OUT="$1"
  URL="$2"
  REFERER="$3"

  if [ ! -f "$DOWNLOAD_SWITCH" ]; then
    rm -f "$OUT"
    if [ -n "$REFERER" ]; then
      wget -q -T 10 -O "$OUT" --header "Referer: $REFERER" --no-check-certificate "$URL" 2>/dev/null
    else
      wget -q -T 10 -O "$OUT" --no-check-certificate "$URL" 2>/dev/null
    fi
    STATUS=$?
    if [ "$STATUS" -eq 0 ] && [ -s "$OUT" ]; then
      return 0
    fi
    rm -f "$OUT"
    return 1
  fi

  # Only announce fallback retries if that initial download fails
  rm -f "$OUT"
  if [ -n "$REFERER" ]; then
    wget -q -T 30 -t 1 -O "$OUT" --header "Referer: $REFERER" --no-check-certificate "$URL" 2>/dev/null
  else
    wget -q -T 30 -t 1 -O "$OUT" --no-check-certificate "$URL" 2>/dev/null
  fi
  STATUS=$?
  if [ "$STATUS" -eq 0 ] && [ -s "$OUT" ]; then
    return 0
  fi
  rm -f "$OUT"

  item "Initial download failed for $OUT"
  item "Retrying with compatibility fallbacks..."
  ATTEMPT=2
  while [ "$ATTEMPT" -le 5 ]; do
    item "Retrying... $((ATTEMPT - 1))/5"

    if command -v curl >/dev/null 2>&1; then
      if [ -n "$REFERER" ]; then
        curl -fsSL --connect-timeout 30 --max-time 120 --insecure -H "Referer: $REFERER" "$URL" -o "$OUT" 2>/dev/null
      else
        curl -fsSL --connect-timeout 30 --max-time 120 --insecure "$URL" -o "$OUT" 2>/dev/null
      fi
      STATUS=$?
      if [ "$STATUS" -eq 0 ] && [ -s "$OUT" ]; then
        return 0
      fi
      rm -f "$OUT"
    fi

    # Retry with wget as well, in case curl is unavailable or also fails.
    if [ -n "$REFERER" ]; then
      wget -q -T 30 -t 1 -O "$OUT" --header "Referer: $REFERER" --no-check-certificate "$URL" 2>/dev/null
    else
      wget -q -T 30 -t 1 -O "$OUT" --no-check-certificate "$URL" 2>/dev/null
    fi
    STATUS=$?
    if [ "$STATUS" -eq 0 ] && [ -s "$OUT" ]; then
      return 0
    fi
    rm -f "$OUT"

    if [ "$ATTEMPT" -lt 5 ]; then
      sleep "$((ATTEMPT - 1))"
    fi
    ATTEMPT=$((ATTEMPT + 1))
  done
  return 1
}

# Profiles
BOX_BRAIN="/data/adb/Box-Brain"
PIF_DIR="$BOX_BRAIN/PIF"
MODE=""
if [ -f "$BOX_BRAIN/wipe" ]; then
  MODE="wipe"
elif [ -f "$BOX_BRAIN/pixelify" ]; then
  MODE="pixelify"
elif [ -f "$BOX_BRAIN/advanced" ]; then
  MODE="advanced"
elif [ -f "$BOX_BRAIN/legacy" ]; then
  MODE="legacy"
fi
case "$MODE" in
  pixelify) item "Current Profile : Pixelify" ;;
  advanced) item "Current Profile : Supreme" ;;
  legacy) item "Current Profile : Legacy" ;;
  wipe) item "Current Profile : Meta" ;;
  *) item "Current Profile : Existing Configuration" ;;
esac

find_busybox() {
  [ -n "$BUSYBOX" ] && return 0;
  local path;
  for path in /data/adb/modules/busybox-ndk/system/*/busybox /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
    if [ -f "$path" ]; then
      BUSYBOX="$path";
      return 0;
    fi;
  done;
  return 1;
}

if ! which wget >/dev/null || grep -q "wget-curl" $(which wget); then
  if ! find_busybox; then
    die_bb "wget not found";
  elif $BUSYBOX ping -c1 -s2 android.com 2>&1 | grep -q "bad address"; then
    die_bb "wget broken";
  else
    wget() { $BUSYBOX wget "$@"; }
  fi;
fi;

if date -D '%s' -d "$(date '+%s')" 2>&1 | grep -qE "bad date|invalid option"; then
  if ! find_busybox; then
    die_bb "date broken";
  else
    date() { $BUSYBOX date "$@"; }
  fi;
fi;

if ! echo "A\nB" | grep -m1 -A1 "A" | grep -q "B"; then
  if ! find_busybox; then
    die_bb "grep broken";
  else
    grep() { $BUSYBOX grep "$@"; }
  fi;
fi;

if [ "$DIR" = /data/adb/modules/playintegrityfix ]; then
  DIR=$DIR/autopif4;
  mkdir -p $DIR;
fi;
cd "$DIR";

SPOOF_APPS=""
for CONFIG_FILE in "$DIR/../custom.pif.prop" "$DIR/custom.pif.prop" /data/adb/modules/playintegrityfix/custom.pif.prop; do
  if [ -f "$CONFIG_FILE" ]; then
    SPOOF_APPS=$(sed -n 's/^[[:space:]]*spoofApps[[:space:]]*=[[:space:]]*\([01]\)[[:space:]]*$/\1/p' "$CONFIG_FILE" | head -n 1)
    [ -n "$SPOOF_APPS" ] && break
  fi
done

item "Fetching Pixel device list...";
fetch_file PIXEL_VERSIONS_HTML "https://developer.android.com/about/versions" "" || die "Failed to download Pixel device list";
LATEST_BETA=$(grep -B4 -A2 'data-icon="preview' PIXEL_VERSIONS_HTML | grep -o 'href="/about/versions/.*[0-9]"' | cut -d\" -f2 | grep -vE '/versions/(1[7-9]|[2-9][0-9])');
[ "$LATEST_BETA" ] || LATEST_BETA=$(grep -oE 'href="/about/versions/[0-9]{2}"' PIXEL_VERSIONS_HTML | cut -d\" -f2 | grep -vE '/versions/(1[7-9]|[2-9][0-9])' | sort -ru | head -n1);
fetch_file PIXEL_LATEST_HTML "https://developer.android.com$LATEST_BETA" "" || die "Failed to download latest Pixel version page";
fetch_file PIXEL_FI_HTML "https://developer.android.com$(grep -o 'href=".*download.*"' PIXEL_LATEST_HTML | grep -v 'ota' | cut -d\" -f2 | sort -ru | head -n1)" "" || die "Failed to download factory image page";
fetch_file PIXEL_OTA_HTML "https://developer.android.com$(grep -o 'href=".*download-ota.*"' PIXEL_LATEST_HTML | cut -d\" -f2 | sort -ru | head -n1)" "" || die "Failed to download OTA page";
SRC=FI; [ "$(grep 'tr id=' PIXEL_FI_HTML | sed 's;.*<tr id="\(.*\)">.*;\1;' | wc -w)" -lt "$(grep 'tr id=' PIXEL_OTA_HTML | sed 's;.*<tr id="\(.*\)">.*;\1;' | wc -w)" ] && SRC=OTA;
MODEL_LIST="$(grep -A1 'tr id=' PIXEL_${SRC}_HTML | grep 'td' | sed 's;.*<td>\(.*\)</td>.*;\1;')";
PRODUCT_LIST="$(grep 'tr id=' PIXEL_${SRC}_HTML | sed 's;.*<tr id="\(.*\)">.*;\1_beta;')";
[ -n "$PRODUCT_LIST" ] || die "Pixel device list is empty";

item "Selecting Pixel build...";
if [ "$FORCE_MATCH" ]; then
  DEVICE="$(getprop ro.product.device)";
  case "$(echo ' '$PRODUCT_LIST' ')" in
    *" ${DEVICE}_beta "*)
      MODEL="$(getprop ro.product.model)";
      PRODUCT="${DEVICE}_beta";
    ;;
  esac;
fi;
set_random_beta() {
  local list_count="$(echo "$MODEL_LIST" | wc -l)";
  local list_rand="$((RANDOM % $list_count + 1))";
  local IFS=$'\n';
  set -- $MODEL_LIST;
  MODEL="$(eval echo \${$list_rand})";
  set -- $PRODUCT_LIST;
  PRODUCT="$(eval echo \${$list_rand})";
  DEVICE="$(echo "$PRODUCT" | sed 's/_beta//')";
}
if [ -z "$PRODUCT" ]; then
  set_random_beta;
fi;
item "Selected $MODEL";
printf '\n';

get_canary_info() {
  item "Fetching build metadata...";
  fetch_file PIXEL_FLASH_HTML "https://flash.android.com/" "" || die "Failed to download Flash Android page";
  fetch_file PIXEL_STATION_JSON "https://content-flashstation-pa.googleapis.com/v1/builds?product=$PRODUCT&key=$(grep -o '<body data-client-config=.*' PIXEL_FLASH_HTML | cut -d\; -f2 | cut -d\& -f1)" "https://flash.android.com" || die "Failed to download Pixel build metadata";
  tac PIXEL_STATION_JSON | grep -m1 -A13 '"canary": true' > PIXEL_CANARY_JSON;
  ID="$(grep 'releaseCandidateName' PIXEL_CANARY_JSON | cut -d\" -f4)";
  INCREMENTAL="$(grep 'buildId' PIXEL_CANARY_JSON | cut -d\" -f4)";
}
get_canary_info;
if [ -z "$ID" -o -z "$INCREMENTAL" ] && [ "$FORCE_MATCH" ]; then
  warn "Failed to extract matching build info from JSON";
  item "Retrying with another Pixel build...";
  set_random_beta;
  item "Selected $MODEL";
  get_canary_info;
fi;
[ -z "$ID" -o -z "$INCREMENTAL" ] && die "Failed to extract build info from JSON";


FI="$(grep 'factoryImageDownloadUrl' PIXEL_CANARY_JSON | cut -d\" -f4)";
FI_HOST="$(echo "$FI" | sed 's;^.*://\(.*\)$;\1;' | cut -d/ -f1)";
FI_PATH="/$(echo "$FI" | sed 's;^.*://\(.*\)$;\1;' | cut -d/ -f2-)";
if [ "$FI" -a "$FI_HOST" -a "$FI_PATH" ]; then
  nc $FI_HOST 80 <<EOF | tr -d '\r' > PIXEL_ZIP_HEADERS;
HEAD $FI_PATH HTTP/1.1
Host: $FI_HOST
Connection: close

EOF
else
  warn "Failed to extract Factory Image URL from JSON";
fi;
if [ ! -s PIXEL_ZIP_HEADERS ] || ! grep -q 'Last-Modified' PIXEL_ZIP_HEADERS; then
  wget -q -T 10 -S --spider -o PIXEL_ZIP_HEADERS --no-check-certificate "$FI" 2>&1;
fi;
if [ -f PIXEL_ZIP_HEADERS ] && grep -q 'Last-Modified' PIXEL_ZIP_HEADERS; then
  CANARY_REL_DATE="$(date -D '%a, %d %b %Y %H:%M:%S %Z' -d "$(grep -o 'Last-Modified.*' PIXEL_ZIP_HEADERS | cut -d\  -f2-)" '+%Y-%m-%d')";
  CANARY_EXP_DATE="$(date -D '%s' -d "$(($(date -D '%Y-%m-%d' -d "$CANARY_REL_DATE" '+%s') + 60 * 60 * 24 * 7 * 6))" '+%Y-%m-%d')";
  item "Build metadata: $CANARY_REL_DATE ·";
  item "Build expiry $CANARY_EXP_DATE";
else
  warn "Failed to determine Release Date from HTTP headers";
  CANARY_REL_DATE="Unknown";
  CANARY_EXP_DATE="Unknown";
fi;

printf '\n';
item "Applying security patch";
SECURITY_PATCH="2026-10-05";

item "Resolving API level...";
case $DEVICE in
  bluejay) DEVICE_INITIAL_SDK_INT=32;; # Pixel 6a
  panther|cheetah) DEVICE_INITIAL_SDK_INT=33;; # Pixel 7 Series
  lynx) DEVICE_INITIAL_SDK_INT=33;; # Pixel 7a
  felix) DEVICE_INITIAL_SDK_INT=33;; # Pixel Fold
  tangorpro) DEVICE_INITIAL_SDK_INT=33;; # Pixel Tablet
  shiba|husky) DEVICE_INITIAL_SDK_INT=34;; # Pixel 8 Series
  akita) DEVICE_INITIAL_SDK_INT=34;; # Pixel 8a
  tokay|caiman|komodo|comet) DEVICE_INITIAL_SDK_INT=34;; # Pixel 9 Series
  tegu) DEVICE_INITIAL_SDK_INT=35;; # Pixel 9a
  frankel|blazer|mustang|rango) DEVICE_INITIAL_SDK_INT=36;; # Pixel 10 Series
  stallion) DEVICE_INITIAL_SDK_INT=35;; # Pixel 10a; Actual 36
  cubs|grizzly|kodiak|yogi) DEVICE_INITIAL_SDK_INT=35;; # Pixel 11 Series
  *) DEVICE_INITIAL_SDK_INT=32;;
esac;
#printf '\n';

printf '\n';
item "Building Pixel config...";
cat <<EOF > pif.prop;
MANUFACTURER=Google
MODEL=$MODEL
FINGERPRINT=google/$PRODUCT/$DEVICE:CANARY/$ID/$INCREMENTAL:user/release-keys
PRODUCT=$PRODUCT
DEVICE=$DEVICE
SECURITY_PATCH=$SECURITY_PATCH
DEVICE_INITIAL_SDK_INT=$DEVICE_INITIAL_SDK_INT
EOF

# Apply the mode detected at startup. Wipe takes precedence.
for MIGRATE in "$DIR/migrate.sh" /data/adb/modules/playintegrityfix/migrate.sh; do
  [ -f "$MIGRATE" ] && break
done

if [ -f "$MIGRATE" ]; then
  item "Generating custom config..."
  # Preserve the existing main config; migrate.sh backs it up if present.
  rm -f pif.json custom.pif.json
  sh "$MIGRATE" -i -f pif.prop custom.pif.prop || die "Migration to custom.pif.prop failed"

  if [ -f custom.pif.prop ]; then
    # Keep only canonical build fields from migration output, then append the selected profile.
    TMP_CONFIG="custom.pif.prop.tmp"
    awk '
      /^# Build Fields[[:space:]]*$/ { in_build=1; next }
      in_build && /^[A-Z_]+=/ { print; next }
      in_build && !/^[A-Z_]+=/ { exit }
    ' custom.pif.prop > "$TMP_CONFIG"
    [ -s "$TMP_CONFIG" ] || die "Could not extract build fields from migrated config"
    mv -f "$TMP_CONFIG" custom.pif.prop

    case "$MODE" in
      pixelify)
        [ -n "$SPOOF_APPS" ] || SPOOF_APPS=1
        printf '\n# Configuration\nspoofBuild=1\nspoofProps=1\nspoofPixel=1\nspoofApps=%s\nspoofVendingFinger=1\nspoofProvider=0\nspoofSignature=0\nspoofVendingSdk=0\nverboseLogs=0\n' "$SPOOF_APPS" >> custom.pif.prop
        ;;
      advanced)
        [ -n "$SPOOF_APPS" ] || SPOOF_APPS=0
        printf '\n# Configuration\nspoofBuild=1\nspoofProps=1\nspoofPixel=0\nspoofApps=%s\nspoofVendingFinger=1\nspoofProvider=0\nspoofSignature=0\nspoofVendingSdk=0\nverboseLogs=0\n' "$SPOOF_APPS" >> custom.pif.prop
        ;;
      legacy)
        [ -n "$SPOOF_APPS" ] || SPOOF_APPS=0
        printf '\n# Configuration\nspoofBuild=1\nspoofProps=1\nspoofPixel=0\nspoofApps=%s\nspoofVendingFinger=0\nspoofProvider=0\nspoofSignature=0\nspoofVendingSdk=0\nverboseLogs=0\n' "$SPOOF_APPS" >> custom.pif.prop
        ;;
      wipe) ;;
    esac

    RUN_DATE=$(date '+%Y-%m-%d')
    {
      printf '\n# Canary Released: %s\n\n' "${CANARY_REL_DATE:-Unknown}"
      printf '# Estimated Expiry: %s\n\n' "${CANARY_EXP_DATE:-Unknown}"
      printf '# Generated by Integrity Box on %s\n' "$RUN_DATE"
    } >> custom.pif.prop

    if [ ! -f "$PIF_DIR/skip_json" ]; then
      # Export only canonical build fields, in their existing order.
      # The generated-by comment is JSONC; no config or system properties are exported.
      {
        printf '{\n'
        printf '  // Generated by Integrity Box on %s\n' "$RUN_DATE"
        awk -F= '
          BEGIN {
            count=0
            fields[1]="MANUFACTURER"; fields[2]="MODEL"; fields[3]="FINGERPRINT"
            fields[4]="BRAND"; fields[5]="PRODUCT"; fields[6]="DEVICE"
            fields[7]="RELEASE"; fields[8]="ID"; fields[9]="INCREMENTAL"
            fields[10]="TYPE"; fields[11]="TAGS"; fields[12]="SECURITY_PATCH"
            fields[13]="DEVICE_INITIAL_SDK_INT"
          }
          /^[A-Z_]+=/ {
            key=$1
            for (i=1; i<=13; i++) if (key == fields[i]) {
              value=substr($0, index($0, "=")+1)
              gsub(/\\/, "\\\\", value); gsub(/"/, "\\\"", value)
              printf "  \"%s\": \"%s\"%s\n", key, value, (count < 12 ? "," : "")
              count++
              break
            }
          }
        ' custom.pif.prop
        printf '}\n'
      } > /sdcard/meow.json
      printf '\n';
      item "Exported /sdcard/meow.json"
    fi
  else
    die "Migration did not create custom.pif.prop"
  fi
fi

if [ "$DIR" = /data/adb/modules/playintegrityfix/autopif4 ]; then
  if [ -f /data/adb/modules/playintegrityfix/migrate.sh ]; then
    NEWNAME="custom.pif.prop"
  else
    NEWNAME="pif.prop"
  fi
  if [ -f "../$NEWNAME" ]; then
    item "Backing up previous config..."
    mv -f "../$NEWNAME" "../$NEWNAME.bak"
  fi
  item "Installing config..."
  cp -f "$NEWNAME" ..
  if [ -f /data/adb/modules/playintegrityfix/killpi.sh ]; then
    item "Restarting Play Integrity processes..."
    sh /data/adb/modules/playintegrityfix/killpi.sh 2>&1 || true
  fi
fi

[ "$DEVICE_INITIAL_SDK_INT" -gt 35 ] && warn "This Fingerprint may require RKP keybox to pass integrity";
printf '\n';
