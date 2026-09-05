#!/system/bin/sh

set -e

OUTPUT_DIR="/sdcard/BootImages"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SLOT=""
LOG_FILE="/data/adb/Box-Brain/Integrity-Box-Logs/BootExtract.log"

mkdir -p "$(dirname "$LOG_FILE")" "$OUTPUT_DIR"
: > "$LOG_FILE"

log() {
    echo "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

raw() {
    echo "$1"
    echo "$1" >> "$LOG_FILE"
}

info() { log "[INFO] $1"; }
ok() { log "[OK] $1"; }
warn() { log "[WARN] $1"; }
error() { log "[ERROR] $1"; }

header() {
  echo "
  ___     _                _ _        
 |_ _|_ _| |_ ___ __ _ _ _(_) |_ _  _ 
  | || ' \  _/ -_) _  | '_| |  _| || |
 |___|_||_\__\___\__, |_| |_|\__|\_, |
 | _ ) _____ __  |___/           |__/ 
 | _ \/ _ \ \ /                       
 |___/\___/_\_\                       
                                                
"
}

banner() {
    raw "  Universal Boot Image Extractor"
    raw "  ==================================="
    raw ""
    raw ""
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Root access required. Run with 'su -c ./extract_boot.sh'"
        exit 1
    fi
    ok "Root access confirmed"
}

detect_slot() {
    SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
    if [ -z "$SLOT" ]; then
        SLOT=""
        info "A-only device detected"
    else
        info "A/B device detected. Active slot: ${SLOT}"
    fi
}

find_partition() {
    local name="$1"
    local found=""

    found=$(find /dev/block \( -type b -o -type c -o -type l \) -iname "$name" -print -quit 2>/dev/null)
    if [ -n "$found" ]; then
        found=$(readlink -f "$found" 2>/dev/null || echo "$found")
    fi

    echo "$found"
}

get_partition_size() {
    local dev="$1"
    local size_bytes=""
    local blockname=""

    if [ -L "$dev" ]; then
        dev=$(readlink -f "$dev" 2>/dev/null || echo "$dev")
    fi

    blockname=$(basename "$dev" 2>/dev/null)
    if [ -f "/sys/class/block/${blockname}/size" ]; then
        size_bytes=$(cat "/sys/class/block/${blockname}/size" 2>/dev/null)
        if [ -n "$size_bytes" ] && [ "$size_bytes" -gt 0 ] 2>/dev/null; then
            echo "$((size_bytes * 512))"
            return
        fi
    fi

    if command -v blockdev >/dev/null 2>&1; then
        size_bytes=$(blockdev --getsize64 "$dev" 2>/dev/null)
        if [ -n "$size_bytes" ] && [ "$size_bytes" -gt 0 ] 2>/dev/null; then
            echo "$size_bytes"
            return
        fi
    fi

    echo "0"
}

format_size() {
    local bytes="$1"
    if [ "$bytes" = "0" ] || [ -z "$bytes" ]; then
        echo "unknown"
        return
    fi
    if [ "$bytes" -ge 1073741824 ] 2>/dev/null; then
        echo "$((bytes / 1024 / 1024 / 1024))G"
    elif [ "$bytes" -ge 1048576 ] 2>/dev/null; then
        echo "$((bytes / 1024 / 1024))M"
    elif [ "$bytes" -ge 1024 ] 2>/dev/null; then
        echo "$((bytes / 1024))K"
    else
        echo "${bytes}B"
    fi
}

extract_partition() {
    local part_name="$1"
    local output_name="$2"
    local block_dev=""
    local size_bytes=""
    local size_human=""
    local output_file=""
    local out_bytes=""
    local out_human=""

    block_dev=$(find_partition "$part_name")

    if [ -z "$block_dev" ]; then
        warn "Partition '$part_name' not found"
        return 1
    fi

    size_bytes=$(get_partition_size "$block_dev")
    size_human=$(format_size "$size_bytes")
    output_file="$OUTPUT_DIR/${output_name}_${TIMESTAMP}.img"

    info "Extracting $part_name -> $output_file (size: $size_human)"

    if dd if="$block_dev" of="$output_file" bs=1048576 2>/dev/null; then
        out_bytes=$(ls -l "$output_file" 2>/dev/null | awk '{print $5}')
        out_human=$(format_size "$out_bytes")
        ok "Extracted $part_name ($out_human)"
        return 0
    else
        error "Failed to extract $part_name"
        return 1
    fi
}

verify_bootimg() {
    local file="$1"
    local magic=""
    local vmagic=""

    if [ ! -f "$file" ]; then
        return 1
    fi

    magic=$(dd if="$file" bs=1 count=8 2>/dev/null)
    if [ "$magic" = "ANDROID!" ]; then
        return 0
    fi

    vmagic=$(dd if="$file" bs=1 count=8 2>/dev/null)
    if [ "$vmagic" = "VNDRBOOT" ]; then
        return 0
    fi

    return 1
}

list_partitions() {
    local found_any=0
    local dev=""
    local size_bytes=""
    local size_human=""
    local ts=""

    info "Scanning available partitions..."
    raw ""
    raw "Available boot-related partitions:"
    raw "-----------------------------------"

    for part in boot boot_a boot_b vendor_boot vendor_boot_a vendor_boot_b recovery dtbo dtbo_a dtbo_b vbmeta vbmeta_a vbmeta_b; do
        dev=$(find_partition "$part")
        if [ -n "$dev" ]; then
            size_bytes=$(get_partition_size "$dev")
            size_human=$(format_size "$size_bytes")
            ts=$(date '+%Y-%m-%d %H:%M:%S')
            printf "  %-20s %-30s (%s)\n" "$part" "$dev" "$size_human"
            printf "[%s]   %-20s %-30s (%s)\n" "$ts" "$part" "$dev" "$size_human" >> "$LOG_FILE"
            found_any=1
        fi
    done

    if [ "$found_any" -eq 0 ]; then
        warn "No standard partitions found"
        find /dev/block -maxdepth 4 \( -iname "*boot*" -o -iname "*recovery*" \) 2>/dev/null | head -20 | while IFS= read -r line; do
            raw "$line"
        done
    fi
    raw ""
}

main() {
    local extract_vendor_boot=0
    local extract_dtbo=0
    local extract_vbmeta=0
    local extract_all=0
    local extracted_count=0
    local targets=""
    local target=""
    local latest_file=""

    header
    
    banner

    check_root

    info "Output directory: $OUTPUT_DIR"

    detect_slot

    list_partitions

    while [ $# -gt 0 ]; do
        case "$1" in
            --vendor-boot|-v) extract_vendor_boot=1 ;;
            --dtbo|-d) extract_dtbo=1 ;;
            --vbmeta|-V) extract_vbmeta=1 ;;
            --all|-a) extract_all=1 ;;
            --help|-h)
                raw "Usage: $0 [OPTIONS]"
                raw ""
                raw "Options:"
                raw "  --all, -a          Extract boot + vendor_boot + dtbo + vbmeta"
                raw "  --vendor-boot, -v  Also extract vendor_boot"
                raw "  --dtbo, -d         Also extract dtbo"
                raw "  --vbmeta, -V       Also extract vbmeta"
                raw "  --help, -h         Show this help"
                raw ""
                raw "Examples:"
                raw "  su -c ./extract_boot.sh"
                raw "  su -c ./extract_boot.sh --all"
                exit 0
                ;;
            *) warn "Unknown option: $1" ;;
        esac
        shift
    done

    if [ "$extract_all" -eq 1 ]; then
        extract_vendor_boot=1
        extract_dtbo=1
        extract_vbmeta=1
    fi

    targets="boot"

    if [ -n "$SLOT" ]; then
        targets="$targets boot${SLOT}"
    fi

    if [ "$extract_vendor_boot" -eq 1 ]; then
        targets="$targets vendor_boot"
        if [ -n "$SLOT" ]; then
            targets="$targets vendor_boot${SLOT}"
        fi
    fi

    if [ "$extract_dtbo" -eq 1 ]; then
        targets="$targets dtbo"
        if [ -n "$SLOT" ]; then
            targets="$targets dtbo${SLOT}"
        fi
    fi

    if [ "$extract_vbmeta" -eq 1 ]; then
        targets="$targets vbmeta"
        if [ -n "$SLOT" ]; then
            targets="$targets vbmeta${SLOT}"
        fi
    fi

    targets=$(echo "$targets" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    raw ""
    info "Starting extraction..."
    raw "-----------------------------------"

    for target in $targets; do
        if extract_partition "$target" "$target"; then
            extracted_count=$((extracted_count + 1))

            latest_file=$(ls -t "$OUTPUT_DIR/${target}_${TIMESTAMP}.img" 2>/dev/null | head -1)
            if [ -n "$latest_file" ]; then
                if verify_bootimg "$latest_file"; then
                    ok "Verified: $target is valid Android boot image"
                else
                    warn "$target may not be a standard boot image"
                fi
            fi
        fi
    done

    if [ "$extracted_count" -eq 0 ] && [ -z "$SLOT" ]; then
        info "No boot found. Trying recovery partition..."
        if extract_partition "recovery" "recovery"; then
            extracted_count=$((extracted_count + 1))
            warn "Recovery extracted. On some devices, recovery IS the boot image."
        fi
    fi

    raw ""
    raw "==================================="
    raw "  Extraction Complete"
    raw "==================================="
    raw ""
    info "Files saved to: $OUTPUT_DIR"
    raw ""

    ls -lh "$OUTPUT_DIR"/*_${TIMESTAMP}.img 2>/dev/null | while IFS= read -r line; do
        raw "$line"
    done || true
    raw ""

    if [ "$extracted_count" -gt 0 ]; then
        ok "Successfully extracted $extracted_count partition(s)"
        info "Use this boot.img to root your device with Apatch / Folkpatch or Magisk."
    else
        error "No partitions could be extracted."
    fi

    raw ""
}

main "$@"
