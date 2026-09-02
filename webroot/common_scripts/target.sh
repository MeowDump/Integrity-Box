#!/system/bin/sh
MODPATH="/data/adb/modules/playintegrityfix"
. $MODPATH/common_func.sh

TARGET_DIR="/data/adb/tricky_store"
TARGET="$TARGET_DIR/target.txt"
SKIP_FILE="/data/adb/Box-Brain/skip"
BACKUP="$TARGET.bak"
TMP="${TARGET}.new.$$"
orig_selinux="$(getenforce 2>/dev/null || echo Permissive)"

mkdir -p "$TARGET_DIR" 2>/dev/null
if [ ! -f "$SKIP_FILE" ] && [ "$orig_selinux" = "Enforcing" ]; then
    setenforce 0
fi

[ -f "$TARGET" ] && mv -f "$TARGET" "$BACKUP" && log_step "BACKUP" "$BACKUP"

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

BLACKLIST="/data/adb/Box-Brain/blacklist.txt"
if [ -s "$BLACKLIST" ]; then
    sed -i 's/^[[:space:]]*//;s/[[:space:]]*$//' "$BLACKLIST"
    grep -Fvxf "$BLACKLIST" "$TMP" > "${TMP}.filtered" || true
    mv -f "${TMP}.filtered" "$TMP"
    log_step "CLEANED" "Blacklisted Apps removed"
else
    log_step "SKIPPED" "Blacklist not configured"
fi

[ "$teeBroken" = "true" ] && sed -i 's/$/!/' "$TMP" && log_step "SUPPORT" "TEE Broken detected"

mv -f "$TMP" "$TARGET" && log_step "UPDATED" "Target Packages updated"

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

exit 0
