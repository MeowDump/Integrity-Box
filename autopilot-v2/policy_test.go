package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPolicyDefaultsWhenFileMissingOrEmpty(t *testing.T) {
	p, notes := parsePolicy("")
	d := defaultPolicy()
	if len(notes) != 0 || p.CandidateBudget != d.CandidateBudget || p.RenewBefore != 24*time.Hour || p.ProbeInterval != 6*time.Hour || p.ProbeSettle != 5*time.Second || strings.Join(p.SourcePriority, ",") != "TAKR,@Xiaomi_Lei_Jun,@Samsung_Jae_Yong,Yuri" {
		t.Fatalf("%+v %v", p, notes)
	}
	e := Engine{} // zero value must behave like the defaults
	if e.candidateBudget() != 5 || e.renewBefore() != 24*time.Hour || e.probeInterval() != 6*time.Hour || e.probeSettleTime() != 5*time.Second {
		t.Fatal("zero Engine lost the defaults")
	}
}

func TestPolicyParsesEveryKey(t *testing.T) {
	p, notes := parsePolicy(`
# comment
candidate_budget = 3
source_priority = mirvora, TAKR
renew_before_hours=48
probe_interval_hours=12
probe_settle_seconds=7
extra_hosts = cdn.example.org, assets.example.net
consumer.tricky_store.modules = tricky_store, tricky_store_fork
consumer.tricky_store.tag = TrickyStore
consumer.tricky_store.rejection = Load Keybox failed
consumer.tricky_store.rejection = new failure text
`)
	if len(notes) != 0 {
		t.Fatal(notes)
	}
	if p.CandidateBudget != 3 || strings.Join(p.SourcePriority, ",") != "mirvora,TAKR" || p.RenewBefore != 48*time.Hour || p.ProbeInterval != 12*time.Hour || p.ProbeSettle != 7*time.Second {
		t.Fatalf("%+v", p)
	}
	if strings.Join(p.ExtraHosts, ",") != "cdn.example.org,assets.example.net" || strings.Join(p.Consumer.Modules, ",") != "tricky_store,tricky_store_fork" || p.Consumer.Tag != "TrickyStore" || len(p.Consumer.compiled) != 2 {
		t.Fatalf("%+v", p)
	}
}

func TestPolicyClampsAndRejectsUnsafeValues(t *testing.T) {
	p, notes := parsePolicy(`
candidate_budget = 99
renew_before_hours = 1
probe_interval_hours = abc
probe_settle_seconds = 0
extra_hosts = 10.0.0.1, localhost, ok.example.org, bad host.example.org, evil.example.org:8443
source_priority = good, ba/d
consumer.tricky_store.modules = ../escape, fine_id
consumer.tricky_store.tag = bad tag
consumer.tricky_store.rejection = (unclosed
unknown_key = 1
`)
	if p.CandidateBudget != 10 || p.RenewBefore != 6*time.Hour || p.ProbeInterval != 6*time.Hour || p.ProbeSettle != time.Second {
		t.Fatalf("%+v", p)
	}
	if strings.Join(p.ExtraHosts, ",") != "ok.example.org" {
		t.Fatalf("hosts %v", p.ExtraHosts)
	}
	if strings.Join(p.SourcePriority, ",") != "good" || strings.Join(p.Consumer.Modules, ",") != "fine_id" || p.Consumer.Tag != "" || len(p.Consumer.compiled) != 0 {
		t.Fatalf("%+v", p)
	}
	if len(notes) < 8 {
		t.Fatalf("every rejected line must be reported: %v", notes)
	}
}

func TestPolicyBoundsInputSize(t *testing.T) {
	huge := strings.Repeat("candidate_budget = 2\n", 5000)
	p, notes := parsePolicy(huge)
	if p.CandidateBudget != defaultPolicy().CandidateBudget || len(notes) == 0 {
		t.Fatal("oversized config must fall back to the defaults", notes)
	}
}

func TestReloadPolicyReadsFileEveryCycleAndSurvivesCorruption(t *testing.T) {
	dir := t.TempDir()
	e := Engine{brain: dir}
	e.reloadPolicy()
	if e.candidateBudget() != 5 {
		t.Fatal("missing file must give defaults")
	}
	os.WriteFile(filepath.Join(dir, "autopilot.conf"), []byte("candidate_budget = 2\n"), 0600)
	e.reloadPolicy()
	if e.candidateBudget() != 2 {
		t.Fatal("change not picked up")
	}
	os.WriteFile(filepath.Join(dir, "autopilot.conf"), []byte(strings.Repeat("x", 20<<10)), 0600)
	e.reloadPolicy()
	if e.candidateBudget() != 5 || len(e.status.ConfigNotes) == 0 {
		t.Fatal("unreadable config must fall back and be reported")
	}
}

func TestPolicyBudgetAndPriorityShapeTheSearch(t *testing.T) {
	entries := []string{}
	for i := 0; i < 6; i++ {
		entries = append(entries, fmt.Sprintf(`{"source":"TAKR","version":"%d","revoked":false,"softbanned":false}`, i))
	}
	entries = append(entries, `{"source":"mirvora","version":"1","revoked":false,"softbanned":false}`)
	catalog := `{"entries":[` + strings.Join(entries, ",") + `]}`
	run := func(conf string) []string {
		p, _ := parsePolicy(conf)
		e := Engine{policy: p}
		calls := []string{}
		e.request = func(r *http.Request) (*http.Response, error) {
			if r.URL.Path == "/catalog" {
				return reply(200, []byte(catalog)), nil
			}
			calls = append(calls, r.URL.Path)
			return reply(404, nil), nil
		}
		e.secondary(context.Background())
		return calls
	}
	if got := run("candidate_budget = 2\n"); len(got) != 2 {
		t.Fatal(got)
	}
	if got := run("source_priority = mirvora, TAKR\n"); got[0] != "/key/mirvora/1" {
		t.Fatal(got)
	}
	if got := run(""); got[0] != "/key/TAKR/0" || len(got) != 5 {
		t.Fatal(got)
	}
}

func TestPolicyRenewWindowDecidesWhenToSearch(t *testing.T) {
	t.Cleanup(func() { renewWindow = 24 * time.Hour }) // the window is a package global set by every cycle: never leak it into other tests
	for _, c := range []struct {
		conf   string
		search bool
	}{{"", false}, {"renew_before_hours = 72\n", true}} {
		dir := t.TempDir()
		b := fixture(t, false) // valid for 48h
		trustFixture(t, b)
		os.WriteFile(filepath.Join(dir, "keybox.xml"), b, 0600)
		os.WriteFile(filepath.Join(dir, "autopilot.conf"), []byte(c.conf), 0600)
		searched := false
		e := Engine{root: dir, ram: dir, brain: dir, timeCheck: func(context.Context) error { return nil }}
		e.request = func(r *http.Request) (*http.Response, error) {
			if r.URL.Path == "/attestation/status" {
				return reply(200, []byte(`{"entries":{}}`)), nil
			}
			searched = true
			return reply(404, nil), nil
		}
		_ = e.cycle(context.Background(), false)
		if searched != c.search {
			t.Fatalf("%q: searched=%v want %v", c.conf, searched, c.search)
		}
	}
}

func TestPolicyConsumerOverrideReachesTheProbe(t *testing.T) {
	log := &fakeLog{}
	log.lines = func(n string) []string {
		return []string{"I BoxAutoPilot: probe=" + n, "E TrickyStore: brand new failure text"}
	}
	e, dir := auditEngine(t, log)
	// Built-in patterns do not know this text.
	e.auditConsumer(context.Background(), true)
	if e.status.Consumer.State != ConsumerAccepted {
		t.Fatal(e.status.Consumer)
	}
	os.WriteFile(filepath.Join(dir, "autopilot.conf"), []byte("consumer.tricky_store.rejection = brand new failure text\nprobe_interval_hours = 1\n"), 0600)
	e.reloadPolicy()
	e.lastProbeFingerprint = ""
	e.auditConsumer(context.Background(), true)
	if e.status.Consumer.State != ConsumerRejected {
		t.Fatal(e.status.Consumer)
	}
}

func TestPolicyExtraHostsAreAdditiveAndReset(t *testing.T) {
	if allowedHost("cdn.example.org") {
		t.Fatal("unexpected host allowed")
	}
	e := Engine{policy: Policy{ExtraHosts: []string{"cdn.example.org"}}}
	e.applyPolicy()
	if !allowedHost("cdn.example.org") || !allowedHost("rawbin.dpejoh.com") {
		t.Fatal("extra host not applied or built-in hosts lost")
	}
	e.policy = Policy{}
	e.applyPolicy()
	if allowedHost("cdn.example.org") {
		t.Fatal("removed host must stop being allowed")
	}
}

func TestPolicySignatureTracksTheConfigFile(t *testing.T) {
	dir := t.TempDir()
	e := Engine{brain: dir}
	absent := e.policySignature()
	os.WriteFile(filepath.Join(dir, "autopilot.conf"), []byte("candidate_budget = 2\n"), 0600)
	first := e.policySignature()
	os.WriteFile(filepath.Join(dir, "autopilot.conf"), []byte("candidate_budget = 3\n\n"), 0600)
	if first == absent || e.policySignature() == first {
		t.Fatal("signature must change with the file")
	}
}
