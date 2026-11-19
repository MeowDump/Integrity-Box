#!/system/bin/sh

TSIM_DIR="/data/adb/teesim"
CONFIG_JSON="$TSIM_DIR/config.json"
PIF_PROP="/data/adb/modules/playintegrityfix/custom.pif.prop"
SEC_PATCH="/data/adb/tricky_store/security_patch.txt"
TARGET_TXT="/data/adb/tricky_store/target.txt"

[ -f "$CONFIG_JSON" ] || exit 0
[ -f "$PIF_PROP" ] || exit 0
[ -f "$SEC_PATCH" ] || exit 0
[ -f "$TARGET_TXT" ] || exit 0

TMP="${CONFIG_JSON}.tmp.$$"
APPS_TMP="/data/local/tmp/.teesim_apps_$$"

NOW_MONTHS=0
NOW_YEAR=$(date +%Y 2>/dev/null)
NOW_MON=$(date +%m 2>/dev/null)
case "$NOW_YEAR$NOW_MON" in
    ''|*[!0-9]*) ;;
    *) [ "$NOW_YEAR" -ge 2020 ] && NOW_MONTHS=$((NOW_YEAR * 12 + NOW_MON)) ;;
esac

AWK_LIB='
function days_in_month(y, m) {
    if (m == 2) {
        if ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) return 29
        return 28
    }
    if (m == 4 || m == 6 || m == 9 || m == 11) return 30
    return 31
}

function okdate(d,    y, m, day) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
    y = substr(d, 1, 4) + 0
    m = substr(d, 6, 2) + 0
    day = substr(d, 9, 2) + 0
    if (m < 1 || m > 12) return 0
    if (day < 1 || day > days_in_month(y, m)) return 0
    return 1
}

function too_old(d, months,    y, m) {
    if (months <= 0) return 0
    y = substr(d, 1, 4) + 0
    m = substr(d, 6, 2) + 0
    return (y * 12 + m) < months - 12
}

function valof(line, key,    head, tail, at) {
    head = "\"" key "\""
    if ((at = index(line, head)) == 0) return ""
    tail = substr(line, at + length(head))
    if (tail !~ /^[[:space:]]*:[[:space:]]*"/) return ""
    sub(/^[[:space:]]*:[[:space:]]*"/, "", tail)
    if ((at = index(tail, "\"")) == 0) return ""
    return substr(tail, 1, at - 1)
}

function setstr(line, key, val,    head, tail, at) {
    head = "\"" key "\""
    if ((at = index(line, head)) == 0) return line
    tail = substr(line, at + length(head))
    if (tail !~ /^[[:space:]]*:[[:space:]]*"/) return line
    sub(/^[[:space:]]*:[[:space:]]*"[^"]*"/, "", tail)
    return substr(line, 1, at - 1) head ": \"" val "\"" tail
}

function json_ok(s,    i, n, c, stack, instr, esc, want) {
    n = length(s)
    stack = ""
    instr = 0
    esc = 0
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (instr) {
            if (esc) { esc = 0; continue }
            if (c == "\\") { esc = 1; continue }
            if (c == "\"") instr = 0
            continue
        }
        if (c == "\"") { instr = 1; continue }
        if (c == "{" || c == "[") { stack = stack c; continue }
        if (c == "}" || c == "]") {
            want = (c == "}") ? "{" : "["
            if (stack == "") return 0
            if (substr(stack, length(stack), 1) != want) return 0
            stack = substr(stack, 1, length(stack) - 1)
            continue
        }
    }
    return (instr == 0 && stack == "")
}
'

fail() {
    rm -f "$TMP" "$APPS_TMP"
    echo "teesim: $1" >&2
    exit 0
}

is_date() {
    CAND="$1" awk "$AWK_LIB"'BEGIN { exit !okdate(ENVIRON["CAND"]) }'
}

is_too_old() {
    [ "$NOW_MONTHS" -gt 0 ] || return 1
    CAND="$1" LIMIT="$NOW_MONTHS" awk \
        "$AWK_LIB"'BEGIN { exit !too_old(ENVIRON["CAND"], ENVIRON["LIMIT"] + 0) }'
}

get_pif() {
    grep -m1 -i "^$1=" "$PIF_PROP" 2>/dev/null | cut -d '=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

esc_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

BRAND=$(esc_json "$(get_pif "BRAND")")
DEVICE=$(esc_json "$(get_pif "DEVICE")")
PRODUCT=$(esc_json "$(get_pif "PRODUCT")")
MANUFACTURER=$(esc_json "$(get_pif "MANUFACTURER")")
MODEL=$(esc_json "$(get_pif "MODEL")")

PIF_PATCH=$(get_pif "SECURITY_PATCH")
is_date "$PIF_PATCH" || PIF_PATCH=""

PROP_PATCH=$(getprop ro.build.version.security_patch 2>/dev/null | tr -d ' \t\r\n')
is_date "$PROP_PATCH" || PROP_PATCH=""
is_too_old "$PROP_PATCH" && PROP_PATCH=""

GENERIC_PATCH=""
[ "$NOW_MONTHS" -gt 0 ] && GENERIC_PATCH=$(date +%Y-%m-05 2>/dev/null)
is_date "$GENERIC_PATCH" || GENERIC_PATCH=""

patch_from_file() {
    val=$(grep -m1 -i "^$1=" "$SEC_PATCH" 2>/dev/null | cut -d '=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    is_date "$val" && { printf '%s' "$val"; return 0; }
    val=$(grep -m1 -i "^all=" "$SEC_PATCH" 2>/dev/null | cut -d '=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    is_date "$val" && { printf '%s' "$val"; return 0; }
    return 1
}

resolve_patch() {
    patch_from_file "$1" && return 0
    [ -n "$PIF_PATCH" ] && { printf '%s' "$PIF_PATCH"; return 0; }
    [ -n "$PROP_PATCH" ] && { printf '%s' "$PROP_PATCH"; return 0; }
    [ -n "$GENERIC_PATCH" ] && { printf '%s' "$GENERIC_PATCH"; return 0; }
    return 1
}

SYSTEM_PATCH=$(resolve_patch "system") || fail "no usable security patch level"
VENDOR_PATCH=$(resolve_patch "vendor") || fail "no usable security patch level"
BOOT_PATCH=$(resolve_patch "boot") || fail "no usable security patch level"

> "$APPS_TMP" || fail "cannot write the apps list"
while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    pkg=$(printf '%s' "$line" | tr -d '\r' | sed 's/[!?]$//')
    [ -z "$pkg" ] && continue
    printf '        "%s"\n' "$(esc_json "$pkg")" >> "$APPS_TMP"
done < "$TARGET_TXT"

MODE=$(awk "$AWK_LIB"'{ if (m == "") m = valof($0, "mode") } END { print m }' "$CONFIG_JSON")
case "$MODE" in
    patch|generation) ;;
    *) MODE="patch" ;;
esac
HAS_MODE=0
grep -q '"mode"[[:space:]]*:' "$CONFIG_JSON" && HAS_MODE=1

OS_RELEASE=$(getprop ro.build.version.release 2>/dev/null | tr -d ' \t\r\n')
case "$OS_RELEASE" in ''|*[!0-9]*) OS_RELEASE="17" ;; esac

APPS="$APPS_TMP" BRAND="$BRAND" DEVICE="$DEVICE" PRODUCT="$PRODUCT" \
MANUFACTURER="$MANUFACTURER" MODEL="$MODEL" OSV="$OS_RELEASE" MODE="$MODE" \
HAS_MODE="$HAS_MODE" SP="$SYSTEM_PATCH" VP="$VENDOR_PATCH" BP="$BOOT_PATCH" \
awk "$AWK_LIB"'
BEGIN {
    apps_file = ENVIRON["APPS"]
    while ((getline item < apps_file) > 0) items[++n] = item
    close(apps_file)
}
{
    if (skip == 1) {
        if ($0 ~ /\]/) {
            print
            skip = 0
        }
        next
    }
    line = $0
    if (lvl == 0 && line ~ /"patchLevel"[[:space:]]*:[[:space:]]*\{/) lvl = 1
    if (lvl == 1) {
        line = setstr(line, "system", ENVIRON["SP"])
        line = setstr(line, "vendor", ENVIRON["VP"])
        line = setstr(line, "boot", ENVIRON["BP"])
        if (line ~ /\}/) lvl = 0
    }
    line = setstr(line, "osVersion", ENVIRON["OSV"])
    line = setstr(line, "brand", ENVIRON["BRAND"])
    line = setstr(line, "device", ENVIRON["DEVICE"])
    line = setstr(line, "product", ENVIRON["PRODUCT"])
    line = setstr(line, "manufacturer", ENVIRON["MANUFACTURER"])
    line = setstr(line, "model", ENVIRON["MODEL"])
    line = setstr(line, "mode", ENVIRON["MODE"])
    if (apps == 0 && match(line, /"apps"[[:space:]]*:[[:space:]]*\[/)) {
        apps = 1
        head = substr(line, 1, RSTART + RLENGTH - 1)
        tail = substr(line, RSTART + RLENGTH)
        match(line, /^[[:space:]]*/)
        indent = substr(line, RSTART, RLENGTH)
        print head
        for (i = 1; i <= n; i++) print items[i] (i < n ? "," : "")
        if ((at = index(tail, "]")) > 0) print indent substr(tail, at)
        else skip = 1
        next
    }
    print line
    if (ENVIRON["HAS_MODE"] + 0 == 0 && added == 0 && line ~ /"keybox"[[:space:]]*:/) {
        match(line, /^[[:space:]]*/)
        print substr(line, RSTART, RLENGTH) "\"mode\": \"" ENVIRON["MODE"] "\","
        added = 1
    }
}' "$CONFIG_JSON" > "$TMP" || fail "could not rewrite the config"

awk "$AWK_LIB"'
{ buf = buf $0 "\n" }
END {
    if (!json_ok(buf)) exit 1
    if (index(buf, "\"keybox\"") == 0) exit 1
    if (index(buf, "\"apps\"") == 0) exit 1
    at = index(buf, "\"patchLevel\"")
    if (at == 0) exit 1
    seg = substr(buf, at)
    at = index(seg, "}")
    if (at == 0) exit 1
    seg = substr(seg, 1, at)
    if (!okdate(valof(seg, "system"))) exit 1
    if (!okdate(valof(seg, "vendor"))) exit 1
    if (!okdate(valof(seg, "boot"))) exit 1
    if (valof(buf, "osVersion") !~ /^[0-9][0-9]*$/) exit 1
    md = valof(buf, "mode")
    if (md != "patch" && md != "generation") exit 1
}' "$TMP" || fail "generated config rejected, previous config kept"

mv -f "$TMP" "$CONFIG_JSON"
rm -f "$APPS_TMP"
exit 0
