#!/system/bin/sh
L="/data/adb/Integrity-Box-Logs/post.log"
MODULE="/data/adb/modules"
MODDIR="$MODULE/integrity_box"
SRC="$MODULE/integrity_box/sus.sh"
DEST_FILE="$SUSFS/action.sh"
PIF="$MODULE/playintegrityfix"
SHAMIKO="$MODULE/zygisk_shamiko"
NOHELLO="$MODULE/zygisk_nohello"
TRICKY_STORE="$MODULE/tricky_store"
SUSFS="$MODULE/susfs4ksu"


log() { echo -e "$1" | tee -a "$L"; }

# Remove unwanted files
if [ -e /data/adb/modules/integrity_box/disable ]; then
    rm -rf /data/adb/modules/integrity_box/disable
    log "Module re-enabled successfully"
else
    log "Status 1"
fi

if [ -e /data/adb/shamiko/whitelist ]; then
    rm -rf /data/adb/shamiko/whitelist
    log "Nuked whitelist to avoid bootloop"
else
    log "Status 2"
fi

if [ -e /data/adb/modules/Integrity-Box]; then
    rm -rf /data/adb/modules/Integrity-Box
    log "Nuked old integrity box module"
else
    log "Status 3"
fi

# Lists for sorted display
ENABLED_LIST=""
DISABLED_LIST=""

# Append helper
append_item() {
    if [ -z "$1" ]; then
        echo "$2"
    else
        echo "$1 | $2"
    fi
}

# Check and sort modules
[ -d "$SHAMIKO" ] && ENABLED_LIST=$(append_item "$ENABLED_LIST" "Shamiko ✅") || DISABLED_LIST=$(append_item "$DISABLED_LIST" "Shamiko ❌")
[ -d "$TRICKY_STORE" ] && ENABLED_LIST=$(append_item "$ENABLED_LIST" "TrickyStore ✅") || DISABLED_LIST=$(append_item "$DISABLED_LIST" "TrickyStore ❌")
[ -d "$NOHELLO" ] && ENABLED_LIST=$(append_item "$ENABLED_LIST" "NoHello ✅") || DISABLED_LIST=$(append_item "$DISABLED_LIST" "NoHello ❌")
[ -d "$SUSFS" ] && ENABLED_LIST=$(append_item "$ENABLED_LIST" "SusFS ✅") || DISABLED_LIST=$(append_item "$DISABLED_LIST" "SusFS ❌")
[ -d "$PIF" ] && ENABLED_LIST=$(append_item "$ENABLED_LIST" "PIF ✅") || DISABLED_LIST=$(append_item "$DISABLED_LIST" "PIF ❌")

# Combine and format final description
ALL_MODULES="$ENABLED_LIST"
[ -n "$DISABLED_LIST" ] && ALL_MODULES="$ALL_MODULES | $DISABLED_LIST"
description="description=assist mode: $ALL_MODULES"

# Update module.prop
sed -i "s/^description=.*/$description/" "$MODDIR/module.prop"

# Check if the destination directory exists
if [ ! -d "$SUSFS" ]; then
    log "- Directory not found: $SUSFS"
    exit 0
fi

# SusFs action button [DEPRECIATED]
# Copy 
#cp "$SRC" "$DEST_FILE"

# Set perms
#chmod +x "$DEST_FILE" 
#chmod 644 "$DEST_FILE" 

log " ok "