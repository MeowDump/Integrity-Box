package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// fakeLog scripts the platform log: lines receives the nonce written by Mark.
type fakeLog struct {
	markErr error
	lines   func(nonce string) []string
	nonce   string
	marks   int
}

func (f *fakeLog) Mark(_ context.Context, nonce string) error {
	f.nonce = nonce
	f.marks++
	return f.markErr
}
func (f *fakeLog) Lines(context.Context) ([]string, error) { return f.lines(f.nonce), nil }

const rejectionLine = "11-13 15:39:46.478  2119  2119 E TrickyStore: Load Keybox failed with exception"

func noTrigger() error { return nil }

func TestProbeStates(t *testing.T) {
	marker := func(n string) string { return "11-13 15:39:45.000  1  1 I BoxAutoPilot: probe=" + n }
	cases := []struct {
		name         string
		log          *fakeLog
		trigger      func() error
		state, proof string
	}{
		{"rejection after marker", &fakeLog{lines: func(n string) []string { return []string{marker(n), rejectionLine} }}, noTrigger, ConsumerRejected, "rejection_logged"},
		{"marker visible and no rejection", &fakeLog{lines: func(n string) []string { return []string{marker(n)} }}, noTrigger, ConsumerAccepted, "no_rejection_logged"},
		{"old rejection before the marker is ignored", &fakeLog{lines: func(n string) []string { return []string{rejectionLine, marker(n)} }}, noTrigger, ConsumerAccepted, "no_rejection_logged"},
		{"other log tags are ignored", &fakeLog{lines: func(n string) []string {
			return []string{marker(n), "W AndroidKeyStoreSpi(31639): A valid keybox.xml was not present"}
		}}, noTrigger, ConsumerAccepted, "no_rejection_logged"},
		{"marker never visible means no usable log channel", &fakeLog{lines: func(string) []string { return []string{"unrelated"} }}, noTrigger, ConsumerUnknown, "marker_not_visible"},
		{"log writer missing", &fakeLog{markErr: errors.New("no log binary"), lines: func(string) []string { return nil }}, noTrigger, ConsumerUnknown, "no_log_channel"},
		{"trigger failure", &fakeLog{lines: func(n string) []string { return []string{marker(n)} }}, func() error { return errors.New("denied") }, ConsumerUnknown, "trigger_failed"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := probeConsumer(context.Background(), trickyStore, c.log, c.trigger, 30*time.Millisecond, 5*time.Millisecond)
			if got.State != c.state || got.Evidence != c.proof {
				t.Fatalf("got %+v want %s/%s", got, c.state, c.proof)
			}
		})
	}
}

func TestReloadTriggerDoesNotModifyFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "keybox.xml")
	os.WriteFile(path, fixture(t, false), 0600)
	before, _ := os.ReadFile(path)
	st1, _ := os.Stat(path)
	if err := reloadTrigger(path)(); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(path)
	st2, _ := os.Stat(path)
	if string(before) != string(after) || !st1.ModTime().Equal(st2.ModTime()) {
		t.Fatal("trigger modified the keybox")
	}
	if reloadTrigger(filepath.Join(t.TempDir(), "missing.xml"))() == nil {
		t.Fatal("missing file must be an error")
	}
}

func TestConsumerPresence(t *testing.T) {
	modules, root := t.TempDir(), t.TempDir()
	e := Engine{modulesRoot: modules, root: root}
	if ok, how := e.consumerPresent(trickyStore); ok || how != "not_installed" {
		t.Fatal(ok, how)
	}
	os.MkdirAll(filepath.Join(modules, "tricky_store"), 0755)
	if ok, how := e.consumerPresent(trickyStore); !ok || how != "module" {
		t.Fatal(ok, how)
	}
	os.WriteFile(filepath.Join(modules, "tricky_store", "disable"), nil, 0600)
	if ok, _ := e.consumerPresent(trickyStore); ok {
		t.Fatal("disabled module counted as present")
	}
	os.WriteFile(filepath.Join(root, "target.txt"), nil, 0600)
	if ok, how := e.consumerPresent(trickyStore); ok || how != "module_disabled" {
		t.Fatal("stale target.txt of a disabled module must not count", ok, how)
	}
	fork := Engine{modulesRoot: t.TempDir(), root: root} // unknown fork sharing the directory contract
	if ok, how := fork.consumerPresent(trickyStore); !ok || how != "directory" {
		t.Fatal(ok, how)
	}
}

func TestRejectedMemoryEvictsOldestAndToleratesCorruption(t *testing.T) {
	dir := t.TempDir()
	e := Engine{brain: dir}
	hash := func(i int) string { s := sha256.Sum256([]byte(fmt.Sprint(i))); return hex.EncodeToString(s[:]) }
	for i := 0; i < 70; i++ {
		if err := e.rememberRejected(hash(i)); err != nil {
			t.Fatal(err)
		}
	}
	if e.isRejected(hash(0)) || !e.isRejected(hash(69)) {
		t.Fatal("eviction order wrong")
	}
	os.WriteFile(filepath.Join(dir, ".autopilot-rejected.json"), []byte("not json"), 0600)
	if e.isRejected(hash(69)) {
		t.Fatal("corrupt memory must read as empty")
	}
	if err := e.rememberRejected(hash(1)); err != nil || !e.isRejected(hash(1)) {
		t.Fatal(err)
	}
}

func TestAfterInstallDecision(t *testing.T) {
	valid, expired := Health{State: "valid"}, Health{State: "expired"}
	rejected, accepted, unknown := probeResult{ConsumerRejected, "rejection_logged"}, probeResult{ConsumerAccepted, "x"}, probeResult{ConsumerUnknown, "x"}
	for _, c := range []struct {
		res  probeResult
		prev Health
		had  bool
		want string
	}{
		{accepted, valid, true, "keep"},
		{unknown, valid, true, "keep"}, // an unobservable consumer never causes a rollback
		{rejected, valid, true, "rollback"},
		{rejected, expired, true, "keep_rejected"},
		{rejected, valid, false, "keep_rejected"},
	} {
		if got := afterInstallDecision(c.res, c.prev, c.had); got != c.want {
			t.Fatalf("%+v: got %s want %s", c, got, c.want)
		}
	}
}
