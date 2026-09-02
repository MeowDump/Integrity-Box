# shellcheck shell=sh
# Sourced library: no shebang on purpose (loaded via `. common_func.sh`)

RECORD="/data/adb/Box-Brain/Integrity-Box-Logs"
BOX="/data/adb/Box-Brain"
LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/action.log"

# Default logger (scripts may override with their own log())
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Locate the resetprop binary (scripts without common_func's backend setup use this)
find_resetprop() {
    for p in $(which resetprop 2>/dev/null) \
             /data/adb/ksu/bin/resetprop \
             /data/adb/ap/bin/resetprop \
             /data/adb/magisk/resetprop \
             /sbin/resetprop \
             /system/xbin/resetprop \
             /system/bin/resetprop; do
        if [ -f "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# Restart Google services (shared by action.sh and gms.sh)
restart_gms() {
    for proc in com.google.android.gms.unstable com.google.android.gms com.android.vending; do
        kill_process "$proc"
    done
}

# Property Backend Setup (consumed by scripts that source this file)
RESETPROP="resetprop"
PROP_DELETE="resetprop --delete"
# shellcheck disable=SC2034  # used by service.sh after sourcing
PROP_WAIT="resetprop -w"
COMPACT_SUPPORTED=false

# Root Solution Detection & Binary Setup
detect_root_solution() {
    if [ -f "/data/adb/ksud" ] || [ -d "/data/adb/ksu" ]; then
        # KernelSU
        if [ -f "/data/adb/ksu/bin/resetprop" ]; then
            export PATH="/data/adb/ksu/bin:$PATH"
            echo "kernelsu"
        else
            echo "kernelsu_legacy"
        fi
    elif [ -f "/data/adb/apd" ] || [ -d "/data/adb/ap" ]; then
        # APatch
        if [ -f "/data/adb/ap/bin/resetprop" ]; then
            export PATH="/data/adb/ap/bin:$PATH"
            echo "apatch"
        else
            echo "apatch_legacy"
        fi
    elif [ -f "/data/adb/magisk" ] || [ -f "/data/adb/magisk/magisk" ]; then
        # Magisk
        echo "magisk"
    else
        echo "unknown"
    fi
}

ROOT_SOL=$(detect_root_solution)

# resetprop Feature Detection
check_compact_support() {
    resetprop --help 2>&1 | grep -q "compact"
}

setup_resetprop() {
    case "$ROOT_SOL" in
        magisk)
            # Check Magisk version for hexpatch fallback
            if [ -f /data/adb/magisk/util_functions.sh ]; then
                MAGISK_VER=$(grep MAGISK_VER_CODE /data/adb/magisk/util_functions.sh | cut -d= -f2)
                [ "$MAGISK_VER" -lt 27003 ] 2>/dev/null && RESETPROP="resetprop_hexpatch" || RESETPROP="resetprop -n"
            else
                RESETPROP="resetprop -n"
            fi
            check_compact_support && COMPACT_SUPPORTED=true
            ;;
        kernelsu|apatch)
            # Modern KSU/APatch with resetprop support
            RESETPROP="resetprop -n"
            PROP_DELETE="resetprop --delete"
            PROP_WAIT="resetprop -w"
            check_compact_support && COMPACT_SUPPORTED=true
            ;;
        kernelsu_legacy|apatch_legacy|unknown)
            # Legacy or unknown - limited setprop only
            RESETPROP="setprop"
            PROP_DELETE="setprop"  # Can't actually delete
            PROP_WAIT="sleep"
            ;;
    esac
}


set_perm_if_needed() {
    _file="$1"
    _perm="$2"
    
    # Skip if missing
    [ -e "$_file" ] || return 0
    
    # For 755: just check if owner executable bit is set
    [ -x "$_file" ] && return 0
    
    # Only chmod if not executable
    chmod "$_perm" "$_file" 2>/dev/null || true
}

# Compact Function
run_compact() {
    $COMPACT_SUPPORTED && resetprop -c 2>/dev/null
}

recommended_settings() {
    touch "$BOX/migrate_force"
    touch "$BOX/run_migrate"
}

get_size() {
  if [ -f "$1" ]; then du -h "$1" 2>/dev/null | awk '{print $1}'; else echo "-"; fi
}


# determine downloader binary
detect_downloader() {
  # curl
  if command -v curl >/dev/null 2>&1; then
    DOWNLOADER=$(command -v curl)
    DL_MODE="curl"
    return
  fi

  # wget
  if command -v wget >/dev/null 2>&1; then
    DOWNLOADER=$(command -v wget)
    DL_MODE="wget"
    return
  fi

  # Magisk BusyBox
  if [ -x /data/adb/magisk/busybox ]; then
    DOWNLOADER="/data/adb/magisk/busybox"
    DL_MODE="busybox"
    return
  fi

  # KSU BusyBox
  if [ -x /data/adb/ksu/bin/busybox ]; then
    DOWNLOADER="/data/adb/ksu/bin/busybox"
    DL_MODE="busybox"
    return
  fi

  # Built-in toybox wget
  if toybox wget --help >/dev/null 2>&1; then
    DOWNLOADER="toybox"
    DL_MODE="toybox"
    return
  fi

  # nothing available
  DOWNLOADER=""
  DL_MODE=""
}

wait_for_network() {
  max_wait=${1:-30} # seconds
  step=2
  waited=0

  while [ $waited -lt $max_wait ]; do
    if command -v ping >/dev/null 2>&1; then
      ping -c 1 1.1.1.1 >/dev/null 2>&1 && return 0
    fi

    if [ -n "$DOWNLOADER" ]; then
      case "$DL_MODE" in
        curl)
          "$DOWNLOADER" -s --head --connect-timeout 5 https://raw.githubusercontent.com >/dev/null 2>&1 && return 0
          ;;
        wget)
          "$DOWNLOADER" --spider --timeout=5 --tries=1 https://raw.githubusercontent.com >/dev/null 2>&1 && return 0
          ;;
        busybox)
          "$DOWNLOADER" wget --spider --timeout=5 --tries=1 https://raw.githubusercontent.com >/dev/null 2>&1 && return 0
          ;;
      esac
    fi

    sleep $step
    waited=$((waited+step))
  done

  return 1
}

chup() {
echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$RECORD/pixel.log"
}

set_simpleprop() {
    local PROP="$1"
    local VALUE="$2"
    local CURRENT

    CURRENT=$(su -c getprop "$PROP")

    if [ -n "$CURRENT" ]; then
        su -c setprop "$PROP" "$VALUE" >/dev/null 2>&1
        chup "Set $PROP to $VALUE"
    else
        chup "Skipping $PROP, property does not exist"
    fi
}

# Print header
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

# Track results
log_step() {
  local status="$1"
  local task="$2"
  local timestamp
  
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  printf -- " ✦ %-10s %s\n" "$status" "$task"
  printf "[%s] %-10s %s\n" "$timestamp" "$status" "$task" >> "$LOG_FILE"
}

# Exit delay
handle_delay() {
  if [ "$KSU" = "true" ] || [ "$APATCH" = "true" ] && [ "$KSU_NEXT" != "true" ] && [ "$MMRL" != "true" ]; then
    echo
    echo " Closing in 7 seconds..."
    sleep 7
  fi
}

log_patch() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$RECORD/patch.log"
}

# Kill GMS / Vending Processes
kill_process() {
  TARGET="$1"
  PID=$(pidof "$TARGET")
  if [ -n "$PID" ]; then
    kill -9 $PID
    log "- Killed $TARGET"
  else
    log "- $TARGET not running"
  fi
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

P() {
  for Q in /data/adb/modules/busybox-ndk/system/*/busybox \
           /data/adb/ksu/bin/busybox \
           /data/adb/ap/bin/busybox \
           /data/adb/magisk/busybox \
           /system/bin/busybox \
           /system/xbin/busybox; do
    [ -x "$Q" ] && echo "$Q" && return
  done
}


writelog() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    /system/bin/log -t PATCH_OVERRIDE "$1"
}

ensure_blacklist_entries() {
    BLACKLIST="/data/adb/Box-Brain/blacklist.txt"

    # Ensure directory & file exist
    mkdir -p "$(dirname "$BLACKLIST")"
    [ -f "$BLACKLIST" ] || touch "$BLACKLIST"

    # list of blacklisted packages 
    REQUIRED_ENTRIES="
io.github.vvb2060.mahoshojo
com.reveny.nativecheck
icu.nullptr.nativetest
com.android.nativetest
io.liankong.riskdetector
me.garfieldhan.holmes
luna.safe.luna
com.zhenxi.hunter
io.github.a13e300.ksuwebui
com.topjohnwu.magisk
com.dergoogler.mmrl.wx
com.dergoogler.mmrl
org.frknkrc44.hma_oss
bin.mt.plus
ch.protonvpn.android
com.android.chrome
com.google.android.apps.docs
com.google.android.apps.photos
com.google.android.contactkeys
com.google.android.safetycore
com.google.android.youtube
com.google.ar.core
com.heytap.browser
com.kimcy929.screenrecorder
com.kowx712.supermanager
com.metrolist.music
mark.via.gp
org.swiftapps.swiftbackup
"

    for entry in $REQUIRED_ENTRIES; do
        # Exact match only
        if ! grep -qxF "$entry" "$BLACKLIST"; then
            echo "$entry" >> "$BLACKLIST"
        fi
    done
}

ensure_exec_permissions() {
  local DIR="/data/adb/modules/playintegrityfix"

  [ -d "$DIR" ] || return 0

  for file in "$DIR"/*.sh; do
    [ -f "$file" ] || continue

    if [ ! -x "$file" ]; then
      chmod +x "$file"
    fi
  done
}

##########################################
# adapted from Play Integrity Fork by @osm0sis & Shamiko by @Lsposed Team
# source: https://github.com/osm0sis/PlayIntegrityFork
# license: GPL-3.0
##########################################

# shellcheck disable=SC2034  # consumed by service.sh / post-fs-data.sh after sourcing
SKIPDELPROP=false
[ -f "$MODPATH/skipdelprop" ] && SKIPDELPROP=true

# Core Property Functions
# resetprop_if_diff <prop> <expected>
resetprop_if_diff() {
    local NAME="$1"
    local EXPECTED="$2"
    local CURRENT
    
    case "$ROOT_SOL" in
        magisk|kernelsu|apatch)
            CURRENT="$(resetprop "$NAME")"
            [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || $RESETPROP "$NAME" "$EXPECTED"
            ;;
        *)
            CURRENT="$(getprop "$NAME")"
            [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || setprop "$NAME" "$EXPECTED" 2>/dev/null
            ;;
    esac
}

# resetprop_if_match <prop> <match> <new_value>
resetprop_if_match() {
    local NAME="$1"
    local MATCH="$2"
    local VALUE="$3"
    local CURRENT
    
    case "$ROOT_SOL" in
        magisk|kernelsu|apatch)
            CURRENT="$(resetprop "$NAME")"
            ;;
        *)
            CURRENT="$(getprop "$NAME")"
            ;;
    esac
    
    case "$CURRENT" in
        *"$MATCH"*) $RESETPROP "$NAME" "$VALUE" ;;
    esac
}

# delprop_if_exist <prop>
delprop_if_exist() {
    case "$ROOT_SOL" in
        magisk|kernelsu|apatch)
            [ -n "$(resetprop "$1")" ] && $PROP_DELETE "$1"
            ;;
        *)
            # Can't delete on legacy, set to empty
            setprop "$1" "" 2>/dev/null
            ;;
    esac
}

# persistprop <prop> <value>
persistprop() {
    [ "$ROOT_SOL" = "kernelsu_legacy" ] || [ "$ROOT_SOL" = "apatch_legacy" ] || [ "$ROOT_SOL" = "unknown" ] && return 0

    local NAME="$1"
    local NEWVALUE="$2"
    local CURVALUE
    CURVALUE="$(resetprop "$NAME")"

    if ! grep -q "$NAME" "$MODPATH/uninstall.sh" 2>/dev/null; then
        if [ "$CURVALUE" ]; then
            [ "$NEWVALUE" = "$CURVALUE" ] || echo "resetprop -n -p \"$NAME\" \"$CURVALUE\"" >> "$MODPATH/uninstall.sh"
        else
            echo "resetprop -p --delete \"$NAME\"" >> "$MODPATH/uninstall.sh"
        fi
    fi
    resetprop -n -p "$NAME" "$NEWVALUE"
}

# Hexpatch Fallback
resetprop_hexpatch() {
    [ "$ROOT_SOL" != "magisk" ] && return 1
    
    case "$1" in
        -f|--force) local FORCE=1; shift;;
    esac 

    local NAME="$1"
    local NEWVALUE="$2"
    local CURVALUE
    CURVALUE="$(resetprop "$NAME")"

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
    NEWHEX="$(printf '%02x' "$NEWLEN")$(printf '%s' "$NEWVALUE" | od -A n -t x1 -v | tr -d ' \n')$(printf "%$((92-NEWLEN))s" | sed 's/ /00/g')"
    # shellcheck disable=SC2059  # deliberate: format carries \xNN escapes that mksh echo -e expands to raw bytes
    echo -ne "\x00\x00" | dd obs=1 count=2 seek=$((NAMEOFFSET-96)) conv=notrunc of="$PROPFILE" 2>/dev/null
    # shellcheck disable=SC2059  # deliberate: mksh echo -e interprets the \xNN sequences below
    echo -ne "$(printf "$NEWHEX" | sed -e 's/.\{2\}/&\\x/g' -e 's/^/\\x/' -e 's/\\x$//')" | dd obs=1 count=93 seek=$((NAMEOFFSET-93)) conv=notrunc of="$PROPFILE" 2>/dev/null
}

boot_log() {
    echo "$1" | tee -a "$RECORD/boot.log"
}

wait_for_boot() {
    boot_log "Waiting for Android to finish booting..."
    local count=0
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
        count=$((count + 1))
        [ "$count" -ge 300 ] && { boot_log "Boot wait timeout"; return 1; }
    done
    sleep 3
    boot_log "Initialising, please wait."
    boot_log " "
}

reset_tricky_store() {
    # Tricky Store
    if [ -d "/data/adb/tricky_store/key_db" ]; then
        rm -rf "/data/adb/tricky_store/key_db"
        mkdir -p "/data/adb/tricky_store/key_db"
    fi

    # TEE Simulator 
    if [ -d "/data/adb/tricky_store/persistent_keys" ]; then
        rm -rf "/data/adb/tricky_store/persistent_keys"
        mkdir -p "/data/adb/tricky_store/persistent_keys"
    fi
}
