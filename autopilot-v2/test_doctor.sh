#!/bin/sh
# Host-side tests for webroot/common_scripts/doctor.sh. Uses synthetic keys generated here
# with openssl; no real keybox is ever read. python3 is used only as an independent oracle
# for dates (those assertions are skipped when it is missing).
# Run: sh autopilot-v2/test_doctor.sh
set -eu

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
DOCTOR="$HERE/../webroot/common_scripts/doctor.sh"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT INT TERM
PASS=0

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { PASS=$((PASS + 1)); }
contains() { case "$1" in *"$2"*) ok ;; *) printf '%s\n' "$1" >&2; fail "expected output to contain: $2" ;; esac; }
lacks() { case "$1" in *"$2"*) printf '%s\n' "$1" >&2; fail "output must not contain: $2" ;; *) ok ;; esac; }

# Real compact status line printed by the engine (before its first cycle).
STATUS_SAMPLE='{"installed_source":"","ready":false,"next_search_due":"0001-01-01T00:00:00Z","next_crl_due":"0001-01-01T00:00:00Z","time_state":"unknown","time_source":"","crl_checked":"0001-01-01T00:00:00Z","crl_valid_until":"0001-01-01T00:00:00Z","desired_enabled":false,"running":false,"phase":"not_started","local":{"keybox_identity":"","root_public_key_hashes":null,"state":"missing","fingerprint":"","serials":null,"expires":"0001-01-01T00:00:00Z","anchor":false},"consumer":{"id":"","required":false,"present":false,"state":"","evidence":"","checked":"0001-01-01T00:00:00Z"},"revocation_state":"unknown","integrity_verdict":"not_measured","reason":"","next_due":"0001-01-01T00:00:00Z","source":"","pid":0,"heartbeat":"0001-01-01T00:00:00Z"}'

# make_keybox NAME KEYFORMAT(sec1|pkcs8) VALID_DAYS SERIAL_HEX [DECLARED_COUNT] [LAYOUT(pretty|oneline)] [ALGO]
make_keybox() {
    d="$W/$1"
    mkdir -p "$d/tricky_store" "$d/modules/tricky_store" "$d/brain"
    openssl ecparam -name prime256v1 -genkey -noout -out "$d/root.key" 2>/dev/null
    openssl ecparam -name prime256v1 -genkey -noout -out "$d/leaf.key" 2>/dev/null
    openssl req -x509 -new -key "$d/root.key" -subj "/CN=test root" -days 20000 -out "$d/root.pem" 2>/dev/null
    openssl req -new -key "$d/leaf.key" -subj "/CN=test leaf" -out "$d/leaf.csr" 2>/dev/null
    printf 'basicConstraints=CA:TRUE\nkeyUsage=keyCertSign,digitalSignature\n' > "$d/ext"
    openssl x509 -req -in "$d/leaf.csr" -CA "$d/root.pem" -CAkey "$d/root.key" -set_serial "0x$4" -days "$3" -extfile "$d/ext" -out "$d/leaf.pem" 2>/dev/null
    if [ "$2" = pkcs8 ]; then
        openssl pkcs8 -topk8 -nocrypt -in "$d/leaf.key" -out "$d/leaf.priv" 2>/dev/null
    else
        cp "$d/leaf.key" "$d/leaf.priv"
    fi
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<AndroidAttestation>\n<NumberOfKeyboxes>1</NumberOfKeyboxes>\n'
        printf '<Keybox DeviceID="test">\n<Key algorithm="%s">\n<PrivateKey format="pem">\n' "${7:-ecdsa}"
        cat "$d/leaf.priv"
        printf '</PrivateKey>\n<CertificateChain>\n<NumberOfCertificates>%s</NumberOfCertificates>\n' "${5:-2}"
        printf '<Certificate format="pem">\n'; cat "$d/leaf.pem"; printf '</Certificate>\n'
        printf '<Certificate format="pem">\n'; cat "$d/root.pem"; printf '</Certificate>\n'
        printf '</CertificateChain>\n</Key>\n</Keybox>\n</AndroidAttestation>\n'
    } > "$d/tricky_store/keybox.xml"
    if [ "${6:-pretty}" = oneline ]; then
        tr -d '\n' < "$d/tricky_store/keybox.xml" > "$d/one.xml"
        mv "$d/one.xml" "$d/tricky_store/keybox.xml"
    fi
}

# Fake platform log: "log" appends the marker (and optionally a rejection), "logcat" prints it.
make_log() {
    mkdir -p "$W/bin"
    : > "$W/log.txt"
    cat > "$W/bin/log" <<'LOGEOF'
#!/bin/sh
[ "${FAKE_MUTE:-0}" = 1 ] && exit 0
echo "11-13 15:00:00.000  1  1 I BoxAutoPilot: $5" >> "$FAKE_LOG"
if [ "${FAKE_REJECT:-0}" = 1 ]; then
    echo "11-13 15:00:01.000  2  2 E TrickyStore: ${FAKE_REJECT_TEXT:-Load Keybox failed with exception}" >> "$FAKE_LOG"
fi
exit 0
LOGEOF
    cat > "$W/bin/logcat" <<'LOGEOF'
#!/bin/sh
cat "$FAKE_LOG"
LOGEOF
    chmod 755 "$W/bin/log" "$W/bin/logcat"
}

# make_engine NAME CONSUMER_STATE: a fake engine printing the real compact status layout.
make_engine() {
    mkdir -p "$W/engines"
    body=$(printf '%s\n' "$STATUS_SAMPLE" | sed "s/\"phase\":\"not_started\"/\"phase\":\"waiting\"/; s/\"running\":false/\"running\":true/; s/\"id\":\"\",\"required\":false,\"present\":false,\"state\":\"\"/\"id\":\"tricky_store\",\"required\":true,\"present\":true,\"state\":\"$2\"/")
    cat > "$W/engines/$1" <<'ENGHEAD'
#!/bin/sh
[ "$1" = status ] || exit 2
ENGHEAD
    printf "cat <<'ENGEOF'\n%s\nENGEOF\n" "$body" >> "$W/engines/$1"
    chmod 755 "$W/engines/$1"
}

# run_doctor NAME [VAR=value ...] -> sets OUT and RC
run_doctor() {
    n=$1
    shift
    d="$W/$n"
    set +e
    OUT=$(env AP_KEYBOX="$d/tricky_store/keybox.xml" AP_MODULES="$d/modules" AP_BRAIN="$d/brain" \
        AP_ENGINE="$d/none" AP_SETTLE=0 AP_LOGCAT="$W/bin/logcat" AP_LOG="$W/bin/log" FAKE_LOG="$W/log.txt" "$@" "${TEST_SH:-sh}" "$DOCTOR" 2>&1)
    RC=$?
    set -e
}

have_python=0
command -v python3 >/dev/null 2>&1 && have_python=1
oracle_end() { # leaf.pem -> ISO end date
    python3 -I -c '
import subprocess,sys,datetime
o=subprocess.run(["openssl","x509","-noout","-enddate","-in",sys.argv[1]],capture_output=True,text=True).stdout.strip().split("=")[1]
print(datetime.datetime.strptime(o,"%b %d %H:%M:%S %Y %Z").strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"
}
oracle_epoch() {
    python3 -I -c '
import subprocess,sys,datetime
o=subprocess.run(["openssl","x509","-noout","-enddate","-in",sys.argv[1]],capture_output=True,text=True).stdout.strip().split("=")[1]
print(int(datetime.datetime.strptime(o,"%b %d %H:%M:%S %Y %Z").replace(tzinfo=datetime.timezone.utc).timestamp()))' "$1"
}

make_log
SERIAL=7a24f50d9090cb23cf6497654c9aee33

# 1. A healthy SEC1 keybox: exit 0, DER fields agree with openssl.
make_keybox good sec1 30 "$SERIAL"
run_doctor good
[ "$RC" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "healthy keybox exited $RC"; }
contains "$OUT" "OK   key-format"
contains "$OUT" "OK   cert-count"
contains "$OUT" "serial $SERIAL valid until"
contains "$OUT" "OK   probe"
if [ "$have_python" -eq 1 ]; then
    contains "$OUT" "valid until $(oracle_end "$W/good/leaf.pem")"
else
    printf 'SKIP: python3 oracle\n'
fi

# 1b. The same file as a single line (no line breaks anywhere) parses identically.
make_keybox oneline sec1 30 "$SERIAL" 2 oneline
run_doctor oneline
[ "$RC" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "single-line keybox exited $RC"; }
contains "$OUT" "OK   cert-count   2 certificates"
contains "$OUT" "serial $SERIAL valid until"

# 2. PKCS#8 is the incident format: FAIL with a specific explanation.
make_keybox pkcs8 pkcs8 30 "$SERIAL"
run_doctor pkcs8
[ "$RC" -eq 1 ] || fail "PKCS#8 keybox must exit 1"
contains "$OUT" "FAIL key-format"
contains "$OUT" "PKCS#8"

# 3. Validity comes from the certificate: expired, near expiry, and not yet valid.
run_doctor good AP_NOW=4102444800
[ "$RC" -eq 1 ] || fail "expired keybox must exit 1"
contains "$OUT" "FAIL cert-1"
contains "$OUT" "expired"
run_doctor good AP_NOW=1000000000
[ "$RC" -eq 1 ] || fail "not-yet-valid keybox must exit 1"
contains "$OUT" "is not valid before"
if [ "$have_python" -eq 1 ]; then
    leaf_end=$(oracle_epoch "$W/good/leaf.pem")
    run_doctor good AP_NOW=$((leaf_end - 7200))
    contains "$OUT" "WARN cert-1"
    contains "$OUT" "renewal window"
fi

# 3b. A serial with the high bit set carries a leading 00 in DER; it is shown like openssl does.
make_keybox highbit sec1 30 f1a2b3c4d5e6f70809a1b2c3d4e5f607
run_doctor highbit
contains "$OUT" "serial f1a2b3c4d5e6f70809a1b2c3d4e5f607 valid until"
# 3c. Dates from 2050 on are GeneralizedTime.
make_keybox far sec1 9500 "$SERIAL"
run_doctor far
contains "$OUT" "valid until 20"
if [ "$have_python" -eq 1 ]; then
    contains "$OUT" "valid until $(oracle_end "$W/far/leaf.pem")"
fi

# 4. Declared and actual certificate counts must agree.
make_keybox count sec1 30 "$SERIAL" 3
run_doctor count
[ "$RC" -eq 1 ] || fail "count mismatch must exit 1"
contains "$OUT" "FAIL cert-count"

# 4b. The key type must match the declared algorithm.
make_keybox mismatch sec1 30 "$SERIAL" 2 pretty rsa
run_doctor mismatch
[ "$RC" -eq 1 ] || fail "algorithm/key type mismatch must exit 1"
contains "$OUT" "FAIL key-format"

# 5. The required consumer must be installed and enabled; a stale target.txt does not count.
make_keybox noconsumer sec1 30 "$SERIAL"
rmdir "$W/noconsumer/modules/tricky_store"
run_doctor noconsumer
[ "$RC" -eq 1 ] || fail "missing consumer must exit 1"
contains "$OUT" "FAIL consumer"
make_keybox disabled sec1 30 "$SERIAL"
: > "$W/disabled/modules/tricky_store/disable"
: > "$W/disabled/tricky_store/target.txt"
run_doctor disabled
[ "$RC" -eq 1 ] || fail "a disabled module with a stale target.txt must exit 1"
contains "$OUT" "disabled or marked for removal"

# 6. Acceptance probe: rejection, silence without a marker, and a device without logcat.
: > "$W/log.txt"
run_doctor good FAKE_REJECT=1
[ "$RC" -eq 1 ] || fail "rejected keybox must exit 1"
contains "$OUT" "FAIL probe"
: > "$W/log.txt"
run_doctor good FAKE_MUTE=1
[ "$RC" -eq 0 ] || fail "an unobservable probe must not fail"
contains "$OUT" "WARN probe"
contains "$OUT" "marker was not visible"
run_doctor good AP_LOGCAT=/nonexistent/logcat
[ "$RC" -eq 0 ] || fail "missing logcat must not fail"
contains "$OUT" "no log channel"

# 6b. A keybox that cannot be opened for writing degrades the probe; the doctor still finishes.
make_keybox readonly sec1 30 "$SERIAL"
chmod 444 "$W/readonly/tricky_store/keybox.xml"
run_doctor readonly
contains "$OUT" "SUMMARY"
contains "$OUT" "cannot open the keybox"
[ ! -e "$W/absent.xml" ] && ok

# 7. Rejection patterns come from autopilot.conf (no rebuild for new log wording).
conf="$W/good/brain/autopilot.conf"
printf 'consumer.tricky_store.rejection = brand new failure text\n' > "$conf"
: > "$W/log.txt"
run_doctor good FAKE_REJECT=1 AP_CONF="$conf"
[ "$RC" -eq 0 ] || fail "the default pattern must not match once the config replaces it"
: > "$W/log.txt"
run_doctor good FAKE_REJECT=1 FAKE_REJECT_TEXT="brand new failure text" AP_CONF="$conf"
[ "$RC" -eq 1 ] || fail "a configured pattern must match"
contains "$OUT" "FAIL probe"
# 7b. Invalid, empty-matching and too-short patterns are ignored; a valid one still works.
printf 'consumer.tricky_store.rejection = [\nconsumer.tricky_store.rejection = .*\nconsumer.tricky_store.rejection = ab\nCONSUMER.TRICKY_STORE.REJECTION = Load Keybox failed\n' > "$conf"
: > "$W/log.txt"
run_doctor good FAKE_REJECT=1 AP_CONF="$conf"
[ "$RC" -eq 1 ] || { printf '%s\n' "$OUT" >&2; fail "valid pattern must survive invalid neighbours"; }
contains "$OUT" "FAIL probe"

# 8. The renewal window is clamped to 6..168 hours and the key is case-insensitive, like the engine.
make_keybox ten sec1 10 "$SERIAL"
printf 'Renew_Before_Hours = 300\n' > "$conf"
run_doctor ten AP_CONF="$conf"
lacks "$OUT" "WARN cert-1"
printf 'renew_before_hours = 5\n' > "$conf"
run_doctor ten AP_CONF="$conf"
lacks "$OUT" "WARN cert-1"

# 9. The engine line is read from the real compact JSON layout.
make_engine accepted accepted
make_engine rejected rejected
run_doctor good AP_ENGINE="$W/engines/accepted"
contains "$OUT" "OK   engine"
contains "$OUT" "phase=waiting"
contains "$OUT" "consumer.state=accepted"
run_doctor good AP_ENGINE="$W/engines/rejected"
[ "$RC" -eq 1 ] || fail "an engine reporting a refusal must exit 1"
contains "$OUT" "FAIL engine"
contains "$OUT" "consumer.state=rejected"
mkdir -p "$W/engines"
cat > "$W/engines/fresh" <<'ENGHEAD'
#!/bin/sh
[ "$1" = status ] || exit 2
ENGHEAD
printf "cat <<'ENGEOF'\n%s\nENGEOF\n" "$STATUS_SAMPLE" >> "$W/engines/fresh"
chmod 755 "$W/engines/fresh"
run_doctor good AP_ENGINE="$W/engines/fresh"
contains "$OUT" "consumer.state=unknown"

# 10. The probe must not modify the keybox, and a missing keybox is never created.
before=$(cksum < "$W/good/tricky_store/keybox.xml")
run_doctor good
after=$(cksum < "$W/good/tricky_store/keybox.xml")
[ "$before" = "$after" ] || fail "doctor changed the keybox"
ok
mkdir -p "$W/none/tricky_store" "$W/none/modules/tricky_store"
run_doctor none
[ ! -e "$W/none/tricky_store/keybox.xml" ] || fail "doctor created a keybox"
ok

# 11. No key material in any output: no base64 line of the private key may appear.
run_doctor good
while IFS= read -r line; do
    case "$line" in
        -----*) ;;
        *) lacks "$OUT" "$line" ;;
    esac
done < "$W/good/leaf.priv"

# 12. PIF fingerprint and patch pair. A fixture is a copy of the healthy keybox dir.
NOV_FP='google/bluejay_beta/bluejay:CANARY/ZP11.261016.008/16754936:user/release-keys'
pif_text() { # PATCH [EXPIRY|none] [ID] [EXTRA_LINE]
    printf 'MANUFACTURER=Google\nMODEL=Pixel 6a\nFINGERPRINT=google/bluejay_beta/bluejay:CANARY/%s/16754936:user/release-keys\nBRAND=google\nPRODUCT=bluejay_beta\nDEVICE=bluejay\nRELEASE=CANARY\nID=%s\nINCREMENTAL=16754936\nTYPE=user\nTAGS=release-keys\nSECURITY_PATCH=%s\nDEVICE_INITIAL_SDK_INT=32\n' "${3:-ZP11.261016.008}" "${3:-ZP11.261016.008}" "$1"
    printf '\n# Configuration\nspoofBuild=1\nverboseLogs=0\n'
    [ "${2:-none}" = none ] || printf '\n# Estimated Expiry: %s\n' "$2"
    [ -z "${4:-}" ] || printf '%s\n' "$4"
}
make_pif() { # NAME PIF_TEXT PATCH_TEXT(or "-" for no file)
    rm -rf "$W/$1"; cp -R "$W/good" "$W/$1"
    mkdir -p "$W/$1/modules/playintegrityfix"
    printf '%s' "$2" > "$W/$1/modules/playintegrityfix/custom.pif.prop"
    [ "$3" = - ] || printf '%s' "$3" > "$W/$1/tricky_store/security_patch.txt"
}

# 12a. Healthy pair: exit 0, all four checks OK.
make_pif pif_ok "$(pif_text 2026-11-05 2026-12-20)
" "all=2026-11-05
"
printf 'PIF/Java:DG: [FINGERPRINT]: Xiaomi/dipper/old -> %s\n' "$NOV_FP" >> "$W/log.txt"
run_doctor pif_ok AP_TODAY=2026-11-16
[ "$RC" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "healthy PIF pair exited $RC"; }
contains "$OUT" "OK   pif-format"
contains "$OUT" "ZP11.261016.008 patch 2026-11-05"
contains "$OUT" "OK   pif-expiry"
contains "$OUT" "in 34 days"
contains "$OUT" "OK   patch-pair"
contains "$OUT" "OK   pif-applied"
contains "$OUT" "SUMMARY fail=0"

# 12b. THE INCIDENT: PIF 2026-11-05, Tricky Store all=2026-10-05 -> FAIL, exit 1.
make_pif pif_incident "$(pif_text 2026-11-05 2026-12-20)
" "all=2026-10-05
"
run_doctor pif_incident AP_TODAY=2026-11-16
[ "$RC" -eq 1 ] || { printf '%s\n' "$OUT" >&2; fail "patch mismatch must exit 1, got $RC"; }
contains "$OUT" "FAIL patch-pair"
contains "$OUT" "Tricky Store patch 2026-10-05 differs from PIF patch 2026-11-05"

# 12c. Other patch file layouts.
make_pif pif_date8 "$(pif_text 2026-11-05 2026-12-20)
" "20261105
"
run_doctor pif_date8 AP_TODAY=2026-11-16; contains "$OUT" "OK   patch-pair"
make_pif pif_dash "$(pif_text 2026-11-05 2026-12-20)
" "2026-10-05
"
run_doctor pif_dash AP_TODAY=2026-11-16; contains "$OUT" "FAIL patch-pair"
make_pif pif_sysok "$(pif_text 2026-11-05 2026-12-20)
" "system=202611
"
run_doctor pif_sysok AP_TODAY=2026-11-16; contains "$OUT" "month 2026-11 matches"
make_pif pif_sysbad "$(pif_text 2026-11-05 2026-12-20)
" "system=202610
"
run_doctor pif_sysbad AP_TODAY=2026-11-16; contains "$OUT" "FAIL patch-pair"
make_pif pif_stock "$(pif_text 2026-11-05 2026-12-20)
" "system=prop
"
run_doctor pif_stock AP_TODAY=2026-11-16; contains "$OUT" "OK   patch-pair"; contains "$OUT" "stock patch mode"
make_pif pif_nofile "$(pif_text 2026-11-05 2026-12-20)
" -
run_doctor pif_nofile AP_TODAY=2026-11-16; contains "$OUT" "WARN patch-pair"
make_pif pif_junk "$(pif_text 2026-11-05 2026-12-20)
" "boot=whatever
"
run_doctor pif_junk AP_TODAY=2026-11-16; contains "$OUT" "WARN patch-pair"
make_pif pif_crlf "$(pif_text 2026-11-05 2026-12-20 | sed 's/$/\r/')
" "all=2026-11-05
"
run_doctor pif_crlf AP_TODAY=2026-11-16; contains "$OUT" "OK   pif-format"; contains "$OUT" "OK   patch-pair"

# 12d. Expiry: expired, expiring soon, boundary, unknown.
run_doctor pif_ok AP_TODAY=2026-12-20; contains "$OUT" "FAIL pif-expiry"
run_doctor pif_ok AP_TODAY=2026-12-21; contains "$OUT" "FAIL pif-expiry"
run_doctor pif_ok AP_TODAY=2026-12-17; contains "$OUT" "WARN pif-expiry"; contains "$OUT" "in 3 day"
run_doctor pif_ok AP_TODAY=2026-12-16; contains "$OUT" "OK   pif-expiry"
make_pif pif_noexp "$(pif_text 2026-11-05 none BUILDX)
" "all=2026-11-05
"
run_doctor pif_noexp AP_TODAY=2026-11-16; contains "$OUT" "WARN pif-expiry"; contains "$OUT" "unknown"
# no comments at all but a dated build id (ZP11.261016.008 = 2026-10-16): release from the id, + 42 days
make_pif pif_idfb "$(pif_text 2026-11-05 none)
" "all=2026-11-05
"
run_doctor pif_idfb AP_TODAY=2026-11-16; contains "$OUT" "OK   pif-expiry"; contains "$OUT" "release 2026-10-16 + 42 days"; contains "$OUT" "lower bound"
# "Canary Released" without an explicit expiry: release + 42 days (same as the engine), policy-tunable
make_pif pif_rel "$(pif_text 2026-11-05 none ZP11.261016.008 '# Canary Released: 2026-10-16')
" "all=2026-11-05
"
run_doctor pif_rel AP_TODAY=2026-11-16; contains "$OUT" "OK   pif-expiry"; contains "$OUT" "release 2026-10-16 + 42 days"; contains "$OUT" "in 11 days"
run_doctor pif_rel AP_TODAY=2026-11-27; contains "$OUT" "FAIL pif-expiry"
printf 'pif_lifetime_days = 60\n' > "$W/pif_rel/brain/autopilot.conf"
run_doctor pif_rel AP_TODAY=2026-11-16 AP_CONF="$W/pif_rel/brain/autopilot.conf"; contains "$OUT" "release 2026-10-16 + 60 days"; contains "$OUT" "in 29 days"

# 12e. Format errors: each must FAIL with its own reason.
for pair in 'ID=ZP11.261016.008:ID=ZP11.260918.007:fingerprint_vs_ID' 'PRODUCT=bluejay_beta:PRODUCT=cubs_beta:fingerprint_vs_PRODUCT' \
            'SECURITY_PATCH=2026-11-05:SECURITY_PATCH=2026-11:SECURITY_PATCH_invalid' 'MODEL=Pixel 6a:MODEL=:invalid_value_MODEL' 'MODEL=Pixel 6a:#MODEL=Pixel 6a:missing_MODEL'; do
    from=${pair%%:*}; rest=${pair#*:}; to=${rest%%:*}; why=${rest#*:}
    make_pif pif_bad "$(pif_text 2026-11-05 2026-12-20 | sed "s/^$from\$/$to/")
" "all=2026-11-05
"
    run_doctor pif_bad AP_TODAY=2026-11-16
    contains "$OUT" "FAIL pif-format"; contains "$OUT" "$why"
done
make_pif pif_dup "$(pif_text 2026-11-05 2026-12-20 ZP11.261016.008 'MODEL=Other')
" "all=2026-11-05
"
# a key after "# Configuration" belongs to the module's configuration, not to the fingerprint
run_doctor pif_dup AP_TODAY=2026-11-16; contains "$OUT" "OK   pif-format"

# 12f. pif-applied: other fingerprint spoofed last, and no line at all.
make_pif pif_old "$(pif_text 2026-11-05 2026-12-20)
" "all=2026-11-05
"
: > "$W/log.txt"; printf 'PIF/Java:DG: [FINGERPRINT]: a -> google/cubs_beta/cubs:CANARY/ZP11.260918.007/16484274:user/release-keys\n' >> "$W/log.txt"
run_doctor pif_old AP_TODAY=2026-11-16; contains "$OUT" "WARN pif-applied"; contains "$OUT" "different fingerprint"
: > "$W/log.txt"
run_doctor pif_old AP_TODAY=2026-11-16; contains "$OUT" "WARN pif-applied"; contains "$OUT" "no fingerprint spoof line"

# 12f2. A patch the user pinned (Custom-Patch marker): WARN (kept as chosen), not FAIL; without the marker it is the FAIL of 12b.
make_pif pif_custom "$(pif_text 2026-11-05 2026-12-20)
" "all=2026-09-01
"
mkdir -p "$W/pif_custom/brain/Custom-Patch"                       # an EMPTY directory records no choice
run_doctor pif_custom AP_TODAY=2026-11-16
contains "$OUT" "FAIL patch-pair"
: > "$W/pif_custom/brain/Custom-Patch/2026-09-01"                  # the marker (created by hand since v48)
run_doctor pif_custom AP_TODAY=2026-11-16
contains "$OUT" "WARN patch-pair"; contains "$OUT" "kept as chosen"; lacks "$OUT" "FAIL patch-pair"
rm -f "$W/pif_custom/brain/Custom-Patch/2026-09-01"
run_doctor pif_custom AP_TODAY=2026-11-16
contains "$OUT" "FAIL patch-pair"        # the directory is empty again: no recorded choice

# 12g. Without the module the checks are silent (no new noise for plain Tricky Store setups); read-only.
run_doctor good AP_TODAY=2026-11-16; lacks "$OUT" "pif-"; lacks "$OUT" "patch-pair"
b1=$(cksum < "$W/pif_incident/modules/playintegrityfix/custom.pif.prop"); b2=$(cksum < "$W/pif_incident/tricky_store/security_patch.txt")
run_doctor pif_incident AP_TODAY=2026-11-16
[ "$b1" = "$(cksum < "$W/pif_incident/modules/playintegrityfix/custom.pif.prop")" ] && [ "$b2" = "$(cksum < "$W/pif_incident/tricky_store/security_patch.txt")" ] || fail "doctor modified the PIF files"
ok

printf 'doctor tests PASS (%s assertions)\n' "$PASS"
