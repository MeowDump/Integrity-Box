#!/system/bin/sh

SCRIPT_DIR="/data/adb/modules/integrity_box"
TMP_KEY="/dev/key_tmp"

MENU="
Disable Auto-Whitelist Mode:stop.sh
Enable Auto-Whitelist Mode:start.sh
Add All apps in Target list:systemuser.sh
Add User app only in Target list:user.sh
Spoof TrickyStore patch:patch.sh
Set AOSP keybox:aosp.sh
Set Valid keybox (if AOSP):keybox.sh
Set Custom Fingerprint:pif.sh
Kill GMS process:kill.sh
Spoof SDK:spoof.sh
Update SusFS Config:sus.sh
Enable GMS Spoofing prop:setprop.sh
Disable GMS Spoofing prop:resetprop.sh
Abnormal Detection:abnormal.sh
Flagged Apps Detection:app.sh
Props Detection:prop.sh
FIX Device not Certified:vending.sh
Help Group:meowverse.sh
Telegram Channel:meowdump.sh
Report a problem:issue.sh
Module Info:info.sh
"

MEOW() {
  am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
  sleep 0.5
}

draw_box() {
  echo " "
  echo "╔══════════════════════════╗"
  while IFS= read -r line; do
    printf "║ %-28s ║\n" "$line"
  done <<EOF
$1
EOF
  echo "╚══════════════════════════╝"
  echo " "
}

print_menu() {
  clear
  draw_box "     Integrity-Box Menu "
  echo "- Use Volume Down to navigate"
  echo "+ Use Volume Up to execute"
  echo "• Press Power to cancel"
  echo " "
  print_selection_only
}

print_selection_only() {
  i=1
  while IFS= read -r line; do
    LABEL=$(echo "$line" | cut -d: -f1)
    [ "$i" -eq "$INDEX" ] && echo ">> $LABEL" || echo "   $LABEL"
    i=$((i + 1))
  done < /dev/tmp_menu
  echo " "
}

# Function to get key press
wait_for_key() {
  while :; do
    keyevent=$(getevent -qlc 1 2>/dev/null | grep "KEY_" | head -n 1)
    case "$keyevent" in
      *KEY_VOLUMEUP*) echo "UP"; return ;;
      *KEY_VOLUMEDOWN*) echo "DOWN"; return ;;
      *KEY_POWER*) echo "POWER"; return ;;
    esac
  done
}

# Setup Menu
echo "$MENU" | sed '/^$/d' > /dev/tmp_menu
TOTAL=$(wc -l < /dev/tmp_menu)
INDEX=1

print_menu

# Main Interaction Loop
while :; do
  key=$(wait_for_key)
  case "$key" in
    UP)
      SELECTED=$(sed -n "${INDEX}p" /dev/tmp_menu)
      LABEL=$(echo "$SELECTED" | cut -d: -f1)
      SCRIPT=$(echo "$SELECTED" | cut -d: -f2)
      sh "$SCRIPT_DIR/$SCRIPT"
      MEOW "Done: $LABEL"
      echo "- Done."
      break
      ;;
    DOWN)
      INDEX=$((INDEX + 1))
      [ "$INDEX" -gt "$TOTAL" ] && INDEX=1
      SELECTED=$(sed -n "${INDEX}p" /dev/tmp_menu)
      LABEL=$(echo "$SELECTED" | cut -d: -f1)
#      MEOW "$LABEL"
      clear
      draw_box "     Integrity-Box Menu "
      echo "- Use Volume Down to navigate"
      echo "+ Use Volume Up to execute"
      echo "• Press Power to cancel"
      echo " "
      print_selection_only
      ;;
    POWER)
      MEOW "Cancelled"
      echo " "
      echo "- Cancelled by user."
      break
      ;;
  esac
done

rm -f /dev/tmp_menu
exit 0
