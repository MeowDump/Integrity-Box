#!/bin/sh

# Paths
MODDIR="/data/adb/modules/Integrity-Box"
SRC_JSON="$MODDIR/pif.json"
DST_DIR="/data/adb"
FORK_JSON="$DST_DIR/custom.pif.json"
NORMAL_JSON="$DST_DIR/pif.json"
LOG="$DST_DIR/Integrity-Box/pif.log"
KILL="$MODDIR/kill.sh"

popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

# Logger
log() { echo -e "$1" | tee -a "$LOG"; }

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "       [👉👈] Updating Fingerprint"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "$SRC_JSON" ]; then
    if [ -f "$FORK_JSON" ]; then
        cp "$SRC_JSON" "$FORK_JSON"
        chmod 644 "$FORK_JSON"
        log "- PIF Fork detected, saved as custom.pif.json"
        popup "custom.pif.json updated"
        sleep 2
        chmod +x "$KILL"
        sh "$KILL"
    else
        cp "$SRC_JSON" "$NORMAL_JSON"
        chmod 644 "$NORMAL_JSON"
        log "- Saved as pif.json"
        popup "pif.json updated"
        sleep 2
        chmod +x "$KILL"
        sh "$KILL"
    fi
else
    log "❌ pif.json not found!"
    popup "pif.json missing"
fi

exit 0
