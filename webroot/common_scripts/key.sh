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

log() {
    echo "$*" | tee -a "$LOG_FILE"
}

# Cleanup temp files on exit
trap 'rm -f "$TEMP_FILE"' EXIT

# Create directories
mkdir -p "$TRICKY_STORE" "$RECORD" "$RECORD/Integrity-Box-Logs" "$BACKUP_DIR"
touch "$LOG_FILE"

# Get busybox path
BB=$(P)

# Backup existing keybox with timestamp
if [ -s "$KEYBOX" ]; then
    cp -f "$KEYBOX" "$KEYBOX_BACKUP"
    log " 𒀭 Backed up existing keybox"
fi

# Keybox download URL
KEYBOX_URL="https://raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/Megatron"

# Download keybox
log " 𒀭 Requesting encrypted keybox from GitHub..."
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
        log " ✪ OMK keybox backup created"
    fi
    cp -f "$KEYBOX" "$OMK_KEYBOX"
    log " ✪ Keybox added to OMK directory"
fi

sed -i "s|^description=.*|description=$DESC ✦ Synced on $NOW|" "$FILE"
