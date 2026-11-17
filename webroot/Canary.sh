#!/system/bin/sh

MODPATH="/data/adb/modules/playintegrityfix"
URL="https://github.com/MeowDump/Integrity-Box/releases/download/archive/Canary.zip"
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/canary.log"
ZIP_PATH="$LOG_DIR/Canary.zip"
WORK_DIR="/data/adb/Box-Brain/Canary-Work"
MAX_ATTEMPTS=3

mkdir -p "$LOG_DIR" || exit 1

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

wait_for_network() {
    max_wait="${1:-30}"
    step=2
    waited=0
    while [ "$waited" -lt "$max_wait" ]; do
        for host in 1.1.1.1 8.8.8.8 9.9.9.9 223.5.5.5 114.114.114.114; do
            ping -c 1 -W 2 "$host" >/dev/null 2>&1 && return 0
        done
        sleep "$step"
        waited=$((waited + step))
    done
    return 1
}

detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="$(command -v curl)"; DL_MODE=curl; return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        DOWNLOADER="$(command -v wget)"; DL_MODE=wget; return 0
    fi
    for candidate in /data/adb/modules/busybox-ndk/system/*/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
        if [ -x "$candidate" ]; then
            DOWNLOADER="$candidate"; DL_MODE=busybox; return 0
        fi
    done
    if command -v toybox >/dev/null 2>&1 && toybox wget --help >/dev/null 2>&1; then
        DOWNLOADER="toybox"; DL_MODE=toybox; return 0
    fi
    DOWNLOADER=""; DL_MODE=""
    return 1
}

find_busybox() {
    for candidate in /data/adb/modules/busybox-ndk/system/*/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
        [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

get_size() {
    size=$(wc -c < "$1" 2>/dev/null) || return 1
    printf '%s bytes' "$(printf '%s' "$size" | tr -d '[:space:]')"
}

download_file() {
    case "$DL_MODE" in
        curl) "$DOWNLOADER" -fLsS --connect-timeout 15 --max-time 180 -o "$ZIP_PATH.tmp" "$URL" ;;
        wget) "$DOWNLOADER" -q --timeout=30 -O "$ZIP_PATH.tmp" "$URL" ;;
        busybox) "$DOWNLOADER" wget -q -T 30 -O "$ZIP_PATH.tmp" "$URL" ;;
        toybox) toybox wget -T 30 -O "$ZIP_PATH.tmp" "$URL" ;;
        *) return 127 ;;
    esac
}

find_unzip() {
    UNZIP_MODE=""
    UNZIP_BIN=""
    if command -v unzip >/dev/null 2>&1; then
        UNZIP_BIN="$(command -v unzip)"
        UNZIP_MODE=unzip
        return 0
    fi
    BUSYBOX="$(find_busybox)" || BUSYBOX=""
    if [ -n "$BUSYBOX" ] && "$BUSYBOX" unzip --help >/dev/null 2>&1; then
        UNZIP_BIN="$BUSYBOX"
        UNZIP_MODE=busybox
        return 0
    fi
    return 1
}

log "========================================"
log "       Initialising Canary Updater"
log "========================================"

log "Checking network connectivity..."
if ! wait_for_network 30; then
    log "ERROR: No network connection available"
    exit 1
fi
log "Network is available"

if ! detect_downloader; then
    log "ERROR: No supported download utility found"
    exit 1
fi
log "Using downloader: $DL_MODE ($DOWNLOADER)"

rm -f "$ZIP_PATH.tmp" "$ZIP_PATH"
attempt=1
downloaded=0
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    log "Download attempt $attempt of $MAX_ATTEMPTS..."
    rm -f "$ZIP_PATH.tmp"
    download_file
    rc=$?
    if [ "$rc" -eq 0 ] && [ -s "$ZIP_PATH.tmp" ] && mv -f "$ZIP_PATH.tmp" "$ZIP_PATH"; then
        downloaded=1
        break
    fi
    log "Attempt $attempt failed (exit code $rc or empty download)."
    rm -f "$ZIP_PATH.tmp"
    attempt=$((attempt + 1))
    [ "$attempt" -le "$MAX_ATTEMPTS" ] && sleep 2
done

if [ "$downloaded" -ne 1 ] || [ ! -s "$ZIP_PATH" ]; then
    rm -f "$ZIP_PATH.tmp" "$ZIP_PATH"
    log "ERROR: Download failed after $MAX_ATTEMPTS attempts."
    exit 1
fi
log "Download complete: $ZIP_PATH ($(get_size "$ZIP_PATH"))"

if ! find_unzip; then
    log "ERROR: No unzip utility found"
    rm -f "$ZIP_PATH"
    exit 1
fi

case "$WORK_DIR" in
    /data/adb/Box-Brain/Canary-Work) ;;
    *) log "ERROR: Unsafe workspace path."; rm -f "$ZIP_PATH"; exit 1 ;;
esac
rm -rf "$WORK_DIR"
if ! mkdir -p "$WORK_DIR"; then
    log "ERROR: Cannot create workspace: $WORK_DIR"
    rm -f "$ZIP_PATH"
    exit 1
fi

log "Extracting customize.sh only to $WORK_DIR..."
case "$UNZIP_MODE" in
    unzip) "$UNZIP_BIN" -oq "$ZIP_PATH" customize.sh -d "$WORK_DIR" ;;
    busybox) "$UNZIP_BIN" unzip -oq "$ZIP_PATH" customize.sh -d "$WORK_DIR" ;;
    *) log "ERROR: Invalid unzip mode."; rm -rf "$WORK_DIR" "$ZIP_PATH"; exit 1 ;;
esac
rc=$?
if [ "$rc" -ne 0 ] || [ ! -f "$WORK_DIR/customize.sh" ]; then
    log "ERROR: Failed to extract customize.sh from archive."
    rm -rf "$WORK_DIR" "$ZIP_PATH"
    exit 1
fi

CUSTOMIZE_SH="$WORK_DIR/customize.sh"
chmod 0755 "$CUSTOMIZE_SH"
export MODPATH="$WORK_DIR"
export ZIPFILE="$ZIP_PATH"
export OUTFD=""

log "Executing original customize.sh with ZIPFILE=$ZIPFILE and MODPATH=$MODPATH..."
OUTPUT_FILE="$WORK_DIR/customize-output.log"
sh "$CUSTOMIZE_SH" >"$OUTPUT_FILE" 2>&1
customize_rc=$?
cat "$OUTPUT_FILE" | tee -a "$LOG_FILE"

if grep -Eq 'Done: .*[, ]0 failed\.' "$OUTPUT_FILE"; then
    log "Update summary reports zero failed file operations."
else
    log "ERROR: customize.sh did not report a clean completion (exit code $customize_rc)."
    rm -rf "$WORK_DIR" "$ZIP_PATH.tmp" "$ZIP_PATH"
    exit 1
fi

rm -rf "$WORK_DIR"
if rm -f "$ZIP_PATH.tmp" "$ZIP_PATH"; then
    log "Removed temporary updater files."
else
    log "WARN: Could not remove one or more temporary updater files."
fi
log "Canary updater completed."
exit 0
