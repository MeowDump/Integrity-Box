# MeowMeow
MEOW() {
  am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity >/dev/null
  sleep 0.5
}

MEOW " Let Me Take Care Of This🤫"

# log file path and output file path
L="/data/adb/Integrity-Box-Logs/sus.log"
O="/data/adb/susfs4ksu/sus_path.txt"

# Ensure files exist before changing permissions
touch "$O" "$L"
chmod 644 "$O" "$L"

# Function to log messages
log() {
    echo "$1" | tee -a "$L"
}

echo "----------------------------------------------------------" >> "$L"
echo "Logged on $(date '+%A %d/%m/%Y %I:%M:%S%p')" >> "$L"
echo "----------------------------------------------------------" >> "$L"
echo " " >> "$L"

# Check if the output file is writable
if [ ! -w "$O" ]; then
    log "- $O is not writable. Please check file permissions."
    exit 1
fi

# Log the start of the process
log "- Adding necessary paths to sus list"
log " "
> "$O"

# Add paths manually
for path in \
    "/system/addon.d" \
    "/sdcard/TWRP" \
    "/sdcard/Fox" \
    "/vendor/bin/install-recovery.sh" \
    "/system/bin/install-recovery.sh"; do
    echo "$path" >> "$O"
    log "- Path added: $path"
done

log "- saved to sus list"
log " "

# Prepare for scanning
log "- Scanning system for Custom ROM detection.."

# Search for traces in the specified directories
for dir in /system /product /data /vendor /etc /root; do
    log "- Searching in: $dir... "
    find "$dir" -type f 2>/dev/null | grep -i -E "lineageos|crdroid|gapps|evolution|magisk" >> "$O"
done

chmod 644 "$O"
log "- Scan complete. & saved to sus list "

MEOW "Make it SUS🥷"
log " "
exit 0