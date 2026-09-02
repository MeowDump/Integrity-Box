#!/system/bin/sh

MODPATH="/data/adb/modules/playintegrityfix"
. $MODPATH/common_func.sh

LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/pifhook.log"
mkdir -p "$(dirname "$LOG_FILE")"

RP="$(find_resetprop)" || {
    echo "[ERROR] resetprop not found" | tee -a "$LOG_FILE"
    exit 1
}

# Detect compact vs full resetprop
IS_COMPACT=false
$RP --help 2>&1 | grep -q "\-p" || IS_COMPACT=true

# Init logging
echo "[INFO] Script started at $(date)" > "$LOG_FILE"
echo "[INFO] resetprop: $RP (compact=$IS_COMPACT)" >> "$LOG_FILE"

# Get matching props, log them, and nuke them
getprop | grep -E "pphooks|pihook|pixelprops|gms|pi" | sed -E "s/^\[(.*)\]:.*/\1/" | while IFS= read -r prop; do
    echo "[DELETE] $prop" >> "$LOG_FILE"
    if [ "$IS_COMPACT" = "true" ]; then
        $RP -d "$prop" && echo "[OK] Deleted: $prop" >> "$LOG_FILE" \
                         || echo "[FAIL] Failed to delete: $prop" >> "$LOG_FILE"
    else
        $RP -p -d "$prop" && echo "[OK] Deleted: $prop" >> "$LOG_FILE" \
                          || echo "[FAIL] Failed to delete: $prop" >> "$LOG_FILE"
    fi
done

echo "[INFO] Task completed at $(date)" >> "$LOG_FILE"
