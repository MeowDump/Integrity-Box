package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// bannedNoReplacement returns a fixture whose installed fingerprint is on the maintainer's denylist while the
// archive offers nothing newer (it serves the very same build), i.e. the window in which DEVICE integrity fails.
func bannedNoReplacement(t *testing.T) *maintainFixture {
	t.Helper()
	m := newMaintain(t, octoberPIF, "all=2026-10-05\n")
	m.net.files[pifArchiveBase+"meow.prop"] = octoberPIF
	return m
}

// While the installed fingerprint is banned and nothing eligible exists, the next search comes within the hour,
// not after the usual six.
func TestBannedFingerprintWithoutReplacementIsSearchedAgainWithinTheHour(t *testing.T) {
	m := bannedNoReplacement(t)
	m.maintain(true)
	if m.e.status.PIF.State != "banned" {
		t.Fatalf("fixture: state %q", m.e.status.PIF.State)
	}
	if d := m.e.pifSearchDue - m.e.uptime(); d <= 0 || d > time.Hour.Seconds() {
		t.Fatalf("banned, nothing eligible: next search in %vs, want within an hour", d)
	}
}

// A fingerprint that is only expiring (still working) keeps the relaxed pace.
func TestExpiringFingerprintWithoutReplacementKeepsTheSlowPace(t *testing.T) {
	m := newMaintain(t, novemberMeow, "all=2026-11-05\n")
	m.e.policy.PIF.RenewBefore = 90 * 24 * time.Hour // expiring, not banned
	m.maintain(true)
	if m.e.status.PIF.State != "expiring" {
		t.Fatalf("fixture: state %q", m.e.status.PIF.State)
	}
	if d := m.e.pifSearchDue - m.e.uptime(); d < (5 * time.Hour).Seconds() {
		t.Fatalf("only expiring: next search in %vs, want about six hours", d)
	}
}

// The denylist is refreshed in the same pass as every search of a banned fingerprint (no separate timer), but a
// healthy fingerprint still waits for the regular denylist interval.
func TestDenylistRidesAlongWithTheSearchOfABannedFingerprint(t *testing.T) {
	m := bannedNoReplacement(t)
	clock := 100000.0
	m.e.bootClock = func() float64 { return clock }
	m.maintain(true)
	first := m.net.hits[pifReleaseAPI]
	if first == 0 {
		t.Fatal("the first pass must read the denylist")
	}
	clock += (time.Hour + time.Minute).Seconds() // the search is due again, the regular denylist timer (6h) is not
	m.maintain(true)
	if m.net.hits[pifReleaseAPI] <= first {
		t.Fatal("a search pass for a banned fingerprint must refresh the denylist too")
	}

	h := newMaintain(t, novemberMeow, "all=2026-11-05\n")
	hc := 100000.0
	h.e.bootClock = func() float64 { return hc }
	h.maintain(true)
	hf := h.net.hits[pifReleaseAPI]
	hc += (time.Hour + time.Minute).Seconds()
	h.maintain(true)
	if h.net.hits[pifReleaseAPI] != hf {
		t.Fatal("a healthy fingerprint must not refresh the denylist before its regular interval")
	}
}

// The Google source is asked at most once per pifGoogleEvery by one phone, even when the archive is polled hourly.
func TestGoogleSourceIsQueriedAtMostOncePerInterval(t *testing.T) {
	m := bannedNoReplacement(t)
	m.e.policy.PIF.Sources = []string{"archive", "google"}
	googleNet(t, m)
	clock := 100000.0
	m.e.bootClock = func() float64 { return clock }
	m.e.pifFindCandidate(context.Background(), pifFile{Props: map[string]string{"PRODUCT": "bluejay_beta"}}, "banned", m.e.pifPolicy())
	first := m.net.hits[pifFlashPage]
	if first != 1 {
		t.Fatalf("first search must ask Google once, asked %d times", first)
	}
	clock += (time.Hour + time.Minute).Seconds()
	m.e.pifFindCandidate(context.Background(), pifFile{Props: map[string]string{"PRODUCT": "bluejay_beta"}}, "banned", m.e.pifPolicy())
	if m.net.hits[pifFlashPage] != first {
		t.Fatal("Google must not be asked again within its interval")
	}
	clock += pifGoogleEvery.Seconds()
	m.e.pifFindCandidate(context.Background(), pifFile{Props: map[string]string{"PRODUCT": "bluejay_beta"}}, "banned", m.e.pifPolicy())
	if m.net.hits[pifFlashPage] != first+1 {
		t.Fatal("Google must be asked again once its interval has passed")
	}
}

// The module's name for the fingerprint file changed between releases: the file that exists is used, and a missing
// one is named after the module directory.
func TestPifPropFollowsTheModulesFileName(t *testing.T) {
	dir := t.TempDir()
	mod := filepath.Join(dir, "integrity-box")
	if err := os.MkdirAll(mod, 0755); err != nil {
		t.Fatal(err)
	}
	e := &Engine{moduleRoot: mod}
	if got := e.pifPropPath(); got != filepath.Join(mod, "config.meow") {
		t.Fatalf("integrity-box without a file: %s", got)
	}
	old := filepath.Join(dir, "playintegrityfix")
	if err := os.MkdirAll(old, 0755); err != nil {
		t.Fatal(err)
	}
	e = &Engine{moduleRoot: old}
	if got := e.pifPropPath(); got != filepath.Join(old, "custom.pif.prop") {
		t.Fatalf("older module id without a file: %s", got)
	}
	if err := os.WriteFile(filepath.Join(old, "config.meow"), []byte("x"), 0644); err != nil {
		t.Fatal(err)
	}
	if got := e.pifPropPath(); got != filepath.Join(old, "config.meow") {
		t.Fatalf("an existing config.meow must win: %s", got)
	}
}

// The module's boot script restores security_patch.txt from Box-Brain/patch.txt: when the engine moves the patch to a
// new fingerprint, that copy follows (and a missing file is not created).
func TestPatchTxtFollowsTheRepairedPatch(t *testing.T) {
	m := newMaintain(t, octoberPIF, "all=2026-10-05\n")
	txt := filepath.Join(m.e.brain, "patch.txt")
	if err := os.WriteFile(txt, []byte("2026-10-05\n"), 0644); err != nil {
		t.Fatal(err)
	}
	m.maintain(true) // October is banned: replaced by the November Canary, patch repaired to 2026-11-05
	if m.patchText() != "all=2026-11-05\n" {
		t.Fatalf("fixture: patch %q", m.patchText())
	}
	if b, _ := os.ReadFile(txt); string(b) != "2026-11-05\n" {
		t.Fatalf("patch.txt must follow the patch, got %q", b)
	}
	if err := os.Remove(txt); err != nil {
		t.Fatal(err)
	}
	m.maintain(false)
	if _, err := os.Stat(txt); err == nil {
		t.Fatal("a missing patch.txt must not be created")
	}
}
