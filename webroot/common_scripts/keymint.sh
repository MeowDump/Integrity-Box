#!/system/bin/sh

OMK_MODULE="/data/adb/modules/oh_my_keymint"
OMK_DIR="/data/misc/keystore/omk"
CONFIG_TOML="$OMK_DIR/config.toml"
INJECTOR_TOML="$OMK_DIR/injector.toml"
PIF_PROP="/data/adb/modules/integrity-box/config.meow"
TARGET_TXT="/data/adb/tricky_store/target.txt"
PIXEL_FLAG="/data/adb/Box-Brain/omk-pixel"
TARGET_FLAG="/data/adb/Box-Brain/omk-target"

# Skip entirely if Oh My Keymint is absent or disabled.
[ -d "$OMK_MODULE" ] || exit 0
[ ! -f "$OMK_MODULE/disable" ] || exit 0

# Do nothing unless at least one operation is explicitly enabled.
[ -f "$PIXEL_FLAG" ] || [ -f "$TARGET_FLAG" ] || exit 0

# Update device/build values from PIF_PROP only when omk-pixel is enabled.
if [ -f "$PIXEL_FLAG" ]; then
    [ -d "$OMK_DIR" ] || exit 0
    [ -f "$CONFIG_TOML" ] || exit 0
    [ -f "$PIF_PROP" ] || exit 0

    TMP_CONFIG="${CONFIG_TOML}.tmp.$$"

    get_prop() {
        grep -i -m1 "^$1=" "$PIF_PROP" 2>/dev/null | cut -d '=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    }

    BRAND=$(get_prop "BRAND")
    DEVICE=$(get_prop "DEVICE")
    PRODUCT=$(get_prop "PRODUCT")
    MANUFACTURER=$(get_prop "MANUFACTURER")
    SECURITY_PATCH=$(get_prop "SECURITY_PATCH")

    # Preserve the existing behavior: skip the PIF update if every value is empty.
    if [ -n "$BRAND$DEVICE$PRODUCT$MANUFACTURER$SECURITY_PATCH" ]; then
        if awk -v brand="$BRAND" -v device="$DEVICE" -v product="$PRODUCT" \
            -v manufacturer="$MANUFACTURER" -v sec_patch="$SECURITY_PATCH" '
            BEGIN { in_device=0; in_trust=0 }
            /^\[device\]/ { in_device=1; in_trust=0; print; next }
            /^\[/ && in_device { in_device=0 }
            /^\[trust\]/ { in_trust=1; in_device=0; print; next }
            /^\[/ && in_trust { in_trust=0 }
            in_device && /^brand[[:space:]]*=/ {
                if (brand != "") print "brand = \"" brand "\""; else print
                next
            }
            in_device && /^device[[:space:]]*=/ {
                if (device != "") print "device = \"" device "\""; else print
                next
            }
            in_device && /^product[[:space:]]*=/ {
                if (product != "") print "product = \"" product "\""; else print
                next
            }
            in_device && /^manufacturer[[:space:]]*=/ {
                if (manufacturer != "") print "manufacturer = \"" manufacturer "\""; else print
                next
            }
            in_trust && /^security_patch[[:space:]]*=/ {
                if (sec_patch != "") print "security_patch = \"" sec_patch "\""; else print
                next
            }
            { print }
        ' "$CONFIG_TOML" > "$TMP_CONFIG" 2>/dev/null; then
            if [ -s "$TMP_CONFIG" ]; then
                mv -f "$TMP_CONFIG" "$CONFIG_TOML" 2>/dev/null || rm -f "$TMP_CONFIG"
            else
                rm -f "$TMP_CONFIG"
            fi
        else
            rm -f "$TMP_CONFIG"
        fi
    fi
fi

# Update only the scoop array when omk-target is enabled.
if [ -f "$TARGET_FLAG" ]; then
    [ -f "$INJECTOR_TOML" ] || exit 0
    [ -f "$TARGET_TXT" ] || exit 0

    TMP_INJECTOR="${INJECTOR_TOML}.tmp.$$"
    SCOOP_TMP="/data/local/tmp/.omk_scoop_$$"
    : > "$SCOOP_TMP" || exit 0
    first=1

    while IFS= read -r line || [ -n "$line" ]; do
        pkg=$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[!?]$//')
        [ -n "$pkg" ] || continue
        # Escape TOML basic-string characters.
        pkg=$(printf '%s' "$pkg" | sed 's/\\/\\\\/g; s/"/\\"/g')
        if [ "$first" -eq 1 ]; then
            printf 'scoop = ["%s"' "$pkg" > "$SCOOP_TMP"
            first=0
        else
            printf ', "%s"' "$pkg" >> "$SCOOP_TMP"
        fi
    done < "$TARGET_TXT"

    if [ "$first" -eq 1 ]; then
        printf 'scoop = []\n' > "$SCOOP_TMP"
    else
        printf ']\n' >> "$SCOOP_TMP"
    fi

    SCOOP_LINE=$(cat "$SCOOP_TMP")
    if awk -v scoop_line="$SCOOP_LINE" '
        BEGIN { updated=0 }
        /^[[:space:]]*scoop[[:space:]]*=/ && !updated { print scoop_line; updated=1; next }
        { print }
        END { if (!updated) exit 2 }
    ' "$INJECTOR_TOML" > "$TMP_INJECTOR" 2>/dev/null; then
        if [ -s "$TMP_INJECTOR" ]; then
            mv -f "$TMP_INJECTOR" "$INJECTOR_TOML" 2>/dev/null || rm -f "$TMP_INJECTOR"
        else
            rm -f "$TMP_INJECTOR"
        fi
    else
        rm -f "$TMP_INJECTOR"
    fi

    rm -f "$SCOOP_TMP"
fi

exit 0
