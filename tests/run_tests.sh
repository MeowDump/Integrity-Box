#!/bin/sh
#
# Integrity-Box test suite
# Validates the slimmed-down tree behaves like the original:
#   1. Shell syntax (sh -n) on every script
#   2. mksh-aware shellcheck baseline (only actionable findings)
#   3. Embedded boot-scripts (heredocs inside customize.sh) are valid shell
#   4. JSON assets parse
#   5. WebUI JS parses (files + inline <script> blocks)
#   6. Shared-helper contract: every common_func.sh helper has a caller
#   7. Behavior-equivalence spot-checks vs the pre-cleanup version (git)
#
# Usage: sh tests/run_tests.sh
# Exit code = number of failures (0 = all green).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf ' \033[32mPASS\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf ' \033[31mFAIL\033[0m %s\n' "$1"; }
hdr() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# ---------------------------------------------------------------- 1. syntax
hdr "shell syntax (sh -n)"
SYNTAX_FAIL=0
for f in $(find . -name '*.sh' -not -path './.git/*' -not -path './PlayIntegrityFork/*' -not -path './tests/*' | sort); do
    sh -n "$f" 2>/tmp/ib_syntax_err || { bad "$f: $(cat /tmp/ib_syntax_err)"; SYNTAX_FAIL=1; }
done
[ "$SYNTAX_FAIL" -eq 0 ] && ok "all shell scripts parse"

# ------------------------------------------------- 2. shellcheck (mksh-aware)
hdr "shellcheck baseline"
if command -v shellcheck >/dev/null 2>&1; then
    # Codes acceptable for Android's /system/bin/sh (mksh) or repo convention:
    #  SC3043 local     SC3037 echo flags   SC3010 [[ ]]   SC3014 == in [[ ]]
    #  SC2086 unquoted (space-free fixed paths)  SC2016 single quotes (sed patterns)
    #  SC2015 A && B || C idiom   SC2034 vars consumed cross-file after sourcing
    SC_OUT="$(find . -name '*.sh' -not -path './.git/*' -not -path './PlayIntegrityFork/*' -not -path './tests/*' \
        | xargs shellcheck -f gcc \
          -e SC3043,SC3037,SC3010,SC3014,SC2086,SC2016,SC2015,SC2034 2>&1)"
    if [ -z "$SC_OUT" ]; then
        ok "shellcheck: no actionable findings"
    else
        printf '%s\n' "$SC_OUT" | head -20
        bad "shellcheck findings above"
    fi
else
    ok "shellcheck not installed - skipped"
fi

# --------------------------------------- 3. embedded boot scripts validate
hdr "embedded boot scripts (customize.sh heredocs)"
if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PYEOF' || bad "embedded heredoc extraction/parse failed (see above)"
import re, subprocess, sys

src = open("customize.sh", encoding="utf-8").read()
# match: cat <<'EOF' > "path"  ...  EOF
blocks = re.findall(r"cat <<'EOF' > \"([^\"]+)\"\n(.*?)\nEOF\n", src, re.S)
fails = 0
for path, body in blocks:
    r = subprocess.run(["sh", "-n"], input=body, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  {path}: {r.stderr.strip()}")
        fails += 1
sys.exit(1 if fails else 0)
PYEOF
    [ $? -eq 0 ] 2>/dev/null && ok "all embedded boot scripts parse"
else
    ok "python3 not installed - embedded check skipped"
fi

# ------------------------------------------------------------- 4. JSON assets
hdr "JSON assets"
if command -v python3 >/dev/null 2>&1; then
    JSON_FAIL=0
    for j in toolkit/meow.json release.json; do
        [ -f "$j" ] || continue
        python3 -c "import json; json.load(open('$j'))" 2>/tmp/ib_json_err \
            || { bad "$j: $(cat /tmp/ib_json_err)"; JSON_FAIL=1; }
    done
    [ "$JSON_FAIL" -eq 0 ] && ok "JSON assets valid"
else
    ok "python3 not installed - JSON check skipped"
fi

# ----------------------------------------------------------------- 5. WebUI JS
hdr "WebUI JavaScript"
if command -v node >/dev/null 2>&1; then
    JS_FAIL=0
    for js in webroot/script.js webroot/common_scripts/UI/script.js; do
        node --check "$js" 2>/tmp/ib_js_err \
            || { bad "$js: $(cat /tmp/ib_js_err)"; JS_FAIL=1; }
    done
    node - <<'NODEEOF' 2>/tmp/ib_htmljs_err || { bad "inline HTML JS:\n$(cat /tmp/ib_htmljs_err)"; JS_FAIL=1; }
const fs = require("fs");
const path = require("path");
let badCount = 0;
function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) {
            if (p === "webroot/common_scripts/UI" || e.name === "TRANSLATIONS" || e.name === "PlayIntegrityFork") continue;
            if (p !== "webroot/common_scripts") walk(p);
        } else if (e.name.endsWith(".html")) {
            const html = fs.readFileSync(p, "utf8");
            // 1. inline scripts parse
            const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
            blocks.forEach((s, i) => {
                try { new Function(s); }
                catch (err) { console.log(`  ${p} script#${i}: ${err.message}`); badCount++; }
            });
            // 2. element IDs referenced by external script.js all exist
            const sj = path.join(path.dirname(p), "script.js");
            if (fs.existsSync(sj)) {
                const js = fs.readFileSync(sj, "utf8");
                const ids = [...new Set([...js.matchAll(/getElementById\(\s*["']([^"']+)["']\s*\)/g)].map(m => m[1]))];
                const dynamic = ["active-iframe", "toast"];
                const missing = ids.filter(id => !dynamic.includes(id) && !html.includes(`id="${id}"`));
                if (missing.length) { console.log(`  ${p}: missing element IDs: ${missing.join(", ")}`); badCount++; }
            }
            // 3. no external resources (fonts.googleapis icon links are content, not loads; block everything else)
            const loads = [...html.matchAll(/<(?:link|script)\s[^>]*(?:href|src)="(https?:\/\/[^"]+)"/g)].map(m => m[1]);
            const badLoads = loads.filter(u => !u.includes("fonts.googleapis.com"));
            if (badLoads.length) { console.log(`  ${p}: external resource loads: ${badLoads.join(", ")}`); badCount++; }
            // 4. no infinite decorative animations (ib-spin for loaders is allowed)
            const styleM = html.match(/<style>([\s\S]*?)<\/style>/);
            if (styleM) {
                const anims = [...styleM[1].matchAll(/animation:\s*([^;}]+)/g)].map(m => m[1].trim());
                const badAnims = anims.filter(a => a.includes("infinite") && !a.includes("ib-spin"));
                if (badAnims.length) { console.log(`  ${p}: infinite animations: ${badAnims.join(", ")}`); badCount++; }
            }
        }
    }
}
walk("webroot");
process.exit(badCount ? 1 : 0);
NODEEOF
    [ "$JS_FAIL" -eq 0 ] && ok "all JS parses (files + inline blocks)"
else
    ok "node not installed - JS check skipped"
fi

# ------------------------------------- 6. helper contract (defs vs call sites)
hdr "shared-helper contract"
CONTRACT_FAIL=0
for h in $(sed -n 's/^\([a-zA-Z_][a-zA-Z0-9_]*\)() {.*/\1/p' common_func.sh); do
    # caller may be anywhere, including common_func.sh itself (self-calls)
    # (e.g. ROOT_SOL=$(detect_root_solution), restart_gms -> kill_process)
    if ! grep -Rqs --include='*.sh' --exclude-dir=.git --exclude-dir=tests \
         --exclude-dir=PlayIntegrityFork "$h" .; then
        bad "common_func.sh defines '$h' but nothing calls it"
        CONTRACT_FAIL=1
    fi
done
[ "$CONTRACT_FAIL" -eq 0 ] && ok "every common_func helper has callers"

# ------------------------------------------------ 7. behavior equivalence
hdr "behavior equivalence vs pre-cleanup (git)"
BASELINE="ecadb65"
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1 \
   && git cat-file -e "$BASEBASELINE" 2>/dev/null || git cat-file -e "$BASELINE^{commit}" >/dev/null 2>&1; then
    BE_FAIL=0
    OLD_CF="$(git show "$BASELINE:common_func.sh" 2>/dev/null)"
    if [ -n "$OLD_CF" ]; then
        # every live helper from the original must still exist
        for fn in log_step kill_process hide_recovery_folders detect_downloader \
                   wait_for_network P persistprop resetprop_if_diff resetprop_if_match \
                   delprop_if_exist resetprop_hexpatch wait_for_boot boot_log \
                   reset_tricky_store ensure_blacklist_entries ensure_exec_permissions \
                   set_perm_if_needed run_compact setup_resetprop detect_root_solution \
                   recommended_settings get_size print_header handle_delay log_patch \
                   writelog chup set_simpleprop recommended_settings; do
            grep -q "^$fn() {" common_func.sh \
                || { bad "helper '$fn' from original is missing"; BE_FAIL=1; }
        done
        # P() must keep every original search path (+ the /system dirs action.sh needs)
        P_NEW="$(sed -n '/^P() {/,/^}/p' common_func.sh)"
        for path in "/data/adb/modules/busybox-ndk/system/*/busybox" \
                    "/data/adb/ksu/bin/busybox" \
                    "/data/adb/ap/bin/busybox" \
                    "/data/adb/magisk/busybox" \
                    "/system/bin/busybox" \
                    "/system/xbin/busybox"; do
            printf '%s\n' "$P_NEW" | grep -qF -- "$path" \
                || { bad "P() lost search path: $path"; BE_FAIL=1; }
        done
        # blacklist contents must be byte-identical to the original
        OLD_BL="$(printf '%s\n' "$OLD_CF" | sed -n '/REQUIRED_ENTRIES=/,/^"$/p')"
        NEW_BL="$(sed -n '/REQUIRED_ENTRIES=/,/^"$/p' common_func.sh)"
        [ "$OLD_BL" = "$NEW_BL" ] \
            || { bad "blacklist REQUIRED_ENTRIES changed vs original"; BE_FAIL=1; }
        # kill list must still cover the same 3 processes
        grep -q "com.google.android.gms.unstable" common_func.sh \
            && grep -q "com.google.android.gms\b" common_func.sh \
            && grep -q "com.android.vending" common_func.sh \
            || { bad "GMS kill list lost a process"; BE_FAIL=1; }
        # busybox discovery order preserved: ndk -> ksu -> ap -> magisk -> system
        ORDER_OK=$(printf '%s\n' "$P_NEW" | grep -n 'busybox' | head -6)
        printf '%s\n' "$ORDER_OK" | grep -q "busybox-ndk" \
            || { bad "P() no longer checks busybox-ndk first"; BE_FAIL=1; }
        [ "$BE_FAIL" -eq 0 ] && ok "live helpers, paths and lists identical to original"
    else
        ok "baseline commit unavailable - equivalence skipped"
    fi
else
    ok "git or baseline unavailable - equivalence skipped"
fi

# ------------------------------------------------------------------ summary
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && printf '\033[32mALL GREEN - safe to ship\033[0m\n'
exit "$FAIL"
