#!/bin/sh
# verify_binary.sh: is the TRACKED engine binary a reproducible build of the COMMITTED source?
#
#   sh autopilot-v2/verify_binary.sh
#
# 1. the tracked binary matches its provenance file (box-autopilot.sha256);
# 2. a fresh build of `git archive HEAD autopilot-v2` (the working tree cannot influence it) gives the same bytes.
# A difference with the SAME Go toolchain means the binary is stale: rebuild it with build.sh in its own commit.
# With a different toolchain the comparison is inconclusive: exit status 3, never a PASS (set VERIFY_BINARY_ALLOW_INCONCLUSIVE=1 to accept it).
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT="$HERE/.."
BIN="$ROOT/webroot/common_scripts/bin/box-autopilot"
PROV="$BIN.sha256"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -s "$BIN" ] || fail "no tracked binary at $BIN"
[ -s "$PROV" ] || fail "no provenance file $PROV (run build.sh in a clean tree)"
recorded=$(head -n 1 "$PROV" | cut -d' ' -f1)
actual=$(shasum -a 256 "$BIN" | cut -d' ' -f1)
[ "$recorded" = "$actual" ] || fail "the binary ($actual) is not the one its provenance file records ($recorded)"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
git -C "$ROOT" archive HEAD autopilot-v2 | tar -x -C "$T"
( cd "$T/autopilot-v2" && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags='-s -w' -o "$T/rebuilt" . )
rebuilt=$(shasum -a 256 "$T/rebuilt" | cut -d' ' -f1)
if [ "$rebuilt" = "$actual" ]; then
    echo "PASS: the tracked binary is a reproducible build of the committed source ($(printf %s "$actual" | cut -c1-12))"
    exit 0
fi
want=$(grep '^# toolchain:' "$PROV" | sed 's/^# toolchain: //')
have=$(go version)
if [ "$want" = "$have" ]; then
    fail "STALE: a rebuild with the recorded toolchain gives $(printf %s "$rebuilt" | cut -c1-12), the tracked binary is $(printf %s "$actual" | cut -c1-12). Rebuild with build.sh in its own commit."
fi
echo "INCONCLUSIVE: toolchain differs (recorded: $want; have: $have); rebuild gives $(printf %s "$rebuilt" | cut -c1-12), tracked is $(printf %s "$actual" | cut -c1-12)"
[ "${VERIFY_BINARY_ALLOW_INCONCLUSIVE:-}" = 1 ] && exit 0
exit 3
