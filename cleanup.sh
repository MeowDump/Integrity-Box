#!/system/bin/sh
FILE="/data/adb/tricky_store/keybox.xml"
TMP="/data/adb/tricky_store/keybox.xml.tmp"
L="/data/adb/Integrity-Box-Logs/remove.log"
PLACEHOLDER="mona.sh"

meow() {
    echo "- $1" | tee -a "$L"
}

nuke() {
    path="$1"
    if [ -e "$path" ]; then
        rm -rf "$path"
        meow "Deleted: $path"
    fi
}

touch $L
echo "" >> "$L"
echo "••••••• Cleanup Started •••••••" >> "$L"

if [ ! -f "$FILE" ]; then
    meow "File not found: $FILE"
    exit 1
fi

echo "Removing leftover files..." >> "$L"

C1=""
while IFS= read -r LINE; do
    C2=$(echo "$LINE" | sed "s/$PLACEHOLDER//g")
    C1="${C1}${C2}\n"
done < "$FILE"

printf "%b" "$C1" > "$TMP" && mv "$TMP" "$FILE"

nuke /data/adb/Integrity-Box/openssl
nuke /data/adb/Integrity-Box/libssl.so.3
nuke /data/adb/modules/Integrity-Box/system/bin/openssl
nuke /data/data/com.termux/files/usr/bin/openssl
nuke /data/data/com.termux/files/lib/openssl.so
nuke /data/data/com.termux/files/lib/libssl.so
nuke /data/data/com.termux/files/lib/libcrypto.so
nuke /data/data/com.termux/files/lib/libssl.so.3
nuke /data/data/com.termux/files/lib/libcrypto.so.3

echo "•••••••= Cleanup Ended •••••••=" >> "$L"
echo "" >> "$L"