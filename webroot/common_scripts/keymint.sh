#!/system/bin/sh

OMK_DIR="/data/misc/keystore/omk"
CONFIG_TOML="$OMK_DIR/config.toml"
TMP_CONFIG="${CONFIG_TOML}.tmp.$$"
PIF_PROP="/data/adb/modules/playintegrityfix/custom.pif.prop"

# Exit silently if OMK directory or config doesn't exist
[ -d "$OMK_DIR" ] || exit 0
[ -f "$CONFIG_TOML" ] || exit 0
[ -f "$PIF_PROP" ] || exit 0

# Read values from Integrity Box spoofer
get_prop() {
    grep -i "^$1=" "$PIF_PROP" 2>/dev/null | cut -d '=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

BRAND=$(get_prop "BRAND")
DEVICE=$(get_prop "DEVICE")
PRODUCT=$(get_prop "PRODUCT")
MANUFACTURER=$(get_prop "MANUFACTURER")
SECURITY_PATCH=$(get_prop "SECURITY_PATCH")

# If no values are set at all, skip silently (individual empty fields keep current values)
[ -z "$BRAND" ] && [ -z "$DEVICE" ] && [ -z "$PRODUCT" ] && [ -z "$MANUFACTURER" ] && [ -z "$SECURITY_PATCH" ] && exit 0

# Write new config
awk -v brand="$BRAND" -v device="$DEVICE" -v product="$PRODUCT" \
    -v manufacturer="$MANUFACTURER" -v sec_patch="$SECURITY_PATCH" \
    '
    BEGIN { in_device=0; in_trust=0 }
    
    /^\[device\]/ { in_device=1; in_trust=0; print; next }
    /^\[/ && in_device { in_device=0 }
    /^\[trust\]/ { in_trust=1; in_device=0; print; next }
    /^\[/ && in_trust { in_trust=0 }
    
    in_device && /^brand[[:space:]]*=/ {
        if (brand != "") print "brand = \"" brand "\""
        else print
        next
    }
    in_device && /^device[[:space:]]*=/ {
        if (device != "") print "device = \"" device "\""
        else print
        next
    }
    in_device && /^product[[:space:]]*=/ {
        if (product != "") print "product = \"" product "\""
        else print
        next
    }
    in_device && /^manufacturer[[:space:]]*=/ {
        if (manufacturer != "") print "manufacturer = \"" manufacturer "\""
        else print
        next
    }
    
    in_trust && /^security_patch[[:space:]]*=/ {
        if (sec_patch != "") print "security_patch = \"" sec_patch "\""
        else print
        next
    }
    
    { print }
' "$CONFIG_TOML" > "$TMP_CONFIG" 2>/dev/null

mv -f "$TMP_CONFIG" "$CONFIG_TOML" 2>/dev/null

exit 0
