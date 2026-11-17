#!/system/bin/sh

BASE_URL="https://rawbin.dpejoh.com/key"
CATALOG_URL="https://rawbin.dpejoh.com/catalog"

RECORD="/data/adb/Box-Brain"
LOG_DIR="$RECORD/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/keybox.log"
BACKUP_DIR="$RECORD/KeyBackup"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

WORKDIR="$RECORD/catalog_test"
CATALOG="$WORKDIR/catalog.json"
ENCODED="$WORKDIR/payload.b64"
STANDARD_B64="$WORKDIR/payload.standard.b64"
DECODED="$WORKDIR/keybox.xml"

mkdir -p "$WORKDIR" "$LOG_DIR" "$BACKUP_DIR" || {
    echo " ✦ ERROR: Cannot create working directories" >&2
    exit 1
}
touch "$LOG_FILE" || {
    echo " ✦ ERROR: Cannot open log file: $LOG_FILE" >&2
    exit 1
}

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

error() {
    log " ✦ ERROR: $*"
}

CATALOG_TMP="$CATALOG.tmp"
ENCODED_TMP="$ENCODED.tmp"
DECODED_TMP="$DECODED.tmp"
ENTRIES="$WORKDIR/entries.tmp"

cleanup() {
    rm -f "$CATALOG_TMP" "$ENCODED_TMP" "$STANDARD_B64" "$DECODED_TMP" "$ENTRIES"
}
trap cleanup EXIT HUP INT TERM

download() {
    url="$1"
    out="$2"
    rm -f "$out"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 4 --max-time 12 --retry 1 --retry-delay 1 \
            -o "$out" "$url" 2>/dev/null
        return $?
    fi

    if command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; then
        busybox wget -q -T 5 -t 2 -O "$out" "$url" 2>/dev/null
        return $?
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q --timeout=5 --tries=2 -O "$out" "$url" 2>/dev/null
        return $?
    fi

    return 1
}

log " "
log " ✦ Using Spectre as default keybox source"
log " ✦ Fetching latest catalog..."

if ! download "$CATALOG_URL" "$CATALOG_TMP" || [ ! -s "$CATALOG_TMP" ]; then
    error "Latest catalog download failed; refusing to use stale data"
    exit 2
fi

mv -f "$CATALOG_TMP" "$CATALOG" || {
    error "Cannot save latest catalog"
    exit 2
}
log " ✦ Latest catalog acquired"
log " "

if ! tr -d '\r\n' < "$CATALOG" |
    sed -n 's/.*"entries":\[\(.*\)\],"latest".*/\1/p' |
    sed 's/},{/}\n{/g' > "$ENTRIES" || [ ! -s "$ENTRIES" ]; then
    error "Could not parse catalog entries"
    exit 3
fi

ENTRY=$(awk '/"revoked":false/ && /"softbanned":false/ { print; exit }' "$ENTRIES")
if [ -z "$ENTRY" ]; then
    ENTRY=$(awk '/"revoked":false/ && /"softbanned":true/ { print; exit }' "$ENTRIES")
fi

if [ -z "$ENTRY" ]; then
    error "Catalog contains no eligible entry"
    exit 3
fi

SOURCE=$(printf '%s\n' "$ENTRY" | sed -n 's/.*"source":"\([^"]*\)".*/\1/p')
VERSION=$(printf '%s\n' "$ENTRY" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
SOFTBANNED=$(printf '%s\n' "$ENTRY" | sed -n 's/.*"softbanned":\(true\|false\).*/\1/p')

if [ -z "$SOURCE" ] || [ -z "$VERSION" ]; then
    error "Selected entry is missing source/version"
    exit 3
fi

URL="${BASE_URL}/${SOURCE}/${VERSION}"
log " ✦ Selected source: $SOURCE"
log " ✦ Selected version: $VERSION"
log " "

log " ✦ Fetching selected payload..."
if ! download "$URL" "$ENCODED_TMP" || [ ! -s "$ENCODED_TMP" ]; then
    error "Payload download failed"
    exit 4
fi

mv -f "$ENCODED_TMP" "$ENCODED" || {
    error "Cannot save payload"
    exit 4
}
log " ✦ Payload acquired"
log " "
log " ✦ Decoding payload..."
STD_ALPHABET='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
SHUFFLED_ALPHABET='1dgWnocayqxU3r6vA5lCIPYfHmkV08b4tz+KMsp2NQ9LRXihODwSj7BEFJ/ZuGTe'

if ! tr "$SHUFFLED_ALPHABET" "$STD_ALPHABET" < "$ENCODED" > "$STANDARD_B64"; then
    error "Alphabet conversion failed"
    exit 5
fi

if ! base64 -d "$STANDARD_B64" > "$DECODED_TMP" 2>/dev/null || [ ! -s "$DECODED_TMP" ]; then
    error "Base64 decoding failed or output was empty"
    exit 5
fi

if ! grep -q '<' "$DECODED_TMP" || ! grep -q '>' "$DECODED_TMP"; then
    error "Decoded payload does not look like XML; previous output was preserved"
    exit 6
fi

chmod 600 "$DECODED_TMP" || {
    error "Cannot set decoded file permissions"
    exit 6
}

if [ -s "$DECODED" ]; then
    cp -f "$DECODED" "$BACKUP_DIR/spectre_keybox_$TIMESTAMP.xml" || {
        error "Could not archive previous decoded output"
        exit 6
    }
    log " ✦ Previous decoded output archived"
fi

mv -f "$DECODED_TMP" "$DECODED" || {
    error "Cannot save decoded output"
    exit 6
}

SIZE=$(wc -c < "$DECODED" | tr -d ' ')
log " ✦ Key decoded successfully"
log " ✦ Size: $SIZE bytes"
log " "

# OMK Keybox Support
OMK_DIR="/data/misc/keystore/omk"
OMK_KEYBOX="$OMK_DIR/keybox.xml"
OMK_KEYBOX_BAK="$OMK_DIR/keybox.xml.bak"

if [ -d "$OMK_DIR" ]; then
    if [ -s "$OMK_KEYBOX" ]; then
        cp -f "$OMK_KEYBOX" "$OMK_KEYBOX_BAK"
        log " ✦ KeyMint attestation archived"
    fi
    cp -f "$DECODED" "$OMK_KEYBOX"
    log " ✦ Attestation loaded to KeyMint"
fi

# Backup TEE SIM keybox with timestamp
if [ -s "$SIM_KEY" ]; then
    cp -f "$SIM_KEY" "$SIM_KEYBACKUP"
    log " ✦ TEE-SIM attestation archived"
fi

# Copy keybox to SIM path
if [ -d "/data/adb/teesim" ] && [ -s "$KEYBOX" ]; then
    cp -f "$DECODED" "$SIM_KEY"
    log " ✦ Attestation loaded to TEE-SIM"
fi

exit 0
