#!/system/bin/sh
logdir=/data/adb/Integrity-Box-Logs
log=$logdir/rebase.log

# Logger
meow() {
    echo "$1" | tee -a "$log"
}

# Create log directory 
mkdir -p $logdir
touch $log

OLD_PATHS="
/data/adb/modules/Integrity-Box
/data/adb/modules_update/Integrity-Box
/data/adb/Integrity-Box
"

meow "- Checking for old Integrity-Box files"
meow " "

found=false

for path in $OLD_PATHS; do
  if [ -e "$path" ]; then
    meow "- Removing: $path"
    rm -rf "$path"
    found=true
  fi
done

 if $found; then
   meow " "
  meow "========================================"
  meow "- Old Integrity-Box installation detected"
   meow "- Performing clean-up for safe update"
   meow " "
   meow "- WHY CLEAN INSTALLATION IS REQUIRED:"
   meow "+ Module internals & structure updated"
   meow "+ Old leftovers can break functionality"
   meow "- Clean install ensures full compatibility"
   meow
   meow "⚠️  REBOOT IS MANDATORY to apply changes"
   meow "========================================"
   meow " "
   meow "- Clean-up complete."
   for i in $(seq 10 -1 1); do
    meow "- Rebooting in $i seconds..."
   sleep 1
   done
   rm -rf /data/adb/modules_update/integrity_box # Delete extracted files
   sleep 1
   meow "- Rebooting now!"
   reboot
   exit 1
 else
   meow "- No old Integrity-Box files found"
   meow "- Proceed with installing the latest version"
   meow " "
fi
exit 0