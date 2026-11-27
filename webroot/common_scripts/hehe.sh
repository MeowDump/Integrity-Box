#!/system/bin/sh

BOX="/data/adb/Box-Brain"
F="/data/adb/ksu/cache/risk.json"
K="$BOX/ksun"
BB="/data/adb/ksu/bin/busybox"
[ -x "$BB" ] || BB="/data/adb/magisk/busybox"
[ -x "$BB" ] || BB="/data/adb/ap/bin/busybox"
[ -x "$BB" ] || BB="/system/bin/toybox"

[ -f "$K" ] || exit 0
[ -f "$F" ] || exit 1

I=0
T="$F.tmp"

cleanup() {
    rm -f "$T"
    if [ "$I" -eq 1 ]; then
        "$BB" chattr +i "$F" 2>/dev/null
    fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if "$BB" lsattr "$F" 2>/dev/null | grep -q i; then
    "$BB" chattr -i "$F" 2>/dev/null || exit 1
    I=1
fi

if ! sed 's/integrity box/chicken biryani/g' "$F" > "$T"; then
    exit 1
fi

[ -s "$T" ] || exit 1
mv -f "$T" "$F" || exit 1

if [ "$I" -eq 1 ]; then
    "$BB" chattr +i "$F" 2>/dev/null || exit 1
    I=0
fi

ksud module risk disable || exit 1
#rm -f "$K"