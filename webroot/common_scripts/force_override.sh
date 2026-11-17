#!/system/bin/sh

MODPATH="/data/adb/modules/playintegrityfix"
. "$MODPATH/common_func.sh"

L="/data/adb/Box-Brain/Integrity-Box-Logs/ForceSpoof.log"
mkdir -p "${L%/*}"

getprop | grep -i lineage | while read l; do
    p=${l#*[}
    p=${p%%]*}

    echo "$(date '+%F %T') DEL $p" >> "$L"
    delprop_if_exist "$p"
done
