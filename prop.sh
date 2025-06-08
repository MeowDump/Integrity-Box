#!/system/bin/sh

L="/data/adb/Integrity-Box-Logs/prop_detection.log"
TIME=$(date "+%Y-%m-%d %H:%M:%S")
Q="------------------------------------------"
R="════════════════════════════"

log() {
    echo -e "$1" | tee -a "$L"
}

MEOW() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

# Clear log and start fresh
echo -e "$Q" > "$L"
echo -e "- INTEGRITY-BOX PROP DETECTION | $TIME " >> "$L"
echo -e "$Q\n" >> "$L"

# ROOT & MAGISK DETECTION
log "- Root & Magisk Detection"
ROOT_PROPS="ro.secure ro.debuggable service.adb.root"
MAGISK_PROPS="init.svc.magiskd ro.boot.verifiedbootstate ro.boot.flash.locked ro.boot.warranty_bit ro.boot.veritymode"

ROOT_FOUND=""
MAGISK_FOUND=""

for prop in $ROOT_PROPS; do
    VALUE=$(getprop $prop)
    [ "$VALUE" = "0" ] || [ "$VALUE" = "1" ] && ROOT_FOUND="$ROOT_FOUND\n$prop=$VALUE"
done

for prop in $MAGISK_PROPS; do
    VALUE=$(getprop $prop)
    [ -n "$VALUE" ] && MAGISK_FOUND="$MAGISK_FOUND\n$prop=$VALUE"
done

[ -n "$ROOT_FOUND" ] && log "   └─ ⚠️ Root Indicators:\n$ROOT_FOUND" || log "   └─ ✅ Not Found"
[ -n "$MAGISK_FOUND" ] && log "   └─ ⚠️ Magisk Indicators:\n$MAGISK_FOUND" || log "   └─ ✅ Not Found"
log "$Q"
log " "

# CUSTOM ROM DETECTION -
CUSTOM_ROM_PROPS="ro.build.fingerprint ro.build.version.incremental ro.modversion"
CUSTOM_ROM_FOUND=""

for prop in $CUSTOM_ROM_PROPS; do
    VALUE=$(getprop $prop)
    echo "$VALUE" | grep -qE "lineage|crdroid|aosp|evolution" && CUSTOM_ROM_FOUND="$CUSTOM_ROM_FOUND\n$prop=$VALUE"
done

if [ -n "$CUSTOM_ROM_FOUND" ]; then
    echo "Detected Custom ROM"
    log "- Custom ROM Detection"
    log "   └─ ⚠️ Custom ROM Properties:\n$CUSTOM_ROM_FOUND"
    log "$Q"
    log " "
fi

# PLAY INTEGRITY & SAFETYNET BYPASS
log "- Play Integrity & SafetyNet Bypass"
SAFETYNET_PROPS="ro.product.model ro.boot.hardware.keystore ro.build.characteristics"

SAFETYNET_FOUND=""

for prop in $SAFETYNET_PROPS; do
    VALUE=$(getprop $prop)
    echo "$VALUE" | grep -qE "Pixel|software|emulator" && SAFETYNET_FOUND="$SAFETYNET_FOUND\n$prop=$VALUE"
done

[ -n "$SAFETYNET_FOUND" ] && log "   └─ ⚠️ Spoofing Detected:\n$SAFETYNET_FOUND" || log "   └─ ✅ Not Found"
log "$Q"
log " "

# KERNEL & SELINUX CHECK
log "- Kernel & SELinux State"
KERNEL_PROPS="ro.kernel.qemu ro.boot.selinux"
KERNEL_FOUND=""

for prop in $KERNEL_PROPS; do
    VALUE=$(getprop $prop)
    [ "$VALUE" = "1" ] || [ "$VALUE" = "permissive" ] && KERNEL_FOUND="$KERNEL_FOUND\n$prop=$VALUE"
done

[ -n "$KERNEL_FOUND" ] && log "   └─ ⚠️ Security Risk:\n$KERNEL_FOUND" || log "   └─ ✅ Not Found"
log "$Q"
log " "

# VIRTUAL MACHINE & EMULATOR DETECTION
log "- Emulator & Virtual Machine Detection"
VM_PROPS="ro.hardware ro.product.manufacturer ro.build.characteristics"
VM_FOUND=""

for prop in $VM_PROPS; do
    VALUE=$(getprop $prop)
    echo "$VALUE" | grep -qE "goldfish|ranchu|Genymotion|emulator" && VM_FOUND="$VM_FOUND\n$prop=$VALUE"
done

[ -n "$VM_FOUND" ] && log "   └─ ⚠️ Emulator Detected:\n$VM_FOUND" || log "   └─ ✅ Not Found"
log "$Q"
log " "

# NETWORK & VPN/PROXY DETECTION
log "- VPN & Proxy Detection"
NETWORK_PROPS="net.tcp.buffersize.wifi net.hostname"
NETWORK_FOUND=""

for prop in $NETWORK_PROPS; do
    VALUE=$(getprop $prop)
    [ -n "$VALUE" ] && NETWORK_FOUND="$NETWORK_FOUND\n$prop=$VALUE"
done

[ -n "$NETWORK_FOUND" ] && log "   └─ ⚠️ Suspicious Network Settings:\n$NETWORK_FOUND" || log "   └─ ✅ Not Found"
log "$Q"
log " "

log "- Detection Complete! ✅\n"
echo -e "$R" >> "$L"
MEOW "Log saved to $L"