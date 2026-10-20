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
sh "$MODPATH/osm0sis.sh"
handle_security_patch
restart_google_services
update_module_description
sh "$SCRIPT_DIR/cleanup.sh" >/dev/null 2>&1; 
echo " "
echo " "
echo "    -- ACTION COMPLETED SUCCESSFULLY --"

if [ "$KSU_NEXT" = "true" ]; then
    sh "$SCRIPT_DIR/hehe.sh"
fi

handle_delay
exit 0
