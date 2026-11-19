#!/system/bin/sh

MODPATH="${0%/*}"
. $MODPATH/common_func.sh

# Paths
BOX="/data/adb/Box-Brain"
LOGDIR="$BOX/Integrity-Box-Logs"
SCRIPT_DIR="$MODPATH/webroot/common_scripts"

mkdir -p "$BOX" "$LOGDIR"
print_header
launch_webui

cleanup_root_logs
cleanup_ota
cleanup_lsposed
cleanup_gapps_logs

download_keybox
# Decide after the keybox was fetched: the stored keys only have to be dropped
# when the installed keybox really changed, and a failed download must not cost
# the user its keys.
reset_tricky_store
update_targets

sh "$SCRIPT_DIR/status.sh" || true
sh "$MODPATH/osm0sis.sh" || true
sh "$SCRIPT_DIR/cleanup.sh" >/dev/null 2>&1

if [ -d "/data/adb/modules/teesim" ]; then
    sh "$SCRIPT_DIR/teesim.sh" || true
fi

if [ -d "/data/adb/modules/oh_my_keymint" ]; then
    sh "$SCRIPT_DIR/keymint.sh" || true
fi

handle_security_patch
restart_google_services
update_module_description

echo " "
echo " "
echo "    -- ACTION COMPLETED SUCCESSFULLY --"
check_integrity >/dev/null 2>&1
handle_delay
exit 0

