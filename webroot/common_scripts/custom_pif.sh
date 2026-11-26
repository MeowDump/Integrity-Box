
#!/system/bin/sh

MODPATH="/data/adb/modules/integrity-box"
. "$MODPATH/common_func.sh"

PROP="$MODPATH/config.meow"
URL="https://github.com/MeowDump/Integrity-Box/releases/download/archive/meow.prop"

echo " ✦ Using manual beta fingerprint mode"
echo " ✦ Custom Beta : Pixel 6A  |  initSDK : 32"
echo " "

TMP="/data/local/tmp/meow.prop"
BACKUP="/data/local/tmp/config.meow.bak"
NEW="$MODPATH/config.meow.tmp"

cleanup() {
    rm -f "$TMP" "$NEW" "$BACKUP"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

download_file() {
    rm -f "$TMP"

    case "$DL_MODE" in
        curl)
            "$DOWNLOADER" -k -fLsS --retry 2 --connect-timeout 15 --max-time 60 "$1" -o "$TMP" >/dev/null 2>&1
            ;;
        wget)
            "$DOWNLOADER" --no-check-certificate -q -T 60 "$1" -O "$TMP" >/dev/null 2>&1
            ;;
        busybox)
            "$DOWNLOADER" wget --no-check-certificate -q -T 60 "$1" -O "$TMP" >/dev/null 2>&1
            ;;
        toybox)
            "$DOWNLOADER" wget -q "$1" -O "$TMP" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac

    [ -s "$TMP" ]
}

download_with_fallback() {
    download_file "$URL" && return 0

    rm -f "$TMP"

    if [ "$DL_MODE" = "curl" ]; then
        for DNS in 1.1.1.1 8.8.8.8 9.9.9.9; do
            IPS=$(
                nslookup github.com "$DNS" 2>/dev/null |
                awk '
                    /^Address [0-9]+: / { print $3 }
                    /^Address: / { print $2 }
                '
            )

            for IP in $IPS; do
                case "$IP" in
                    *:*)
                        continue
                        ;;
                    *.*.*.*)
                        ;;
                    *)
                        continue
                        ;;
                esac

                if "$DOWNLOADER" -k -fLsS --retry 1 \
                    --connect-timeout 10 --max-time 60 \
                    --resolve "github.com:443:$IP" "$URL" \
                    -o "$TMP" >/dev/null 2>&1 && [ -s "$TMP" ]; then
                    return 0
                fi

                rm -f "$TMP"
            done
        done
    fi

    return 1
}

echo " ✦ Downloading build properties..."

detect_downloader

if ! download_with_fallback; then
    rm -f "$TMP"
    echo " ✖ Download failed. Check your internet connection and try again."
    echo " ✦ Existing properties were not changed."
    exit 1
fi

if [ ! -s "$TMP" ] ||
   ! grep -q '^MANUFACTURER=' "$TMP" ||
   ! grep -q '^MODEL=' "$TMP" ||
   ! grep -q '^FINGERPRINT=' "$TMP" ||
   ! grep -q '^DEVICE=' "$TMP"; then
    echo " ✖ Invalid build properties. Existing file was not changed."
    exit 1
fi

if [ -f "$PROP" ]; then
    echo " ✦ Existing config.meow found."

    if grep -q '^# Configuration$' "$PROP"; then
        if ! sed -n '/^# Configuration$/,$p' "$PROP" > "$BACKUP"; then
            echo " ✖ Failed to preserve configuration."
            exit 1
        fi
    elif grep -q '^# Advanced Settings$' "$PROP"; then
        if ! sed -n '/^# Advanced Settings$/,$p' "$PROP" > "$BACKUP"; then
            echo " ✖ Failed to preserve configuration."
            exit 1
        fi
    else
        : > "$BACKUP"
    fi

    if ! cp "$TMP" "$NEW"; then
        echo " ✖ Failed to prepare properties."
        exit 1
    fi

    if [ -s "$BACKUP" ]; then
        printf '\n' >> "$NEW" || exit 1
        cat "$BACKUP" >> "$NEW" || exit 1
    fi
else
    echo " ✦ No existing config.meow found."

    if ! cp "$TMP" "$NEW"; then
        echo " ✖ Failed to prepare properties."
        exit 1
    fi
fi

if [ ! -s "$NEW" ]; then
    echo " ✖ Failed to prepare properties."
    exit 1
fi

chmod 0644 "$NEW" || {
    echo " ✖ Failed to set file permissions."
    exit 1
}

if ! mv -f "$NEW" "$PROP"; then
    echo " ✖ Failed to install properties."
    exit 1
fi

echo " "
echo " ✦ Your PIF configuration is preserved."
echo " ✦ Build properties updated successfully."
echo " "
