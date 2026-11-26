#!/system/bin/sh
# AutoPilot v2 controller. The module's own entry points hand over to it whenever bin/box-autopilot is installed
# (see the first lines of autopilot.sh, key.sh and spectre.sh); without the engine they keep working as before.
#   autopilot.sh <command>              ->  ap2.sh <command>
#   key.sh [Megatron|Megatron2]         ->  ap2.sh keybox [variant]
#   spectre.sh                          ->  ap2.sh secondary
# No network work is performed by this shell: the engine does all of it.
set -u
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 1
ENGINE="$SCRIPT_DIR/bin/box-autopilot"
BRAIN=${AP_BOX:-/data/adb/Box-Brain}      # AP_BOX / AP_MODULES: tests only
MODS=${AP_MODULES:-/data/adb/modules}

# The doctor is independent of the compiled engine and must work without it.
if [ "${1:-}" = doctor ]; then
    exec sh "$SCRIPT_DIR/doctor.sh"
fi
[ -x "$ENGINE" ] || { printf '%s\n' 'AutoPilot ARM64 engine missing' >&2; exit 1; }

# A keybox target whose module is installed and enabled, but which the user did not switch on, is skipped by the
# engine. Tell the user how to enable it (same wording and conditions as the module's key.sh).
hint_disabled() { # MODULE FLAG TITLE
    [ -d "$MODS/$1" ] && [ ! -f "$MODS/$1/disable" ] && [ ! -f "$BRAIN/$2" ] || return 0
    echo "----------------------------------------"
    echo " ✦ $3 keybox update is disabled by user"
    echo "    DO THIS TO ENABLE :"
    echo "    WebUI -> Customise Scope -> Keybox"
    echo "----------------------------------------"
}

case "${1:-start}" in
    status|inspect|probe|run-once|import|configure|clock-status|pif-refresh)
        exec "$ENGINE" "$@"
        ;;
    keybox)
        case "${2:-}" in
            '')
                hint_disabled oh_my_keymint omk-key OhMyKeyMint
                hint_disabled teesim sim-key TEE-SIM
                exec "$ENGINE" run-once ;;
            Megatron|Megatron2) exec "$ENGINE" fetch "$2" ;;
            *) printf '%s\n' 'Unsupported key variant' >&2; exit 2 ;;
        esac
        ;;
    secondary)
        exec "$ENGINE" fetch secondary
        ;;
    enable)
        mkdir -p "$BRAIN" || exit 1
        "$ENGINE" configure autopilot on || exit 1
        ;;
    disable)
        exec "$ENGINE" disable
        ;;
    start) ;;
    *) printf '%s\n' 'Usage: autopilot.sh enable|disable|start|status|doctor|probe|inspect PATH|import PATH [SLOT]|run-once|pif-refresh' >&2; exit 2 ;;
esac
[ -f "$BRAIN/autopilot" ] || exit 0
# Detach standard descriptors so WebUI/boot callers cannot wait on the daemon.
nohup "$ENGINE" supervise </dev/null >/dev/null 2>&1 &
exit 0
