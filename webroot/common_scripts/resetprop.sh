#!/system/bin/sh

LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/pifhook.log"
RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-arm64-v8a"

[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-armeabi-v7a"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86_64"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86"

mkdir -p "$(dirname "$LOG_FILE")"

if [ ! -x "$RESETPROP_RS" ]; then
    echo "[ERROR] resetprop-rs binary not found" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[INFO] Script started at $(date)" > "$LOG_FILE"
echo "[INFO] resetprop-rs: $RESETPROP_RS" >> "$LOG_FILE"

$RESETPROP_RS | grep -E "pphooks|pihook|pixelprops|gms|pi" | sed -E "s/^\[(.*)\]:.*/\1/" | while IFS= read -r prop; do
    echo "[NUKE] $prop" >> "$LOG_FILE"
    $RESETPROP_RS --nuke "$prop"
    if [ $? -eq 0 ]; then
        echo "[OK] Nuked: $prop" >> "$LOG_FILE"
    else
        echo "[FAIL] Failed to nuke: $prop" >> "$LOG_FILE"
    fi
done

echo "[INFO] Task completed at $(date)" >> "$LOG_FILE"
