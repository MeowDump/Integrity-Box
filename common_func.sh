RECORD="/data/adb/Box-Brain/Integrity-Box-Logs"
BOX="/data/adb/Box-Brain"
LOGZ="/data/adb/Box-Brain/Integrity-Box-Logs/move.log"
LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/action.log"

# Truncate per-run logs once at startup instead of inside every logger
mkdir -p "$RECORD"
for _f in denylist.log lineage.log patch.log boot.log; do
    : > "$RECORD/$_f"
done
: > "$LOG_FILE"

record() { # record <file> <message>
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $2" >> "$RECORD/$1"
}
say() {    # say <file> <message>
    record "$1" "$2"; echo "$2"
}
log() {    # log <message>
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    /system/bin/log -t PATCH_OVERRIDE "$1"
}

update_module_description() {
  MODPATH="/data/adb/modules/playintegrityfix"
  PROP="$MODPATH/module.prop"
  BAK="$PROP.bak"
  P="$MODPATH/custom.pif.prop"

  # Find BusyBox
  bb=""
  for p in /data/adb/modules/busybox-ndk/system/*/busybox \
           /data/adb/ksu/bin/busybox \
           /data/adb/ap/bin/busybox \
           /data/adb/magisk/busybox \
           /system/bin/busybox \
           /system/xbin/busybox; do
    [ -x "$p" ] && bb="$p" && break
  done
  [ -z "$bb" ] && return 0

  # Read device identity
  MODEL=""
  DEVICE=""
  INIT_SDK=""

  if [ -f "$P" ]; then
    MODEL=$("$bb" sed -n 's/^MODEL=//p' "$P" | "$bb" head -n1)
    DEVICE=$("$bb" sed -n 's/^DEVICE=//p' "$P" | "$bb" head -n1)
    INIT_SDK=$("$bb" sed -n 's/^DEVICE_INITIAL_SDK_INT=//p' "$P" | "$bb" head -n1)
  fi

  [ -z "$MODEL" ] && MODEL="Unknown"
  [ -z "$DEVICE" ] && DEVICE="Unknown"
  [ -z "$INIT_SDK" ] && INIT_SDK="Unknown"

  # Build description
  DESC="current spoofing indentify: $MODEL ($DEVICE) | InitSDK: $INIT_SDK"

  # Backup original properties
  [ ! -f "$BAK" ] && "$bb" cp "$PROP" "$BAK"

  # Update description
  "$bb" sed -i '/^description=/d' "$PROP"
  echo "description=$DESC" >> "$PROP"
}

cleanup_root_logs() {
  BOX="/data/adb/Box-Brain"
  DIR="/sdcard/Download"

  [ -f "$BOX/root" ] || return 0

  rm -f "$BOX/root"

  find "$DIR" -type f \( \
    -name "*_install_log_2026*" -o \
    -name "*_action_log_2026*" \
  \) | while read -r f; do
    echo "$(date '+%F %T') Deleted: $f" | tee -a "$LOG"
    rm -f "$f"
  done

  handle_delay
  exit 0
}

cleanup_ota() {
  BOX="/data/adb/Box-Brain"
  
  [ -e "$BOX/ota" ] || return 0

  rm -f "$MODPATH/system.prop" "$BOX/NoLineageProp"
  rm -rf "$BOX/override" "$BOX/ota"
  touch "$BOX/safemode"

  echo " "
  echo " "
  echo "  D O N E | REBOOT YOUR DEVICE"

  handle_delay
  exit 0
}

cleanup_lsposed() {
  BOX="/data/adb/Box-Brain"
  
  [ -f "$BOX/lsposed" ] || return 0

  echo "[*] Starting cleanup..."

  if getprop | grep -q '^\[dalvik.vm.dex2oat-flags\]'; then
    echo "[*] Removing dalvik.vm.dex2oat-flags..."
    resetprop -p dalvik.vm.dex2oat-flags &&
      echo "[✓] Property removed." ||
      echo "[!] Failed to remove property."
  fi

  rm -f "$BOX/lsposed" && echo "[✓] Cleanup complete."

  echo "[*] Done. Exiting."
  exit 0
}

cleanup_gapps_logs() {
  BOX="/data/adb/Box-Brain"
  LOGFILE="$BOX/Integrity-Box-Logs/gapps.log"

  [ -f "$BOX/gapps" ] || return 0

  rm -f "$BOX/gapps"

  {
    echo "===================================="
    echo "Starting Log Cleanup"
    echo "===================================="
    echo ""

    TARGETS="
/sdcard/Android/litegapps/litegapps_controller.log
/tmp/NikGapps/logfiles
/tmp/NikGapps/addonscripts
/tmp/NikGapps/logfiles/package_log
/tmp/NikGapps
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
        echo "Found: $path"
        echo "$files"

        echo "$files" | while IFS= read -r f; do
          [ -n "$f" ] || continue
          echo "Deleting: $f"
          rm -rf "$f" 2>&1
        done
      elif [ -d "$path" ]; then
        echo "Deleting directory: $path"
        rm -rf "$path" 2>&1
      fi
    done

    echo ""
    echo "Cleanup complete."
    echo "===================================="
  } | tee -a "$LOGFILE"

  handle_delay
  exit 0
}

download_keybox() {
  MODPATH="${0%/*}"
  BOX="/data/adb/Box-Brain"

  SCRIPT_DIR="$MODPATH/webroot/common_scripts"
  UNOFFICIAL="$BOX/disable-default-source"
  PRIMARY="$SCRIPT_DIR/key.sh"
  SECONDARY="$SCRIPT_DIR/spectre.sh"

  if [ -f "$UNOFFICIAL" ]; then
    sh "$SECONDARY" || { sleep 10; exit 1; }
  else
    sh "$PRIMARY" || { sleep 10; exit 1; }
  fi

  echo " "
}

update_targets() {
  local BOX="/data/adb/Box-Brain"
  local SKIP_FILE="$BOX/skip"
  local TARGET_DIR="/data/adb/tricky_store"
  local TARGET="$TARGET_DIR/target.txt"
  local BACKUP="$TARGET.bak"
  local TMP="$TARGET.new.$$"
  local BLACKLIST="$BOX/blacklist.txt"
  local TEE_STATUS="$TARGET_DIR/tee_status"
  local orig_selinux
  local teeBroken="false"
  local pkg
  local success=0
  local made_backup=0

  orig_selinux="$(getenforce 2>/dev/null)" || orig_selinux="Permissive"

  # Restore SELinux state and clean temporary files on exit 
  _restore_target_update_state() {
    [ -n "$TMP" ] && rm -f "$TMP" "${TMP}.filtered"

    if [ "$orig_selinux" = "Enforcing" ] &&
       [ ! -f "$SKIP_FILE" ]; then
      setenforce 1 2>/dev/null
    fi
  }

  # Ensure the target directory exists.
  if ! mkdir -p "$TARGET_DIR" 2>/dev/null; then
    echo " ✖ Failed to create Tricky Store directory."
    _restore_target_update_state
    unset -f _restore_target_update_state
    return 1
  fi

  # Temporarily disable SELinux enforcement
  if [ ! -f "$SKIP_FILE" ] && [ "$orig_selinux" = "Enforcing" ]; then
    if ! setenforce 0 2>/dev/null; then
      echo " ✖ Failed to change SELinux mode."
      _restore_target_update_state
      unset -f _restore_target_update_state
      return 1
    fi
  fi

  # Back up existing target configuration.
  if [ -f "$TARGET" ]; then
    if mv -f "$TARGET" "$BACKUP"; then
      made_backup=1
      echo " ✦ Backing up existing targets"
    else
      echo " ✖ Failed to back up existing targets."
      _restore_target_update_state
      unset -f _restore_target_update_state
      return 1
    fi
  fi

  # Read TEE status.
  if [ -f "$TEE_STATUS" ] &&
     grep -q '^teeBroken=true$' "$TEE_STATUS"; then
    teeBroken="true"
  fi

  # Create the default target list.
  for pkg in \
    com.android.vending \
    com.google.android.gms \
    com.google.android.gsf \
    io.github.qwq233.keyattestation \
    io.github.vvb2060.keyattestation \
    com.google.android.apps.walletnfcrel \
    com.google.android.apps.messaging; do
    echo "$pkg" >> "$TMP"
  done

  # Add third-party packages.
  cmd package list packages -3 2>/dev/null |
    cut -d ':' -f2 |
    while IFS= read -r pkg; do
      [ -z "$pkg" ] && continue
      grep -Fxq "$pkg" "$TMP" || echo "$pkg" >> "$TMP"
    done

  # Normalize and deduplicate targets.
  if ! sed -i 's/^[[:space:]]*//;s/[[:space:]]*$//' "$TMP" ||
     ! sort -u "$TMP" -o "$TMP"; then
    echo " ✖ Failed to prepare target list."
    [ "$made_backup" -eq 1 ] && mv -f "$BACKUP" "$TARGET"
    _restore_target_update_state
    unset -f _restore_target_update_state
    return 1
  fi

  # Apply blacklist.
  if [ -s "$BLACKLIST" ]; then
    if ! sed -i 's/^[[:space:]]*//;s/[[:space:]]*$//' "$BLACKLIST" ||
       ! grep -Fvxf "$BLACKLIST" "$TMP" > "${TMP}.filtered"; then
      echo " ✖ Failed to apply blacklist."
      [ "$made_backup" -eq 1 ] && mv -f "$BACKUP" "$TARGET"
      _restore_target_update_state
      unset -f _restore_target_update_state
      return 1
    fi

    mv -f "${TMP}.filtered" "$TMP" || {
      echo " ✖ Failed to save filtered target list."
      [ "$made_backup" -eq 1 ] && mv -f "$BACKUP" "$TARGET"
      _restore_target_update_state
      unset -f _restore_target_update_state
      return 1
    }

    echo " ✦ Filtering blacklisted packages"
  else
    echo " ✦ No blacklist configured. Skipping.."
  fi

  # Mark targets for broken TEE devices.
  if [ "$teeBroken" = "true" ]; then
    if ! sed -i 's/$/!/' "$TMP"; then
      echo " ✖ Failed to apply TEE markers."
      [ "$made_backup" -eq 1 ] && mv -f "$BACKUP" "$TARGET"
      _restore_target_update_state
      unset -f _restore_target_update_state
      return 1
    fi
    echo " ✦ Extended support for broken TEE devices"
  fi

  # Install the new target list.
  if mv -f "$TMP" "$TARGET"; then
    success=1
    echo " ✦ Target verification succeed"
    echo " "
  else
    echo " ✖ Failed to update target packages."
    echo " "
    [ "$made_backup" -eq 1 ] && mv -f "$BACKUP" "$TARGET"
  fi

  _restore_target_update_state
  unset -f _restore_target_update_state

  [ "$success" -eq 1 ]
}

handle_security_patch() {
  local BOX="/data/adb/Box-Brain"
  local LOGDIR="$BOX/Integrity-Box-Logs"
  local PATCH_LOG="$LOGDIR/patch.log"
  local PATCH_FLAG="$BOX/patch"
  local SKIP_FILE="$BOX/skip"
  local PATCH_DATE="2026-10-05"
  local PROP_MAIN="ro.build.version.security_patch"
  local FILE_PATH="/data/adb/tricky_store/security_patch.txt"
  local BRAND_PROP
  local CURRENT_PROP

  BRAND_PROP="$(getprop ro.product.system.brand)"

  if ! mkdir -p "${FILE_PATH%/*}" 2>/dev/null; then
    echo " ✖ Failed to create Tricky Store directory."
    return 1
  fi

  # Write security_patch.txt based on patch flag
  if [ -f "$PATCH_FLAG" ]; then
    if ! echo "system=prop" > "$FILE_PATH" 2>>"$PATCH_LOG"; then
      echo " ✖ Failed to write security patch configuration."
      return 1
    fi

    echo " ✦ Updated Patch to Stock"
  else
    if ! echo "all=$PATCH_DATE" > "$FILE_PATH" 2>>"$PATCH_LOG"; then
      echo " ✖ Failed to write security patch configuration."
      return 1
    fi

    echo " ✦ Spoofed Attestation Patch to $PATCH_DATE"

    CURRENT_PROP="$(getprop "$PROP_MAIN" | tr -d ' \t\r\n')"
    echo "Current $PROP_MAIN: $CURRENT_PROP" >> "$PATCH_LOG"

    # Skip resetprop if skip file exists
    if [ -f "$SKIP_FILE" ]; then
      echo " ✦ Skip patch is ON, skipping resetprop"

    # Skip resetprop only for Oplus devices
    elif [ "$BRAND_PROP" = "oplus" ]; then
      echo " ✦ Skipped patch due to 1+ hardware issues"

    else
      if [ "$CURRENT_PROP" != "$PATCH_DATE" ]; then
        if command -v resetprop >/dev/null 2>&1; then
          if resetprop "$PROP_MAIN" "$PATCH_DATE"; then
            resetprop --compact >/dev/null 2>&1 || true
            echo " ✦ Patched $PROP_MAIN to $PATCH_DATE"
          else
            echo " ✖ Unable to update $PROP_MAIN"
          fi
        else
          echo " ✖ resetprop not found"
        fi
      else
        echo " ✦ Android Patch spoofed to latest Pixel release"
      fi
    fi
  fi

  echo "Patch handling complete" >> "$PATCH_LOG"
  echo "" >> "$PATCH_LOG"
}

# Property Backend Setup
RESETPROP="resetprop -n"
PROP_DELETE="resetprop --delete"
COMPACT_SUPPORTED=false
PROP_WAIT="resetprop -w"
IS_MAGISK=false

setup_resetprop() {
    if [ -f "/data/adb/magisk" ] || [ -f "/data/adb/magisk/magisk" ]; then
        if [ -f /data/adb/magisk/util_functions.sh ]; then
            MAGISK_VER=$(grep MAGISK_VER_CODE /data/adb/magisk/util_functions.sh | cut -d= -f2)
            [ "$MAGISK_VER" -lt 27003 ] 2>/dev/null && RESETPROP="resetprop_hexpatch"
        fi
        resetprop --help 2>&1 | grep -q "compact" && COMPACT_SUPPORTED=true
    else
        for _p in /data/adb/ksu/bin /data/adb/ap/bin; do
            [ -x "$_p/resetprop" ] && { export PATH="$_p:$PATH"; break; }
        done
        COMPACT_SUPPORTED=true
    fi
}
setup_resetprop

# stub for boot-time
if [ "$(getprop sys.boot_completed)" != "1" ]; then
    ui_print() { return; }
fi

run_compact() {
    $COMPACT_SUPPORTED && resetprop -c 2>/dev/null
}

make_exec() {
    chmod 755 "$1"
}

randomize_banner() {
    local prop_file="/data/adb/modules/playintegrityfix/module.prop"
    local base_url="https://raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/Banner"
    local random_num=$((RANDOM % 14 + 1))
    local new_banner="${base_url}/mona${random_num}.png"

    sed -i "s|^banner=.*|banner=${new_banner}|" "$prop_file"
}

detect_downloader() {
  if command -v curl >/dev/null 2>&1; then
    DOWNLOADER=$(command -v curl); DL_MODE="curl"; return
  fi
  if command -v wget >/dev/null 2>&1; then
    DOWNLOADER=$(command -v wget); DL_MODE="wget"; return
  fi
  if [ -x /data/adb/magisk/busybox ]; then
    DOWNLOADER="/data/adb/magisk/busybox"; DL_MODE="busybox"; return
  fi
  if [ -x /data/adb/ksu/bin/busybox ]; then
    DOWNLOADER="/data/adb/ksu/bin/busybox"; DL_MODE="busybox"; return
  fi
  if toybox wget --help >/dev/null 2>&1; then
    DOWNLOADER="toybox"; DL_MODE="toybox"; return
  fi
  DOWNLOADER=""; DL_MODE=""
}

# Connectivity check 
wait_for_network() { 
  local max_wait="${1:-30}" step=2 waited=0 host

  while [ "$waited" -lt "$max_wait" ]; do
    for host in 1.1.1.1 8.8.8.8 9.9.9.9 223.5.5.5 114.114.114.114; do
      ping -c1 -W2 "$host" >/dev/null 2>&1 && return 0
    done
    sleep "$step"
    waited=$((waited+step))
  done
  return 1
}

safe_mv() {
  src="$1"; dst="$2"
  mkdir -p "$(dirname "$dst")"
  mv "$src" "$dst" 2>>"$LOGZ" || cp -f "$src" "$dst" 2>>"$LOGZ" && rm -f "$src"
  return $?
}

denylog() { say denylist.log "$1"; }
lineage() { say lineage.log "$*"; }
chup()    { record pixel.log "$1"; }
boot_log(){ say boot.log "$1"; }
log_patch(){ record patch.log "$*"; }
writelog(){ log "$1"; }

# Configure DenyList
add_if_missing() {
    pkg="$1"; proc="$2"
    entry="$pkg|${proc:-$pkg}"
    if ! magisk --denylist ls | grep -q "$entry"; then
        magisk --denylist add "$pkg" $proc
        denylog "[AutoDeny] Added $entry"
    fi
}

setval() { grep -q "^$2=" "$1" && sed -i "s/^$2=.*/$2=$3/" "$1" && log "$2 > $3" || log "$2 not found"; }

add_pkg() {
  pkg="$1"
  if [ "$teeBroken" = "true" ]; then
    echo "${pkg}!" >> "$TMP"
  else
    echo "$pkg" >> "$TMP"
  fi
}

print_header() {
  echo "
  ___     _                _ _
 |_ _|_ _| |_ ___ __ _ _ _(_) |_ _  _
  | || ' \  _/ -_) _  | '_| |  _| || |
 |___|_||_\__\___\__, |_| |_|\__|\_, |
 | _ ) _____ __  |___/           |__/
 | _ \/ _ \ \ /
 |___/\___/_\_\


"
}

log_step() {
  local status="$1" task="$2" timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf -- " ✦ %-10s %s\n" "$status" "$task"
  printf "[%s] %-10s %s\n" "$timestamp" "$status" "$task" >> "$LOG_FILE"
}

handle_delay() {
  [ -f "/data/adb/Box-Brain/wait" ] || return 0

  echo
  echo " Closing in 10 seconds..."
  sleep 10
}

kill_process() {
  PID=$(pidof "$1")
  [ -n "$PID" ] && kill -9 $PID 2>/dev/null
}

restart_google_services() {
  for proc in com.google.android.gms.unstable com.google.android.gms com.android.vending; do
    kill_process "$proc"
  done

  echo " ✦ Killed Google Service Processes"
}

hide_recovery_folders() {
    [ -f /data/adb/Box-Brain/twrp ] || return

    SRC="/sdcard"
    DEST="/data/adb/recovery_backups"
    mkdir -p "$DEST"

    FOLDERS="TWRP OrangeFox FOX PBRP PitchBlack Recovery"

    random_str() { head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12; }

    for F in $FOLDERS; do
        DIR="$SRC/$F"
        [ -d "$DIR" ] || continue

        if [ -f "$DIR/.twrps" ]; then
            rm -f "$DIR/.twrps" 2>/dev/null
            if [ -f "$DIR/.twrps" ]; then
                NEWF=".$(random_str)_$(date +%s)"
                mv "$DIR" "$SRC/$NEWF" 2>/dev/null
                DIR="$SRC/$NEWF"
                rm -f "$DIR/.twrps" 2>/dev/null
            fi
        fi

        SUB=$(find "$DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" 2>/dev/null | wc -l)

        if [ "$SUB" -gt 0 ]; then
            mv "$DIR" "$DEST/$(random_str)" 2>/dev/null
        else
            rm -rf "$DIR" 2>/dev/null
        fi
    done
}

run_temp_exec() {
    local script="$1" orig_mode

    if [ ! -r "$script" ]; then
        echo "Script $script not readable ❌"
        return 1
    fi

    orig_mode=$(stat -c "%a" "$script")
    echo "Original permission: $orig_mode"

    chmod +x "$script"
    echo "Temporary +x granted, executing..."
    "$script"

    echo "Execution finished, reverting permission"
    chmod "$orig_mode" "$script"
}

remove_if_exists() {
    if [ -e "$1" ]; then
        rm -rf "$1"
        record action.log "Deleted: $1"
    fi
}

safemode_flags() {
    local dir="/data/adb/Box-Brain"
    [ -f "$dir/safemode" ] || return 0

    for f in spoof-los-boot nuke-los-boot spoof-custom-rom-boot NoLineageProp nodebug build tag encrypt hidehook; do
        remove_if_exists "$dir/$f"
    done
}

# BusyBox detector
P() {
  for Q in /data/adb/modules/busybox-ndk/system/*/busybox \
           /data/adb/ksu/bin/busybox \
           /data/adb/ap/bin/busybox \
           /data/adb/magisk/busybox; do
    [ -x "$Q" ] && echo "$Q" && return
  done
}

# Base64 decoder
Z() {
  b=0; s=0
  while IFS= read -r -n1 c; do
    case "$c" in
      [A-Z]) v=$(printf '%d' "'$c"); v=$((v - 65));;
      [a-z]) v=$(printf '%d' "'$c"); v=$((v - 71));;
      [0-9]) v=$(printf '%d' "'$c"); v=$((v + 4));;
      '+') v=62;;
      '/') v=63;;
      '=') break;;
      *) continue;;
    esac
    b=$((b << 6 | v)); s=$((s + 6))
    if [ "$s" -ge 8 ]; then
      s=$((s - 8)); o=$(((b >> s) & 0xFF))
      printf \\$(printf '%03o' "$o")
    fi
  done
}

check_and_set_prop() {
    local PROP="$1"
    local VALUE="$2"
    local CURRENT

    if [ -f /data/adb/Box-Brain/force-reset ]; then
        if $RESETPROP "$PROP" "$VALUE" >/dev/null 2>&1; then
            record pixel.log "Forced $PROP > $VALUE"
            return 0
        fi

        record pixel.log "Failed to force $PROP"
        return 1
    fi

    if ! getprop | grep -Fq "[$PROP]:"; then
        record pixel.log "Skipped $PROP (not found)"
        return 0
    fi

    CURRENT=$(getprop "$PROP")

    if [ "$CURRENT" = "$VALUE" ]; then
        record pixel.log "Unchanged $PROP = $CURRENT"
        return 0
    fi

    if $RESETPROP "$PROP" "$VALUE" >/dev/null 2>&1; then
        record pixel.log "Set $PROP > $VALUE (was: $CURRENT)"
        return 0
    fi

    record pixel.log "Failed to set $PROP"
    return 1
}

resetprop_if_match() {
    local PROP="$1"
    local MATCH="$2"
    local VALUE="$3"
    local CURRENT

    CURRENT=$(resetprop "$PROP")

    case "$CURRENT" in
        *"$MATCH"*)
            if $RESETPROP "$PROP" "$VALUE" >/dev/null 2>&1; then
                record pixel.log "Matched $PROP: $CURRENT -> $VALUE"
                return 0
            fi

            record pixel.log "Failed modifying $PROP"
            return 1
            ;;
    esac

    return 2
}

delprop_if_exist() {
    local PROP="$1"

    if resetprop "$PROP" >/dev/null 2>&1; then
        if $PROP_DELETE "$PROP" >/dev/null 2>&1; then
            record pixel.log "Deleted $PROP"
            return 0
        fi

        record pixel.log "Failed deleting $PROP"
        return 1
    fi

    return 2
}

persistprop() {
    local NAME="$1"
    local NEWVALUE="$2"
    local CURVALUE

    CURVALUE=$(resetprop "$NAME")

    if ! grep -qF "\"$NAME\"" "$MODPATH/uninstall.sh" 2>/dev/null; then
        if [ -n "$CURVALUE" ]; then
            [ "$NEWVALUE" = "$CURVALUE" ] || \
                echo "resetprop -n -p \"$NAME\" \"$CURVALUE\"" >> "$MODPATH/uninstall.sh"
        else
            echo "resetprop -p --delete \"$NAME\"" >> "$MODPATH/uninstall.sh"
        fi
    fi

    resetprop -n -p "$NAME" "$NEWVALUE"
}

# Hexpatch Fallback
resetprop_hexpatch() {
    case "$1" in
        -f|--force) local FORCE=1; shift;;
    esac

    local NAME="$1"
    local NEWVALUE="$2"
    local CURVALUE
    CURVALUE=$(resetprop "$NAME")

    [ ! "$NEWVALUE" ] || [ ! "$CURVALUE" ] && return 1
    [ "$NEWVALUE" = "$CURVALUE" ] && [ ! "$FORCE" ] && return 2

    local NEWLEN=${#NEWVALUE}
    local PROPFILE
    if [ -f /dev/__properties__ ]; then
        PROPFILE=/dev/__properties__
    else
        PROPFILE="/dev/__properties__/$(resetprop -Z "$NAME")"
    fi
    [ ! -f "$PROPFILE" ] && return 3
    local NAMEOFFSET
    NAMEOFFSET=$(strings -t d "$PROPFILE" | grep "$NAME" | head -1 | cut -d\  -f1)

    local NEWHEX
    NEWHEX="$(printf '%02x' "$NEWLEN")$(printf "$NEWVALUE" | od -A n -t x1 -v | tr -d ' \n')$(printf "%$((92-NEWLEN))s" | sed 's/ /00/g')"
    echo -ne "\x00\x00" | dd obs=1 count=2 seek=$((NAMEOFFSET-96)) conv=notrunc of="$PROPFILE" 2>/dev/null
    echo -ne "$(printf "$NEWHEX" | sed -e 's/.\{2\}/&\\x/g' -e 's/^/\\x/' -e 's/\\x$//')" | dd obs=1 count=93 seek=$((NAMEOFFSET-93)) conv=notrunc of="$PROPFILE" 2>/dev/null
}

wait_for_boot() {
    say boot.log "Waiting for Android to finish booting..."
    local count=0
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
        count=$((count + 1))
        [ "$count" -ge 300 ] && { say boot.log "Boot wait timeout"; return 1; }
    done
    sleep 3
    say boot.log "Initialising, please wait."
    say boot.log " "
}

reset_tricky_store() {
    if [ -d "/data/adb/tricky_store/key_db" ]; then
        rm -rf "/data/adb/tricky_store/key_db"
        mkdir -p "/data/adb/tricky_store/key_db"
    fi

    if [ -d "/data/adb/tricky_store/persistent_keys" ]; then
        rm -rf "/data/adb/tricky_store/persistent_keys"
        mkdir -p "/data/adb/tricky_store/persistent_keys"
    fi
}
