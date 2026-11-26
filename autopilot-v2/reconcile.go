package main

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math"
	"math/big"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func generation(brain string) string {
	var b strings.Builder
	for _, n := range configFlags {
		fmt.Fprintf(&b, "%s:%t;", n, exists(filepath.Join(brain, n)))
	}
	for _, mod := range []string{"teesim", "oh_my_keymint"} {
		p := filepath.Join("/data/adb/modules", mod)
		fmt.Fprintf(&b, "%s:%t:%t:%t;", mod, exists(p), exists(filepath.Join(p, "disable")), exists(filepath.Join(p, "remove")))
	}
	rev, err := readLimited(filepath.Join(brain, ".autopilot-config-revision"), 64)
	if err != nil && !os.IsNotExist(err) {
		b.WriteString("revision_unreadable")
	}
	b.Write(rev)
	return b.String()
}

// errSearchBusy: another cycle (or a manual pif-refresh from the Action button) holds the search lock.
var errSearchBusy = errors.New("search already running")

func (e *Engine) cycle(ctx context.Context, automatic bool) error {
	base := ctx
	e.timeFresh = false
	searchLock, lockErr := lock(filepath.Join(e.ram, "search.lock"))
	if lockErr != nil {
		return errSearchBusy
	}
	defer searchLock.Close()
	// The fingerprint contour is registered BEFORE every early return of this cycle (a transaction to
	// recover, a bad configuration revision, missing anchors, a missing keybox consumer ...): BASIC
	// depends on PIF alone, and the two contours must not hide behind each other's problems. It runs
	// when the key work is finished, with its own time budget and HTTP cooldown scope.
	e.reloadPolicy()
	pifFile, pifPatch := e.pifAudit(false) // expiry is judged later, with a clock verified in this cycle
	if er := e.pifSyncPatch(pifFile, pifPatch); er != nil {
		logEvent("pif_cycle_error", "local", 0)
	}
	defer func() { e.pifMaintain(base, automatic) }()
	if !e.dryRun {
		f, er := lock(filepath.Join(e.ram, "write.lock"))
		if er != nil {
			return er
		}
		er = e.recoverTransaction()
		f.Close()
		if er != nil {
			return er
		}
	}
	e.status.Phase = "auditing"
	e.reloadPolicy()
	e.publish()
	if _, revisionErr := configRevision(e.brain); revisionErr != nil {
		return errors.New("invalid configuration revision")
	}
	previousLocal := e.status.Local
	e.status.Local = e.health()
	if _, er := e.knownAnchors(); er != nil {
		return errors.New("anchor metadata unavailable; current file preserved")
	}
	e.auditConsumer(ctx, !e.dryRun)
	// The fingerprint contour is independent of the keybox contour: a failure here is logged and
	// never blocks (or is blocked by) the key. Patch repair needs no network and no clock.
	if e.requireConsumer && !e.status.Consumer.Present {
		e.status.Phase = "required_consumer_missing"
		return errors.New("required keybox consumer is not installed")
	}
	ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	if !e.dryRun {
		if er := e.checkTime(ctx); er != nil {
			e.status.Phase = "time_unknown"
			return er
		}
	}
	e.crl(ctx)
	h := e.status.Local
	if h.State == "time_unknown" {
		return errors.New("system clock unknown")
	}
	needs := h.State != "valid" || h.Anchor || e.isRevoked(h) || time.Until(h.Expires) < e.renewBefore()
	if !needs && e.forcedTier == "" {
		return nil
	}
	event := ""
	if e.isRevoked(h) {
		event = "revoked:" + h.Fingerprint
	} else if h.State == "expired" {
		event = "expired:" + h.Fingerprint
	}
	if automatic && event != "" && e.urgentEvidence != event {
		e.urgentEvidence = event
		urgent := e.lastSearchBoot + 1800
		if (e.isRevoked(h) || previousLocal.State == "valid") && e.automaticFetchDue > urgent {
			e.automaticFetchDue = urgent
		}
	}
	if automatic && e.uptime() < e.automaticFetchDue {
		return nil
	}
	e.searched = true
	e.lastSearchBoot = e.uptime()
	original, err := readKey(e.target())
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	expected := sha256Hex(original)
	gen := generation(e.brain)
	tiers := []string{"Megatron", "secondary"}
	if exists(filepath.Join(e.brain, "disable-default-source")) {
		tiers = []string{"secondary", "Megatron"}
	}
	// Anchor is only a last resort when the current certificate is unusable.
	if h.State != "valid" || e.isRevoked(h) || !trusted(h) {
		tiers = append(tiers, "Megatron2")
	}
	if e.forcedTier != "" {
		tiers = []string{e.forcedTier}
	}
	for _, tier := range tiers {
		e.status.Phase = "fetching"
		e.status.Source = tier
		e.publish()
		var data []byte
		var candidate Health
		if tier == "secondary" {
			data, candidate, err = e.secondary(ctx)
		} else {
			data, candidate, err = e.candidate(ctx, pifArchiveBase+tier, false)
		}
		if err != nil {
			continue
		}
		if !e.eligible(candidate) {
			continue
		}

		if ctx.Err() != nil {
			return ctx.Err()
		}
		// Same rule as manual import: never install without a fresh revocation list.
		if e.status.Revocation != "fresh" {
			e.status.Phase = "waiting_for_revocation_list"
			return errors.New("revocation status unknown or stale; installation deferred")
		}
		e.status.Phase = "installing"
		e.publish()
		if automatic {
			if er := e.checkTime(ctx); er != nil {
				return er
			}
		}
		err = e.install(data, expected, gen, automatic)
		if err != nil {
			return err
		}
		e.status.Local = e.health()
		e.status.Phase = "installed"
		if e.dryRun {
			e.status.Phase = "dry_run_candidate_validated"
			e.status.Local = candidate
			return nil
		}
		// Tricky Store watches its config; no global keystore restart is required.
		if e.verifyInstalled(ctx, data, candidate, h, original) == "keep" {
			return nil
		}
		// The consumer refused this file: refresh compare-and-commit inputs, try the next tier.
		original, _ = readKey(e.target())
		h = e.status.Local
		expected = sha256Hex(original)
	}
	return errors.New("no suitable replacement; current file preserved")
}

func (e *Engine) recordSearchResult(err error, failures int) int {
	if !e.searched {
		return failures
	}
	if err == nil {
		e.automaticFetchDue = 0
		return 0
	}
	e.automaticFetchDue = e.uptime() + jitter(backoff(failures)).Seconds()
	return failures + 1
}

func localAuditDeadline(h Health, now time.Time) time.Time {
	if h.State != "valid" || !h.Expires.After(now) {
		return time.Time{}
	}
	boundary := h.Expires.Add(-renewWindow)
	if boundary.After(now) {
		return boundary
	}
	return h.Expires
}

func (e *Engine) targetSignature() string {
	st, err := os.Lstat(e.target())
	if err != nil {
		return "unavailable"
	}
	inode := uint64(0)
	if sys, ok := st.Sys().(*syscall.Stat_t); ok {
		inode = uint64(sys.Ino)
	}
	return fmt.Sprintf("%d:%d:%d", inode, st.Size(), st.ModTime().UnixNano())
}

func jitter(d time.Duration) time.Duration {
	n, err := rand.Int(rand.Reader, big.NewInt(201))
	if err != nil {
		return d
	}
	v := d + time.Duration(int64(d)*(n.Int64()-100)/1000)
	if v > 12*time.Hour {
		v = 12 * time.Hour
	}
	return v
}

func backoff(failures int) time.Duration {
	switch failures {
	case 0:
		return 30 * time.Minute
	case 1:
		return 2 * time.Hour
	case 2:
		return 6 * time.Hour
	default:
		return 12 * time.Hour
	}
}

func charging() bool {
	for _, n := range []string{"usb", "pc_port", "dc"} {
		b, _ := os.ReadFile("/sys/class/power_supply/" + n + "/online")
		if strings.TrimSpace(string(b)) == "1" {
			return true
		}
	}
	return false
}

// Sensor locations (variables so tests can point them at temporary files).
var (
	backlightPattern    = "/sys/class/backlight/*/brightness"
	batteryCapacityPath = "/sys/class/power_supply/battery/capacity"
)

// screen reports whether any display backlight is lit. A device with no readable backlight
// cannot be judged, so it counts as "on": an unknown sensor never blocks the updater (the
// battery, temperature and charger gates still apply).
func screen() bool {
	files, _ := filepath.Glob(backlightPattern)
	known := false
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		v, err := strconv.Atoi(strings.TrimSpace(string(b)))
		if err != nil {
			continue
		}
		known = true
		if v > 0 {
			return true
		}
	}
	return !known
}

func tooHot() bool {
	b, err := os.ReadFile("/sys/class/power_supply/battery/temp")
	if err != nil {
		return false
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(b)))
	return err == nil && n >= 450
}

// batteryOK is false only for a readable level below 15%; an unreadable level is unknown
// and does not block (devices without a battery node, such as boxes on mains power).
func batteryOK() bool {
	b, err := os.ReadFile(batteryCapacityPath)
	if err != nil {
		return true
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(b)))
	return err != nil || n >= 15
}

func bootSeconds() float64 {
	b, err := os.ReadFile("/proc/uptime")
	if err != nil {
		if runtime.GOOS != "linux" {
			return float64(time.Now().Unix())
		}
		return math.NaN()
	}
	f := strings.Fields(string(b))
	if len(f) == 0 {
		return math.NaN()
	}
	v, err := strconv.ParseFloat(f[0], 64)
	if err != nil || v < 0 {
		return math.NaN()
	}
	return v
}

// failureRetry: how long to wait after a failed cycle. An unset clock (typically right after boot) is fixed within
// minutes, so that case is retried soon; everything else waits two hours.
// An offline phone must not run a full cycle every few minutes forever, so the wait doubles: 5, 10, 20, ... up to 2 hours.
func failureRetry(phase string, clockFailures int) time.Duration {
	if phase != "time_unknown" {
		return 2 * time.Hour
	}
	d := 5 * time.Minute
	for i := 1; i < clockFailures && d < 2*time.Hour; i++ {
		d *= 2
	}
	if d > 2*time.Hour {
		d = 2 * time.Hour
	}
	return d
}

func (e *Engine) daemon(ctx context.Context) error {
	if math.IsNaN(e.uptime()) {
		return errors.New("BOOTTIME unavailable")
	}
	f, err := lock(filepath.Join(e.ram, "daemon.lock"))
	if err != nil {
		return err
	}
	defer f.Close()
	applyBackground()
	recoveryLock, recoveryErr := lock(filepath.Join(e.ram, "write.lock"))
	if recoveryErr != nil {
		return recoveryErr
	}
	recoveryErr = e.recoverTransaction()
	recoveryLock.Close()
	if recoveryErr != nil {
		e.status.Phase = "recovery_required"
		e.status.Reason = recoveryErr.Error()
		e.publish()
		return recoveryErr
	}
	if _, revisionErr := configRevision(e.brain); revisionErr != nil {
		e.status.Phase = "configuration_required"
		e.status.Reason = "invalid configuration revision"
		e.publish()
		return errors.New("invalid configuration revision")
	}
	deadline := time.Now().Add(60 * time.Second)
	bootCtx, bootCancel := context.WithTimeout(ctx, 60*time.Second)
	defer bootCancel()
	for {
		b, er := exec.CommandContext(bootCtx, "getprop", "sys.boot_completed").Output()
		if er != nil {
			return errors.New("boot status unavailable")
		}
		if strings.TrimSpace(string(b)) == "1" {
			break
		}
		if time.Now().After(deadline) {
			return errors.New("boot not complete")
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(time.Second):
		}
	}
	e.status.Ready = true
	e.status.Running = true
	e.status.PID = os.Getpid()
	defer func() { e.status.Ready = false; e.status.Running = false; e.status.Phase = "stopped"; e.publish() }()
	failures := 0
	clockFailures := 0
	next := time.Now().Add(2 * time.Minute)
	nextBoot := e.uptime() + 120
	var screenSince time.Time
	lastAttemptBoot := float64(-3600)
	wasCharging := charging()
	observedFile := e.targetSignature()
	observedPolicy := e.policySignature()
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	for {
		if !e.enabled() {
			return nil
		}
		e.status.Next = time.Now().Add(time.Duration((nextBoot - e.uptime()) * float64(time.Second)))
		e.publish()
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
		signature := e.targetSignature()
		if signature != observedFile {
			observedFile = signature
			nextBoot = e.uptime()
		}
		if policy := e.policySignature(); policy != observedPolicy {
			observedPolicy = policy
			nextBoot = e.uptime()
		}
		chargingNow := charging()
		if chargingNow && !wasCharging && e.uptime()-lastAttemptBoot >= 1800 {
			nextBoot = e.uptime()
		}
		wasCharging = chargingNow
		on := screen()
		if on && screenSince.IsZero() {
			screenSince = time.Now()
		}
		if !on {
			screenSince = time.Time{}
		}
		if e.uptime() < nextBoot {
			continue
		}
		if tooHot() || !chargingNow && (!batteryOK() || !on || time.Since(screenSince) < 25*time.Second) {
			e.status.Phase = "deferred_power_or_screen"
			continue
		}
		lastAttemptBoot = e.uptime()
		e.searched = false
		err = e.cycle(ctx, true)
		if errors.Is(err, errSearchBusy) {
			// Somebody else (the Action button) holds the lock for a few seconds: try again soon, do not
			// treat it as a failure that pushes the next cycle two hours away.
			nextBoot = e.uptime() + 120
			e.status.Phase = "waiting"
			continue
		}
		failures = e.recordSearchResult(err, failures)
		if err != nil {
			e.status.Reason = err.Error()

			if e.status.Phase == "time_unknown" {
				clockFailures++
			} else {
				clockFailures = 0
			}
			next = time.Now().Add(failureRetry(e.status.Phase, clockFailures))
			if e.automaticFetchDue > e.uptime() {
				next = time.Now().Add(time.Duration((e.automaticFetchDue - e.uptime()) * float64(time.Second)))
			}
		} else {
			e.status.Reason = ""

			next = time.Now().Add(12 * time.Hour)
			if e.status.Local.Anchor || time.Until(e.status.Local.Expires) < e.renewBefore() {
				next = time.Now().Add(30 * time.Minute)
			}
		}
		if e.automaticFetchDue > e.uptime() && time.Until(next).Seconds() > e.automaticFetchDue-e.uptime() {
			next = time.Now().Add(time.Duration((e.automaticFetchDue - e.uptime()) * float64(time.Second)))
		}
		if e.status.TimeState == "verified" {
			audit := localAuditDeadline(e.status.Local, time.Now())
			if !audit.IsZero() && audit.Before(next) {
				next = audit
			}
		}
		if d := e.pifDeadline(); !d.IsZero() && d.Before(next) {
			next = d
		}
		nextBoot = e.uptime() + time.Until(next).Seconds()
		if e.status.Revocation == "fresh" {
			remaining := e.crlTTL.Seconds() - (e.uptime() - e.crlBoot)
			if remaining < 1800 {
				remaining = 1800
			}
			if remaining < time.Until(next).Seconds() {
				next = time.Now().Add(time.Duration(remaining * float64(time.Second)))
				nextBoot = e.uptime() + remaining
			}
		}
		if e.status.Revocation != "fresh" && time.Until(next) > 2*time.Hour {
			next = time.Now().Add(2 * time.Hour)
			nextBoot = e.uptime() + 7200
		}
		if exists("/system/bin/log") {
			message := "cycle complete; local=" + e.status.Local.State + "; source=" + e.status.Source + "; result=" + e.status.Reason
			_ = exec.Command("/system/bin/log", "-p", "i", "-t", "BoxAutoPilot", message).Run()
		}
		e.status.Phase = "waiting"
	}
}
