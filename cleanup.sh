#!/system/bin/sh

LOG_FILE="/data/adb/Integrity-Box/remove.log"

log() {
    echo "[+] $1" | tee -a "$LOG_FILE"
}

delete_if_exists() {
    local path="$1"
    if [ -e "$path" ]; then
        rm -rf "$path"
        log "Deleted: $path"
    else
        log "File not found: $path"
    fi
}

mkdir -p /data/adb/Integrity-Box
echo "••••••• Cleanup Started: $(date) •••••••" >> "$LOG_FILE"

log "Removing leftover files..."

delete_if_exists /data/adb/Integrity-Box/openssl
delete_if_exists /data/adb/Integrity-Box/libssl.so.3
delete_if_exists /data/adb/modules/Integrity-Box/system/bin/openssl
delete_if_exists /data/data/com.termux/files/usr/bin/openssl
delete_if_exists /data/data/com.termux/files/lib/openssl.so
delete_if_exists /data/data/com.termux/files/lib/libssl.so
delete_if_exists /data/data/com.termux/files/lib/libcrypto.so
delete_if_exists /data/data/com.termux/files/lib/libssl.so.3
delete_if_exists /data/data/com.termux/files/lib/libcrypto.so.3

echo "•••••••= Cleanup Ended: $(date) •••••••=" >> "$LOG_FILE"
