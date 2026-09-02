#!/system/bin/sh

MODPATH="${0%/*}"
. $MODPATH/common_func.sh

# Paths
BOX="/data/adb/Box-Brain"
LOGDIR="$BOX/Integrity-Box-Logs"

CPP="$LOGDIR/spoofing.log"
PATCH_LOG="$LOGDIR/patch.log"
LOG="$LOGDIR/root.log"
LOGFILE="$LOGDIR/gapps.log"

SCRIPT_DIR="$MODPATH/webroot/common_scripts"
UPDATE="$SCRIPT_DIR/key.sh"

PROP="$MODPATH/module.prop"
BAK="$PROP.bak"

FLAG="$BOX/advanced"
PATCH_FLAG="$BOX/patch"

P="$MODPATH/custom.pif.prop"
SKIP_FILE="$BOX/skip"
SPOOF_APPS="$BOX/per-app-spoofing"

PATCH_DATE="2026-08-05"
PROP_MAIN="ro.build.version.security_patch"

TARGET_DIR="/data/adb/tricky_store"
FILE_PATH="$TARGET_DIR/security_patch.txt"

DIR="/sdcard/Download"
OUTJSON="/sdcard/meow.json"

BRAND_PROP=$(getprop ro.product.system.brand)

MIGRATE_OK=0
INPUT_PROP=""

mkdir -p "$BOX" "$LOGDIR"
ensure_exec_permissions
recommended_settings
ensure_blacklist_entries

if [ -f "$BOX/root" ]; then
  rm -f "$BOX/root"
  find "$DIR" -type f \( -name "*_install_log_2026*" -o -name "*_action_log_2026*" \) | while read -r f; do
    echo "$(date '+%F %T') Deleted: $f" | tee -a "$LOG"
    rm -f "$f"
  done
  handle_delay
  exit 0
fi

if [ -e "$BOX/ota" ]; then
    rm -f "$MODPATH/system.prop"
    rm -f "$BOX/NoLineageProp"
    rm -rf "$BOX/override"
    rm -rf "$BOX/ota"
    touch "$BOX/safemode"
    echo " "
    echo " "
    echo "  D O N E 👍 | REBOOT YOUR DEVICE"
    handle_delay
    exit 0
fi

[ -f "$BOX/lsposed" ] && {
  echo "[*] Starting cleanup...";
  if getprop | grep -q "^\[dalvik.vm.dex2oat-flags\]"; then
    echo "[*] Removing dalvik.vm.dex2oat-flags...";
    if resetprop -p --delete dalvik.vm.dex2oat-flags 2>/dev/null; then
      echo "[✓] Property removed."
    else
      resetprop -p -d dalvik.vm.dex2oat-flags && echo "[✓] Property removed." || echo "[!] Failed to remove property."
    fi
  fi;
  rm -f "$BOX/lsposed" && echo "[✓] Cleanup complete.";
  echo "[*] Done. Exiting.";
  exit 0;
}

if [ -f "$BOX/gapps" ]; then
  rm -f "$BOX/gapps"
  echo "====================================" | tee -a "$LOGFILE"
  echo "Starting Log Cleanup" | tee -a "$LOGFILE"
  echo "====================================" | tee -a "$LOGFILE"
  echo "" | tee -a "$LOGFILE"

  TARGETS="
/sdcard/Android/litegapps/litegapps_controller.log
/tmp/NikGapps
/tmp/NikGapps/logfiles
/tmp/NikGapps/addonscripts
/tmp/NikGapps/logfiles/package_log
/sdcard/NikGapps
/tmp/recovery.log
/tmp/NikGapps.log
/tmp/Mount.log
/tmp/installation_size.log
/tmp/busybox.log
/tmp/Logs-*.tar.gz
/tmp/bitgapps_debug_logs_*.tar.gz
/sdcard/bitgapps_debug_logs_*.tar.gz
/system/etc/bitgapps_debug_logs_*.tar.gz
/sdcard/Download/*_install_log_2026*
/sdcard/Download/*_action_log_2026*
"

  for path in $TARGETS; do
    if echo "$path" | grep -q '\*'; then
      files=$(find "$(dirname "$path")" -type f -name "$(basename "$path")" 2>/dev/null)
    else
      files=$(find "$path" -type f 2>/dev/null)
    fi

    if [ -n "$files" ]; then
      echo "Found: $path" | tee -a "$LOGFILE"
      echo "$files" | tee -a "$LOGFILE"
      echo "$files" | while read -r f; do
        echo "Deleting: $f" | tee -a "$LOGFILE"
        rm -rf "$f" 2>&1 | tee -a "$LOGFILE"
      done
    fi

    if [ -d "$path" ]; then
      echo "Deleting directory: $path" | tee -a "$LOGFILE"
      rm -rf "$path" 2>&1 | tee -a "$LOGFILE"
    fi
  done

  echo "" | tee -a "$LOGFILE"
  echo "Cleanup complete." | tee -a "$LOGFILE"
  echo "====================================" | tee -a "$LOGFILE"
  handle_delay
  exit 0
fi

# Ensure log directory/file exists
mkdir -p "$(dirname "$CPP")" 2>/dev/null || true
touch "$CPP" 2>/dev/null || true

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$CPP"; }

# Exit if offline
#if ! megatron; then exit 1; fi

# Show header
print_header
reset_tricky_store

sh "$UPDATE" || { sleep 10; exit 1; }
echo " "

if [ -f "$BOX/keymint" ]; then
    "$SCRIPT_DIR/keymint.sh"
fi

# Mode
ARGDESC=""

[ -f "$BOX/use_qpr2" ]       && ARGDESC="$ARGDESC QPR2 "
[ -f "$BOX/use_advanced" ]   && ARGDESC="$ARGDESC ADVANCED "
[ -f "$BOX/use_strong" ]     && ARGDESC="$ARGDESC STRONG "
[ -f "$BOX/use_match" ]      && ARGDESC="$ARGDESC MATCH "
[ -f "$BOX/skip_json" ]      && ARGDESC="$ARGDESC SKIP_JSON "
[ -f "$BOX/skip_patch" ]     && ARGDESC="$ARGDESC SKIP_PATCH "
[ -f "$BOX/skip_keybox" ]    && ARGDESC="$ARGDESC SKIP_KEYBOX "
[ -f "$BOX/verbose_mode" ]   && ARGDESC="$ARGDESC VERBOSE "
[ -f "$BOX/force_spoof_off" ]&& ARGDESC="$ARGDESC NO_SPOOF "

for i in 1 2 3 4 5 6 7 8 9; do
    [ -f "$BOX/top_$i" ]   && ARGDESC="$ARGDESC top=$i" && break
done

for i in 1 2 3 4 5 6 7 8 9; do
    [ -f "$BOX/depth_$i" ] && ARGDESC="$ARGDESC depth=$i" && break
done

[ -n "$ARGDESC" ] && log_step "MODE" "$ARGDESC"

# Keybox Handling
for f in keybox keybox2; do
    SRC="$TARGET_DIR/$f.xml"
    [ "$f" = "keybox2" ] && DEST="/sdcard/aosp.xml" || DEST="/sdcard/$f.xml"
    su -c "[ -e \"$BOX/$f\" ] && [ -r \"$SRC\" ] && cat \"$SRC\" > \"$DEST\" && sync" >/dev/null 2>&1
done

# Spoofing
[ -f "$FLAG" ] && LABEL="Advanced Fingerprint" || LABEL="Pixel Canary Imprint"
sh "$MODPATH/osm0sis.sh" && log_step "UPDATED" "$LABEL" || log_step "FAILED" "$LABEL"

# Migrate
MARGS=""
MDESC=""

[ -f "$BOX/migrate_force" ]    && MARGS="$MARGS -f" && MDESC="$MDESC force "
[ -f "$BOX/migrate_override" ] && MARGS="$MARGS -o" && MDESC="$MDESC override "
[ -f "$BOX/migrate_advanced" ] && MARGS="$MARGS -a" && MDESC="$MDESC advanced "

HAS_JSON=0
HAS_PROP=0
[ -f "$BOX/migrate_json" ] && HAS_JSON=1
[ -f "$BOX/migrate_prop" ] && HAS_PROP=1

if [ "$HAS_JSON" -eq 1 ] && [ "$HAS_PROP" -eq 1 ]; then
    log_step "WARNING" "Migrate Format Conflict"
    MARGS="$MARGS -p"
    MDESC="$MDESC prop"
elif [ "$HAS_JSON" -eq 1 ]; then
    MARGS="$MARGS -j"
    MDESC="$MDESC json"
elif [ "$HAS_PROP" -eq 1 ]; then
    MARGS="$MARGS -p"
    MDESC="$MDESC prop"
fi

if [ -f "$BOX/run_migrate" ]; then
    if sh "$MODPATH/migrate.sh" $MARGS "$INPUT_PROP" >>"$CPP" 2>&1; then
        MIGRATE_OK=1
        log_step "MIGRATE" "Pixel RAW Fingerprint"
    else
        log_step "WARNING" "migrate.sh failed ($MDESC)"
    fi
else
    log_step "SKIPPED" "migrate.sh disabled"
fi

# Expiry Handling
if [ "$MIGRATE_OK" -eq 1 ] && [ -f "$BOX/remove_expiry" ]; then
    sed -i '/Released On:/d;/Estimated Expiry:/d' "$P"
#    log_step "REMOVED" "Expiry comment removed"
#else
#    log_step "SKIPPED" "Expiry handling"
fi

# JSON Export
if [ "$MIGRATE_OK" -eq 1 ] && [ -f "$BOX/json" ] && [ ! -f "$BOX/skip_json" ] && [ -f "$P" ]; then
    {
        echo "{"
        echo '  "BuildFields": {'
        first=1
        skip_section=0
        while IFS= read -r line; do
            case "$line" in
                "# Advanced Settings"*) skip_section=1; continue ;;
                "# Build Fields"*|"# System Properties"*) skip_section=0; continue ;;
                \#*|"") continue ;;
            esac
            [ "$skip_section" -eq 1 ] && continue
            case "$line" in *=*) ;; *) continue ;; esac
            key="${line%%=*}"
            val="${line#*=}"
            key="${key#*.}"
            [ "$first" -eq 0 ] && echo ","
            printf '    "%s": "%s"' "$key" "$val"
            first=0
        done < "$P"
        echo
        echo "  }"
        echo "}"
    } > "$OUTJSON"
    log_step "CREATED" "PIF.json to $OUTJSON"
else
    log_step "SKIPPED" "PIF.json dump"
fi


# Rebuild targets + OMK injector (shared pipeline with target.sh)
sh "$SCRIPT_DIR/target.sh"

# Write security_patch.txt based on patch flag
if [ -f "$PATCH_FLAG" ]; then
  echo "system=prop" > "$FILE_PATH" 2>>"$PATCH_LOG"
  log_step "UPDATED" "Patch to Stock"

else
  echo "all=$PATCH_DATE" > "$FILE_PATH" 2>>"$PATCH_LOG"
  log_step "SPOOFED" "Tricky Patch to $PATCH_DATE"

  CURRENT_PROP="$(getprop "$PROP_MAIN" | tr -d ' \t\r\n')"
  log_patch "Current $PROP_MAIN: $CURRENT_PROP"

  # Skip resetprop if skip file exists
  if [ -f "$SKIP_FILE" ]; then
    log_step "SKIPPED" "Skip file present, resetprop disabled"

  # Skip resetprop only for Oplus devices
  elif [ "$BRAND_PROP" = "oplus" ]; then
    log_step "ONEPLUS" "Avoiding due to hardware issues"

  else
    if [ "$CURRENT_PROP" != "$PATCH_DATE" ]; then
      if command -v resetprop >/dev/null 2>&1; then
        resetprop "$PROP_MAIN" "$PATCH_DATE"
        log_step "PATCHED" "$PROP_MAIN to $PATCH_DATE"
      else
        log_step "FAILED" "resetprop not found"
      fi
    else
      log_step "MASKING" "System & Vendor patch not required"
    fi
  fi
fi

log_patch "Patch handling complete"
log_patch " "

restart_gms

log_step "RESTART" "Google Service Processes"

sh "$SCRIPT_DIR/cleanup.sh" >/dev/null 2>&1; 

# Execute teesim.sh unless explicitly disabled
if [ ! -e "$BOX/teesim" ]; then
    sh "$SCRIPT_DIR/teesim.sh"
    log_step "WRITING" "TEEsim Build fields"
fi

# Restore per-App-Spoofing value
if [ -f "$P" ]; then
    if [ -f "$SPOOF_APPS" ]; then
        sed -i 's/^spoofApps=.*/spoofApps=1/' "$P"
    else
        sed -i 's/^spoofApps=.*/spoofApps=0/' "$P"
    fi
fi

# Update module description
bb="$(P)"

if [ -n "$bb" ]; then
  # Model
  MODEL=""
  [ -f "$P" ] && MODEL=$($bb sed -n 's/^MODEL=//p' "$P" | $bb head -n1)
  [ -z "$MODEL" ] && MODEL="Unknown"

  # Targets
  T=0
  [ -f "/data/adb/tricky_store/target.txt" ] && T=$($bb grep -c '.' "/data/adb/tricky_store/target.txt" 2>/dev/null | $bb tr -d ' ')
  [ -z "$T" ] && T=0

  # Spoofed apps
  S=0
  SPOOF_APPS_VAL=""
  [ -f "$P" ] && SPOOF_APPS_VAL=$($bb sed -n 's/^spoofApps=//p' "$P" | $bb head -n1)

  if [ "$SPOOF_APPS_VAL" = "1" ]; then
    [ -f "/data/adb/modules/playintegrityfix/apps.txt" ] && S=$($bb grep -c '.' "/data/adb/modules/playintegrityfix/apps.txt" 2>/dev/null | $bb tr -d ' ')
    [ -z "$S" ] && S=0
  fi

  # Blocked
  B=0
  [ -f "$BOX/blacklist.txt" ] && B=$($bb grep -c '.' "$BOX/blacklist.txt" 2>/dev/null | $bb tr -d ' ')
  [ -z "$B" ] && B=0

  # Build & write
  DESC="$MODEL    Targets: $T    Spoofed: $S    Blocked: $B"

  [ ! -f "$BAK" ] && $bb cp "$PROP" "$BAK"
  $bb sed -i '/^description=/d' "$PROP"
  echo "description=$DESC" >> "$PROP"
fi

echo " "
echo " "
echo "    -- ACTION COMPLETED SUCCESSFULLY --"
#randomize_banner
handle_delay

# Special treatment for an AI-generated garbage module named SPECTER that removes IntegrityBox for no reason, 

# It deliberately removes IntegrityBox under the vague excuse of a "conflict" without ever identifying or explaining any actual incompatibility. 

# If a real conflict existed, it could've been documented instead of silently removing it.

# We don't support misleading behavior or arbitrary decisions disguised as compatibility fixes 

for path in \
    "/data/adb/modules/specter" \
    "/data/adb/specter" \
    "/data/adb/modules_update/specter" \
    "/sdcard/specter-update"
do
    [ -e "$path" ] && rm -rf "$path" 2>/dev/null || true
done

# https://github.com/dpejoh/specter/blob/489ca15ba02d8de781d275c5db8c502dbb255247/src/lib/conflicts.sh#L20

# Looks more like another blind hater than someone acting in good faith. Anyway, I got you, bro.
exit 0
