#!/system/bin/sh

LOGDIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOGFILE="$LOGDIR/romhide.log"
mkdir -p "$LOGDIR"

log() {
 echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

log "••••• ROM Hide Started •••••"
getprop | sed 's/^\[//; s/\]:.*//' | grep -i -E '(lineage|evolution|crdroid|arrow|mistos|axion|infinity|pixelos|rising|lunaris|halcyon|havoc|alphadroid|avium|bliss|calyx|derpfest|graphene|lmodroid|lumine|matrixx|sakura|statix|superior|clover|witaqua|yaap|mica)' | while IFS= read -r prop; do
 [ -z "$prop" ] && continue
 
 log "FOUND: $prop"
 if resetprop -d "$prop" 2>/dev/null; then
     log "DELETED: $prop"
 else
     log "FAILED: $prop"
 fi
done

log "••••• ROM Hide Finished •••••"
