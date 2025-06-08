#!/system/bin/sh

# Paths
LOG="/data/adb/Integrity-Box-Logs"
LOGFILE="$LOG/patch.log"
TARGET_DIR="/data/adb/tricky_store"
FILE_PATH="$TARGET_DIR/security_patch.txt"
FILE_CONTENT="all=2025-05-05"
U="/data/adb/modules/integrity_box"

chmod +x "$U/kill.sh"
sh "$U/kill.sh"

# Ensure directories exist
mkdir -p "$LOG"
mkdir -p "$TARGET_DIR"

# Logging function
log() { echo -e "$1" | tee -a "$LOGFILE"; }

# MeowMeow
MEOW() { am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity >/dev/null 2>&1; sleep 0.5; }

# Function to Detect Key Press
CheckKey() {
  while true; do
    key=$(getevent -qlc 1 | awk '/KEY_/ {print $3; exit}')
    case $key in
      KEY_VOLUMEUP|KEY_VOLUMEDOWN|KEY_POWER) echo "$key"; return ;;
    esac
    sleep 0.1
  done
}

# Start Logging
log "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  📝 Logged on:  $(date '+%A %d/%m/%Y %I:%M:%S %p')"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log " "

#: Security Patch Spoofing
log "For A13+ checks only"
log "\n📢 Security Patch Hack Options:"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "   [➕]  Spoof security patch"
log "   [➖]  Remove spoofed patch"
log "   [🔴]  Cancel operation"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log " "
MEOW " Vol+ Enable / Vol- Disable"
log " "

case $(CheckKey) in
  KEY_VOLUMEUP) 
    echo "$FILE_CONTENT" > "$FILE_PATH"
    log "✅ Security patch spoofed successfully!"
    MEOW "✅ Spoof applied!"
    ;;
  KEY_VOLUMEDOWN) 
    rm -f "$FILE_PATH"
    log "🗑️ Spoof removed!"
    MEOW "🗑️ File removed!"
    ;;
  KEY_POWER) 
    log "❌ Operation canceled!"
    MEOW "❌ Canceled!"
    exit 0 ;;
esac

log " "