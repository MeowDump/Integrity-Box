#!/bin/sh
# uninstall.sh must reach its cleanup even when "autopilot.sh disable" fails (no engine, other ABI, stop timeout).
# Runs only the header of uninstall.sh (up to `set -x`) in a sandbox; the destructive part is never executed.
# Run: sh autopilot-v2/test_uninstall_continues.sh
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT INT TERM
mkdir -p "$W/m/webroot/common_scripts/bin"
printf '#!/bin/sh\nexit 1\n' > "$W/m/webroot/common_scripts/autopilot.sh"
: > "$W/m/webroot/common_scripts/bin/box-autopilot"; chmod 755 "$W/m/webroot/common_scripts/bin/box-autopilot"
grep -q '^set -x' "$HERE/../uninstall.sh" || { echo 'FAIL: marker line set -x not found: the test would run the whole uninstall body'; exit 1; }
sed -n '1,/^set -x/p' "$HERE/../uninstall.sh" | sed 's#/data/adb/Box-Brain/autopilot#'"$W"'/flag#' > "$W/m/uninstall.sh"
echo 1 > "$W/flag"
echo 'echo REACHED_CLEANUP' >> "$W/m/uninstall.sh"
out=$(sh "$W/m/uninstall.sh" 2>/dev/null) || { echo "FAIL: uninstall.sh exited early"; exit 1; }
case "$out" in *REACHED_CLEANUP*) ;; *) echo "FAIL: cleanup not reached"; exit 1 ;; esac
[ ! -e "$W/flag" ] || { echo "FAIL: the enable flag was not removed when disable failed"; exit 1; }
# the success path: when disable works, the header leaves the flag alone (the engine owns it then)
printf '#!/bin/sh\nexit 0\n' > "$W/m/webroot/common_scripts/autopilot.sh"
echo 1 > "$W/flag"
sh "$W/m/uninstall.sh" >/dev/null 2>&1 || { echo "FAIL: uninstall.sh failed although disable worked"; exit 1; }
[ -e "$W/flag" ] || { echo "FAIL: the flag was removed by hand although disable succeeded"; exit 1; }
# no engine installed (other ABI, removed): autopilot.sh is not called at all and the flag is left to the module's own scripts
rm "$W/m/webroot/common_scripts/bin/box-autopilot"
printf '#!/bin/sh\ntouch "%s/called"\nexit 1\n' "$W" > "$W/m/webroot/common_scripts/autopilot.sh"
echo 1 > "$W/flag"
sh "$W/m/uninstall.sh" >/dev/null 2>&1 || { echo "FAIL: uninstall.sh failed without an engine"; exit 1; }
[ ! -e "$W/called" ] && [ -e "$W/flag" ] || { echo "FAIL: without the engine uninstall.sh must not call autopilot.sh"; exit 1; }
echo "PASS: uninstall.sh continues and drops the enable flag when disable fails"
