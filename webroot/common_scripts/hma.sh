#!/system/bin/sh

SRC_CONFIG="/data/adb/modules/playintegrityfix/toolkit/HMA-OOS.json"

HMA_PKG="org.frknkrc44.hma_oss"
HMA_ACTIVITY="org.frknkrc44.hma_oss/.ui.activity.MainActivity"

MISC_DIR="/data/misc"
HMA_PREFIX="hide_my_applist"

LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/hma.log"

BACKUP_DIR="/data/adb/HMA"
DATE_TAG="$(date '+%Y-%m-%d_%H-%M-%S')"
SKIP_FLAG="/data/adb/Box-Brain/skip"

ORIG_SELINUX=""
SELINUX_CHANGED=0

mkdir -p "$LOG_DIR"
mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_selinux_mode() {
    if command -v getenforce >/dev/null 2>&1; then
        getenforce
    else
        echo "Unknown"
    fi
}

set_selinux_permissive() {
    if command -v setenforce >/dev/null 2>&1; then
        setenforce 0
    fi
}

restore_selinux() {
    if [ "$SELINUX_CHANGED" -eq 1 ] && [ "$ORIG_SELINUX" = "Enforcing" ]; then
        log "Restoring SELinux to Enforcing"
        setenforce 1
    fi
}

log "•••••••••••••= HMA config sync started •••••••••••••"

if [ ! -f "$SRC_CONFIG" ]; then
    log "ERROR: Source config not found: $SRC_CONFIG"
    exit 1
fi

log "Source config found: $SRC_CONFIG"

if ! pm list packages | grep -q "^package:${HMA_PKG}$"; then
    log "HMA-OSS not installed"
    log "Opening download page..."
    nohup am start -a android.intent.action.VIEW -d "https://github.com/frknkrc44/HMA-OSS/releases" > /dev/null 2>&1 &
    exit 1
fi

log "HMA-OSS installed: $HMA_PKG"

TARGET_DIR=""
for DIR in "$MISC_DIR"/${HMA_PREFIX}_*; do
    if [ -d "$DIR" ]; then
        TARGET_DIR="$DIR"
        log "Found target directory: $DIR"
        break
    fi
done

if [ -z "$TARGET_DIR" ]; then
    log "Target directory not found, launching app to create it..."
    log "Launching activity: $HMA_ACTIVITY"
    am start --user 0 -a android.intent.action.VIEW -n "$HMA_ACTIVITY" >>"$LOG_FILE" 2>&1
    sleep 5
    am force-stop "$HMA_PKG" >>"$LOG_FILE" 2>&1

    for DIR in "$MISC_DIR"/${HMA_PREFIX}_*; do
        if [ -d "$DIR" ]; then
            TARGET_DIR="$DIR"
            log "Target directory now available: $DIR"
            break
        fi
    done

    if [ -z "$TARGET_DIR" ]; then
        log "ERROR: Target directory still not created after launch"
        exit 1
    fi
fi

TARGET_CONFIG="$TARGET_DIR/config.json"

if [ -f "$TARGET_CONFIG" ]; then
    BACKUP_NAME="config_${DATE_TAG}.json"
    log "Existing config found, backing up to $BACKUP_DIR/$BACKUP_NAME"
    cp "$TARGET_CONFIG" "$BACKUP_DIR/$BACKUP_NAME" || {
        log "ERROR: Failed to backup existing config"
        exit 1
    }
fi

log "Copying config to: $TARGET_CONFIG"
cp "$SRC_CONFIG" "$TARGET_CONFIG" || {
    log "ERROR: Failed to copy new config"
    exit 1
}

chmod 644 "$TARGET_CONFIG" || {
    log "ERROR: Failed to set permissions on $TARGET_CONFIG"
    exit 1
}

log "Config copied successfully"

log "Force stopping HMA OSS"
am force-stop "$HMA_PKG" >>"$LOG_FILE" 2>&1

if [ -f "$SKIP_FLAG" ]; then
    log "skip flag found, skipping SELinux mode change"
else
    ORIG_SELINUX="$(get_selinux_mode)"
    log "SELinux mode: $ORIG_SELINUX"
    if [ "$ORIG_SELINUX" = "Enforcing" ]; then
        log "Temporarily setting SELinux to Permissive"
        set_selinux_permissive
        SELINUX_CHANGED=1
        sleep 0.5
    fi
fi

log "Launching HMA OSS"
am start --user 0 -a android.intent.action.VIEW -n "$HMA_ACTIVITY" >>"$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    log "HMA OSS launched successfully"
else
    log "ERROR: Failed to launch app"
fi

restore_selinux

log "••••••••••••• HMA config sync finished •••••••••••••"
log
log
exit 0
