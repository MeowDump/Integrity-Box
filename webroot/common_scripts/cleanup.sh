#!/system/bin/sh
F="/data/adb/tricky_store/keybox.xml"
T="/data/adb/tricky_store/keybox.xml.tmp"
L="/data/adb/Box-Brain/Integrity-Box-Logs/remove.log"
X="aristotle,socrates,plato,confucius"

log() {
    if [[ -z "${_L_LOG_INITIALIZED:-}" ]]; then
        : > "$L"
        _L_LOG_INITIALIZED=1
    fi

    echo "- $1" >> "$L"
}

delete_if_exist() {
    path="$1"
    if [ -e "$path" ]; then
        rm -rf "$path"
        log "Deleted: $path"
    fi
}

mkdir -p "$(dirname "$L")"
touch "$L"
{
    echo ""
    echo "••••••• Cleanup Started •••••••"

    if [ ! -f "$F" ]; then
        log "File not found: $F"
        echo "••••••• Cleanup Aborted •••••••"
        exit 0
    fi

    log "Removing leftover files"

Z="$(cat "$F")"

Y=""
FIRST=1
IFS=','

for LINE in $(echo "$Z"); do
    for WORD in $X; do
        LINE="${LINE//$WORD/}"
    done
    if [ "$FIRST" -eq 1 ]; then
        Y="$LINE"
        FIRST=0
    else
        Y="$Y
$LINE"
    fi
done

IFS="$OLD_IFS"

printf "%s\n" "$Y" > "$T"
mv "$T" "$F"

    log "Deleting known leftover files from my modules..."
    delete_if_exist /data/adb/integrity_box_verify
	delete_if_exist /data/adb/modules_update/integrity-box/verify.sh
	delete_if_exist /data/adb/service.d/shamiko.sh # we don't need this anymore 
	delete_if_exist /data/adb/modules_update/auto_generated # canary updater
	delete_if_exist /data/adb/modules/auto_generated # canary updater
	delete_if_exist /data/adb/modules_update/playintegrityfork # conflict 
	delete_if_exist /data/adb/modules/playintegrityfork # conflict
	delete_if_exist /data/adb/modules/COPG-VD # conflict
	delete_if_exist /data/adb/modules_update/COPG-VD # conflict
	delete_if_exist /data/adb/modules_update/integrity-box/hash
	delete_if_exist /data/adb/modules_update/integrity-box/credits.md
	delete_if_exist /data/adb/modules_update/integrity-box/acknowledgement.md
	delete_if_exist /data/adb/modules_update/integrity-box/README.md
	delete_if_exist /data/adb/modules_update/integrity-box/CHANGELOG.md
	delete_if_exist /data/adb/modules/integrity-box/tmp.prop
	delete_if_exist /data/adb/modules/integrity-box/custom.pif.json
	delete_if_exist /data/adb/modules/integrity-box/custom.pif.json.bak
	delete_if_exist /data/adb/modules/integrity-box/pixel.txt.bak
	delete_if_exist /data/adb/modules/integrity-box/pixel.txt
	delete_if_exist /data/adb/modules/integrity-box/pif.prop
	delete_if_exist /data/adb/modules/integrity-box/pif.json
	delete_if_exist /data/adb/modules/integrity-box/toolkit/legacy.prop
	delete_if_exist /data/adb/modules/integrity-box/toolkit/pixelify.prop
	delete_if_exist /data/adb/modules/integrity-box/PIXEL_LATEST_HTML
	delete_if_exist /data/adb/modules/integrity-box/PIXEL_OTA_HTML
	delete_if_exist /data/adb/modules/integrity-box/PIXEL_VERSIONS_HTML
	delete_if_exist /data/adb/modules/integrity-box/PIXEL_ZIP_METADATA
	delete_if_exist /data/adb/modules/integrity-box/pixelprop
	delete_if_exist /data/adb/pif.prop
	delete_if_exist /data/adb/service.d/package.sh
	delete_if_exist /data/adb/pif.json
	delete_if_exist /data/local/tmp/keybox_scan.log
	delete_if_exist /data/local/tmp/keybox_runner.log
	delete_if_exist /data/adb/modules/integrity-box/consent.sh
	delete_if_exist /data/adb/modules/integrity-box/config.md
	delete_if_exist /data/adb/modules/integrity-box/legacy
	delete_if_exist /data/adb/modules/integrity-box/autopif4
	delete_if_exist /data/adb/modules/integrity-box/hello.sh
    echo "••••••• Cleanup Ended •••••••"
    echo " "
} >> "$L" 2>&1

exit 0