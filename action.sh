#!/system/bin/sh

MODPATH="${0%/*}"
. $MODPATH/common_func.sh

# Paths
BOX="/data/adb/Box-Brain"
LOGDIR="$BOX/Integrity-Box-Logs"

LOGFILEZ="$LOGDIR/PIF.log"
CPP="$LOGDIR/spoofing.log"
PATCH_LOG="$LOGDIR/patch.log"
LOG="$LOGDIR/root.log"
LOGFILE="$LOGDIR/gapps.log"
LOGZ="$LOGDIR/integrity_downloader.log"

SCRIPT_DIR="$MODPATH/webroot/common_scripts"
UPDATE="$SCRIPT_DIR/key.sh"

PROP="$MODPATH/module.prop"
BAK="$PROP.bak"

URL="https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/keybox/key-status"
INSTALLATION="/data/adb/modules_update/playintegrityfix/webroot/common_scripts/key.sh"

FLAG="$BOX/advanced"
PATCH_FLAG="$BOX/patch"

P="$MODPATH/custom.pif.prop"
SKIP_FILE="$BOX/skip"
SPOOF_APPS="$BOX/per-app-spoofing"

PATCH_DATE="2026-07-05"
PROP_MAIN="ro.build.version.security_patch"

TARGET_DIR="/data/adb/tricky_store"
FILE_PATH="$TARGET_DIR/security_patch.txt"

DIR="/sdcard/Download"
OUTJSON="/sdcard/meow.json"

URL_ZN="https://github.com/Dr-TSNG/ZygiskNext/releases/download/v1.4.3/Zygisk-Next-1.4.3-817-e815170-release.zip"
SUM_ZN="82fb9176037771a9ed4f6a530581c7826460dbc19ca5a6908b95c60b86903858"
URL_CP="https://github.com/LSPosed/CorePatch/releases/download/4.9/app-release.apk"
SUM_CP="1bdc47d5b48afffd37948a9f5638ae6a5f3d4d02ca01ae36143588284b979996"
URL_TH="https://github.com/trinadhthatakula/Thor/releases/download/v1.92.0/foss-release.apk"
SUM_TH="4a11ab3a9d0e454fbf00051fa1b6ec883d5cb4ffad450255f87520b1d6c21d68"
URL_AF="https://github.com/Android1500/AndroidFaker/releases/download/v2.0.0-beta-9-5/AF-v2.0.0-beta-9-5.apk"
SUM_AF="ec46d481c8f455f36204ffb113dd2623c464dab58d1d2e64e4e42d24fa69d7c8"
URL_TS="https://github.com/5ec1cff/TrickyStore/releases/download/1.4.1/Tricky-Store-v1.4.1-245-72b2e84-release.zip"
SUM_TS="2f5e73fcba0e4e43b6e96b38f333cbe394873e3a81cf8fe1b831c2fbd6c46ea9"
URL_KA="https://github.com/qwq233/KeyAttestation/releases/download/1.8.4/key-attestation-v1.8.4-release.apk"
SUM_KA="c9bbc118c75b11bfca7d99b67470d68b5505e1959b6a5f0b298b38ba8104c93a"
URL_UL="https://github.com/Xposed-Modules-Repo/ru.mike.updatelocker/releases/download/20-1.4.3/updatelocker_v1.4.3_icon.apk"
SUM_UL="a5ad1d5263e5f55500423f629b314c6003e8108df3f6d487db7581474b44d097"
URL_HMA="https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/toolkit/config.json"
SUM_HMA="c8eba943f9c5611f3f53dd661d51f364120b23b0e2ed9c2a2f0089a603ce30d7"
URL_HMA2="https://github.com/frknkrc44/HMA-OSS/releases/download/oss-164/HMA-OSS-ZYGISK-oss-164-release.zip"
SUM_HMA2="4bf157db64f0daa59137436fef8eafeb3180d0fd545ca2e1196b47aa8abef9fa"
URL_RP="https://github.com/uragiristereo/Reverse_Pixelify/releases/download/v1.0/Reverse_Pixelify_v1.0.apk"
SUM_RP="d7c69f958bfdec13f8d3ded5cf34705cf3743645aad713813f463aefab9d971a"
URL_KW="https://github.com/MeowDump/KsuWebUIStandalone/releases/download/v2/v2-Meow-KsuWebUI.apk"
SUM_KW="f48a940c951e669a0b8c577a54e7cd1d6159d4c7a0107d6511d18aa3fadaac91"
URL_MA="https://github.com/MeowDump/MeowAssistant/releases/download/v1/v1-MeowTile.apk"
SUM_MA="b2aa89e09d1177ecdfbffe9d0925fd491135228df450e65f5d599a1836fc764a"
PIPE="$RECORD/integrity_downloader.pipe"
OUT="/storage/emulated/0/Download/IntegrityModules"
WIDTH=55
BRAND_PROP=$(getprop ro.product.system.brand)

mkdir -p "$BOX" "$LOGDIR"
ensure_exec_permissions
recommended_settings
ensure_blacklist_entries

AUTOPIF_OK=0
MIGRATE_OK=0
INPUT_PROP=""

if [ -f $BOX/download ]; then

    rm -f "$LOGZ" "$PIPE"
    mkdir -p "$OUT"

    if command -v mkfifo >/dev/null 2>&1; then
        mkfifo "$PIPE"
        tee -a "$LOGZ" < "$PIPE" &
        exec 1> "$PIPE" 2>&1
    else
        exec >> "$LOGZ" 2>&1
    fi

    banner
    printf "Module                  Size         Status\n"
    printf "%${WIDTH}s\n" | tr ' ' '-'

    download "$URL_ZN" "ZygiskNext.zip" "$SUM_ZN"
    [ -f "$OUT/ZygiskNext.zip" ] &&
        print_row "ZygiskNext" "$(get_size "$OUT/ZygiskNext.zip")" "Verified" ||
        print_row "ZygiskNext" "-" "Failed"

    download "$URL_TS" "TrickyStore.zip" "$SUM_TS"
    [ -f "$OUT/TrickyStore.zip" ] &&
        print_row "TrickyStore" "$(get_size "$OUT/TrickyStore.zip")" "Verified" ||
        print_row "TrickyStore" "-" "Failed"

    download "$URL_KA" "KeyAttestation.apk" "$SUM_KA"
    [ -f "$OUT/KeyAttestation.apk" ] &&
        print_row "KeyAttestation" "$(get_size "$OUT/KeyAttestation.apk")" "Verified" ||
        print_row "KeyAttestation" "-" "Failed"

    download "$URL_UL" "UpdateLocker.apk" "$SUM_UL"
    [ -f "$OUT/UpdateLocker.apk" ] &&
        print_row "UpdateLocker" "$(get_size "$OUT/UpdateLocker.apk")" "Verified" ||
        print_row "UpdateLocker" "-" "Failed"

    download "$URL_HMA" "HMA_Config.json" "$SUM_HMA"
    [ -f "$OUT/HMA_Config.json" ] &&
        print_row "HMA_Config" "$(get_size "$OUT/HMA_Config.json")" "Verified" ||
        print_row "HMA_Config" "-" "Failed"

    download "$URL_HMA2" "HMA_zygisk.zip" "$SUM_HMA2"
    [ -f "$OUT/HMA_zygisk.zip" ] &&
        print_row "HideMyApplist" "$(get_size "$OUT/HMA_zygisk.zip")" "Verified" ||
        print_row "HideMyApplist" "-" "Failed"

    download "$URL_RP" "Disable_ROM_spoofing_lsposed.apk" "$SUM_RP"
    [ -f "$OUT/Disable_ROM_spoofing_lsposed.apk" ] &&
        print_row "Reverse Pixelify" "$(get_size "$OUT/Disable_ROM_spoofing_lsposed.apk")" "Verified" ||
        print_row "Reverse Pixelify" "-" "Failed"
        
    download "$URL_KW" "WebUI.apk" "$SUM_KW"
    [ -f "$OUT/WebUI.apk" ] &&
        print_row "KSU WebUI" "$(get_size "$OUT/WebUI.apk")" "Verified" ||
        print_row "KSU WebUI" "-" "Failed"
        
    download "$URL_CP" "Downgrade_Playstore.apk" "$SUM_CP"
    [ -f "$OUT/Downgrade_Playstore.apk" ] &&
        print_row "Core Patch" "$(get_size "$OUT/Downgrade_Playstore.apk")" "Verified" ||
        print_row "Core Patch" "-" "Failed"
        
    download "$URL_TH" "Installation_Spoofer.apk" "$SUM_TH"
    [ -f "$OUT/Installation_Spoofer.apk" ] &&
        print_row "Thor Installer" "$(get_size "$OUT/Installation_Spoofer.apk")" "Verified" ||
        print_row "Thor Installer" "-" "Failed"
        
    download "$URL_MA" "Meow_QS_Tile.apk" "$SUM_MA"
    [ -f "$OUT/Meow_QS_Tile.apk" ] &&
        print_row "Meow QS Tile" "$(get_size "$OUT/Meow_QS_Tile.apk")" "Verified" ||
        print_row "Meow QS Tile" "-" "Failed"
        
#    download "$URL_AF" "Android_Faker.apk" "$SUM_AF"
#    [ -f "$OUT/Android_Faker.apk" ] &&
#        print_row "Android Faker" "$(get_size "$OUT/Android_Faker.apk")" "Verified" ||
#        print_row "Android Faker" "-" "Failed"

    printf "%${WIDTH}s\n" | tr ' ' '='
    center "DONE"
    printf "%${WIDTH}s\n" | tr ' ' '='

    rm -rf "$BOX/download"
    echo 
    echo "Saved to $OUT"
    handle_delay
    exit 0
fi

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

if [ -f "$BOX/override" ]; then
  sh "$SCRIPT_DIR/override_lineage.sh"
  rm -f "$BOX/override"
  handle_delay
  exit 0
fi

if [ -f "$BOX/hma" ]; then
  sh "$SCRIPT_DIR/hma.sh"
  echo " D O N E 👍"
  rm -f "$BOX/hma"
  handle_delay
  exit 0
fi

[ -f $BOX/lsposed ] && { 
  echo "[*] Starting cleanup..."; 
  if getprop | grep -q "^\[dalvik.vm.dex2oat-flags\]"; then 
    echo "[*] Removing dalvik.vm.dex2oat-flags..."; 
    resetprop -p dalvik.vm.dex2oat-flags && echo "[✓] Property removed." || echo "[!] Failed to remove property."; 
  fi; 
  rm -f $BOX/lsposed && echo "[✓] Cleanup complete."; 
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
    elif [ -d "$path" ]; then
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

# Description content update
{
  for p in /data/adb/modules/busybox-ndk/system/*/busybox \
           /data/adb/ksu/bin/busybox \
           /data/adb/ap/bin/busybox \
           /data/adb/magisk/busybox \
           /system/bin/busybox \
           /system/xbin/busybox; do
    [ -x "$p" ] && bb=$p && break
  done
  [ -z "$bb" ] && return 0

  C=$($bb wget -qO- "$URL" 2>/dev/null)
  if [ -n "$C" ]; then
    [ ! -f "$BAK" ] && $bb cp "$PROP" "$BAK"
    $bb sed -i '/^description=/d' "$PROP"
    echo "description=$C" >> "$PROP"
  else
    [ -f "$BAK" ] && $bb cp "$BAK" "$PROP"
  fi
} || true

# Show header
print_header
reset_tricky_store

sh "$UPDATE" || { sleep 10; exit 1; }
echo " "

if [ -f "$BOX/keymint" ]; then
    "$SCRIPT_DIR/keymint.sh"
fi

# RUN STEPS
# Ensure log file exists
mkdir -p "$(dirname "$CPP")" 2>/dev/null || true
touch "$CPP" 2>/dev/null || true

# Mode
ARGDESC=""
ARGS=""

[ -f "$BOX/use_qpr2" ]       && ARGS="$ARGS -q" && ARGDESC="$ARGDESC QPR2 "
[ -f "$BOX/use_advanced" ]   && ARGS="$ARGS -a" && ARGDESC="$ARGDESC ADVANCED "
[ -f "$BOX/use_strong" ]     && ARGS="$ARGS -s" && ARGDESC="$ARGDESC STRONG "
[ -f "$BOX/use_match" ]      && ARGS="$ARGS -m" && ARGDESC="$ARGDESC MATCH "
[ -f "$BOX/skip_json" ]      && ARGS="$ARGS -n" && ARGDESC="$ARGDESC SKIP_JSON "
[ -f "$BOX/skip_patch" ]     && ARGS="$ARGS -x" && ARGDESC="$ARGDESC SKIP_PATCH " && SKIP_PATCH=1
[ -f "$BOX/skip_keybox" ]    && ARGS="$ARGS -k" && ARGDESC="$ARGDESC SKIP_KEYBOX " && SKIP_KEYBOX=1
[ -f "$BOX/verbose_mode" ]   && ARGS="$ARGS -v" && ARGDESC="$ARGDESC VERBOSE "
[ -f "$BOX/force_spoof_off" ]&& ARGS="$ARGS -S" && ARGDESC="$ARGDESC NO_SPOOF "

for i in {1..9}; do
    [ -f "$BOX/top_$i" ]   && ARGS="$ARGS -t $i" && ARGDESC="$ARGDESC top=$i" && break
done

for i in {1..9}; do
    [ -f "$BOX/depth_$i" ] && ARGS="$ARGS -d $i" && ARGDESC="$ARGDESC depth=$i" && break
done

[ -n "$ARGDESC" ] && log_step "MODE" "$ARGDESC"

# Keybox Handling
for f in keybox keybox2; do
    FLAG="$BOX/$f"
    SRC="$TARGET_DIR/$f.xml"

    [ "$f" = "keybox2" ] && DEST="/sdcard/aosp.xml" || DEST="/sdcard/$f.xml"

    su -c "[ -e \"$FLAG\" ] && [ -r \"$SRC\" ] && cat \"$SRC\" > \"$DEST\" && sync" >/dev/null 2>&1
done

# Spoofing
if [ -f "$FLAG" ] && [ -f "$MODPATH/osm0sis.sh" ]; then
    sh "$MODPATH/osm0sis.sh" && log_step "UPDATED" "Advanced Fingerprint" || log_step "FAILED" "osm0sis.sh"
else
    FP_SCRIPT="$MODPATH/osm0sis.sh"
    [ ! -f "$FP_SCRIPT" ] && FP_SCRIPT="$MODPATH/osm0sis.sh"
    if [ -n "$FP_SCRIPT" ]; then
        echo " "
        sh "$FP_SCRIPT" && log_step "UPDATED" "Pixel Canary Imprint" || log_step "FAILED" "Fingerprint update"
    else
        echo " "
        log_step "WARNING" "PLEASE RE-FLASH THE MODULE"
    fi
fi

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
            [[ "$line" != *=* ]] && continue
            key="${line%%=*}"
            val="${line#*=}"
            key="${key#*.}"
            key="${key#*}"
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


# Blacklist
mkdir -p "$TARGET_DIR" 2>/dev/null
TARGET="$TARGET_DIR/target.txt"
BACKUP="$TARGET.bak"
TMP="${TARGET}.new.$$"
success=0
made_backup=0
orig_selinux="$(getenforce 2>/dev/null || echo Permissive)"

if [ ! -f "$SKIP_FILE" ] && [ "$orig_selinux" = "Enforcing" ]; then
    setenforce 0
fi

[ -f "$TARGET" ] && mv -f "$TARGET" "$BACKUP" && made_backup=1 && log_step "PERFORM" "Targets Backup"

teeBroken="false"
TEE_STATUS="$TARGET_DIR/tee_status"
[ -f "$TEE_STATUS" ] && [ "$(grep -E '^teeBroken=' "$TEE_STATUS" | cut -d '=' -f2)" = "true" ] && teeBroken="true"

for pkg in com.android.vending com.google.android.gms com.google.android.gsf io.github.qwq233.keyattestation com.google.android.apps.walletnfcrel com.google.android.apps.messaging; do
    echo "$pkg" >> "$TMP"
done

cmd package list packages -3 2>/dev/null | cut -d ":" -f2 | while read -r pkg; do
    [ -z "$pkg" ] && continue
    grep -Fxq "$pkg" "$TMP" || echo "$pkg" >> "$TMP"
done

sed -i 's/^[[:space:]]*//;s/[[:space:]]*$//' "$TMP"
sort -u "$TMP" -o "$TMP"

BLACKLIST="$BOX/blacklist.txt"
if [ -s "$BLACKLIST" ]; then
    sed -i 's/^[[:space:]]*//;s/[[:space:]]*$//' "$BLACKLIST"
    grep -Fvxf "$BLACKLIST" "$TMP" > "${TMP}.filtered" || true
    mv -f "${TMP}.filtered" "$TMP"
    log_step "MIGRATE" "Blacklisted Targets"
else
    log_step "SKIPPED" "Blacklist not configured"
fi

[ "$teeBroken" = "true" ] && sed -i 's/$/!/' "$TMP" && log_step "SUPPORT" "TEE Broken Device"

mv -f "$TMP" "$TARGET" && success=1 && log_step "UPDATED" "Target Packages config"

if [ ! -f "$SKIP_FILE" ] && [ "$orig_selinux" = "Enforcing" ]; then
    setenforce 1
fi

# OMK Injector TOML Support
OMK_DIR="/data/misc/keystore/omk"
INJECTOR_TOML="$OMK_DIR/injector.toml"
TMP_TOML="${INJECTOR_TOML}.tmp.$$"
SCOOP_TMP="/data/local/tmp/.omk_scoop_$$"

if [ -d "$OMK_DIR" ]; then
    # Build scoop array from target.txt
    {
        echo "scoop = ["
        while IFS= read -r pkg || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            pkg_clean="${pkg%!}"
            echo "  \"$pkg_clean\","
        done < "$TARGET"
        echo "]"
    } > "$SCOOP_TMP" 2>/dev/null

    if [ -f "$INJECTOR_TOML" ]; then
        # Extract everything before scoop section
        sed -n '1,/^scoop[[:space:]]*=[[:space:]]*\[/p' "$INJECTOR_TOML" | sed '$d' > "$TMP_TOML" 2>/dev/null
        
        # Append our new scoop section
        cat "$SCOOP_TMP" >> "$TMP_TOML" 2>/dev/null
        
        # Extract everything after scoop section
        sed -n '/^[[:space:]]*\]/,$p' "$INJECTOR_TOML" | sed '1d' >> "$TMP_TOML" 2>/dev/null
        
        mv -f "$TMP_TOML" "$INJECTOR_TOML" 2>/dev/null
        rm -f "$SCOOP_TMP" 2>/dev/null
        log_step "SCOOPED" "Targets in injector.toml"
    else
        # No existing file, create fresh
        {
            echo '# Only packages listed in `scoop` are intercepted.'
            echo ''
            cat "$SCOOP_TMP"
            echo ''
            echo '[main]'
            echo 'enabled = true'
            echo 'log_level = "debug"'
            echo ''
            echo '[filter]'
            echo 'enabled = true'
            echo 'deny_packages = []'
            echo 'block_android_package = true'
            echo 'allow_unknown_package = false'
            echo ''
            echo '# Do not edit if you have no idea about the things below'
            echo '[intercept]'
            echo 'get_security_level = true'
            echo 'get_key_entry = true'
            echo 'update_subcomponent = true'
            echo 'list_entries = true'
            echo 'delete_key = true'
            echo 'grant = true'
            echo 'ungrant = true'
            echo 'get_number_of_entries = true'
            echo 'list_entries_batched = true'
            echo 'get_supplementary_attestation_info = true'
        } > "$INJECTOR_TOML" 2>/dev/null
        rm -f "$SCOOP_TMP" 2>/dev/null
        log_step "CREATED" "Missing injector.toml for OMK"
    fi
fi

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

for proc in com.google.android.gms.unstable com.google.android.gms com.android.vending; do
  kill_process "$proc"
done

log_step "RESTART" "Google Service Processes"

sh "$SCRIPT_DIR/cleanup.sh" >/dev/null 2>&1; 

# Restore per-App-Spoofing value
#if [ -f "$P" ]; then
#    if [ -f "$SPOOF_APPS" ]; then
#        sed -i 's/^spoofApps=.*/spoofApps=1/' "$P"
#    else
#        sed -i 's/^spoofApps=.*/spoofApps=0/' "$P"
#    fi
#fi

# TSA Farewell || Disable auto target update of outdated module 
if [ -f "/data/adb/modules/tsupport-advance/service.sh" ]; then
    mkdir -p "/sdcard/TSupportConfig"
    touch "/sdcard/TSupportConfig/stop-tspa-auto-target"
fi
echo " "
echo " "
echo "    -- ACTION COMPLETED SUCCESSFULLY --"
randomize_banner
handle_delay
exit 0
