#!/system/bin/sh
# shellcheck disable=SC3043,SC2034,SC1091,SC2329
# ==============================================================================
# Integrity Box - Key Provisioner (v46+)
# Multi-Variant Fallback (Megatron2/Megatron/Megatron3/Megatron4) & ASN.1 Validator
# ==============================================================================

MODPATH="/data/adb/modules/playintegrityfix"
UPDATEPATH="/data/adb/modules_update/playintegrityfix"

if [ -f "$MODPATH/common_func.sh" ]; then
    . "$MODPATH/common_func.sh"
elif [ -f "$UPDATEPATH/common_func.sh" ]; then
    . "$UPDATEPATH/common_func.sh"
else
    echo "ERROR: common_func.sh not found"
    exit 1
fi

RECORD="/data/adb/Box-Brain"
TRICKY_STORE="/data/adb/tricky_store"
KEYBOX="$TRICKY_STORE/keybox.xml"
LOG_FILE="$RECORD/Integrity-Box-Logs/keybox.log"
CLEANUP="$MODPATH/webroot/common_scripts/cleanup.sh"
UCLEANUP="$UPDATEPATH/webroot/common_scripts/cleanup.sh"
BACKUP_DIR="$RECORD/KeyBackup"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
KEYBOX_BACKUP="$BACKUP_DIR/keybox_$TIMESTAMP.xml"
SIM_KEY="/data/adb/teesim/keybox.xml"

log() {
    echo "$*" | tee -a "$LOG_FILE"
}

mkdir -p "$TRICKY_STORE" "$RECORD" "$RECORD/Integrity-Box-Logs" "$BACKUP_DIR"
touch "$LOG_FILE"

BB=$(P 2>/dev/null || which busybox 2>/dev/null)

if [ -s "$KEYBOX" ]; then
    cp -f "$KEYBOX" "$KEYBOX_BACKUP"
    log " ✦ Backed up current keybox"
fi

GITHUB_IPS="140.82.112.3 140.82.113.3 140.82.114.3 140.82.115.3"

_try_download() {
    local url="$1"
    local out="$2"
    local dl_tool="$3"
    local ip="$4"

    rm -f "$out"

    case "$dl_tool" in
        bb_wget)
            [ -n "$BB" ] && "$BB" wget -q --no-check-certificate -T 15 -t 1 -O "$out" "$url" 2>/dev/null
            ;;
        wget)
            wget -q --no-check-certificate --timeout=15 --tries=1 -O "$out" "$url" 2>/dev/null
            ;;
        curl)
            curl -fsSL --connect-timeout 15 --max-time 60 --insecure "$url" -o "$out" 2>/dev/null
            ;;
        curl_resolve)
            curl -fsSL --connect-timeout 15 --max-time 60 --insecure \
                 --resolve "github.com:443:$ip" \
                 "$url" \
                 -o "$out" 2>/dev/null
            ;;
    esac

    [ -s "$out" ]
}

_phase1_normal() {
    local url="$1"
    local out="$2"
    local attempt=0

    while [ "$attempt" -lt 2 ]; do
        attempt=$((attempt + 1))
        if [ -n "$BB" ] && _try_download "$url" "$out" "bb_wget"; then return 0; fi
        if _try_download "$url" "$out" "wget"; then return 0; fi
        if _try_download "$url" "$out" "curl"; then return 0; fi
        sleep 1
    done
    return 1
}

_phase2_dns_override() {
    local url="$1"
    local out="$2"
    local old_dns1 old_dns2
    old_dns1=$(getprop net.dns1)
    old_dns2=$(getprop net.dns2)

    for dns in "1.1.1.1 1.0.0.1" "8.8.8.8 8.8.4.4" "9.9.9.9 149.112.112.112"; do
        setprop net.dns1 "${dns%% *}"
        setprop net.dns2 "${dns##* }"
        if _phase1_normal "$url" "$out"; then
            _restore_dns "$old_dns1" "$old_dns2"
            return 0
        fi
        sleep 1
    done

    _restore_dns "$old_dns1" "$old_dns2"
    return 1
}

_restore_dns() {
    [ -n "$1" ] && setprop net.dns1 "$1"
    [ -n "$2" ] && setprop net.dns2 "$2"
}

_phase3_direct_ip() {
    local url="$1"
    local out="$2"

    for ip in $GITHUB_IPS; do
        if _try_download "$url" "$out" "curl_resolve" "$ip"; then return 0; fi
        sleep 1
    done
    return 1
}

fail_safe_download() {
    local url="$1"
    local out="$2"

    if _phase1_normal "$url" "$out"; then return 0; fi
    if _phase2_dns_override "$url" "$out"; then return 0; fi
    if _phase3_direct_ip "$url" "$out"; then return 0; fi
    return 1
}

parse_epoch() {
    raw="$1"
    [ -n "$raw" ] || { printf '%s' "0"; return; }
    yy=$(printf '%s' "$raw" | cut -c 1-2)
    mm=$(printf '%s' "$raw" | cut -c 3-4)
    dd=$(printf '%s' "$raw" | cut -c 5-6)
    hh=$(printf '%s' "$raw" | cut -c 7-8)
    min=$(printf '%s' "$raw" | cut -c 9-10)
    ss=$(printf '%s' "$raw" | cut -c 11-12)
    date -u -d "20${yy}-${mm}-${dd} ${hh}:${min}:${ss}" +%s 2>/dev/null || printf '%s' "0"
}

decode_and_validate() {
    local enc_file="$1"
    local xml_out="$2"

    local current="$enc_file"
    local tmp_step
    for i in $(seq 1 10); do
        tmp_step="$(mktemp -p /dev)"
        if ! base64 -d "$current" > "$tmp_step" 2>/dev/null; then
            rm -f "$tmp_step"
            [ "$current" != "$enc_file" ] && rm -f "$current"
            return 1
        fi
        [ "$current" != "$enc_file" ] && rm -f "$current"
        current="$tmp_step"
    done

    local tmp_hex
    tmp_hex="$(mktemp -p /dev)"
    if ! xxd -r -p "$current" > "$tmp_hex" 2>/dev/null; then
        rm -f "$current" "$tmp_hex"
        return 1
    fi
    rm -f "$current"

    if ! tr 'A-Za-z' 'N-ZA-Mn-za-m' < "$tmp_hex" > "$xml_out"; then
        rm -f "$tmp_hex" "$xml_out"
        return 1
    fi
    rm -f "$tmp_hex"

    # Verify XML Keybox structure
    if ! grep -q '<Keybox' "$xml_out" || ! grep -q '</Keybox>' "$xml_out"; then
        rm -f "$xml_out"
        return 2
    fi

    # Verify certificate dates
    local cert_b64 strings_out dates not_before not_after start_epoch end_epoch now_epoch
    cert_b64=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$xml_out" | head -n 35 | grep -v 'CERTIFICATE' | tr -d ' \n\r\t')
    [ -n "$cert_b64" ] || { rm -f "$xml_out"; return 3; }

    strings_out=$(printf '%s' "$cert_b64" | base64 -d 2>/dev/null | strings)
    dates=$(printf '%s\n' "$strings_out" | grep -oE '[0-9]{12}Z')
    not_before=$(printf '%s\n' "$dates" | head -n 1)
    not_after=$(printf '%s\n' "$dates" | tail -n 1)

    start_epoch=$(parse_epoch "$not_before")
    end_epoch=$(parse_epoch "$not_after")
    now_epoch=$(date +%s)

    if [ "$now_epoch" -lt "$start_epoch" ] || [ "$now_epoch" -gt "$end_epoch" ]; then
        log " ✦ Variant certificate has expired ($not_before to $not_after)"
        rm -f "$xml_out"
        return 4
    fi

    return 0
}

# Key variants list (Megatron2 valid until 2032)
VARIANTS="${1:-Megatron Megatron2}"
SUCCESS=0

log "••••••• KEYBOX PROVISIONER (INTEGRITY BOX OFFICIAL) •••••••"

for variant in $VARIANTS; do
    log " ✦ Checking Integrity Box variant: $variant..."
    KEYBOX_URL="https://github.com/MeowDump/Integrity-Box/releases/download/archive/$variant"
    TEMP_FILE="$(mktemp -p /dev)"
    
    if [ -f "$RECORD/keyswitch" ]; then
        fail_safe_download "$KEYBOX_URL" "$TEMP_FILE"
    else
        _try_download "$KEYBOX_URL" "$TEMP_FILE" "curl" || _try_download "$KEYBOX_URL" "$TEMP_FILE" "wget" || fail_safe_download "$KEYBOX_URL" "$TEMP_FILE"
    fi

    if [ ! -s "$TEMP_FILE" ]; then
        log " ✦ Variant $variant: Download failed or empty, trying next..."
        rm -f "$TEMP_FILE"
        continue
    fi

    CANDIDATE_XML="$(mktemp -p /dev)"
    if decode_and_validate "$TEMP_FILE" "$CANDIDATE_XML"; then
        log " ✦ Variant $variant: Decoded and verified successfully!"
        
        # Deploy atomically
        cp -f "$CANDIDATE_XML" "$KEYBOX"
        chmod 644 "$KEYBOX" 2>/dev/null
        chown root:root "$KEYBOX" 2>/dev/null
        killall -TERM keystore2 2>/dev/null || true

        # Synchronize Oh My KeyMint if enabled by user (v46 standard)
        OMK_DIR="/data/misc/keystore/omk"
        OMK_MODULE="/data/adb/modules/oh_my_keymint"
        if [ -d "$OMK_MODULE" ] && [ ! -f "$OMK_MODULE/disable" ]; then
            if [ -f "$RECORD/omk-key" ] && [ -d "$OMK_DIR" ]; then
                cp -f "$KEYBOX" "$OMK_DIR/keybox.xml"
                log " ✦ Attestation loaded to KeyMint"
            fi
        fi

        # Synchronize TEE-SIM if enabled by user (v46 standard)
        SIM_MODULE="/data/adb/modules/teesim"
        if [ -d "$SIM_MODULE" ] && [ ! -f "$SIM_MODULE/disable" ]; then
            if [ -f "$RECORD/sim-key" ] && [ -d "/data/adb/teesim" ]; then
                cp -f "$KEYBOX" "$SIM_KEY"
                chmod 600 "$SIM_KEY"
                log " ✦ Attestation loaded to TEE-SIM"
            fi
        fi

        # Synchronize WebUI catalog_test
        if [ -d "$RECORD/catalog_test" ]; then
            cp -f "$KEYBOX" "$RECORD/catalog_test/keybox.xml"
        fi

        rm -f "$TEMP_FILE" "$CANDIDATE_XML"
        SUCCESS=1
        log " ✦ Keybox upgrade complete using variant $variant"
        break
    else
        log " ✦ Variant $variant: Rejected (invalid or expired). Trying next variant..."
        rm -f "$TEMP_FILE" "$CANDIDATE_XML"
    fi
done

if [ -f "$CLEANUP" ]; then
    sh "$CLEANUP" >/dev/null 2>&1
elif [ -f "$UCLEANUP" ]; then
    sh "$UCLEANUP" >/dev/null 2>&1
fi

if [ "$SUCCESS" -eq 1 ]; then
    exit 0
else
    log " ✦ ERROR: All Integrity Box variants exhausted without valid keybox"
    if [ -s "$KEYBOX_BACKUP" ]; then
        cp -f "$KEYBOX_BACKUP" "$KEYBOX"
        log " ✦ Restored backup keybox"
    fi
    exit 7
fi
