#!/system/bin/sh
FILE="/data/adb/tricky_store/keybox.xml"
TMP="/data/adb/tricky_store/keybox.xml.tmp"
LOG_FILE="/data/adb/Integrity-Box-Logs/remove.log"
PLACEHOLDER="mona.sh"

log() {
    echo "- $1" | tee -a "$LOG_FILE"
}

delete_if_exists() {
    path="$1"
    if [ -e "$path" ]; then
        rm -rf "$path"
        log "Deleted: $path"
    fi
}

touch $LOG_FILE
echo "" >> "$LOG_FILE"
echo "••••••• Cleanup Started •••••••" >> "$LOG_FILE"

if [ ! -f "$FILE" ]; then
    log "File not found: $FILE"
    exit 1
fi

log "Removing leftover files..."

C1=""
while IFS= read -r LINE; do
    C2=$(echo "$LINE" | sed "s/$PLACEHOLDER//g")
    C1="${C1}${C2}\n"
done < "$FILE"

printf "%b" "$C1" > "$TMP" && mv "$TMP" "$FILE"

delete_if_exists /data/adb/Integrity-Box/openssl
delete_if_exists /data/adb/Integrity-Box/libssl.so.3
delete_if_exists /data/adb/modules/Integrity-Box/system/bin/openssl
delete_if_exists /data/data/com.termux/files/usr/bin/openssl
delete_if_exists /data/data/com.termux/files/lib/openssl.so
delete_if_exists /data/data/com.termux/files/lib/libssl.so
delete_if_exists /data/data/com.termux/files/lib/libcrypto.so
delete_if_exists /data/data/com.termux/files/lib/libssl.so.3
delete_if_exists /data/data/com.termux/files/lib/libcrypto.so.3

echo "•••••••= Cleanup Ended •••••••=" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"