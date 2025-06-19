# Meowpopup
popup() {
  am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity >/dev/null
  sleep 0.5
}

# log file path and output file path
L="/data/adb/Integrity-Box-Logs/sus.log"
O="/data/adb/susfs4ksu/sus_path.txt"

# If file doesn't exist, notify and exit
if [ ! -f "$O" ]; then
  popup "susfs isn't installed ❌"
  exit 1
fi

popup " Let Me Take Care Of This🤫"

# Ensure file exists before changing permissions
touch "$L"
chmod 644 "$O" "$L"

# Function to meow messages
meow() {
    echo "$1" | tee -a "$L"
}

echo "----------------------------------------------------------" >> "$L"
echo "Logged on $(date '+%A %d/%m/%Y %I:%M:%S%p')" >> "$L"
echo "----------------------------------------------------------" >> "$L"
echo " " >> "$L"

# Check if the output file is writable
if [ ! -w "$O" ]; then
    meow "- $O is not writable. Please check file permissions."
    exit 1
fi

# Log the start of the process
meow "- Adding necessary paths to sus list"
meow " "
> "$O"

# Add paths manually
for path in \
    "/system/addon.d" \
    "/sdcard/TWRP" \
    "/sdcard/Fox" \
    "/vendor/bin/install-recovery.sh" \
    "/system/bin/install-recovery.sh"; do
    echo "$path" >> "$O"
    meow "- Path added: $path"
done

meow "- saved to sus list"
meow " "

# Prepare for scanning
meow "- Scanning system for Custom ROM detection.."

# Search for traces in the specified directories
for dir in /system /product /data /vendor /etc /root; do
    meow "- Searching in: $dir... "
    find "$dir" -type f 2>/dev/null | grep -i -E "lineageos|crdroid|gapps|evolution|magisk" >> "$O"
done

chmod 644 "$O"
meow "- Scan complete. & saved to sus list "

popup "Make it SUS🥷"
meow " "
exit 0