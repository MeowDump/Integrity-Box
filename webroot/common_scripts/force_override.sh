#!/system/bin/sh

# Universal resetprop detection
RP=""
for p in $(which resetprop 2>/dev/null) /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop /sbin/resetprop /system/xbin/resetprop /system/bin/resetprop; do
    if [ -f "$p" ]; then
        RP="$p"
        break
    fi
done

# Detect compact vs full resetprop
IS_COMPACT=false
if [ -n "$RP" ]; then
    HELP=$($RP --help 2>&1 || true)
    if echo "$HELP" | grep -q "\-p"; then
        : # Full resetprop, -p supported
    else
        IS_COMPACT=true
    fi
fi

# Helper functions
resetprop_delete(){
    if [ "$IS_COMPACT" = "true" ]; then
        $RP -d "$1"
    else
        $RP -d "$1"
    fi
}

L=/data/adb/Box-Brain/Integrity-Box-Logs/ForceSpoof.log
mkdir -p ${L%/*}
getprop | grep -i lineage | while read l; do
p=${l#*[}; p=${p%%]*}
echo "$(date '+%F %T') DEL $p" >> $L
resetprop_delete "$p"
done
