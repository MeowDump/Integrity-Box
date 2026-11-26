"""Mutation harness for the PIF contour (run after changing pif*.go): every mutation is written into the tracked source files (they are edited IN PLACE, so run it on a clean
tree), tested, and restored from an in-memory copy of the originals in `finally`; after a kill -9 run `git checkout autopilot-v2` to restore them. Exit status reflects survivors. Usage: python3 mutate_pif.py <autopilot-v2 dir>; every mutation must be reported as killed"""
import os
import subprocess
import sys

D = sys.argv[1].rstrip('/') + '/'
FILES = ['pif.go', 'pif_engine.go', 'pif_install.go', 'pif_source.go', 'pif_google.go', 'transport.go', 'reconcile.go', 'clock.go',
         '../pif_policy.sh', '../webroot/common_scripts/doctor.sh']
SHELL_TESTS = {'policy': 'test_pif_policy.sh', 'doctor': 'test_doctor.sh'}   # runner name -> script in this directory
ORIG = {f: open(D + f).read() for f in FILES}
# The month-long simulations are slow (~35 s): only mutations of timing/backoff/denylist-state logic run them.
LIFE = {'unverified clock polls every 30 min', 'failed listing marks the denylist known', 'empty listing not known', 'denylist backoff flat', 'search backoff flat', 'contour not registered in the cycle', 'denylist replaced instead of merged'}
# Defense in depth: each of these guards is made redundant by another one, so removing either ALONE cannot change
# behaviour (the flag is cleared both when a cycle starts and when the contour consumes it).
M_RUNNER = {'user-chosen patch ignored by the boot script policy': 'policy', 'doctor fails a user-chosen patch': 'doctor'}
EQUIVALENT = {'fresh-clock flag not consumed', 'cycle does not reset the clock flag'}
RUN = 'PIF|Maintain|Probe|Eligibility|RefreshBanned|Patch|Incident|Audit|Classify|Release|Denylist|Google|NewestCanary|Generated|Remote|Install|Strict|Failed|Cooldown|Budget|DoctorAgrees|PlayServices|Restore|WriteLock|Torn|Detects|Empty|TestCycle|UserChosen|Clock|Deadline|EachMaintain|AStable|AMissing|Undated|BusyLock|EarlyReturn|Unrepairable|UnverifiedClock|SlowDenylist|ListingDown|Listing|NeverTrusted|Oversized|UnknownSource|RealCommandRunner|PolicyDefaults|ZeroPolicy|ColonFields|ImpossibleDate|EveryPIFEndpoint|NativeCurl|FailedFirstInstall|BannedFingerprint|ExpiringFingerprint|RidesAlong|GoogleSourceIs'

M = [
    ("curl may negotiate HTTP/2 again", 'transport.go', '"--include", "--http1.1",', '"--include",'),
    ("non-release candidates accepted", 'pif_source.go', 'if cand.Props["TYPE"] != "user" || cand.Props["TAGS"] != "release-keys" {', 'if false {'),
    ("first-install failure keeps the moved patch", 'pif_install.go', '_ = e.writeMeta(e.patchPath(), patchOrig, 0644)', '_ = patchOrig'),
    ("denylist replaced instead of merged", 'pif_source.go', '	merged := make(map[string]bool, len(e.pifBanned)+len(fresh))\n	for k := range e.pifBanned {\n		merged[k] = true\n	}', '	merged := make(map[string]bool, len(fresh))'),
    ("fail-closed gate removed", 'pif_install.go', 'if !e.pifBannedKnown {', 'if false {'),
    ("patch sanity removed (future)", 'pif_source.go', '|| pt.After(now.AddDate(0, 0, 62)) {', '|| false {'),
    ("patch sanity removed (vs build)", 'pif_source.go', '(pt.Before(rel.AddDate(0, 0, -35)) || pt.After(rel.AddDate(0, 0, 125)))', 'false'),
    ("remote dates believed", 'pif_source.go', '		cand.Released, cand.Expires = time.Time{}, time.Time{}', '		_ = cand'),
    ("expiry clamp removed", 'pif.go', 'if !r.IsZero() && f.Expires.After(r.Add(2*lifetime)) {', 'if false {'),
    ("stale tail used", 'pif_install.go', '		if now.Tail != "" {\n			tail = now.Tail\n		}', '		if cur.Tail != "" {\n			tail = cur.Tail\n		}'),
    ("changed-during-search guard removed", 'pif_install.go', 'if perr != nil || now.Props["FINGERPRINT"] != cur.Props["FINGERPRINT"] || now.patch() != cur.patch() {', 'if perr != nil {'),
    ("early refusal removed", 'pif_install.go', 'if !pol.SyncPatch && pf.Kind != "stock" && pf.Kind != "none" && pf.pair(cand.patch()) != "match" {', 'if false && pf.Kind != "" {'),
    ("restore does not realign patch", 'pif_install.go', '	f, p := e.pifAudit(true)\n	_ = e.pifSyncPatch(f, p)\n}', '	_, _ = e.pifAudit(true)\n}'),
    ("pif scope not set", 'pif_install.go', '	e.scope = pifScope', '	e.scope = ""'),
    ("strict context ignored", 'pif_engine.go', 'case e.strictContext:', 'case false:'),
    ("budget removed", 'pif_install.go', 'ctx, cancel := context.WithTimeout(parent, pifBudget)', 'ctx, cancel := context.WithCancel(parent)'),
    ("backoff flat", 'pif_install.go', '		d *= 2', '		d += 0'),
    ("names sorted/oldest kept", 'pif_source.go', '		names = names[len(names)-pifMaxBanned:]', '		names = names[:pifMaxBanned]'),
    ("stale cleanup removes everything", 'pif_engine.go', 'time.Since(info.ModTime()) > age', 'time.Since(info.ModTime()) > -age'),
    ("scoped cooldown not scoped", 'transport.go', 'e.hostNext[e.scope+u.Hostname()] = time.Now().Add(delay)', 'e.hostNext[u.Hostname()] = time.Now().Add(delay)'),
    ("write lock skipped", 'pif_install.go', '	wl, err := lock(filepath.Join(e.ram, "write.lock"))\n	if err != nil {\n		return errors.New("write lock busy")\n	}\n	defer wl.Close()', '	var err error'),
    ("probe restart skipped", 'pif_install.go', '	_ = e.restartPlayServices(ctx)', '	_ = ctx'),
    ("respawn request skipped", 'pif_install.go', '	return run(ctx, "am", "startservice", "-n", pifDroidGuard, "-a", pifDroidGuardPing)', '	return nil'),
    ("respawn uses a different intent", 'pif_install.go', 'pifDroidGuardPing = "com.google.android.gms.droidguard.service.PING"', 'pifDroidGuardPing = "com.google.android.gms.droidguard.service.NOPE"'),
    ("empty listing not known", 'pif_source.go', '		e.pifBannedKnown = true // an authoritative empty list: nothing is withdrawn, remembered bans stay\n', ''),
    ("denylist backoff flat", 'pif_install.go', '			wait = pifBackoff(e.pifBannedFails) // 2, 4, 8, 16, 24 h: an outage must not be hammered', '			wait = 2 * time.Hour'),
    ("search backoff flat", 'pif_install.go', '			wait = pifBackoff(e.pifSearchFails)', '			wait = 2 * time.Hour'),
    ("fresh-clock flag not consumed", 'pif_install.go', '	e.timeFresh = false // the flag belongs to ONE cycle: consume it so a later call checks again\n', ''),
    ("own clock check leaks freshness", 'pif_install.go', '		e.timeFresh = false // our own check serves this call only\n', ''),
    ("contour not registered in the cycle", 'reconcile.go', '	defer func() { e.pifMaintain(base, automatic) }()', '	defer func() { _ = base }()'),
    ("cycle does not reset the clock flag", 'reconcile.go', '	e.timeFresh = false\n	searchLock', '	searchLock'),
    ("checkTime does not mark freshness", 'clock.go', '	e.timeFresh = true\n', ''),
    ("non-Canary fingerprints are managed", 'pif_engine.go', 'case perr == nil && !absent && f.Props["RELEASE"] != "CANARY":', 'case false:'),
    ("JSON-fed module gets a competing .prop", 'pif_engine.go', 'case absent && e.pifJSONSource():', 'case false:'),
    ("a missing file is never recreated", 'pif_install.go', 'state == "expiring" || state == "absent" ||', 'state == "expiring" ||'),
    ("undated candidates accepted", 'pif_source.go', '	if candExp.IsZero() {\n		return false, "candidate_undated"', '	if false {\n		return false, "candidate_undated"'),
    ("a busy lock is an ordinary error", 'reconcile.go', '		return errSearchBusy\n', '		return errors.New("search already running")\n'),
    ("patch-sync wake never backs off", 'pif_engine.go', '			return now.Add(pifBackoff(e.pifSyncFails)) // an unwritable patch file is not retried every 30 minutes', '			return soon'),
    ("unverified clock polls every 30 min", 'pif_engine.go', '		if !clockOK {\n			return later\n		}\n		if wait :=', '		if wait :='),
    ("failed listing marks the denylist known", 'pif_source.go', '	if listed {\n		e.pifBannedKnown = true\n	}', '	e.pifBannedKnown = true'),
    ("refresh has no own budget", 'pif_install.go', 'refreshCtx, stop := context.WithTimeout(ctx, pifRefreshBudget)', 'refreshCtx, stop := context.WithCancel(ctx)'),
    ("sync failures not counted", 'pif_engine.go', '		e.pifSyncFails++\n		e.status.PIF.Reason = "patch_sync_failed: " + err.Error()', '		e.status.PIF.Reason = "patch_sync_failed: " + err.Error()'),
    ("only DroidGuard is killed", 'pif_install.go', 'var pifPlayProcesses = []string{"com.google.android.gms.unstable", "com.google.android.gms", "com.android.vending"}', 'var pifPlayProcesses = []string{"com.google.android.gms.unstable"}'),
    ("engine repairs a user-chosen patch", 'pif_engine.go', 'if st.PatchPair == "mismatch" && e.customPatchMarker() {', 'if false {'),
    ("an empty marker dir counts as a choice", 'pif_engine.go', 'return err == nil && len(entries) > 0', 'return err == nil && len(entries) >= 0'),
    ("user-chosen patch ignored by the boot script policy", '../pif_policy.sh', '    [ -n "$(ls -A "${PIF_BOX:-/data/adb/Box-Brain}/Custom-Patch" 2>/dev/null)" ] && return 1\n', ''),
    ("doctor fails a user-chosen patch", '../webroot/common_scripts/doctor.sh', '            elif [ -n "$(ls -A "$BRAIN/Custom-Patch" 2>/dev/null)" ]; then', '            elif false; then'),
    ("banned fingerprint searched only every 6h", 'pif_install.go', 'var pifBannedSearchEvery = time.Hour', 'var pifBannedSearchEvery = 6 * time.Hour'),
    ("denylist not refreshed with the search of a banned fingerprint", 'pif_install.go', 'if timeOK && (!automatic || urgent || e.uptime() >= e.pifBannedDue) {', 'if timeOK && (!automatic || urgent && false || e.uptime() >= e.pifBannedDue) {'),
    ("google asked on every search", 'pif_source.go', 'if e.uptime() < e.pifGoogleDue {', 'if false {'),
    ("readback not checked", 'pif_install.go', 'if err != nil || !bytes.Equal(back, data) {', 'if err != nil || !bytes.Equal(back, data) && false {'),
]


def precheck():
    """Refuse to run on an uncommitted tree (a crash could then lose work) or with tests the filter never runs."""
    st = subprocess.run(['git', 'status', '--porcelain', '--'] + FILES, cwd=D, capture_output=True, text=True)
    if st.stdout.strip():
        print('REFUSED: commit (or stash) your changes first; the harness edits these files in place:\n' + st.stdout)
        sys.exit(3)
    # Coverage is demanded for the tests OF THIS CONTOUR (pif*_test.go): the older keybox suite is not what these
    # mutations are about. A test that the filter never runs would make every mutation it should catch look "alive".
    import glob
    import re
    tests = []
    for path in sorted(glob.glob(os.path.join(D, 'pif*_test.go'))):
        tests += re.findall(r'^func (Test\w+)\(', open(path).read(), re.M)
    both = RUN + '|Lifecycle|DaemonCycleRate'
    missing = [t for t in tests if not re.search(both, t)]
    if missing:
        print('REFUSED: these tests are never run by any mutation (add a word of each name to RUN):\n  ' + '\n  '.join(missing))
        sys.exit(3)
    print(f'precheck ok: clean tree, {len(tests)} tests all reachable by the filter')


def restore():
    for f, s in ORIG.items():
        open(D + f, 'w').write(s)


precheck()
bad = 0
try:
    base = subprocess.run(['go', 'test', '-count=1', '-run', RUN, './...'], cwd=D, capture_output=True, text=True)
    if base.returncode != 0:
        print('BASELINE RED, aborting:\n', base.stdout[-800:], base.stderr[-400:])
        sys.exit(2)
    for desc, f, a, b in M:
        restore()
        s = ORIG[f]
        if s.count(a) != 1:
            print(f'SETUP FAIL ({s.count(a)} matches): {desc}')
            bad += 1
            continue
        open(D + f, 'w').write(s.replace(a, b, 1))
        build = subprocess.run(['go', 'build', '-o', '/dev/null', '.'], cwd=D, capture_output=True, text=True) if f.endswith('.go') else subprocess.CompletedProcess([], 0, '', '')
        if build.returncode != 0:
            print(f'NOT COMPILABLE (mutation proves nothing): {desc}: {build.stderr.strip().splitlines()[-1][:90]}')
            bad += 1
            continue
        runner = M_RUNNER.get(desc)
        if runner:
            r = subprocess.run(['sh', SHELL_TESTS[runner]], cwd=D, capture_output=True, text=True)
        else:
            pattern = RUN + '|Lifecycle|DaemonCycleRate' if desc in LIFE else RUN
            r = subprocess.run(['go', 'test', '-count=1', '-run', pattern, './...'], cwd=D, capture_output=True, text=True)
        if r.returncode == 0 and desc in EQUIVALENT:
            print('equivalent (redundant guard):', desc)
        elif r.returncode == 0:
            print('SURVIVED (bad):', desc)
            bad += 1
        else:
            print('killed (good):', desc)
finally:
    restore()
chk = subprocess.run(['go', 'test', '-count=1', '-run', RUN, './...'], cwd=D, capture_output=True, text=True)
print('restored, baseline green:', chk.returncode == 0)
dirty = subprocess.run(['git', 'status', '--porcelain', '--'] + FILES, cwd=D, capture_output=True, text=True).stdout.strip()
if dirty:
    print('ERROR: the working tree is not restored:\n' + dirty)
    bad += 1
sys.exit(1 if bad else 0)
