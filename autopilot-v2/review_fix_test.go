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

// stubSELinux (a no-op on Android) puts harmless "chcon" and "ls -Zd" in PATH so the real install and rollback
// transaction can run on a host without SELinux. Android-only tests still use the real tools.
func stubSELinux(t *testing.T) {
	t.Helper()
	if exists("/system/bin/chcon") {
		return // a real Android device: exercise the real SELinux tools
	}
	bin := t.TempDir()
	os.WriteFile(filepath.Join(bin, "chcon"), []byte("#!/bin/sh\nexit 0\n"), 0755)
	os.WriteFile(filepath.Join(bin, "ls"), []byte("#!/bin/sh\nif [ \"$1\" = \"-Zd\" ]; then echo \"u:object_r:adb_data_file:s0 $2\"; exit 0; fi\nexec /bin/ls \"$@\"\n"), 0755)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// rollbackEngine: a usable key with 10h left, a 72h candidate that the consumer refuses.
func rollbackEngine(t *testing.T, tier string) (*Engine, []byte, []byte) {
	t.Helper()
	stubSELinux(t)
	dir, modules := t.TempDir(), t.TempDir()
	os.MkdirAll(filepath.Join(modules, "tricky_store"), 0755)
	old := fixtureWith(t, fixtureOpts{ValidFor: 10 * time.Hour})
	next := fixtureWith(t, fixtureOpts{ValidFor: 72 * time.Hour})
	trustAll(t, old, next)
	os.WriteFile(filepath.Join(dir, "keybox.xml"), old, 0644)
	log := &fakeLog{}
	log.lines = func(n string) []string {
		got, _ := os.ReadFile(filepath.Join(dir, "keybox.xml"))
		if string(got) == string(next) {
			return []string{"I BoxAutoPilot: probe=" + n, rejectionLine}
		}
		return []string{"I BoxAutoPilot: probe=" + n}
	}
	e := &Engine{root: dir, ram: dir, brain: dir, modulesRoot: modules, logs: log, probeSettle: 30 * time.Millisecond, probePoll: 5 * time.Millisecond, forcedTier: tier, timeCheck: func(context.Context) error { return nil }}
	e.request = func(r *http.Request) (*http.Response, error) {
		if r.URL.Path == "/attestation/status" {
			return reply(200, []byte(`{"entries":{}}`)), nil
		}
		return reply(200, officialEncode(next)), nil
	}
	return e, old, next
}

func TestRefusedInstallIsRolledBackOnAnyHost(t *testing.T) {
	e, old, next := rollbackEngine(t, "Megatron")
	_ = e.cycle(context.Background(), false)
	got, _ := os.ReadFile(e.target())
	nh, _ := inspect(next, time.Now())
	if string(got) != string(old) || !e.isRejected(nh.Fingerprint) {
		t.Fatal("refused key was not rolled back and remembered")
	}
}

// The user may switch autopilot off between the install and the probe. Restoring the
// previous key is cleanup of our own write and must not depend on the enable flag.
func TestRollbackIsNotBlockedByDisablingAutopilot(t *testing.T) {
	e, old, next := rollbackEngine(t, "Megatron")
	e.moduleRoot = t.TempDir()
	os.WriteFile(filepath.Join(e.brain, "autopilot"), nil, 0600)
	previous := e.health()
	e.status.Local = previous
	nh, _ := inspect(next, time.Now())
	if err := e.install(next, sha256Hex(old), generation(e.brain), true); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(e.moduleRoot, "disable"), nil, 0600)
	result := e.verifyInstalled(context.Background(), next, nh, previous, old)
	got, _ := os.ReadFile(e.target())
	if string(got) != string(old) {
		t.Fatal("refused key left in place:", result)
	}
}

// A rollback is not a new source: it must not be recorded as the tier that was just tried.
func TestRollbackDoesNotRecordTheTierAsSourceOrAnchor(t *testing.T) {
	for _, tier := range []string{"Megatron", "Megatron2"} {
		e, old, _ := rollbackEngine(t, tier)
		_ = e.cycle(context.Background(), false)
		oh, _ := inspect(old, time.Now())
		if got := e.installedSource(oh.Fingerprint); got != "unknown" {
			t.Fatalf("%s: rolled-back key recorded as %q", tier, got)
		}
		if e.isKnownAnchor(oh.Identity) {
			t.Fatalf("%s: previous key remembered as an emergency anchor", tier)
		}
	}
}

// A disabled module leaves target.txt behind; that must not make the consumer look present.
func TestDisabledModuleWithStaleTargetIsNotPresent(t *testing.T) {
	modules, root := t.TempDir(), t.TempDir()
	os.MkdirAll(filepath.Join(modules, "tricky_store"), 0755)
	os.WriteFile(filepath.Join(modules, "tricky_store", "disable"), nil, 0600)
	os.WriteFile(filepath.Join(root, "target.txt"), []byte("x"), 0600)
	e := Engine{modulesRoot: modules, root: root}
	if ok, how := e.consumerPresent(trickyStore); ok {
		t.Fatalf("disabled module reported present via %s", how)
	}
	removed := t.TempDir()
	os.MkdirAll(filepath.Join(removed, "tricky_store"), 0755)
	os.WriteFile(filepath.Join(removed, "tricky_store", "remove"), nil, 0600)
	e.modulesRoot = removed
	if ok, _ := e.consumerPresent(trickyStore); ok {
		t.Fatal("module marked for removal reported present")
	}
}

func TestDryRunReportsUnknownConsumerNotEmpty(t *testing.T) {
	e, _ := auditEngine(t, &fakeLog{lines: func(string) []string { return nil }})
	e.auditConsumer(context.Background(), false)
	if e.status.Consumer.State != ConsumerUnknown {
		t.Fatalf("state=%q", e.status.Consumer.State)
	}
}

// A pattern that matches everything would make every probe "rejected".
func TestPolicyRejectsOverBroadRejectionPatterns(t *testing.T) {
	// Long enough to pass the length rule, but each one matches the empty string.
	for _, bad := range []string{".*", "a*", "x?", "^", "(|a)", "ab", "a*b*c*", "(abc)?", "(x|y)*"} {
		p, notes := parsePolicy("consumer.tricky_store.rejection = " + bad + "\n")
		if len(p.Consumer.compiled) != 0 || len(notes) == 0 {
			t.Fatalf("%q accepted", bad)
		}
	}
	if p, notes := parsePolicy("consumer.tricky_store.rejection = Load Keybox failed\n"); len(p.Consumer.compiled) != 1 || len(notes) != 0 {
		t.Fatal(notes)
	}
}

func TestRefusalMemoryResetsWhenConsumerPolicyChanges(t *testing.T) {
	dir := t.TempDir()
	e := Engine{brain: dir}
	os.WriteFile(filepath.Join(dir, "autopilot.conf"), []byte("consumer.tricky_store.rejection = old wording\n"), 0600)
	e.reloadPolicy()
	fp := strings.Repeat("a", 64)
	e.rememberRejected(fp)
	e.reloadPolicy() // unchanged policy keeps the memory
	if !e.isRejected(fp) {
		t.Fatal("memory dropped without a policy change")
	}
	os.WriteFile(filepath.Join(dir, "autopilot.conf"), []byte("consumer.tricky_store.rejection = new wording\n"), 0600)
	e.reloadPolicy()
	if e.isRejected(fp) {
		t.Fatal("memory must reset when the consumer description changes")
	}
}

// Backups exist only inside a real transaction and are removed when it completes.
// Nothing with a private key may stay on the device after an install.
func TestInstallLeavesNoPersistentBackup(t *testing.T) {
	stubSELinux(t)
	dir := t.TempDir()
	old := fixtureWith(t, fixtureOpts{ValidFor: 10 * time.Hour})
	next := fixtureWith(t, fixtureOpts{ValidFor: 72 * time.Hour})
	os.WriteFile(filepath.Join(dir, "keybox.xml"), old, 0644)
	e := Engine{root: dir, ram: dir, brain: dir}
	if err := e.install(next, sha256Hex(old), generation(dir), false); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(e.target()); string(got) != string(next) {
		t.Fatal("install did not commit")
	}
	entries, _ := os.ReadDir(dir)
	for _, ent := range entries {
		name := ent.Name()
		if strings.Contains(name, "backup") || strings.HasSuffix(name, ".bak") || name == ".autopilot-transaction" || strings.HasPrefix(name, ".autopilot-stage-") {
			t.Fatalf("leftover after install: %s", name)
		}
	}
}

// A backup left behind by an earlier engine version is cleaned up on the next recovery pass.
func TestRecoveryRemovesLegacyPersistentBackup(t *testing.T) {
	dir := t.TempDir()
	legacy := filepath.Join(dir, "keybox.autopilot-backup.xml")
	os.WriteFile(legacy, []byte("old key material"), 0600)
	e := Engine{root: dir, ram: dir, brain: dir}
	if err := e.recoverTransaction(); err != nil {
		t.Fatal(err)
	}
	if exists(legacy) {
		t.Fatal("legacy backup survived recovery")
	}
}
