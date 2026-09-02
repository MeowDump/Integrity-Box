#!/system/bin/sh

MODPATH="/data/adb/modules/playintegrityfix"
. $MODPATH/common_func.sh

RP="$(find_resetprop)" || {
    echo "[ERROR] resetprop not found"
    exit 1
}

L=/data/adb/Box-Brain/Integrity-Box-Logs/ForceSpoof.log
mkdir -p "${L%/*}"
getprop | grep -i lineage | while read -r l; do
p=${l#*[}; p=${p%%]*}
echo "$(date '+%F %T') DEL $p" >> "$L"
$RP -d "$p"
done
