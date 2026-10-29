#!/system/bin/sh

MODPATH="${0%/*}"
. $MODPATH/common_func.sh

# Paths
BOX="/data/adb/Box-Brain"
LOGDIR="$BOX/Integrity-Box-Logs"
SCRIPT_DIR="$MODPATH/webroot/common_scripts"

mkdir -p "$BOX" "$LOGDIR"
print_header

cleanup_root_logs
cleanup_ota
cleanup_lsposed
cleanup_gapps_logs

reset_tricky_store
download_keybox
update_targets

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
handle_delay
exit 0

