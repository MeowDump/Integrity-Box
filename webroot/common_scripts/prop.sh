#!/system/bin/sh

LOGDIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOGFILE="$LOGDIR/romhide.log"
RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-arm64-v8a"

[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-armeabi-v7a"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86_64"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86"

mkdir -p "$LOGDIR"

log() {
 echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

log "••••• ROM Hide Started •••••"

$RESETPROP_RS | sed 's/^\[//; s/\]:.*//' | grep -i -E '(lineage|evolution|crdroid|arrow|mistos|axion|infinity|pixelos|rising|lunaris|halcyon|havoc|alphadroid|avium|bliss|calyx|derpfest|graphene|lmodroid|lumine|matrixx|sakura|statix|superior|clover|witaqua|yaap|mica)' | while IFS= read -r prop; do
 [ -z "$prop" ] && continue
 
 log "FOUND: $prop"
 if $RESETPROP_RS --nuke "$prop" 2>/dev/null; then
     log "NUKED: $prop"
 else
     log "FAILED: $prop"
 fi
done

log "••••• ROM Hide Finished •••••"
