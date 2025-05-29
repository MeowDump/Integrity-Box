#!/system/bin/sh
MODDIR=${0%/*}
TRICKY="/data/adb/modules/tricky_store"
T="/data/adb/tricky_store"
KB="$T/keybox.xml"
BC="$T/keybox.xml.bak"
IB="/data/adb/Integrity-Box"
L="$IB/Installation.log"
U="/data/adb/modules_update/Integrity-Box"
SUS="$U/sus.sh"
SUSF="/data/adb/susfs4ksu"
SUSP="$SUSF/sus_path.txt"
X="https://raw.githubusercontent.com/MeowDump/Integrity-Box/alpha/DUMP/buffer"
ASS="/system/product/app/MeowAssistant/MeowAssistant.apk"
PACKAGE="com.helluva.product.integrity"
TT="$T/target.txt"
PIF="/data/adb/modules/playintegrityfix"
PROP_FILE="$PIF/module.prop"
PATCH_DATE="2025-05-05"
FILE="/data/adb/tricky_store/security_patch.txt"
W="apatch,busybox,toybox,wget,curl"
HASH="$U/hashes.txt"
SCRIPT="$U/customize.sh"
TEE_STATUS="$TT/tee_status"
B="$U/busybox"
TMP="$T/keybox.tmp"

log() {
    echo "$1" | tee -a "$L"
}

MEOW() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

#Refresh the fp
log " "
log "- Scanning Play Integrity Fix"
if [ -d "$PIF" ] && [ -f "$PROP_FILE" ]; then
    if grep -q "name=Play Integrity Fix" "$PROP_FILE"; then
        log "- Detected: PIF by chiteroman"
        log "- Refreshing fingerprint using chiteroman's module"
        log " "
        log " "
        sh "$PIF/action.sh"
        log " "
    elif grep -q "name=Play Integrity Fork" "$PROP_FILE"; then
        log "- Detected: PIF by osm0sis"
        log "- Refreshing fingerprint using osm0sis's module"
        log " "
        log " "
        sh "$PIF/autopif2.sh"
        echo " "
        echo " "
        
    fi
fi

log " "
log "   ︵‿︵‿︵‿︵︵‿︵‿︵‿︵︵‿︵‿︵ "
log " "
log "    Starting Main Installation "
log "   ︵‿︵‿︵‿︵︵‿︵‿︵‿︵︵‿︵‿︵ "
log " "
sleep 1
mkdir -p $IB
touch $IB/Integrity-Box.log
#mv "$BIN" "$B"

# Network check
_hosts="8.8.8.8 1.1.1.1 google.com"
_success=0
for host in $_hosts; do
    if ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
        _success=1
        break
    fi
done

if [ $_success -eq 1 ]; then
    log "- Internet connection is available"
else
    log "- No / Poor internet connection. Please check your network"
    exit 1
fi

echo "- Checking Module Integrity...."

# Check if hash file exists
if [ ! -f "$HASH" ]; then
    log "- Error: Hash file not found at $HASH"
    exit 1
fi

. "$HASH"

SUM=$(md5sum "$SCRIPT" 2>/dev/null | awk '{print $1}')
if [ -z "$SUM" ]; then
    log "- Error calculating checksum for $SCRIPT"
    exit 1
fi
if [ "$SUM" != "$SCRIPT_HASH" ]; then
    log "- Tampering detected in module script!"
    log "- Expected: $SCRIPT_HASH"
    log "- Found:    $SUM"
    exit 1
fi

log "- Activating Meow Assistant"
if pm install "$MODPATH/$ASS" &>/dev/null; then
    MEOW "- Meow Assistant is Online"
else
log "- Meow assistant is Offline"
fi
echo " "
sleep 1

# Skip if tricky store doesn't exist
if [ -n "$TRICKY" ] && [ -d "$TRICKY" ]; then

# Backup Keybox
if [ -f "$KB" ]; then
    local _timestamp=$(date +%s)
    mv "$KB" "$BC"
    log "- Backing up old keybox"
else
    log "- Keybox not found. Skipping backup"
fi

chmod +x "$B"
[ -x "$B" ] && export PATH="${B%/*}:$PATH"
"$B" wget --no-check-certificate -qO "$TMP" "$X" || { echo "- Error 69"; exit 1; }
[ -s "$TMP" ] || { echo "- File empty"; exit 1; }

base64 -d "$TMP" | "$B" sed -E "s/($W)//g" > "$KB"
rm -f "$TMP"
[ -s "$KB" ] && echo "- Verification complete" || echo "- Verification failed"

# Remove the target.txt file if it exists
[ -f "$TT" ] && rm "$TT"

# Read teeBroken value
teeBroken="false"
if [ -f "$TEE_STATUS" ]; then
    teeBroken=$(grep -E '^teeBroken=' "$TEE_STATUS" | cut -d '=' -f2 2>/dev/null || echo "false")
fi

echo "- Updating target list as per your TEE status"
MEOW "This may take a while, have patience☕"

# Start writing the target list
echo "# Last updated on $(date '+%A %d/%m/%Y %I:%M:%S%p')" > "$TT"
echo "#" >> "$TT"
echo "android" >> "$TT"
echo "com.android.vending!" >> "$TT"
echo "com.google.android.gms!" >> "$TT"
echo "com.reveny.nativecheck!" >> "$TT"
echo "io.github.vvb2060.keyattestation!" >> "$TT"
echo "io.github.vvb2060.mahoshojo" >> "$TT"
echo "icu.nullptr.nativetest" >> "$TT"

# Function to add package names to target list
add_packages() {
    pm list packages "$1" | cut -d ":" -f 2 | while read -r pkg; do
        if [ -n "$pkg" ] && ! grep -q "^$pkg" "$TT"; then
            if [ "$teeBroken" = "true" ]; then
                echo "$pkg!" >> "$TT"
            else
                echo "$pkg" >> "$TT"
            fi
        fi
    done
}

# Add user apps
add_packages "-3"

# Add system apps
add_packages "-s"

# Display the result
MEOW "Target list has been updated ❤️"
  
  [ ! -f "$FILE" ] && echo "all=$PATCH_DATE" > "$FILE"
  MEOW "TrickyStore Spoof Applied ✅"
  
  chmod 644 "$TT"
  echo " "
  sleep 1

else
    log "- Skipping keybox steps: TrickyStore is missing ❌"
fi

# Check if the package exists before disabling it
if su -c pm list packages | grep -q "eu.xiaomi.module.inject"; then
    log "- Disabling spoofing for EU ROMs"
    su -c pm disable eu.xiaomi.module.inject &>/dev/null
fi

if pm list packages | grep -q "$PACKAGE"; then
    pm disable-user $PACKAGE
    echo "- Disabled Hentai PIF"
fi
sleep 1

log "- Performing internal checks"
log "- Checking for susFS"
if [ -f "$SUSP" ]; then
    log "- SusFS is installed"
    MEOW " Let Me Take Care Of This🤫"

touch "$SUSP"
chmod 644 "$SUSP"

echo "----------------------------------------------------------" >> "$L"
echo "Logged on $(date '+%A %d/%m/%Y %I:%M:%S%p')" >> "$L"
echo "----------------------------------------------------------" >> "$L"
echo " " >> "$L"

# Check if the output file is writable
if [ ! -w "$SUSP" ]; then
    log "- $SUSP is not writable. Please check file permissions."
    exit 0
fi

log "- Adding necessary paths to sus list"
log " "
> "$SUSP"

# Add paths manually
for path in \
    "/system/addon.d" \
    "/sdcard/TWRP" \
    "/sdcard/Fox" \
    "/vendor/bin/install-recovery.sh" \
    "/system/bin/install-recovery.sh"; do
    echo "$path" >> "$SUSP"
    log "- Path added: $path"
done

log "- Saved to sus list"
log " "

# Prepare for scanning
log "- Scanning system for Custom ROM detection.."

# Search for traces in the specified directories
for dir in /system /product /data /vendor /etc /root; do
    log "- Searching in: $dir... "
    find "$dir" -type f 2>/dev/null | grep -i -E "lineageos|crdroid|gapps|evolution|magisk" >> "$SUSP"
done

chmod 644 "$SUSP"
log "- Scan complete. & saved to sus list "

MEOW "Make it SUS🥷"
log " "
exit 0
else
    log "- SusFS not found. Skipping file generation"
fi

# Remove Old Config File If Exists
if [ -f "$SUSF/config.sh" ]; then
    log "- Removing old config file"
    rm "$SUSF/config.sh"
    log "- Old config file removed successfully"

# Update Config File
log "- Updating config file"
{
    echo "sus_su=7"
    echo "sus_su_active=7"
    echo "hide_cusrom=1"
    echo "hide_vendor_sepolicy=1"
    echo "hide_compat_matrix=1"
    echo "hide_gapps=1"
    echo "hide_revanced=1"
    echo "spoof_cmdline=1"
    echo "hide_loops=1"
    echo "force_hide_lsposed=1"
    echo "spoof_uname=2"
    echo "fake_service_list=1"
    echo "susfs_log=0"
} > "$SUSF/config.sh"
echo "#" >> $SUSF/config.sh
echo "# set SUS_SU & ACTIVE_SU" >> $SUSF/config.sh
echo "# according to your preferences" >> $SUSF/config.sh
echo "#" >> $SUSF/config.sh
echo "#" >> $SUSF/config.sh
echo "# Last updated on $(date '+%A %d/%m/%Y %I:%M:%S%p')" >> $SUSF/config.sh
log "- Config file generated successfully"
chmod 644 "$SUSF/config.sh"
chmod +x "$U/cleanup.sh"
echo " "
sleep 1
fi

echo " "
echo " ▬▬▬.◙.▬▬▬"
echo " ═▂▄▄▓▄▄▂"
echo " ◢◤ █▀▀████▄▄▄▄◢◤"
echo " █▄ █ █▄ ███▀▀▀▀▀▀▀╬"
echo " ◥█████◤"
echo " ══╩══╩═"
echo " ╬═╬"
echo " ╬═╬"
echo " ╬═╬"
echo " ╬═╬"
echo " ╬═╬ ☻/ Finishing installation"
echo " ╬═╬/▌ 👋 Bye - Bye "
echo " ╬═╬/ \ "
echo " "
sh "$U/cleanup.sh"
sleep 2

# Final User Prompt
log "- Smash The WebUI After Rebooting"
echo " "
echo " "
log "              Installation Completed "
log " "
log " " 

# Redirect Module Release Source and Finish Installation
nohup am start -a android.intent.action.VIEW -d https://t.me/MeowDump >/dev/null 2>&1 &
MEOW "This module was released by 𝗠𝗘𝗢𝗪 𝗗𝗨𝗠𝗣"
exit 0
# End Of File
