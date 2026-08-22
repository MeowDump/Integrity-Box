#!/system/bin/sh

LOG="/data/adb/Box-Brain/Integrity-Box-Logs/kernel.log"
mkdir -p "$(dirname "$LOG")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

FLAG_DIR="/data/adb/Box-Brain"

# sanitize a list of props with a sed expression
sanitize_props() {
    local flag_file="$1"
    local label="$2"
    local sed_expr="$3"
    shift 3
    local props="$*"
    
    [ -f "$flag_file" ] || return 0
    
    local PROP VAL CLEAN
    for PROP in $props; do
        VAL=$(resetprop "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed -E "$sed_expr")
        [ "$CLEAN" != "$VAL" ] && {
            resetprop -n "$PROP" "$CLEAN"
            log "$label/$PROP: $VAL → $CLEAN"
        }
    done
}

# build time
if [ -f "$FLAG_DIR/buildtime" ]; then
    KERNEL_BUILD=$(uname -v | sed 's/.*PREEMPT //; s/.*SMP //')
    
    MONTH=$(echo "$KERNEL_BUILD" | awk '{print $2}')
    DAY=$(echo "$KERNEL_BUILD" | awk '{print $3}')
    TIME=$(echo "$KERNEL_BUILD" | awk '{print $4}')
    YEAR=$(echo "$KERNEL_BUILD" | awk '{print $6}')
    
    case "$MONTH" in
        Jan) M=01;; Feb) M=02;; Mar) M=03;; Apr) M=04;; May) M=05;; Jun) M=06;;
        Jul) M=07;; Aug) M=08;; Sep) M=09;; Oct) M=10;; Nov) M=11;; Dec) M=12;;
    esac
    
    EPOCH=$(date -d "$YEAR-$M-$DAY $TIME" +%s 2>/dev/null || echo "0")
    SEC_PATCH="$YEAR-$M-05"
    
    resetprop -n ro.build.date "$KERNEL_BUILD"
    resetprop -n ro.build.date.utc "$EPOCH"
    resetprop -n ro.build.version.security_patch "$SEC_PATCH"
    
    log "buildTime: $KERNEL_BUILD | epoch=$EPOCH | patch=$SEC_PATCH"
fi

# Strip kernel name strings
sanitize_props "$FLAG_DIR/customkernel" "customKernel" \
    's/Blaze|blaze|BLAZE|custom|CUSTOM|kernel|KERNEL//g; s/-v[0-9]+//g; s/_{2,}/_/g; s/^_|_$//g' \
    ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags ro.build.type

# Strip emoji-related strings
sanitize_props "$FLAG_DIR/emoji" "emojiScan" \
    's/[😀-🿿]//g; s/[🀀-🃏]//g; s/[🄀-🇿]//g; s/emoji//gi; s/ Emoji//gi' \
    ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags ro.build.type

# Strip Chinese characters
sanitize_props "$FLAG_DIR/chinese" "chineseScan" \
    's/[一-龯]//g; s/[ぁ-ゔ]//g; s/[ァ-ヴ]//g; s/chinese//gi' \
    ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags ro.build.type

# Strip script-related strings
sanitize_props "$FLAG_DIR/script" "scriptScan" \
    's/script//gi; s/Script//gi; s/SCRIPT//gi' \
    ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags ro.build.type

# Strip Telegram-related strings
sanitize_props "$FLAG_DIR/telegram" "telegramScan" \
    's/telegram//gi; s/Telegram//gi; s/TELEGRAM//gi; s/t\.me//gi; s/@//g' \
    ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags ro.build.type

# Strip mention-related strings
sanitize_props "$FLAG_DIR/mention" "mentionScan" \
    's/mention//gi; s/Mention//gi; s/@//g; s/@[a-zA-Z0-9_]*//g' \
    ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags ro.build.type

# Sanitize boot-derived props
if [ -f "$FLAG_DIR/cmdline" ]; then
    sanitize_props "$FLAG_DIR/cmdline" "cmdlineCheck" \
        's/Blaze|blaze|BLAZE|custom|CUSTOM|kernel|KERNEL//g; s/-v[0-9]+//g' \
        ro.boot.bootloader ro.boot.baseband ro.boot.hardware ro.boot.hardware.sku ro.boot.revision
    
    resetprop -n ro.boot.vbmeta.device_state "locked"
    resetprop -n ro.boot.verifiedbootstate "green"
    resetprop -n ro.boot.veritymode "enforcing"
    
    log "cmdlineCheck: boot state normalized"
fi

# Sanitize platform props
sanitize_props "$FLAG_DIR/board" "board" \
    's/Blaze|blaze|BLAZE|custom|CUSTOM|kernel|KERNEL//g; s/-v[0-9]+//g; s/_{2,}/_/g' \
    ro.product.board ro.board.platform ro.hardware ro.system.build.board

# Deep scan all ro.boot.* props
if [ -f "$FLAG_DIR/scanall" ]; then
    SUSPICIOUS="Lineage|lineage|LINEAGE|custom|CUSTOM|kernel|KERNEL|telegram|TELEGRAM|emoji|script|chinese|mention"
    
    local PROP VAL CLEAN
    for PROP in $(resetprop -Z 2>/dev/null | grep "^ro.boot\." | cut -d' ' -f1); do
        VAL=$(resetprop "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        echo "$VAL" | grep -qiE "$SUSPICIOUS" || continue
        CLEAN=$(echo "$VAL" | sed -E "s/$SUSPICIOUS//g; s/-v[0-9]+//g")
        resetprop -n "$PROP" "$CLEAN"
        log "scanAll/$PROP: $VAL → $CLEAN"
    done
fi

log "Kernel sanitization complete"
