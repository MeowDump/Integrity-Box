#!/system/bin/sh

[ -f "/data/adb/Box-Brain/kernel" ] || exit 0

RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-arm64-v8a"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-armeabi-v7a"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86_64"
[ -x "$RESETPROP_RS" ] || RESETPROP_RS="/data/adb/modules/playintegrityfix/resetprop-rs/resetprop-x86"
[ -x "$RESETPROP_RS" ] || exit 1

LOG="/data/adb/Box-Brain/Integrity-Box-Logs/kernel.log"
mkdir -p "$(dirname "$LOG")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

FLAG_DIR="/data/adb/Box-Brain"

# build time
if [ -f "$FLAG_DIR/buildtime" ]; then
    KERNEL_BUILD=$(uname -v | sed 's/.*PREEMPT //')
    MONTH=$(echo "$KERNEL_BUILD" | awk '{print $2}')
    DAY=$(echo "$KERNEL_BUILD" | awk '{print $3}')
    TIME=$(echo "$KERNEL_BUILD" | awk '{print $4}')
    YEAR=$(echo "$KERNEL_BUILD" | awk '{print $6}')

    case "$MONTH" in
        Jan) M=01;; Feb) M=02;; Mar) M=03;; Apr) M=04;; May) M=05;; Jun) M=06;;
        Jul) M=07;; Aug) M=08;; Sep) M=09;; Oct) M=10;; Nov) M=11;; Dec) M=12;;
    esac

    EPOCH=$(date -d "$YEAR-$M-$DAY $TIME" +%s 2>/dev/null || echo "")
    SEC_PATCH="$YEAR-$M-05"

    "$RESETPROP_RS" ro.build.date "$KERNEL_BUILD"
    "$RESETPROP_RS" ro.build.date.utc "$EPOCH"
    "$RESETPROP_RS" ro.build.version.security_patch "$SEC_PATCH"

    log "buildTime: $KERNEL_BUILD | epoch=$EPOCH | patch=$SEC_PATCH"
fi

# Strip kernel name strings
if [ -f "$FLAG_DIR/customkernel" ]; then
    for PROP in ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags ro.build.type; do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed -E 's/Blaze|blaze|BLAZE|custom|CUSTOM|kernel|KERNEL//g; s/-v[0-9]+//g; s/_{2,}/_/g; s/^_|_$//g')
        [ "$CLEAN" != "$VAL" ] && {
            "$RESETPROP_RS" "$PROP" "$CLEAN"
            log "customKernel/$PROP: $VAL → $CLEAN"
        }
    done
fi

# Strip emoji-related strings
if [ -f "$FLAG_DIR/emoji" ]; then
    for PROP in ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags; do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed 's/[😀-?]//g; s/[🀀-🃏]//g; s/[🄀-🇿]//g; s/emoji//gi; s/ Emoji//gi')
        [ "$CLEAN" != "$VAL" ] && {
            "$RESETPROP_RS" "$PROP" "$CLEAN"
            log "emojiScan/$PROP: sanitized"
        }
    done
fi

# Strip Chinese characters
if [ -f "$FLAG_DIR/chinese" ]; then
    for PROP in ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor; do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed 's/[一-龯]//g; s/[ぁ-ゔ]//g; s/[ァ-ヴ]//g; s/chinese//gi')
        [ "$CLEAN" != "$VAL" ] && {
            "$RESETPROP_RS" "$PROP" "$CLEAN"
            log "chineseScan/$PROP: sanitized"
        }
    done
fi

# Strip script-related strings
if [ -f "$FLAG_DIR/script" ]; then
    for PROP in ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor; do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed 's/script//gi; s/Script//gi; s/SCRIPT//gi')
        [ "$CLEAN" != "$VAL" ] && {
            "$RESETPROP_RS" "$PROP" "$CLEAN"
            log "scriptScan/$PROP: $VAL → $CLEAN"
        }
    done
fi

# Strip Telegram-related strings
if [ -f "$FLAG_DIR/telegram" ]; then
    for PROP in ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor ro.build.tags; do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed 's/telegram//gi; s/Telegram//gi; s/TELEGRAM//gi; s/t\\.me//gi; s/@//g')
        [ "$CLEAN" != "$VAL" ] && {
            "$RESETPROP_RS" "$PROP" "$CLEAN"
            log "telegramScan/$PROP: $VAL → $CLEAN"
        }
    done
fi

# Strip mention-related strings
if [ -f "$FLAG_DIR/mention" ]; then
    for PROP in ro.build.id ro.build.display.id ro.build.version.incremental ro.build.flavor; do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed 's/mention//gi; s/Mention//gi; s/@//g; s/@[a-zA-Z0-9_]*//g')
        [ "$CLEAN" != "$VAL" ] && {
            "$RESETPROP_RS" "$PROP" "$CLEAN"
            log "mentionScan/$PROP: $VAL → $CLEAN"
        }
    done
fi

# Sanitize boot-derived props
if [ -f "$FLAG_DIR/cmdline" ]; then
    for PROP in ro.boot.bootloader ro.boot.baseband ro.boot.hardware ro.boot.hardware.sku ro.boot.revision; do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed -E 's/Blaze|blaze|BLAZE|custom|CUSTOM|kernel|KERNEL//g; s/-v[0-9]+//g')
        [ "$CLEAN" != "$VAL" ] && {
            "$RESETPROP_RS" "$PROP" "$CLEAN"
            log "cmdlineCheck/$PROP: $VAL → $CLEAN"
        }
    done

    "$RESETPROP_RS" ro.boot.vbmeta.device_state "locked"
    "$RESETPROP_RS" ro.boot.verifiedbootstate "green"
    "$RESETPROP_RS" ro.boot.veritymode "enforcing"

    log "cmdlineCheck: boot state normalized"
fi

# Sanitize platform props
if [ -f "$FLAG_DIR/board" ]; then
    for PROP in ro.product.board ro.board.platform ro.hardware ro.system.build.board; do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        CLEAN=$(echo "$VAL" | sed -E 's/Blaze|blaze|BLAZE|custom|CUSTOM|kernel|KERNEL//g; s/-v[0-9]+//g; s/_{2,}/_/g')
        [ "$CLEAN" != "$VAL" ] && {
            "$RESETPROP_RS" "$PROP" "$CLEAN"
            log "board/$PROP: $VAL → $CLEAN"
        }
    done
fi

# Deep scan all ro.boot.* props
if [ -f "$FLAG_DIR/scanall" ]; then
    SUSPICIOUS="Lineage|lineage|LINEAGE|custom|CUSTOM|kernel|KERNEL|telegram|TELEGRAM|emoji|script|chinese|mention"
    for PROP in $(("$RESETPROP_RS" -Z 2>/dev/null | grep "^ro.boot\." | cut -d' ' -f1)); do
        VAL=$("$RESETPROP_RS" "$PROP" 2>/dev/null)
        [ -z "$VAL" ] && continue
        echo "$VAL" | grep -qiE "$SUSPICIOUS" || continue
        CLEAN=$(echo "$VAL" | sed -E "s/$SUSPICIOUS//g; s/-v[0-9]+//g")
        "$RESETPROP_RS" "$PROP" "$CLEAN"
        log "scanAll/$PROP: $VAL → $CLEAN"
    done
fi

log "Kernel sanitization complete"

