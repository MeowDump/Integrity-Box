#!/system/bin/sh

LOG="/data/adb/Box-Brain/Integrity-Box-Logs/sus.log"

mkdir -p "$(dirname "$LOG")" 2>/dev/null

log_msg() {
    local msg
    msg="$(date '+%F %T') | $1"
    echo "$msg" >> "$LOG"
    echo "$msg"
}

log_msg " ••••• Cleanup started •••••"

DIR="/sdcard/Download"

if [ -d "$DIR" ]; then
    log_msg "Scanning $DIR for old action logs..."

    find "$DIR" -maxdepth 1 -type f -name "*_action_log_2025*" 2>/dev/null | while IFS= read -r f; do
        log_msg "Deleted: $f"
        rm -f "$f"
    done
else
    log_msg "Directory $DIR not found, skipping..."
fi

TARGETS="
/sdcard/Android/litegapps/litegapps_controller.log|file
/tmp/NikGapps|dir
/tmp/NikGapps/logfiles|dir
/tmp/NikGapps/addonscripts|dir
/tmp/NikGapps/logfiles/package_log|dir
/sdcard/NikGapps|dir
/tmp/recovery.log|file
/tmp/NikGapps.log|file
/tmp/Mount.log|file
/tmp/installation_size.log|file
/tmp/busybox.log|file
/tmp/Logs-*.tar.gz|file
/tmp/bitgapps_debug_logs_*.tar.gz|file
/sdcard/bitgapps_debug_logs_*.tar.gz|file
/system/etc/bitgapps_debug_logs_*.tar.gz|file
/sdcard/Download/*_install_log_2026*|file
/sdcard/Download/*_action_log_2026*|file
"

echo "$TARGETS" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    
    path="${line%|*}"
    type="${line#*|}"
    [ -z "$path" ] && continue
    
    if echo "$path" | grep -q '\*'; then
        dir_path="${path%/*}"
        pattern="${path##*/}"
        
        [ -d "$dir_path" ] || continue
        
        find "$dir_path" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | while IFS= read -r match; do
            log_msg "Deleting file: $match"
            rm -f "$match"
        done
    else
        if [ "$type" = "file" ] && [ -f "$path" ]; then
            log_msg "Deleting file: $path"
            rm -f "$path"
        elif [ "$type" = "dir" ] && [ -d "$path" ]; then
            log_msg "Deleting directory: $path"
            rm -rf "$path"
        fi
    fi
done

log_msg " ••••• Cleanup complete •••••"
log_msg " "
