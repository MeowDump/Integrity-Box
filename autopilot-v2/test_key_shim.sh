#!/bin/sh
# Host test of webroot/common_scripts/key.sh (the thin shim over the engine plus the author's v48.1 hints for
# keybox targets the user did not enable). Run: sh autopilot-v2/test_key_shim.sh
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT INT TERM
PASS=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

mkdir -p "$W/s/bin" "$W/mods" "$W/box"
cp "$HERE/../webroot/common_scripts/key.sh" "$W/s/key.sh"
printf '#!/bin/sh\necho "ENGINE $*"\n' > "$W/s/bin/box-autopilot"; chmod 755 "$W/s/bin/box-autopilot"
run() { AP_BOX="$W/box" AP_MODULES="$W/mods" sh "$W/s/key.sh" "$@" 2>&1; }
has() { printf '%s\n' "$OUT" | grep -q -- "$1" || fail "$CASE: expected '$1' in: $OUT"; }
lacks() { printf '%s\n' "$OUT" | grep -q -- "$1" && fail "$CASE: unexpected '$1' in: $OUT"; PASS=$((PASS + 1)); return 0; }

CASE=plain; OUT=$(run); has 'ENGINE run-once'; lacks 'DO THIS TO ENABLE'
CASE=variant; OUT=$(run Megatron2); has 'ENGINE fetch Megatron2'
CASE=unsupported; if OUT=$(run Bogus); then fail "unsupported variant must fail"; fi; has 'Unsupported key variant'

CASE=omk-installed-not-enabled; mkdir -p "$W/mods/oh_my_keymint"; OUT=$(run)
has 'OhMyKeyMint keybox update is disabled by user'; has 'WebUI -> Customise Scope -> Keybox'; has 'ENGINE run-once'; lacks 'TEE-SIM'
CASE=omk-enabled; : > "$W/box/omk-key"; OUT=$(run); lacks 'OhMyKeyMint keybox update is disabled'
CASE=omk-module-disabled; rm -f "$W/box/omk-key"; : > "$W/mods/oh_my_keymint/disable"; OUT=$(run); lacks 'OhMyKeyMint keybox update is disabled'
CASE=sim-installed-not-enabled; mkdir -p "$W/mods/teesim"; OUT=$(run); has 'TEE-SIM keybox update is disabled by user'; lacks 'OhMyKeyMint'
CASE=sim-enabled; : > "$W/box/sim-key"; OUT=$(run); lacks 'TEE-SIM keybox update is disabled'

printf 'test_key_shim.sh: %d checks passed\n' "$PASS"
