#!/system/bin/sh

MODPATH="/data/adb/modules/playintegrityfix"
UPDATEPATH="/data/adb/modules_update/playintegrityfix"

# Load common functions
if [ -f "$MODPATH/common_func.sh" ]; then
    . "$MODPATH/common_func.sh"
elif [ -f "$UPDATEPATH/common_func.sh" ]; then
    . "$UPDATEPATH/common_func.sh"
else
    echo "ERROR: common_func.sh not found"
    exit 1
fi

# Paths
RECORD="/data/adb/Box-Brain"
TRICKY_STORE="/data/adb/tricky_store"
KEYBOX="$TRICKY_STORE/keybox.xml"
LOG_FILE="$RECORD/Integrity-Box-Logs/keybox.log"
TEMP_FILE="$(mktemp -p /data/local/tmp)"
CLEANUP="$MODPATH/webroot/common_scripts/cleanup.sh"
UCLEANUP="$UPDATEPATH/webroot/common_scripts/cleanup.sh"
BACKUP_DIR="$RECORD/KeyBackup"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
KEYBOX_BACKUP="$BACKUP_DIR/keybox_$TIMESTAMP.xml"
FILE="/data/adb/modules/playintegrityfix/module.prop"
DESC=$(grep '^description=' "$FILE" | sed 's| ✦ Synced on .*||' | cut -d= -f2-)
NOW=$(date '+%d %B %I:%M %p')
SIM_KEY="/data/adb/teesim/keybox.xml"

log() {
    echo "$*" | tee -a "$LOG_FILE"
}

# Cleanup temp files on exit
trap 'rm -f "$TEMP_FILE" "$TMP_HEX" "$CURRENT" "$NEXT"' EXIT

# Create directories
mkdir -p "$TRICKY_STORE" "$RECORD" "$RECORD/Integrity-Box-Logs" "$BACKUP_DIR"
touch "$LOG_FILE"

# Get busybox path
BB=$(P)

# Backup existing keybox with timestamp
if [ -s "$KEYBOX" ]; then
    cp -f "$KEYBOX" "$KEYBOX_BACKUP"
    log " 𒀭 Backed up default keybox"
fi

# Keybox download URL
KEYBOX_URL="https://raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/Megatron"

# Known GitHub raw CDN IPs (round-robin fallback)
GITHUB_IPS="185.199.108.133 185.199.109.133 185.199.110.133 185.199.111.133"

# Core download helper: tries one method with timeout
_try_download() {
    local url="$1"
    local out="$2"
    local dl_tool="$3"

    rm -f "$out"

    case "$dl_tool" in
        bb_wget)
            [ -n "$BB" ] && "$BB" wget -q --no-check-certificate -T 15 -t 1 -O "$out" "$url" 2>/dev/null
            ;;
        wget)
            wget -q --no-check-certificate --timeout=15 --tries=1 -O "$out" "$url" 2>/dev/null
            ;;
        curl)
            curl -fsSL --connect-timeout 15 --max-time 120 --insecure "$url" -o "$out" 2>/dev/null
            ;;
        curl_resolve)
            # curl with forced Host header (direct IP access)
            local ip="$4"
            curl -fsSL --connect-timeout 15 --max-time 120 --insecure \
                 -H "Host: raw.githubusercontent.com" \
                 "https://$ip/MeowDump/MeowDump/refs/heads/main/Megatron" \
                 -o "$out" 2>/dev/null
            ;;
    esac

    [ -s "$out" ]
}

# Normal download with retries and backoff
_phase1_normal() {
    local url="$1"
    local out="$2"
    local attempt=0

    while [ "$attempt" -lt 3 ]; do
        attempt=$((attempt + 1))
        log " 𒀭 Stock download (attempt $attempt/3)..."

        if [ -n "$BB" ] && _try_download "$url" "$out" "bb_wget"; then return 0; fi
        if _try_download "$url" "$out" "wget"; then return 0; fi
        if _try_download "$url" "$out" "curl"; then return 0; fi

        sleep "$attempt"
    done
    return 1
}

# Temporarily override DNS and retry
_phase2_dns_override() {
    local url="$1"
    local out="$2"
    local attempt=0

    log " 𒀭 Trying with public DNS..."

    # Save current DNS (best effort)
    local old_dns1 old_dns2
    old_dns1=$(getprop net.dns1 2>/dev/null)
    old_dns2=$(getprop net.dns2 2>/dev/null)

    # Set public DNS temporarily
    setprop net.dns1 8.8.8.8
    setprop net.dns2 1.1.1.1
    setprop net.dns3 8.8.4.4
    sleep 2

    while [ "$attempt" -lt 2 ]; do
        attempt=$((attempt + 1))
        log " 𒀭 DNS override attempt $attempt/2..."

        { [ -n "$BB" ] && _try_download "$url" "$out" "bb_wget"; } ||
        _try_download "$url" "$out" "wget" ||
        _try_download "$url" "$out" "curl" || true
        if [ -s "$out" ]; then
            _restore_dns "$old_dns1" "$old_dns2"
            return 0
        fi

        sleep 2
    done

    _restore_dns "$old_dns1" "$old_dns2"
    return 1
}

_restore_dns() {
    [ -n "$1" ] && setprop net.dns1 "$1"
    [ -n "$2" ] && setprop net.dns2 "$2"
}

# Direct IP connection (bypass DNS entirely)
_phase3_direct_ip() {
    local out="$1"
    local attempt=0

    log " 𒀭 Trying direct GitHub CDN IPs..."

    for ip in $GITHUB_IPS; do
        attempt=$((attempt + 1))
        log " 𒀭 Trying IP $ip ($attempt/4)..."

        if _try_download "" "$out" "curl_resolve" "$ip"; then return 0; fi
        sleep 1
    done
    return 1
}

# Master fail-safe download orchestrator
fail_safe_download() {
    local url="$1"
    local out="$2"

    # Normal retries
    if _phase1_normal "$url" "$out"; then
        log " 𒀭 Download succeeded"
        return 0
    fi

    # DNS override
    if _phase2_dns_override "$url" "$out"; then
        log " 𒀭 Download succeeded (DNS override)"
        return 0
    fi

    # Direct IP
    if _phase3_direct_ip "$out"; then
        log " 𒀭 Download succeeded (Direct IP)"
        return 0
    fi

    log " 𒀭 ERROR: All download phases exhausted"
    return 1
}

# Flag-based download switch
if [ -f "$RECORD/keyswitch" ]; then
    if ! fail_safe_download "$KEYBOX_URL" "$TEMP_FILE"; then
        log " 𒀭 ERROR: Download failed - check internet/DNS"
        rm -f "$TEMP_FILE"
        exit 3
    fi
else
    # download
    log " 𒀭 Fetching keybox from GitHub..."
    if [ -n "$BB" ] && "$BB" wget --help >/dev/null 2>&1; then
        "$BB" wget -q --no-check-certificate -O "$TEMP_FILE" "$KEYBOX_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate -O "$TEMP_FILE" "$KEYBOX_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --insecure "$KEYBOX_URL" -o "$TEMP_FILE"
    else
        log " 𒀭 ERROR: No downloader available (wget or curl)"
        exit 2
    fi
fi

# Check download succeeded
if [ ! -s "$TEMP_FILE" ]; then
    log " 𒀭 ERROR: Download failed - check internet connection"
    rm -f "$TEMP_FILE"
    exit 3
fi

# Decode the downloaded file
# The file is encoded as: base64 > hex > ROT13
log " 𒀭 Decoding keybox file..."

TMP_HEX="$(mktemp -p /data/local/tmp)"

# Base64 decode 
CURRENT="$TEMP_FILE"
for i in $(seq 1 10); do
    NEXT="$(mktemp -p /data/local/tmp)"
    if ! base64 -d "$CURRENT" > "$NEXT" 2>/dev/null; then
        log " 𒀭 ERROR: Base64 decode failed at iteration $i"
        rm -f "$NEXT" "$TMP_HEX"
        exit 4
    fi
    rm -f "$CURRENT"
    CURRENT="$NEXT"
done

# Hex decode
if ! xxd -r -p "$CURRENT" > "$TMP_HEX" 2>/dev/null; then
    log " 𒀭 ERROR: Hex decoding failed"
    rm -f "$CURRENT" "$TMP_HEX"
    exit 5
fi
rm -f "$CURRENT"

# ROT13 decode
if ! tr 'A-Za-z' 'N-ZA-Mn-za-m' < "$TMP_HEX" > "$KEYBOX"; then
    log " 𒀭 ERROR: ROT13 decoding failed"
    rm -f "$TMP_HEX"
    exit 6
fi
rm -f "$TMP_HEX"

# Verify final keybox file
if [ ! -s "$KEYBOX" ]; then
    log " 𒀭 ERROR: Keybox is empty after decoding"
    rm -f "$KEYBOX"
    if [ -s "$KEYBOX_BACKUP" ]; then
        cp -f "$KEYBOX_BACKUP" "$KEYBOX"
        log " 𒀭 Restored backup keybox from $KEYBOX_BACKUP"
    fi
    exit 7
fi

log " 𒀭 Keybox successfully updated"

# Clean temporary files
if [ -f "$CLEANUP" ]; then
  sh "$CLEANUP" > /dev/null 2>&1
elif [ -f "$UCLEANUP" ]; then
  sh "$UCLEANUP" > /dev/null 2>&1
fi

# OMK Keybox Support
OMK_DIR="/data/misc/keystore/omk"
OMK_KEYBOX="$OMK_DIR/keybox.xml"
OMK_KEYBOX_BAK="$OMK_DIR/keybox.xml.bak"

if [ -d "$OMK_DIR" ]; then
    if [ -s "$OMK_KEYBOX" ]; then
        cp -f "$OMK_KEYBOX" "$OMK_KEYBOX_BAK"
        log " ✪ OMK key backup created"
    fi
    cp -f "$KEYBOX" "$OMK_KEYBOX"
    log " ✪ Keybox added to OMK directory"
fi

# Backup TEE SIM keybox with timestamp
SIM_KEYBACKUP="$SIM_KEY.bak"
if [ -s "$SIM_KEY" ]; then
    cp -f "$SIM_KEY" "$SIM_KEYBACKUP"
    log " 𒀭 TEE-SIM key backup created"
fi

# Copy keybox to SIM path
if [ -d "/data/adb/teesim" ] && [ -s "$KEYBOX" ]; then
    cp -f "$KEYBOX" "$SIM_KEY"
    log " ✪ Keybox added to TEEsim directory"
fi

sed -i "s|^description=.*|description=$DESC ✦ Synced on $NOW|" "$FILE"
