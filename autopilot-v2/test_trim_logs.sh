#!/bin/sh
# Host test of trim_logs (common_func.sh): big logs are cut to their last lines, small ones and non-logs stay.
# Run: sh autopilot-v2/test_trim_logs.sh
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

sed -n '/^trim_logs() {/,/^}/p' "$HERE/../common_func.sh" > "$W/fn.sh"
[ -s "$W/fn.sh" ] || fail "trim_logs not found in common_func.sh"
# shellcheck disable=SC1091
. "$W/fn.sh"

D=$W/logs; mkdir -p "$D"
i=0; : > "$D/big.log"
while [ "$i" -lt 8000 ]; do printf 'line %05d padding padding padding padding padding\n' "$i" >> "$D/big.log"; i=$((i + 1)); done
printf 'small\n' > "$D/small.log"
head -c 400000 /dev/zero | tr '\0' 'x' > "$D/not-a-log.txt"
chmod 644 "$D/big.log"

[ "$(wc -c < "$D/big.log")" -gt 262144 ] || fail "fixture: big.log must exceed the limit"
trim_logs "$D"
[ "$(wc -l < "$D/big.log" | tr -d ' ')" -eq 500 ] || fail "big.log must keep exactly its last 500 lines"
[ "$(tail -n 1 "$D/big.log")" = "line 07999 padding padding padding padding padding" ] || fail "the newest line must survive"
[ "$(head -n 1 "$D/big.log" | cut -c1-10)" = "line 07500" ] || fail "the oldest kept line must be 7500"
[ "$(cat "$D/small.log")" = small ] || fail "a small log must be untouched"
[ "$(wc -c < "$D/not-a-log.txt")" -eq 400000 ] || fail "only *.log files are trimmed"
[ ! -e "$D/big.log.trim" ] || fail "no temp file may stay"
[ "$(stat -c %a "$D/big.log" 2>/dev/null || stat -f %Lp "$D/big.log")" = 644 ] || fail "mode must be preserved"
trim_logs "$W/does-not-exist" || fail "a missing directory is fine"
printf 'test_trim_logs.sh: PASS\n'
