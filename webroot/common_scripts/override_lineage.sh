#!/system/bin/sh

MODPATH="/data/adb/modules/playintegrityfix"
. $MODPATH/common_func.sh

RP="$(find_resetprop)" || {
    echo "[ERROR] resetprop not found"
    exit 1
}

resetprop_set(){
    $RP -n "$1" "$2"
}

OVERRIDE="/data/adb/modules/playintegrityfix/webroot/common_scripts/force_override.sh"

if [ -f "/data/adb/Box-Brain/safemode" ]; then
    echo " Permission denied by Safe Mode"
    exit 1
fi

echo " Checking for Lineage Props"
getprop | grep -i lineage
echo " "

PROP_FILE="/data/adb/modules/playintegrityfix/system.prop"
LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/prop_debug.log"

echo "[prop spoof debug log]" >> "$LOG_FILE"
echo "[INFO] Script started at $(date)" >> "$LOG_FILE"

if [ ! -f "$PROP_FILE" ]; then
    echo "[ERROR] Prop file not found: $PROP_FILE" >> "$LOG_FILE"
    exit 1
fi

if [ ! -r "$PROP_FILE" ]; then
    echo "[ERROR] Cannot read prop file: $PROP_FILE" >> "$LOG_FILE"
    exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
    clean_line=$(echo "$line" | sed -E 's/^\[(.*)\]=\[(.*)\]$/\1=\2/')

    if [ -z "$clean_line" ] || echo "$clean_line" | grep -qE '^#'; then
        echo "[SKIP] Empty or comment: $line" >> "$LOG_FILE"
        continue
    fi

    key=$(echo "$clean_line" | cut -d '=' -f1)
    value=$(echo "$clean_line" | cut -d '=' -f2-)

    if [ -z "$key" ] || [ -z "$value" ]; then
        echo "[SKIP] Malformed line: $line" >> "$LOG_FILE"
        continue
    fi

    case "$key" in
        init.svc.*|ro.boottime.*)
            echo "[SKIP] Dynamic prop (not changeable): $key" >> "$LOG_FILE"
            continue
            ;;
        ro.crypto.state)
            echo "[SKIP] Encryption state spoof skipped: $key" >> "$LOG_FILE"
            continue
            ;;
        *)
            resetprop_set "$key" "$value"
            actual_value=$(getprop "$key")
            if [ "$actual_value" = "$value" ]; then
                echo "[OK] Overridden: $key=$value" >> "$LOG_FILE"
            else
                echo "[WARN] Failed to override: $key. Current value: $actual_value" >> "$LOG_FILE"
            fi
            ;;
    esac
done < "$PROP_FILE"

# Compact arenas to fix holes from other modules/sources
$RP -c >/dev/null 2>&1

if [ -f "$OVERRIDE" ]; then
    sh "$OVERRIDE"
fi

echo "[INFO] Script completed at $(date)" >> "$LOG_FILE"
echo "•••••••••••••••••••••=" >> "$LOG_FILE"
echo " "
echo " "
exit 0
