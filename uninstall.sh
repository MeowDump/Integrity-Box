#!/system/bin/sh
set -x

# Log file & Logger
LOGFILE="/data/local/tmp/uninstall.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" >> "$LOGFILE" 2>&1
}

# Safely delete files & directories
delete_file() {
    local FILE="$1"
    if [ -e "$FILE" ]; then
        rm -rf "$FILE" >> "$LOGFILE" 2>&1
        if [ $? -eq 0 ]; then
            log "Deleted $FILE"
        else
            log "Failed to delete $FILE"
        fi
    else
        log "Skipped $FILE (not found)"
    fi
}

# Safely restore backups
restore_backup() {
    local BACKUP="$1"
    local ORIGINAL="$2"
    if [ -e "$BACKUP" ]; then
        mv "$BACKUP" "$ORIGINAL" >> "$LOGFILE" 2>&1
        if [ $? -eq 0 ]; then
            log "Restored $ORIGINAL from backup"
        else
            log "Failed to restore $ORIGINAL from backup"
        fi
    else
        log "No $BACKUP found"
    fi
}

# Revert system properties if modified
revert_prop_if_modified() {
    local PROP="$1"
    local MODIFIED="$2"
    local DEFAULT="$3"
    local CURRENT
    CURRENT="$(getprop "$PROP" 2>/dev/null)"

    if [ "$CURRENT" = "$MODIFIED" ]; then
        resetprop -n "$PROP" "$DEFAULT" >> "$LOGFILE" 2>&1
        if [ $? -eq 0 ]; then
            log "Reverted $PROP to $DEFAULT (was $MODIFIED)"
        else
            log "Failed to revert $PROP (was $MODIFIED)"
        fi
    else
        log "Skipped $PROP (current=$CURRENT)"
    fi
}

# Start logging
log "•••••• Integrity-Box Uninstall Started ••••••"

# Define paths
TRICKY_STORE="/data/adb/tricky_store"
KEYBOX="$TRICKY_STORE/keybox.xml"
KEYBOX_BACKUP="$TRICKY_STORE/keybox.xml.bak"
TARGET="$TRICKY_STORE/target.txt"
TARGET_BACKUP="$TRICKY_STORE/target.txt.bak"

# Delete files and directories
delete_file "$KEYBOX"
delete_file "$TARGET"
delete_file /data/adb/shamiko/whitelist
delete_file /data/adb/nohello/whitelist
MODDIR="${0%/*}"
delete_file "$MODDIR"
delete_file /data/adb/Box-Brain
delete_file /data/adb/service.d/hash.sh
delete_file /data/adb/service.d/lineage.sh
delete_file /data/adb/service.d/prop.sh
delete_file /data/adb/service.d/shamiko.sh
delete_file /data/adb/service.d/package.sh
delete_file /data/adb/service.d/.box_cleanup.sh

# Restore backups
restore_backup "$TARGET_BACKUP" "$TARGET"
restore_backup "$KEYBOX_BACKUP" "$KEYBOX"

# Revert props
revert_prop_if_modified "persist.sys.pihooks.disable.gms_key_attestation_block" "true" "false"
revert_prop_if_modified "persist.sys.pihooks.disable.gms_props" "true" "false"
revert_prop_if_modified "persist.sys.pihooks.disable" "1" "0"
revert_prop_if_modified "persist.sys.kihooks.disable" "1" "0"

# Unhide hidden files
if [ -f "/data/adb/Vault/.hidefiles/last_action.sh" ]; then
    sh "/data/adb/Vault/.hidefiles/last_action.sh"
fi

# Finish
log "•••••• Integrity-Box Uninstall Completed ••••••"
sync
resetprop -p --delete "persist.sys.entryhooks_enabled"
resetprop -p --delete "persist.sys.spoof.gms"
resetprop -p --delete "persist.sys.pixelprops.gms"
resetprop -p --delete "persist.sys.pixelprops.gapps"
resetprop -p --delete "persist.sys.pixelprops.google"
resetprop -p --delete "persist.sys.pixelprops.pi"
