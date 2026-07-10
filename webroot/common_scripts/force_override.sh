#!/system/bin/sh

RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-arm64-v8a"

[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-armeabi-v7a"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86_64"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86"

if [ ! -x "$RESETPROP_RS" ]; then
    exit 1
fi

L=/data/adb/Box-Brain/Integrity-Box-Logs/ForceSpoof.log
mkdir -p ${L%/*}

$RESETPROP_RS | grep -i lineage | while read l; do
p=${l#*[}; p=${p%%]*}
echo "$(date '+%F %T') NUKE $p" >> $L
$RESETPROP_RS --nuke "$p"
done
