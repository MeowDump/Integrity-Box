#!/system/bin/sh

file="/sdcard/stop"
shamiko="/data/adb/shamiko/whitelist"
nohello="/data/adb/nohello/whitelist"

MEOW() {
  am start -a android.intent.action.MAIN -e mona "$1" -n meow.helper/.MainActivity &>/dev/null
  sleep 0.5
}

# Create the stop file
if ! touch "$file"; then
  MEOW "❌ Failed to create stop file"
  exit 1
#else
#   MEOW "✅ Auto Whitelist Mode disabled"
fi

# Delete Shamiko whitelist if it exists
[ -f "$shamiko" ] && {
  rm -f "$shamiko"
  MEOW "🛑 Shamiko auto-whitelist stopped"
}

# Delete NoHello whitelist if it exists
[ -f "$nohello" ] && {
  rm -f "$nohello"
  MEOW "🛑 NoHello auto-whitelist stopped"
}

exit 0