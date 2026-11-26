package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTimeSourceIsClearedWhenTheCheckFails(t *testing.T) {
	e := Engine{networkClock: func(context.Context) error { return errors.New("unavailable") }}
	e.status.TimeSource = "android_network_time" // left over from an earlier success
	e.request = func(*http.Request) (*http.Response, error) { return nil, errors.New("offline") }
	if err := e.probeTime(context.Background()); err == nil {
		t.Fatal("expected failure")
	}
	if e.status.TimeSource != "" {
		t.Fatalf("stale time source %q", e.status.TimeSource)
	}
}

// Power sensors differ between devices. A sensor that cannot be read must never block the
// updater forever; a readable one decides.
func TestScreenAndBatteryUnknownSensorsDoNotBlock(t *testing.T) {
	dir := t.TempDir()
	oldB, oldC := backlightPattern, batteryCapacityPath
	t.Cleanup(func() { backlightPattern, batteryCapacityPath = oldB, oldC })
	backlightPattern = filepath.Join(dir, "none", "*", "brightness")
	batteryCapacityPath = filepath.Join(dir, "no-battery")
	if !screen() || !batteryOK() {
		t.Fatal("unknown sensors must not block")
	}
}

func TestScreenUsesAnyLitBacklightAndBatteryThreshold(t *testing.T) {
	dir := t.TempDir()
	oldB, oldC := backlightPattern, batteryCapacityPath
	t.Cleanup(func() { backlightPattern, batteryCapacityPath = oldB, oldC })
	backlightPattern = filepath.Join(dir, "backlight", "*", "brightness")
	for name, v := range map[string]string{"panelA": "0", "panelB": "120"} {
		os.MkdirAll(filepath.Join(dir, "backlight", name), 0755)
		os.WriteFile(filepath.Join(dir, "backlight", name, "brightness"), []byte(v+"\n"), 0644)
	}
	if !screen() {
		t.Fatal("a lit second backlight must count as screen on")
	}
	os.WriteFile(filepath.Join(dir, "backlight", "panelB", "brightness"), []byte("0\n"), 0644)
	if screen() {
		t.Fatal("all backlights are off")
	}
	batteryCapacityPath = filepath.Join(dir, "capacity")
	os.WriteFile(batteryCapacityPath, []byte("14\n"), 0644)
	if batteryOK() {
		t.Fatal("14% is below the threshold")
	}
	os.WriteFile(batteryCapacityPath, []byte("15\n"), 0644)
	if !batteryOK() {
		t.Fatal("15% meets the threshold")
	}
}

// The stale copy must go even when a (here damaged) journal blocks the rest of recovery.
func TestRecoveryRemovesLegacyBackupBeforeTouchingTheJournal(t *testing.T) {
	dir := t.TempDir()
	legacy := filepath.Join(dir, "keybox.autopilot-backup.xml")
	os.WriteFile(legacy, []byte("old key material"), 0600)
	os.MkdirAll(filepath.Join(dir, ".autopilot-transaction"), 0700)
	os.WriteFile(filepath.Join(dir, ".autopilot-transaction", "journal.json"), []byte("not json"), 0600)
	e := Engine{root: dir, ram: dir, brain: dir}
	if err := e.recoverTransaction(); err == nil {
		t.Fatal("a damaged journal must still be reported")
	}
	if exists(legacy) {
		t.Fatal("legacy backup survived")
	}
}

// Manual import must obey the same consumer contract as the automatic path.
func importEngine(t *testing.T, refuse bool) (*Engine, []byte, []byte, string) {
	t.Helper()
	e, old, next := rollbackEngine(t, "")
	e.requireConsumer = true
	if !refuse {
		e.logs = &fakeLog{lines: func(n string) []string { return []string{"I BoxAutoPilot: probe=" + n} }}
	}
	path := filepath.Join(t.TempDir(), "import.xml")
	os.WriteFile(path, next, 0600)
	return e, old, next, path
}

func TestImportRollsBackAKeyTheConsumerRefuses(t *testing.T) {
	e, old, _, path := importEngine(t, true)
	err := e.importKey(context.Background(), path)
	got, _ := os.ReadFile(e.target())
	if err == nil || !strings.Contains(err.Error(), "refused") || string(got) != string(old) {
		t.Fatalf("err=%v restored=%v", err, string(got) == string(old))
	}
}

func TestImportKeepsAKeyTheConsumerAccepts(t *testing.T) {
	e, _, next, path := importEngine(t, false)
	if err := e.importKey(context.Background(), path); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(e.target())
	if string(got) != string(next) || e.status.Consumer.State != ConsumerAccepted {
		t.Fatal("accepted import was not kept", e.status.Consumer)
	}
}

func TestImportRequiresTheConsumer(t *testing.T) {
	e, old, _, path := importEngine(t, false)
	e.modulesRoot = t.TempDir() // consumer not installed
	err := e.importKey(context.Background(), path)
	got, _ := os.ReadFile(e.target())
	if err == nil || !strings.Contains(err.Error(), "required keybox consumer") || string(got) != string(old) {
		t.Fatalf("err=%v", err)
	}
}
