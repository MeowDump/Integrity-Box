#!/system/bin/sh

BOX="/data/adb/Box-Brain"
LOG="$BOX/Integrity-Box-Logs/Multiple-Root-Implementation.log"
ROOT_DIR="$BOX/ROOT"

# All items to manage
ALL_ITEMS="/data/adb/magisk /data/adb/ap /data/adb/fp /data/adb/apd /data/adb/ksu /data/adb/ksud"

# Flag-to-protected paths mapping
# When a flag is active, these paths stay on device
protect_apatch="/data/adb/ap /data/adb/apd"
protect_magisk="/data/adb/magisk"
protect_kernelsu="/data/adb/ksu /data/adb/ksud"

log_msg() {
    if [[ -z "${_LOG_MSG_INITIALIZED:-}" ]]; then
        : > "$LOG"
        _LOG_MSG_INITIALIZED=1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# Ensure directories exist
mkdir -p "$BOX/Integrity-Box-Logs"
mkdir -p "$ROOT_DIR"

# Determine active flag
active_flag=""
flag_count=0

for flag in apatch magisk kernelsu; do
    if [ -f "$ROOT_DIR/$flag" ]; then
        active_flag="$flag"
        flag_count=$((flag_count + 1))
    fi
done

# Multiple flags = conflict, log and exit
if [ "$flag_count" -gt 1 ]; then
    log_msg "ERROR: Multiple flags detected ($flag_count). Only one allowed."
    exit 1
fi

# No flag active = restore
if [ "$flag_count" -eq 0 ]; then
    log_msg "No active flag found. Restoring backup"
    restored=0

    for src in $ALL_ITEMS; do
        name=$(basename "$src")
        backup="$ROOT_DIR/$name"

        if [ -e "$backup" ]; then
            if [ -e "$src" ]; then
                log_msg "Source $src already exists. Removing stale backup $backup"
                rm -rf "$backup"
            else
                log_msg "Restoring $backup > $src"
                mv -f "$backup" "$src"
                restored=1
            fi
        fi
    done

    if [ "$restored" -eq 1 ]; then
        log_msg "Restore completed successfully."
    else
        log_msg "No backups found. Nothing to restore."
    fi
    exit 0
fi

# One flag active = backup mode
log_msg "Active flag: $active_flag"

# Determine protected paths for flag
eval 'protected="$protect_'"$active_flag"'"'

for src in $ALL_ITEMS; do
    name=$(basename "$src")
    backup="$ROOT_DIR/$name"

    # Skip if this path is protected for the active flag
    skip=0
    for p in $protected; do
        if [ "$src" = "$p" ]; then
            skip=1
            break
        fi
    done

    if [ "$skip" -eq 1 ]; then
        log_msg "Protected: $src (skipped)"
        continue
    fi

    if [ -e "$src" ]; then
        # Source exists on device = move to backup
        if [ -e "$backup" ]; then
            log_msg "Removing old backup $backup"
            rm -rf "$backup"
        fi
        log_msg "Backing up $src > $backup"
        mv -f "$src" "$backup"
    else
        # Source already gone
        if [ -e "$backup" ]; then
            log_msg "Already backed up: $backup"
        else
            log_msg "Not found: $src (no backup)"
        fi
    fi
done

log_msg "Backup operation completed for: $active_flag"
log_msg " "
exit 0
