#!/system/bin/sh

MODPATH="/data/adb/modules/integrity-box"
. "$MODPATH/common_func.sh"

URL="https://android.googleapis.com/attestation/status"
DEST="/data/adb/Box-Brain/status.json"
TMP="/data/local/tmp/status.json.tmp"

cleanup() {
    rm -f "$TMP"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

download_file() {
    rm -f "$TMP"

    case "$DL_MODE" in
        curl)
            "$DOWNLOADER" -k -fLsS --retry 2 --connect-timeout 15 --max-time 60 \
                "$1" -o "$TMP" >/dev/null 2>&1
            ;;
        wget)
            "$DOWNLOADER" --no-check-certificate -q -T 60 \
                "$1" -O "$TMP" >/dev/null 2>&1
            ;;
        busybox)
            "$DOWNLOADER" wget --no-check-certificate -q -T 60 \
                "$1" -O "$TMP" >/dev/null 2>&1
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
                nslookup android.googleapis.com "$DNS" 2>/dev/null |
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
                    --resolve "android.googleapis.com:443:$IP" "$URL" \
                    -o "$TMP" >/dev/null 2>&1 && [ -s "$TMP" ]; then
                    return 0
                fi

                rm -f "$TMP"
            done
        done
    fi

    return 1
}

echo " ✦ Fetching google revocation list..."

detect_downloader

if ! download_with_fallback; then
    rm -f "$TMP"
    echo " ✖ Download failed. Check your internet connection and try again."
    echo " ✦ Existing status.json was not changed."
    exit 1
fi

if [ ! -s "$TMP" ]; then
    echo " ✖ Downloaded file is empty. Existing status.json was not changed."
    exit 1
fi

if ! mkdir -p "$(dirname "$DEST")"; then
    echo " ✖ Failed to create destination directory."
    exit 1
fi

if ! chmod 0664 "$TMP"; then
    echo " ✖ Failed to set file permissions."
    exit 1
fi

if ! mv -f "$TMP" "$DEST"; then
    echo " ✖ Failed to install status.json."
    exit 1
fi

chmod 0664 "$DEST" || {
    echo " ✖ File downloaded, but failed to set permissions."
    exit 1
}

echo " ✦ Updated keybox revocation list"
echo " "
