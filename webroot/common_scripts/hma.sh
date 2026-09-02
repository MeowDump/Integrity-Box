#!/system/bin/sh

SRC_CONFIG="/data/adb/modules/playintegrityfix/hidemyapplist/config.json"

APP_PATHS="
/data/user/0/org.frknkrc44.hma_oss
/data/user/0/com.google.android.hmal
/data/user/0/com.tsng.hidemyapplist
"

LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG_FILE="$LOG_DIR/hma.log"

BACKUP_DIR="/data/adb/HMA"
DATE_TAG="$(date '+%Y-%m-%d_%H-%M-%S')"
ANTISELINUX="/data/adb/Box-Brain/antiselinux"

ORIG_SELINUX=""
SELINUX_CHANGED=0
PKG_NAME=""
ACTIVITY=""

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

HMA_INSTALLED=0
if pm list packages | grep -q "^package:org.frknkrc44.hma_oss$"; then
    HMA_INSTALLED=1
    PKG_NAME="org.frknkrc44.hma_oss"
    ACTIVITY="org.frknkrc44.hma_oss/.ui.activity.MainActivity"
elif pm list packages | grep -q "^package:com.google.android.hmal$"; then
    HMA_INSTALLED=1
    PKG_NAME="com.google.android.hmal"
    ACTIVITY="com.google.android.hmal/icu.nullptr.hidemyapplist.ui.activity.MainActivity"
elif pm list packages | grep -q "^package:com.tsng.hidemyapplist$"; then
    HMA_INSTALLED=1
    PKG_NAME="com.tsng.hidemyapplist"
    ACTIVITY="com.tsng.hidemyapplist/icu.nullptr.hidemyapplist.ui.activity.MainActivity"
fi

if [ "$HMA_INSTALLED" -eq 0 ]; then
    log "No supported HMA app installed"
    log "Opening download page..."
    nohup am start -a android.intent.action.VIEW -d "https://github.com/frknkrc44/HMA-OSS/releases" > /dev/null 2>&1 &
    exit 1
fi

log "Resolved package name: $PKG_NAME"

find_target_app() {
    for APP in $APP_PATHS; do
        if [ -d "$APP" ]; then
            TARGET_APP="$APP"
            log "$1: $APP"
            return 0
        fi
    done
    return 1
}

TARGET_APP=""
find_target_app "Found installed app data path"

if [ -z "$TARGET_APP" ]; then
    log "App installed but data directory not found"
    log "Launching app to create data directory..."
    log "Launching activity: $ACTIVITY"
    am start --user 0 -a android.intent.action.VIEW -n "$ACTIVITY" >>"$LOG_FILE" 2>&1
    sleep 5
    am force-stop "$PKG_NAME" >>"$LOG_FILE" 2>&1
    log "App launched and stopped, checking data directory..."

    find_target_app "Data directory now available"

    if [ -z "$TARGET_APP" ]; then
        log "ERROR: Data directory still not created after launch"
        exit 1
    fi
fi

TARGET_FILES="$TARGET_APP/files"
TARGET_CONFIG="$TARGET_FILES/config.json"

if [ ! -d "$TARGET_FILES" ]; then
    log "/files directory missing, creating: $TARGET_FILES"
    mkdir -p "$TARGET_FILES" || {
        log "ERROR: Failed to create $TARGET_FILES"
        exit 1
    }
fi

if [ -f "$TARGET_CONFIG" ]; then
    BACKUP_NAME="config_${DATE_TAG}.json"
    log "Existing config found, moving to $BACKUP_DIR/$BACKUP_NAME"
    mv "$TARGET_CONFIG" "$BACKUP_DIR/$BACKUP_NAME" || {
        log "ERROR: Failed to move existing config"
        exit 1
    }
fi

log "Copying new config to $TARGET_CONFIG"
cp "$SRC_CONFIG" "$TARGET_CONFIG" || {
    log "ERROR: Failed to copy new config"
    exit 1
}

chmod 666 "$TARGET_CONFIG"
chown system:system "$TARGET_CONFIG" 2>/dev/null

if [ ! -f "$ANTISELINUX" ]; then
    ORIG_SELINUX="$(get_selinux_mode)"
    log "Current SELinux mode: $ORIG_SELINUX"
    if [ "$ORIG_SELINUX" = "Enforcing" ]; then
        log "Switching SELinux to Permissive temporarily"
        set_selinux_permissive
        SELINUX_CHANGED=1
        sleep 0.5
    fi
else
    log "antiselinux flag found, skipping SELinux mode change"
fi

log "Force stopping app: $PKG_NAME"
am force-stop "$PKG_NAME" >>"$LOG_FILE" 2>&1
sleep 1
log "Launching activity: $ACTIVITY"
if am start --user 0 -a android.intent.action.VIEW -n "$ACTIVITY" >>"$LOG_FILE" 2>&1; then
    log "App launched successfully"
else
    log "ERROR: Failed to launch app"
fi

restore_selinux
log "Config copy completed successfully"
log "••••••••••••• Finished •••••••••••••"
exit 0
