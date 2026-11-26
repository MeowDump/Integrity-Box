package main

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func auditEngine(t *testing.T, log *fakeLog) (*Engine, string) {
	t.Helper()
	dir, modules := t.TempDir(), t.TempDir()
	os.MkdirAll(filepath.Join(modules, "tricky_store"), 0755)
	b := fixture(t, false)
	trustFixture(t, b)
	os.WriteFile(filepath.Join(dir, "keybox.xml"), b, 0600)
	e := &Engine{root: dir, ram: dir, brain: dir, modulesRoot: modules, logs: log, probeSettle: 30 * time.Millisecond, probePoll: 5 * time.Millisecond, bootClock: func() float64 { return 1000 }}
	e.status.Local = e.health()
	return e, dir
}

func TestAuditDemotesRememberedRejectedKey(t *testing.T) {
	e, _ := auditEngine(t, &fakeLog{lines: func(n string) []string { return nil }})
	if err := e.rememberRejected(e.status.Local.Fingerprint); err != nil {
		t.Fatal(err)
	}
	e.auditConsumer(context.Background(), true)
	if e.status.Local.State != "consumer_rejected" || e.status.Consumer.State != ConsumerRejected || e.status.Consumer.Evidence != "remembered_rejection" {
		t.Fatalf("%+v %s", e.status.Consumer, e.status.Local.State)
	}
}

func TestAuditProbesOncePerKeyAndInterval(t *testing.T) {
	log := &fakeLog{}
	log.lines = func(n string) []string { return []string{"I BoxAutoPilot: probe=" + n} }
	e, _ := auditEngine(t, log)
	for i := 0; i < 3; i++ {
		e.auditConsumer(context.Background(), true)
	}
	if log.marks != 1 || e.status.Consumer.State != ConsumerAccepted {
		t.Fatal(log.marks, e.status.Consumer)
	}
	e.bootClock = func() float64 { return 1000 + 7*3600 }
	e.auditConsumer(context.Background(), true)
	if log.marks != 2 {
		t.Fatal("probe not repeated after the interval", log.marks)
	}
}

func TestAuditDoesNotProbeInDryRunOrWithoutConsumer(t *testing.T) {
	log := &fakeLog{lines: func(n string) []string { return nil }}
	e, _ := auditEngine(t, log)
	e.auditConsumer(context.Background(), false)
	if log.marks != 0 {
		t.Fatal("dry run must not touch the keybox")
	}
	e.modulesRoot = t.TempDir()
	e.auditConsumer(context.Background(), true)
	if log.marks != 0 || e.status.Consumer.Present {
		t.Fatal("probed an absent consumer")
	}
}

func TestRequiredConsumerMissingStopsBeforeNetwork(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "keybox.xml"), fixture(t, true), 0600)
	requests := 0
	e := Engine{root: dir, ram: dir, brain: dir, modulesRoot: t.TempDir(), requireConsumer: true, timeCheck: func(context.Context) error { return nil }}
	e.request = func(*http.Request) (*http.Response, error) { requests++; return reply(404, nil), nil }
	err := e.cycle(context.Background(), false)
	if err == nil || !strings.Contains(err.Error(), "required keybox consumer") || requests != 0 {
		t.Fatal(err, requests)
	}
}

func TestCandidateRejectedBeforeIsSkipped(t *testing.T) {
	b := fixture(t, false)
	trustFixture(t, b)
	h, _ := inspect(b, time.Now())
	e := Engine{brain: t.TempDir()}
	e.rememberRejected(h.Fingerprint)
	e.request = func(*http.Request) (*http.Response, error) { return reply(200, secondaryEncode(b)), nil }
	if _, _, err := e.candidate(context.Background(), "https://rawbin.dpejoh.com/key/TAKR/40", true); err == nil || !strings.Contains(err.Error(), "rejected") {
		t.Fatal(err)
	}
}

// With no usable previous key a refusal keeps the file but must demote it, so that a
// replacement is not blocked by the "must outlive the current key" rule.
func TestRefusedInstallWithoutFallbackDemotesLocalKey(t *testing.T) {
	log := &fakeLog{}
	log.lines = func(n string) []string { return []string{"I BoxAutoPilot: probe=" + n, rejectionLine} }
	e, _ := auditEngine(t, log)
	installed, _ := os.ReadFile(e.target())
	got := e.verifyInstalled(context.Background(), installed, e.status.Local, Health{State: "expired"}, []byte("previous"))
	if got != "keep_rejected" || e.status.Local.State != "consumer_rejected" || !e.isRejected(e.status.Local.Fingerprint) {
		t.Fatal(got, e.status.Local.State)
	}
}
