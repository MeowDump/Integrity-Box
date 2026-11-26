package main

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"math/big"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// trustAll pins the terminal certificate of every given keybox.
func trustAll(t *testing.T, blobs ...[]byte) {
	t.Helper()
	roots := []string{}
	for _, b := range blobs {
		var doc Document
		xmlUnmarshal(t, b, &doc)
		chain := doc.Boxes[0].Keys[0].Certificates
		roots = append(roots, chain[len(chain)-1])
	}
	old := rootBundle
	rootBundle = mustJSON(t, roots)
	t.Cleanup(func() { rootBundle = old })
}

// officialEncode is the inverse of decodeOfficial.
func officialEncode(data []byte) []byte {
	b := append([]byte(nil), data...)
	for i, c := range b {
		if c >= 'a' && c <= 'z' {
			b[i] = 'a' + (c-'a'+13)%26
		}
		if c >= 'A' && c <= 'Z' {
			b[i] = 'A' + (c-'A'+13)%26
		}
	}
	b = []byte(hex.EncodeToString(b))
	for i := 0; i < 10; i++ {
		b = []byte(base64.StdEncoding.EncodeToString(b))
	}
	return b
}

func TestRevocationMatchesDecimalSerialKeys(t *testing.T) {
	serial := new(big.Int).SetUint64(0x7a8b9c0d1e2f3a4b)
	h, err := inspect(fixtureWith(t, fixtureOpts{LeafSerial: serial}), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	e := Engine{}
	e.request = func(*http.Request) (*http.Response, error) {
		return reply(200, []byte(`{"entries":{"`+serial.String()+`":{"status":"REVOKED"}}}`)), nil
	}
	e.crl(context.Background())
	if e.status.Revocation != "fresh" || !e.isRevoked(h) {
		t.Fatal("decimal CRL key not matched", e.status.Revocation)
	}
	other, _ := inspect(fixtureWith(t, fixtureOpts{LeafSerial: big.NewInt(12345)}), time.Now())
	if e.isRevoked(other) {
		t.Fatal("unrelated serial reported revoked")
	}
}

func TestRevocationMatchesHexSerialKeys(t *testing.T) {
	serial := new(big.Int).SetUint64(0x7a8b9c0d1e2f3a4b)
	h, _ := inspect(fixtureWith(t, fixtureOpts{LeafSerial: serial}), time.Now())
	e := Engine{revoked: map[string]bool{"7a8b9c0d1e2f3a4b": true}}
	if !e.isRevoked(h) {
		t.Fatal("hex serial not matched")
	}
}

func TestAutomaticInstallRequiresFreshRevocationList(t *testing.T) {
	dir := t.TempDir()
	old := fixture(t, true)
	next := fixtureWith(t, fixtureOpts{LeafSerial: big.NewInt(9)})
	trustAll(t, old, next)
	os.WriteFile(filepath.Join(dir, "keybox.xml"), old, 0600)
	e := Engine{root: dir, ram: dir, brain: dir, forcedTier: "Megatron", timeCheck: func(context.Context) error { return nil }}
	e.request = func(r *http.Request) (*http.Response, error) {
		if r.URL.Path == "/attestation/status" {
			return reply(500, nil), nil
		}
		return reply(200, officialEncode(next)), nil
	}
	err := e.cycle(context.Background(), false)
	if err == nil || !strings.Contains(err.Error(), "revocation status") {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(e.target())
	if string(got) != string(old) {
		t.Fatal("target changed without a fresh revocation list")
	}
}
