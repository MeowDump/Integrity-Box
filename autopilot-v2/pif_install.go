package main

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Configuration section used when there is no previous file to inherit it from (same defaults
// the module ships).
const pifDefaultTail = `# Configuration
spoofBuild=1
spoofProps=1
spoofPixel=1
spoofApps=1
spoofPhotos=1
spoofPatch=1
spoofVendingFinger=0
spoofProvider=0
spoofSignature=0
spoofVendingSdk=0
verboseLogs=0`

// pifRefreshBudget is the slice of the budget the denylist refresh may use (a variable for the tests).
var pifRefreshBudget = 18 * time.Second

// pifBannedSearchEvery is how soon a replacement is searched again while the installed fingerprint is banned
// and nothing eligible exists yet. Short, because every hour without a working fingerprint is an hour of
// failing DEVICE integrity; the Google source stays on its own slower pace (pifGoogleEvery).
var pifBannedSearchEvery = time.Hour

// pifGoogleEvery is the minimum gap between two queries of the Google Flash Tool source from one phone, whatever
// the state: it is the heavier source (a page plus an API call) and must not be hit by every device at once.
var pifGoogleEvery = 6 * time.Hour

const (
	pifBudget       = 45 * time.Second // the whole fingerprint maintenance of one cycle
	pifMaxBackoff   = 24 * time.Hour
	pifStaleTmpAge  = time.Hour
	pifScope        = "pif|" // HTTP cooldown scope of this contour
	pifProbeDefault = 500 * time.Millisecond
)

// pifApplied matches the line Play Integrity Fork logs when it spoofs a process.
var pifApplied = regexp.MustCompile(`PIF/Java:DG: \[FINGERPRINT\]: .* -> (.+?)\s*$`)

// pifBackoff returns 2h, 4h, ... capped at 24h for n consecutive failures (n >= 1).
func pifBackoff(n int) time.Duration {
	d := 2 * time.Hour
	for i := 1; i < n && d < pifMaxBackoff; i++ {
		d *= 2
	}
	if d > pifMaxBackoff {
		d = pifMaxBackoff
	}
	return d
}

// pifMaintain is the time-dependent half of the contour: refresh the denylist, audit with a
// verified clock, repair the patch pair, and replace a withdrawn/expired/expiring fingerprint.
// It runs after the keybox work, with its own time budget and HTTP cooldown scope, and never
// returns an error: the keybox contour must not depend on it.
func (e *Engine) pifMaintain(parent context.Context, automatic bool) {
	if !e.pifActive() || e.dryRun {
		return
	}
	ctx, cancel := context.WithTimeout(parent, pifBudget)
	defer cancel()
	e.scope = pifScope
	defer func() { e.scope = "" }()

	pol := e.pifPolicy()
	// The contour no longer depends on the keybox work having reached its own time check (it runs even
	// when Tricky Store is absent): verify the clock here unless this cycle already did.
	fresh := e.timeFresh
	e.timeFresh = false // the flag belongs to ONE cycle: consume it so a later call checks again
	if !fresh {
		_ = e.checkTime(ctx)
		e.timeFresh = false // our own check serves this call only
	}
	timeOK := e.status.TimeState == "verified"
	e.loadBanned()
	cleanStale(filepath.Dir(e.pifPropPath()), pifStaleTmpAge)
	cleanStale(e.root, pifStaleTmpAge)
	// The denylist rides along with the replacement search: while the fingerprint is withdrawn or dead, every
	// search pass refreshes it with the same budget, so a new ban is known no later than the next search.
	urgent := (e.status.PIF.State == "banned" || e.status.PIF.State == "expired") && e.uptime() >= e.pifSearchDue
	if timeOK && (!automatic || urgent || e.uptime() >= e.pifBannedDue) {
		wait := 6 * time.Hour
		// the denylist refresh gets its own slice of the budget: a slow network must not eat the search
		refreshCtx, stop := context.WithTimeout(ctx, pifRefreshBudget)
		err := e.refreshBanned(refreshCtx)
		stop()
		if err != nil {
			e.pifBannedFails++
			wait = pifBackoff(e.pifBannedFails) // 2, 4, 8, 16, 24 h: an outage must not be hammered
			logEvent("pif_denylist_error", "local", e.pifBannedFails)
		} else {
			e.pifBannedFails = 0
		}
		e.pifBannedDue = e.uptime() + wait.Seconds()
	}
	cur, patch := e.pifAudit(timeOK)
	if err := e.pifSyncPatch(cur, patch); err != nil {
		logEvent("pif_cycle_error", "local", 0)
	}
	if pol.Mode != "auto" || !timeOK {
		return
	}
	state := e.status.PIF.State
	if !(state == "banned" || state == "expired" || state == "expiring" || state == "absent" || state == "ok" && pol.FollowLatest) {
		return
	}
	if automatic && e.uptime() < e.pifSearchDue {
		return
	}
	// Fail closed: without a denylist we cannot tell a good candidate from a withdrawn one.
	if !e.pifBannedKnown {
		e.pifSearchDue = e.uptime() + pifBackoff(1).Seconds()
		e.status.PIF.Reason = "no_replacement:denylist_unavailable"
		e.publish()
		return
	}
	cand, why := e.pifFindCandidate(ctx, cur, state, pol)
	if cand == nil {
		wait := 6 * time.Hour
		if state == "banned" {
			wait = pifBannedSearchEvery // withdrawn fingerprint: look again soon (archive only, see pifFindCandidate)
		}
		if strings.HasSuffix(why, "_unavailable") {
			e.pifSearchFails++
			wait = pifBackoff(e.pifSearchFails)
		} else {
			e.pifSearchFails = 0 // the sources answered: there is simply nothing eligible yet
		}
		e.pifSearchDue = e.uptime() + wait.Seconds()
		e.status.PIF.Reason = "no_replacement:" + why
		logEvent("pif_no_replacement", "local", 0)
		e.publish()
		return
	}
	if err := e.pifInstall(ctx, *cand, cur); err != nil {
		e.pifFailures++
		e.pifSearchDue = e.uptime() + pifBackoff(e.pifFailures).Seconds()
		e.status.PIF.Reason = "install_failed: " + err.Error()
		logEvent("pif_install_failed", "local", e.pifFailures)
	} else {
		e.pifFailures, e.pifSearchFails = 0, 0
	}
	e.publish()
}

// pifInstall writes the candidate, proves the write by reading it back, repairs the patch pair,
// then asks Play Services to restart and looks for the spoof in the log. Nothing is kept on
// disk as a backup (rule: no copies on the phone); the previous bytes live in memory only until
// the install is settled. Every failure after the write restores the previous file AND realigns
// the patch with it.
func (e *Engine) pifInstall(ctx context.Context, cand, cur pifFile) error {
	pol := e.pifPolicy()
	wl, err := lock(filepath.Join(e.ram, "write.lock"))
	if err != nil {
		return errors.New("write lock busy")
	}
	defer wl.Close()
	prop := e.pifPropPath()
	orig, absent, err := readOptional(prop, pifMaxBytes)
	if err != nil {
		return err
	}
	// The file may have been edited (WebUI, user) since the audit: work from what is on disk now,
	// and give up if it is no longer the file the decision was made for.
	tail := pifDefaultTail
	if !absent {
		now, perr := parsePIF(orig)
		if perr != nil || now.Props["FINGERPRINT"] != cur.Props["FINGERPRINT"] || now.patch() != cur.patch() {
			return errors.New("the fingerprint file changed during the search; try again next cycle")
		}
		if now.Tail != "" {
			tail = now.Tail
		}
	}
	// Refuse BEFORE touching anything when the pair could not be made consistent: replacing the
	// fingerprint without the matching patch recreates the incident of 2026-11-16.
	pb, pAbsent, perr := readOptional(e.patchPath(), 4096)
	if perr != nil {
		return errors.New("security_patch.txt unreadable: " + perr.Error())
	}
	pf := patchFile{Kind: "none"}
	if !pAbsent {
		pf = parsePatchFile(pb)
	}
	if !pol.SyncPatch && pf.Kind != "stock" && pf.Kind != "none" && pf.pair(cand.patch()) != "match" {
		return errors.New("would leave the patch pair mismatched while pif_sync_patch is off")
	}
	data := cand.render(tail, cand.releaseDate(), cand.expiry(pol.Lifetime), e.now().Format("2006-01-02"))
	if _, err = parsePIF(data); err != nil {
		return errors.New("rendered file invalid: " + err.Error())
	}
	restoreAll := func() { e.pifRestore(prop, orig, absent, pb, pAbsent) }
	if err = e.writeFile(prop, data, 0644); err != nil {
		restoreAll() // the rename may have happened before a later step (directory sync) failed
		return err
	}
	back, _, err := readOptional(prop, pifMaxBytes)
	if err != nil || !bytes.Equal(back, data) {
		restoreAll()
		return errors.New("readback differs; previous state restored")
	}
	f, p := e.pifAudit(true)
	if err = e.pifSyncPatch(f, p); err != nil {
		restoreAll()
		return errors.New("patch pair repair failed; previous file restored: " + err.Error())
	}
	if e.status.PIF.PatchPair == "mismatch" {
		// Defensive tripwire: unreachable by construction (the pair is checked before the write and repaired right
		// after it), kept because this is the line that would otherwise leave the incident's state on the phone.
		restoreAll()
		return errors.New("patch pair still mismatched; previous file restored")
	}
	applied, evidence := e.pifProbe(ctx, cand)
	e.status.PIF.Applied, e.status.PIF.Evidence, e.status.PIF.Action = applied, evidence, "installed"
	e.status.PIF.Reason = ""
	logEvent("pif_installed", "local", 0)
	return nil
}

// pifRestore puts the previous fingerprint file and the previous security_patch.txt back from the
// in-memory copies taken before the write, then lets the patch policy realign the pair if the
// previous state was itself split. Restoring the patch bytes directly (instead of relying on the
// resync alone) matters because the resync is skipped for an override pair and in dry runs.
func (e *Engine) pifRestore(prop string, orig []byte, absent bool, patchOrig []byte, patchAbsent bool) {
	if absent {
		_ = os.Remove(prop) // there was no file before: do not leave the candidate behind as if it were the user's
	} else {
		_ = e.writeMeta(prop, orig, 0644)
	}
	if patchAbsent {
		_ = os.Remove(e.patchPath())
	} else {
		_ = e.writeMeta(e.patchPath(), patchOrig, 0644)
	}
	if !absent {
		f, p := e.pifAudit(true)
		_ = e.pifSyncPatch(f, p)
	}
}

var pifPlayProcesses = []string{"com.google.android.gms.unstable", "com.google.android.gms", "com.android.vending"}

const (
	pifDroidGuard     = "com.google.android.gms/.droidguard.DroidGuardService"
	pifDroidGuardPing = "com.google.android.gms.droidguard.service.PING"
)

// pifRespawnDelay lets the killed process die before the next one is requested.
var pifRespawnDelay = 500 * time.Millisecond

// runCommand is the real command runner of the contour (tests replace it through Engine.runCommand).
func runCommand(ctx context.Context, name string, args ...string) error {
	return exec.CommandContext(ctx, name, args...).Run()
}

// restartPlayServices makes Play Services run DroidGuard again with the new fingerprint: kill the
// DroidGuard, Play Services and Play Store processes, then ask Android to start its service so the process comes back NOW (a plain
// kill, which killpi.sh and Integrity Box's restart_google_services do, leaves it dead until some
// app happens to use DroidGuard, so nothing is spoofed or logged for a long time). The PING intent
// is the one DroidGuardService itself declares. One `am` call = one JVM start: acceptable, it runs
// only when a fingerprint was actually installed.
func (e *Engine) restartPlayServices(ctx context.Context) error {
	if e.restartGMS != nil {
		return e.restartGMS(ctx)
	}
	run := e.runCommand
	if run == nil {
		run = runCommand
	}
	// The same three processes the module's own restart_google_services kills: Play Services and the Play
	// Store may keep an attestation built with the previous fingerprint (observed on the phone: after a
	// short window with a wrong file DEVICE stayed red until all three were restarted, killing only the
	// DroidGuard process was not enough).
	for _, proc := range pifPlayProcesses {
		_ = run(ctx, "killall", proc) // non-zero when it was not running: fine
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(pifRespawnDelay):
	}
	return run(ctx, "am", "startservice", "-n", pifDroidGuard, "-a", pifDroidGuardPing)
}

// pifProbe restarts Play Services and looks, after a marker with a random code, for the line in
// which PIF reports spoofing the candidate. Result is accepted|unknown only: PIF never says
// "refused", so silence is never read as acceptance and never causes a rollback.
func (e *Engine) pifProbe(ctx context.Context, cand pifFile) (string, string) {
	pol := e.pifPolicy()
	if !pol.Probe {
		return "not_probed", "disabled"
	}
	var logs logChannel = androidLog{} // same default as the consumer probe (probe.go)
	if e.logs != nil {
		logs = e.logs
	}
	nonce := newNonce()
	if err := logs.Mark(ctx, nonce); err != nil {
		return "unknown", "no_log_channel"
	}
	_ = e.restartPlayServices(ctx)
	poll := e.probePoll
	if poll <= 0 {
		poll = pifProbeDefault
	}
	deadline := time.Now().Add(pol.ProbeWait)
	evidence := "marker_not_visible"
	for {
		lines, err := logs.Lines(ctx)
		if err == nil {
			if after, seen := linesAfterMarker(lines, nonce); seen {
				evidence = "no_spoof_line"
				for i := len(after) - 1; i >= 0; i-- {
					if m := pifApplied.FindStringSubmatch(after[i]); m != nil {
						if strings.TrimSpace(m[1]) == cand.Props["FINGERPRINT"] {
							return "accepted", "applied_in_log"
						}
						evidence = "different_fingerprint_seen"
					}
				}
			}
		}
		if time.Now().After(deadline) || ctx.Err() != nil {
			return "unknown", evidence
		}
		select {
		case <-ctx.Done():
			return "unknown", evidence
		case <-time.After(poll):
		}
	}
}
