#!/bin/sh
# Host test of refresh_pif_fingerprint (common_func.sh): when may the Action button fall back to the
# legacy osm0sis.sh generator? Run: sh autopilot-v2/test_action_pif.sh
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT INT TERM
PASS=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# the function under test, extracted verbatim (common_func.sh is not safe to source on a host)
sed -n '/^refresh_pif_fingerprint() {/,/^}/p' "$HERE/../common_func.sh" > "$W/fn.sh"
[ -s "$W/fn.sh" ] || fail "function not found in common_func.sh"

run_case() { # NAME ENGINE_PRESENT(1|0) ENGINE_RC EXPECT_LEGACY(1|0)
    d="$W/$1"; mkdir -p "$d/webroot/common_scripts/bin"
    : > "$d/legacy.log"; : > "$d/engine.log"
    printf '#!/bin/sh\necho ran >> "%s/legacy.log"\n' "$d" > "$d/osm0sis.sh"
    printf '#!/bin/sh\necho "$@" >> "%s/engine.log"\nexit %s\n' "$d" "$3" > "$d/webroot/common_scripts/autopilot.sh"
    if [ "$2" = 1 ]; then : > "$d/webroot/common_scripts/bin/box-autopilot"; chmod 755 "$d/webroot/common_scripts/bin/box-autopilot"; fi
    ( MODPATH="$d"; . "$W/fn.sh"; refresh_pif_fingerprint ) >/dev/null 2>&1 || fail "$1: the function must always succeed (Action must not abort)"
    got=0; [ -s "$d/legacy.log" ] && got=1
    [ "$got" = "$4" ] || fail "$1: legacy generator used=$got, expected $4"
    if [ "$2" = 1 ]; then grep -q 'pif-refresh' "$d/engine.log" || fail "$1: the engine was not asked to refresh"; fi
    PASS=$((PASS + 1))
}

run_case engine_ok        1 0 0
run_case pif_mode_off     1 3 1
run_case engine_busy      1 4 0
run_case engine_error     1 1 0
run_case engine_crash     1 139 0
run_case engine_missing   0 0 1
printf 'action fingerprint tests PASS (%s cases)\n' "$PASS"
