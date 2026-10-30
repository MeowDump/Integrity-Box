#!/system/bin/sh
# shellcheck disable=SC3043,SC2034,SC1091,SC2329
# ==============================================================================
# Integrity Box - Multi-Tier Keybox Provisioner (v46+)
# Resilient Dynamic Fetcher, Fallback Cascades & Certificate Date Parser
# ==============================================================================

BASE_URL="https://rawbin.dpejoh.com/key"
CATALOG_URL="https://rawbin.dpejoh.com/catalog"
RECORD="/data/adb/Box-Brain"
WORKDIR="/dev/.spectre_work_$$"
CATALOG="$WORKDIR/catalog.json"
ENCODED="$WORKDIR/payload.enc"
DECODED="$WORKDIR/payload.xml"
STANDARD_B64="$WORKDIR/standard.b64"
TRICKY_STORE="/data/adb/tricky_store"
KEYBOX="$TRICKY_STORE/keybox.xml"
KEYBOX_BAK="$KEYBOX.bak"

mkdir -p "$WORKDIR" "$TRICKY_STORE" 2>/dev/null

log() {
    echo "$*"
}

error() {
    echo " ✦ ERROR: $*" >&2
}

# Cleanup temporary artifacts
CATALOG_TMP="$CATALOG.tmp"
ENCODED_TMP="$ENCODED.tmp"
DECODED_TMP="$DECODED.tmp"
ENTRIES="$WORKDIR/entries.tmp"

cleanup() {
    rm -f "$CATALOG_TMP" "$ENCODED_TMP" "$STANDARD_B64" "$DECODED_TMP" "$ENTRIES"
}
trap cleanup EXIT HUP INT TERM

parse_epoch() {
    raw="$1"
    [ -n "$raw" ] || { printf '%s' "0"; return; }
    yy=$(printf '%s' "$raw" | cut -c 1-2)
    mm=$(printf '%s' "$raw" | cut -c 3-4)
    dd=$(printf '%s' "$raw" | cut -c 5-6)
    hh=$(printf '%s' "$raw" | cut -c 7-8)
    min=$(printf '%s' "$raw" | cut -c 9-10)
    ss=$(printf '%s' "$raw" | cut -c 11-12)
    date -u -d "20${yy}-${mm}-${dd} ${hh}:${min}:${ss}" +%s 2>/dev/null || printf '%s' "0"
}

download() {
    url="$1"
    out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -s -k --connect-timeout 8 --max-time 15 -f -L "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate --timeout=15 -O "$out" "$url"
    else
        error "No curl or wget available"
        return 1
    fi
}

log "••••••• KEYBOX PROVISIONER (SPECTRE) •••••••"

# ------------------------------------------------------------------------------
# 0. LOCAL KEYBOX HEALTH AUDIT
# ------------------------------------------------------------------------------
LOCAL_SERIAL=""
LOCAL_HEALTHY=false

if [ -s "$KEYBOX" ]; then
    LOCAL_CERT_B64=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$KEYBOX" | head -n 35 | grep -v 'CERTIFICATE' | tr -d ' \n\r\t')
    if [ -n "$LOCAL_CERT_B64" ]; then
        LOCAL_STRINGS=$(printf '%s' "$LOCAL_CERT_B64" | base64 -d 2>/dev/null | strings)
        LOCAL_SERIAL=$(printf '%s\n' "$LOCAL_STRINGS" | grep -oE '[0-9a-f]{32}' | head -n 1)
        LOCAL_DATES=$(printf '%s\n' "$LOCAL_STRINGS" | grep -oE '[0-9]{12}Z')
        LOCAL_NOT_BEFORE=$(printf '%s\n' "$LOCAL_DATES" | head -n 1)
        LOCAL_NOT_AFTER=$(printf '%s\n' "$LOCAL_DATES" | tail -n 1)
        
        if [ -n "$LOCAL_NOT_BEFORE" ] && [ -n "$LOCAL_NOT_AFTER" ]; then
            LOCAL_START=$(parse_epoch "$LOCAL_NOT_BEFORE")
            LOCAL_END=$(parse_epoch "$LOCAL_NOT_AFTER")
            LOCAL_NOW=$(date +%s)
            if [ "$LOCAL_NOW" -ge "$LOCAL_START" ] && [ "$LOCAL_NOW" -le "$LOCAL_END" ]; then
                LOCAL_HEALTHY=true
            fi
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 1. CATALOG FETCH & PARSE
# ------------------------------------------------------------------------------
log " ✦ Fetching remote catalog..."
if ! download "$CATALOG_URL" "$CATALOG_TMP" || [ ! -s "$CATALOG_TMP" ]; then
    error "Failed to retrieve catalog from $CATALOG_URL"
    exit 1
fi
mv -f "$CATALOG_TMP" "$CATALOG"

if ! grep -o '"entries":\[.*\]' "$CATALOG" | \
    sed 's/"entries":\[//; s/\]$//' | \
    sed 's/},{/}\n{/g' > "$ENTRIES" || [ ! -s "$ENTRIES" ]; then
    error "Could not parse catalog entries"
    exit 3
fi

# If local key is expired/invalid, blacklist its dead serial so we don't re-pick it
DEAD_SERIAL=""
if [ "$LOCAL_HEALTHY" != "true" ] && [ -n "$LOCAL_SERIAL" ]; then
    DEAD_SERIAL="$LOCAL_SERIAL"
fi

find_entry() {
    pattern="$1"
    if [ -n "$DEAD_SERIAL" ]; then
        awk "$pattern"' && /"revoked":false/ && /"softbanned":false/ {
            if (index($0, "'"$DEAD_SERIAL"'") > 0) next;
            print; exit
        }' "$ENTRIES"
    else
        awk "$pattern"' && /"revoked":false/ && /"softbanned":false/ { print; exit }' "$ENTRIES"
    fi
}

# Multi-Tier Cascade Entry Selection
# Priority 1: TAKR
ENTRY=$(find_entry '/"source":"TAKR"/')

# Priority 2: @Xiaomi_Lei_Jun
if [ -z "$ENTRY" ]; then
    log " ✦ TAKR not available, cascading to @Xiaomi_Lei_Jun..."
    ENTRY=$(find_entry '/"source":"@Xiaomi_Lei_Jun"/')
fi

# Priority 3: Yuri
if [ -z "$ENTRY" ]; then
    log " ✦ Cascading to Yuri..."
    ENTRY=$(find_entry '/"source":"Yuri"/')
fi

# Fallback: Any valid unrevoked entry
if [ -z "$ENTRY" ]; then
    ENTRY=$(find_entry '1')
fi

if [ -z "$ENTRY" ]; then
    if [ -n "$DEAD_SERIAL" ]; then
        log " ✦ Spectre catalog contains no alternate keys (available entries match expired serial $DEAD_SERIAL)."
        log " ✦ Triggering repository fallback..."
        exit 2
    else
        error "Catalog contains no eligible unrevoked entry"
        exit 3
    fi
fi

SOURCE=$(printf '%s\n' "$ENTRY" | sed -n 's/.*"source":"\([^"]*\)".*/\1/p')
VERSION=$(printf '%s\n' "$ENTRY" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
CATALOG_SERIAL=$(printf '%s\n' "$ENTRY" | sed -n 's/.*"serial":"\([^"]*\)".*/\1/p')

if [ -z "$SOURCE" ] || [ -z "$VERSION" ]; then
    error "Selected entry is missing source/version"
    exit 3
fi

# Guard: Check if selected key matches installed keybox
if [ -s "$KEYBOX" ] && [ -n "$CATALOG_SERIAL" ] && [ "$LOCAL_SERIAL" = "$CATALOG_SERIAL" ]; then
    if [ "$LOCAL_HEALTHY" = "true" ]; then
        log " ✦ Selected key ($SOURCE v$VERSION, serial $CATALOG_SERIAL) matches installed keybox and is healthy."
        log " ✦ Payload download skipped (already up to date)."
        exit 0
    else
        log " ✦ Selected key matches installed serial ($CATALOG_SERIAL), but installed key is expired/broken."
        log " ✦ Triggering repository fallback..."
        exit 2
    fi
fi

# ------------------------------------------------------------------------------
# 2. PAYLOAD FETCH & DECODE
# ------------------------------------------------------------------------------
URL="${BASE_URL}/${SOURCE}/${VERSION}"
log " ✦ Selected source: $SOURCE"
log " ✦ Selected version: $VERSION"
log " "

log " ✦ Fetching selected payload..."
if ! download "$URL" "$ENCODED_TMP" || [ ! -s "$ENCODED_TMP" ]; then
    error "Failed to fetch payload from $URL"
    exit 4
fi
mv -f "$ENCODED_TMP" "$ENCODED"

log " ✦ Decoding payload via shuffled alphabet..."
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

# ------------------------------------------------------------------------------
# 3. VERIFICATION & VALIDATION GATE
# ------------------------------------------------------------------------------
if ! grep -q '<Keybox' "$DECODED_TMP" || ! grep -q '</Keybox>' "$DECODED_TMP"; then
    error "Decoded payload does not contain valid XML Keybox structure; aborting deploy"
    exit 6
fi

DECODED_B64=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$DECODED_TMP" | head -n 35 | grep -v 'CERTIFICATE' | tr -d ' \n\r\t')
STRINGS_OUT=$(printf '%s' "$DECODED_B64" | base64 -d 2>/dev/null | strings)

DATES=$(printf '%s\n' "$STRINGS_OUT" | grep -oE '[0-9]{12}Z')
NOT_BEFORE_RAW=$(printf '%s\n' "$DATES" | head -n 1)
NOT_AFTER_RAW=$(printf '%s\n' "$DATES" | tail -n 1)

START_EPOCH=$(parse_epoch "$NOT_BEFORE_RAW")
END_EPOCH=$(parse_epoch "$NOT_AFTER_RAW")
NOW_EPOCH=$(date +%s)

if [ "$NOW_EPOCH" -lt "$START_EPOCH" ] || [ "$NOW_EPOCH" -gt "$END_EPOCH" ]; then
    error "Decoded certificate has expired or is not yet valid ($NOT_BEFORE_RAW to $NOT_AFTER_RAW); aborting deploy"
    exit 6
fi

SIZE=$(wc -c < "$DECODED_TMP" | tr -d ' ')
if [ "$SIZE" -lt 3000 ]; then
    error "Decoded file is suspiciously small ($SIZE bytes); aborting deploy"
    exit 6
fi

mv -f "$DECODED_TMP" "$DECODED"

# ------------------------------------------------------------------------------
# 4. ATOMIC TARGET DEPLOYMENT
# ------------------------------------------------------------------------------
if [ -s "$KEYBOX" ]; then
    cp -f "$KEYBOX" "$KEYBOX_BAK"
fi

if cp -f "$DECODED" "$KEYBOX"; then
    chmod 644 "$KEYBOX"
    chown root:root "$KEYBOX" 2>/dev/null || true
    log " ✦ Deployed valid keybox to $KEYBOX"
else
    error "Failed to write keybox to $KEYBOX"
    if [ -s "$KEYBOX_BAK" ]; then
        cp -f "$KEYBOX_BAK" "$KEYBOX"
        log " ✦ Restored backup keybox"
    fi
    exit 7
fi

# Soft reload Keystore2 to adopt new keybox
killall -TERM keystore2 2>/dev/null || true
log " ✦ Sent reload signal to keystore2"

# Synchronize TEE SIM and KeyMint if installed
SIM_KEY="/data/adb/teesim/keybox.xml"
if [ -d "/data/adb/teesim" ]; then
    cp -f "$KEYBOX" "$SIM_KEY"
    chmod 600 "$SIM_KEY"
    log " ✦ Synchronized to TEE-SIM"
fi

# Synchronize WebUI catalog_test
if [ -d "$RECORD/catalog_test" ]; then
    cp -f "$KEYBOX" "$RECORD/catalog_test/keybox.xml"
fi

log " ✦ Keybox successfully installed & verified!"
exit 0
