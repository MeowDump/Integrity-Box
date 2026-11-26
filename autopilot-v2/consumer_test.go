package main

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestConsumerFormatGate(t *testing.T) {
	cases := []struct {
		name    string
		opts    fixtureOpts
		wantErr bool
	}{
		{"SEC1 EC key is accepted", fixtureOpts{}, false},
		{"PKCS#8 EC key is rejected", fixtureOpts{PrivateType: "PRIVATE KEY"}, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			b := fixtureWith(t, c.opts)
			if _, err := inspect(b, time.Now()); err != nil {
				t.Fatal("fixture must be cryptographically valid:", err)
			}
			err := checkConsumerFormat(b, strictProfile)
			if (err != nil) != c.wantErr {
				t.Fatalf("wantErr=%v got %v", c.wantErr, err)
			}
		})
	}
}

func TestConsumerFormatGateRejectsUnknownAlgorithmAndNonPEM(t *testing.T) {
	b := fixtureWith(t, fixtureOpts{})
	for _, bad := range []string{strings.Replace(string(b), `algorithm="ecdsa"`, `algorithm="ed25519"`, 1), strings.Replace(string(b), "-----BEGIN EC PRIVATE KEY-----", "garbage", 1)} {
		if err := checkConsumerFormat([]byte(bad), strictProfile); err == nil {
			t.Fatal("accepted unsupported keybox")
		}
	}
}

func TestLocalPKCS8KeyIsReportedAsConsumerIncompatible(t *testing.T) {
	dir := t.TempDir()
	b := fixtureWith(t, fixtureOpts{PrivateType: "PRIVATE KEY"})
	trustFixture(t, b)
	if err := os.WriteFile(filepath.Join(dir, "keybox.xml"), b, 0600); err != nil {
		t.Fatal(err)
	}
	e := Engine{root: dir, ram: dir, brain: dir}
	if got := e.health().State; got != "consumer_incompatible" {
		t.Fatalf("state=%q", got)
	}
}

func TestCandidateRejectsIncompatibleFormat(t *testing.T) {
	b := fixtureWith(t, fixtureOpts{PrivateType: "PRIVATE KEY"})
	trustFixture(t, b)
	e := Engine{}
	e.request = func(*http.Request) (*http.Response, error) { return reply(200, secondaryEncode(b)), nil }
	_, _, err := e.candidate(context.Background(), "https://rawbin.dpejoh.com/key/TAKR/40", true)
	if err == nil || !strings.Contains(err.Error(), "consumer format") {
		t.Fatal(err)
	}
}

// A valid but unloadable key must start a search; a valid loadable key must not.
func TestIncompatibleLocalKeyTriggersSearch(t *testing.T) {
	for _, c := range []struct {
		name       string
		opts       fixtureOpts
		wantSearch bool
	}{{"incompatible", fixtureOpts{PrivateType: "PRIVATE KEY"}, true}, {"compatible", fixtureOpts{}, false}} {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			b := fixtureWith(t, c.opts)
			trustFixture(t, b)
			os.WriteFile(filepath.Join(dir, "keybox.xml"), b, 0600)
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
			if searched != c.wantSearch {
				t.Fatalf("searched=%v want %v", searched, c.wantSearch)
			}
		})
	}
}

func xmlUnmarshal(t *testing.T, b []byte, v any) {
	t.Helper()
	if err := xml.Unmarshal(b, v); err != nil {
		t.Fatal(err)
	}
}
func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return b
}
