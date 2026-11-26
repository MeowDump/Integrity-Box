#!/bin/sh
# device_test.sh: run the whole test suite ON the phone (a host test is not proof).
#
#   sh autopilot-v2/device_test.sh ADDR:PORT [--serial S] [--skip REGEX]
#
# Builds the arm64 test binary, stages it and its fixtures in RAM (/dev/.ap, nothing is written to flash), runs the Go
# suite (month-long simulations are platform independent and skipped by default) and the boot-script test under the
# phone's own shell, prints the totals, removes /dev/.ap. Exit 1 on any failure.
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT="$HERE/.."
SERIAL=${DEVICE_SERIAL:-}
SKIP='Lifecycle|DaemonCycleRate'
ADDR=${1:?usage: device_test.sh ADDR:PORT [--serial S] [--skip REGEX]}
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --serial) SERIAL=$2; shift 2 ;;
        --skip) SKIP=$2; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
[ -n "$SERIAL" ] || { echo "ABORT: name the device you mean: --serial S or DEVICE_SERIAL=S (the serial is checked before anything is touched)" >&2; exit 2; }
got=$(adb -s "$ADDR" shell getprop ro.serialno 2>/dev/null | tr -d '\r')
[ "$got" = "$SERIAL" ] || { echo "ABORT: $ADDR is '$got', expected '$SERIAL'" >&2; exit 1; }

BIN=$(mktemp)
trap 'rm -f "$BIN"' EXIT INT TERM
( cd "$HERE" && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go test -c -o "$BIN" . )
host=$(shasum -a 256 "$BIN" | cut -c1-16)

put() { # local remote (RAM scratch only: nothing here can damage the system)
    [ -s "$1" ] || { echo "ABORT: $1 missing" >&2; exit 1; }
    adb -s "$ADDR" shell "su -c 'mkdir -p $(dirname "$2") && cat > $2'" < "$1"
}
adb -s "$ADDR" shell "su -c 'rm -rf /dev/.ap; mkdir -p /dev/.ap/autopilot-v2/testdata /dev/.ap/webroot/common_scripts'"
put "$BIN" /dev/.ap/autopilot-v2/ap.test
adb -s "$ADDR" shell "su -c 'chmod 700 /dev/.ap/autopilot-v2/ap.test'"
for f in "$HERE"/testdata/*; do put "$f" "/dev/.ap/autopilot-v2/testdata/$(basename "$f")"; done
put "$ROOT/webroot/common_scripts/doctor.sh" /dev/.ap/webroot/common_scripts/doctor.sh
put "$ROOT/customize.sh" /dev/.ap/customize.sh
put "$ROOT/pif_policy.sh" /dev/.ap/pif_policy.sh
put "$HERE/test_pif_policy.sh" /dev/.ap/autopilot-v2/test_pif_policy.sh
dev=$(adb -s "$ADDR" shell "su -c 'sha256sum /dev/.ap/autopilot-v2/ap.test'" | cut -c1-16)
[ "$host" = "$dev" ] || { echo "ABORT: test binary hash differs (host $host, device $dev)" >&2; exit 1; }

echo "== Go suite on the device (skipping: $SKIP)"
out=$(adb -s "$ADDR" shell "su -c 'cd /dev/.ap/autopilot-v2 && TMPDIR=/dev/.ap ./ap.test -test.v -test.count=1 -test.skip \"$SKIP\" 2>&1'" || true)
pass=$(printf '%s\n' "$out" | grep -c '^--- PASS' || true)
fails=$(printf '%s\n' "$out" | grep -c '^--- FAIL' || true)
skips=$(printf '%s\n' "$out" | grep -c '^--- SKIP' || true)
printf '%s\n' "$out" | grep -E '^(--- FAIL|    .*_test.go)' | head -20 || true
echo "Go: $pass passed, $fails failed, $skips skipped"
echo "== boot-script / policy test under the phone's shell"
sh_out=$(adb -s "$ADDR" shell "su -c 'cd /dev/.ap && TMPDIR=/dev/.ap sh autopilot-v2/test_pif_policy.sh 2>&1 | tail -3'" || true)
printf '%s\n' "$sh_out"
adb -s "$ADDR" shell "su -c 'rm -rf /dev/.ap'"
status=0
[ "$fails" = 0 ] && [ "$pass" -gt 100 ] || status=1
printf '%s\n' "$sh_out" | grep -q 'tests PASS' || status=1
[ "$status" = 0 ] && echo "DEVICE TESTS PASS" || echo "DEVICE TESTS FAILED"
exit $status
