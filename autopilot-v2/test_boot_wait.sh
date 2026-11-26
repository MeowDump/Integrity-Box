#!/bin/sh
# Host test of wait_boot_completed (common_func.sh): service.sh must continue as soon as the boot is done, whatever
# resetprop flavour is installed (resetprop-rs --wait NAME 0 waits for the value 0 and hung the boot script forever).
# Run: sh autopilot-v2/test_boot_wait.sh
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
sed -n '/^wait_boot_completed() {/,/^}/p' "$HERE/../common_func.sh" > "$W/fn.sh"
[ -s "$W/fn.sh" ] || fail "function not found in common_func.sh"
grep -q 'PROP_WAIT sys.boot_completed' "$HERE/../service.sh" && fail "service.sh must not wait with \$PROP_WAIT sys.boot_completed"
grep -q '^wait_boot_completed$' "$HERE/../service.sh" || fail "service.sh does not call wait_boot_completed"

mkdir -p "$W/bin"
printf '#!/bin/sh\nn=$(cat "%s/n" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "%s/n"\n[ "$n" -ge "$GETPROP_READY_AT" ] && echo 1 || echo 0\n' "$W" "$W" > "$W/bin/getprop"
printf '#!/bin/sh\necho s >> "%s/sleeps"\n' "$W" > "$W/bin/sleep"
chmod 755 "$W/bin/getprop" "$W/bin/sleep"
run() { : > "$W/sleeps"; rm -f "$W/n"; PATH="$W/bin:$PATH" GETPROP_READY_AT=$1 sh -c ". '$W/fn.sh'; wait_boot_completed"; wc -l < "$W/sleeps" | tr -d ' '; }

[ "$(run 1)" = 0 ] || fail "boot already completed: must not sleep"
[ "$(run 4)" = 3 ] || fail "must poll until sys.boot_completed becomes 1"
[ "$(run 100000)" = 600 ] || fail "must give up after 600 polls (never hang)"
printf 'test_boot_wait.sh: 5 checks passed\n'
