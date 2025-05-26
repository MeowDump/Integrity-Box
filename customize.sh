#!/system/bin/sh
#MODDIR=${0%/*}
MODDIR=${MODPATH:-/data/adb/modules/Integrity-Box}
TRICKY="/data/adb/modules/tricky_store"
T="/data/adb/tricky_store"
D="$T/keybox.xml"
B="$T/keybox.xml.bak"
IB="/data/adb/Integrity-Box"
SP="$IB/spam.log"
BF="$T/buffer.log"
L="$IB/Integrity-Box.log"
U="/data/adb/modules_update/Integrity-Box"
SUS="$U/sus.sh"
SUSF="/data/adb/susfs4ksu"
SUSP="$SUSF/sus_path.txt"
X="https://raw.githubusercontent.com/MeowDump/Integrity-Box/alpha/DUMP/spam.log"
ASS="/system/product/app/MeowAssistant/MeowAssistant.apk"
PACKAGE="com.helluva.product.integrity"
TT="$T/target.txt"
PIF="/data/adb/modules/playintegrityfix"
PROP_FILE="$PIF/module.prop"
PATCH_DATE="2025-05-05"
FILE="/data/adb/tricky_store/security_patch.txt"
W=""

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

chmod +x "$U/hash.sh"
sh "$U/hash.sh"

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

log "- Activating Meow Assistant"
if pm install "$MODPATH/$ASS" &>/dev/null; then
    MEOW "- Meow Assistant is Online"
else
log "- Meow assistant is signed with private key"
fi
echo " "
sleep 1

# Skip if tricky store doesn't exist
if [ -n "$TRICKY" ] && [ -d "$TRICKY" ]; then

# Backup Keybox
if [ -f "$D" ]; then
    local _timestamp=$(date +%s)
    mv "$D" "$B"
    log "- Backing up old keybox"
else
    log "- Keybox not found. Skipping backup"
fi

curl -sSL "$X" -o "$SP"
[ -s "$SP" ] && base64 -d "$SP" > "$BF" && rm -f "$SP"

F=$(head -n1 "$BF")
R=$(tail -n +2 "$BF")

for w in ${W//,/ }
do F=${F//$w/}; done

echo "$F" > "$TMP"
echo "$R" >> "$TMP"
mv "$TMP" "$BF"

  chmod +x "$U/temp.sh"
  sh "$U/temp.sh"
  sleep 1
  
  [ ! -f "$FILE" ] && echo "all=$PATCH_DATE" > "$FILE"
  MEOW "TrickyStore Spoof Applied ✅"
  
  chmod 644 "$TT"
  echo " "
  sleep 1

else
    log "- Skipping keybox steps: TrickyStore is missing 💀"
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
    chmod +x "$SUS"
    sh -x "$SUS"
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
echo " "
sleep 1
fi

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
sleep 1

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
