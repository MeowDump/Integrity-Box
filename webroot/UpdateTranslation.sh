#!/system/bin/sh

MODPATH="/data/adb/modules/playintegrityfix"
. $MODPATH/common_func.sh

LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/translation.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

URL="https://github.com/MeowDump/TG2Git/releases/download/TG2Git/Translation-Updater.zip"
ZIP_NAME="Translation-Updater.zip"
OUT_DIR="/storage/emulated/0/Download/IntegrityModules"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
EXTRACT_DIR="/data/adb/modules_update/auto_generated"

log "========================================"
log "Translation Updater - Download & Extract"
log "========================================"

# Wait for network
log "Checking network connectivity..."
if ! wait_for_network 30; then
    log "ERROR: No network connection available"
    exit 1
fi
log "Network is available"

# Ensure directories exist
mkdir -p "$OUT_DIR"
mkdir -p "$EXTRACT_DIR"

# Clean up previous attempts
rm -f "$ZIP_PATH.tmp" "$ZIP_PATH"

# Detect downloader
detect_downloader
if [ -z "$DOWNLOADER" ]; then
    log "ERROR: No download utility found"
    exit 1
fi
log "Using downloader: $DL_MODE"

# Download with retry
attempt=1
max_attempts=3
success=false

while [ $attempt -le $max_attempts ]; do
    log "Download attempt $attempt of $max_attempts..."
    
    case "$DL_MODE" in
        curl)
            "$DOWNLOADER" -L --fail --connect-timeout 15 --max-time 180 -o "$ZIP_PATH.tmp" "$URL" 2>/dev/null
            rc=$?
            ;;
        wget)
            "$DOWNLOADER" --no-check-certificate -O "$ZIP_PATH.tmp" "$URL" 2>/dev/null
            rc=$?
            ;;
        busybox)
            "$DOWNLOADER" wget --no-check-certificate -O "$ZIP_PATH.tmp" "$URL" 2>/dev/null
            rc=$?
            ;;
        toybox)
            toybox wget -O "$ZIP_PATH.tmp" "$URL" 2>/dev/null
            rc=$?
            ;;
    esac
    
    if [ $rc -eq 0 ] && [ -s "$ZIP_PATH.tmp" ]; then
        mv "$ZIP_PATH.tmp" "$ZIP_PATH"
        success=true
        break
    else
        log "Attempt $attempt failed (rc=$rc)"
        rm -f "$ZIP_PATH.tmp"
        attempt=$((attempt + 1))
        sleep 2
    fi
done

if [ "$success" != "true" ]; then
    log "ERROR: Download failed after $max_attempts attempts"
    exit 1
fi

log "Download complete: $ZIP_PATH ($(get_size "$ZIP_PATH"))"

# Clean extraction directory
log "Preparing extraction directory: $EXTRACT_DIR"
rm -rf "${EXTRACT_DIR:?}"/*
mkdir -p "$EXTRACT_DIR"

# Find unzip binary
UNZIP_BIN=""
if command -v unzip >/dev/null 2>&1; then
    UNZIP_BIN="unzip"
else
    BUSYBOX="$(P)"
    if [ -n "$BUSYBOX" ] && "$BUSYBOX" unzip --help >/dev/null 2>&1; then
        UNZIP_BIN="$BUSYBOX unzip"
    fi
fi

if [ -z "$UNZIP_BIN" ]; then
    log "ERROR: No unzip utility found"
    exit 1
fi

# Extract zip
log "Extracting zip to $EXTRACT_DIR..."
if $UNZIP_BIN -o "$ZIP_PATH" -d "$EXTRACT_DIR" >/dev/null 2>&1; then
    log "Extraction successful"
else
    log "ERROR: Failed to extract zip"
    exit 1
fi

# Locate customize.sh (handles both flat and single-root-folder zips)
CUSTOMIZE_SH=""
if [ -f "$EXTRACT_DIR/customize.sh" ]; then
    CUSTOMIZE_SH="$EXTRACT_DIR/customize.sh"
else
    CUSTOMIZE_SH=$(find "$EXTRACT_DIR" -maxdepth 2 -name "customize.sh" 2>/dev/null | head -n 1)
fi

if [ -z "$CUSTOMIZE_SH" ] || [ ! -f "$CUSTOMIZE_SH" ]; then
    log "ERROR: customize.sh not found in extracted archive"
    exit 1
fi

log "Found customize.sh at: $CUSTOMIZE_SH"

# Set MODPATH to the directory containing customize.sh so the script knows its home
MODULE_ROOT="$(dirname "$CUSTOMIZE_SH")"
export MODPATH="$MODULE_ROOT"
chmod +x "$CUSTOMIZE_SH"

log "Executing customize.sh (MODPATH=$MODPATH)..."
if sh "$CUSTOMIZE_SH"; then
    log "customize.sh executed successfully"
else
    log "WARN: customize.sh exited with non-zero code"
fi

# Delete downloaded zip
if rm -f "$ZIP_PATH"; then
    log "Cleaned up: $ZIP_PATH"
else
    log "WARN: Failed to delete $ZIP_PATH"
fi

log "Translation Updater process completed"
exit 0
