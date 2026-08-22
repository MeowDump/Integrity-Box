#!/system/bin/sh

LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/pifhook.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Universal resetprop detection
RP=""
for p in $(which resetprop 2>/dev/null) /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop /sbin/resetprop /system/xbin/resetprop /system/bin/resetprop; do
    if [ -f "$p" ]; then
        RP="$p"
        break
    fi
done

if [ -z "$RP" ]; then
    echo "[ERROR] resetprop not found" | tee -a "$LOG_FILE"
    exit 1
fi

# Detect compact vs full resetprop
IS_COMPACT=false
if [ -n "$RP" ]; then
    HELP=$($RP --help 2>&1 || true)
    if echo "$HELP" | grep -q "\-p"; then
        : # Full resetprop, -p supported
    else
        IS_COMPACT=true
    fi
fi

# Init logging
echo "[INFO] Script started at $(date)" > "$LOG_FILE"
echo "[INFO] resetprop: $RP (compact=$IS_COMPACT)" >> "$LOG_FILE"

# Helper: delete prop
resetprop_delete(){
    if [ "$IS_COMPACT" = "true" ]; then
        $RP -d "$1"
    else
        $RP -p -d "$1"
    fi
}

# Get matching props, log them, and nuke them
getprop | grep -E "pphooks|pihook|pixelprops|gms|pi" | sed -E "s/^\[(.*)\]:.*/\1/" | while IFS= read -r prop; do
    echo "[DELETE] $prop" >> "$LOG_FILE"
    resetprop_delete "$prop"
    if [ $? -eq 0 ]; then
        echo "[OK] Deleted: $prop" >> "$LOG_FILE"
    else
        echo "[FAIL] Failed to delete: $prop" >> "$LOG_FILE"
    fi
done

echo "[INFO] Task completed at $(date)" >> "$LOG_FILE"
