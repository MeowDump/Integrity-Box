package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type fixtureOpts struct {
	Expired     bool
	LeafSerial  *big.Int
	PrivateType string        // "EC PRIVATE KEY" (default) or "PRIVATE KEY" (PKCS#8)
	ValidFor    time.Duration // leaf lifetime from now, default 48h
}

func fixtureWith(t *testing.T, o fixtureOpts) []byte {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	root := &x509.Certificate{SerialNumber: big.NewInt(42), Subject: pkix.Name{CommonName: "test root"}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(365 * 24 * time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	rd, err := x509.CreateCertificate(rand.Reader, root, root, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	rc, _ := x509.ParseCertificate(rd)
	end := now.Add(48 * time.Hour)
	if o.ValidFor > 0 {
		end = now.Add(o.ValidFor)
	}
	if o.Expired {
		end = now.Add(-time.Minute)
	}
	serialNumber := o.LeafSerial
	if serialNumber == nil {
		serialNumber = big.NewInt(7)
	}
	leaf := &x509.Certificate{SerialNumber: serialNumber, Subject: pkix.Name{CommonName: "test"}, NotBefore: now.Add(-time.Hour), NotAfter: end, KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign, IsCA: true, BasicConstraintsValid: true}
	ld, err := x509.CreateCertificate(rand.Reader, leaf, rc, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	privateType := o.PrivateType
	if privateType == "" {
		privateType = "EC PRIVATE KEY"
	}
	var kd []byte
	if privateType == "PRIVATE KEY" {
		kd, err = x509.MarshalPKCS8PrivateKey(key)
	} else {
		kd, err = x509.MarshalECPrivateKey(key)
	}
	if err != nil {
		t.Fatal(err)
	}
	return []byte(fmt.Sprintf("<AndroidAttestation><NumberOfKeyboxes>1</NumberOfKeyboxes><Keybox><Key algorithm=\"ecdsa\"><PrivateKey>%s</PrivateKey><CertificateChain><NumberOfCertificates>2</NumberOfCertificates><Certificate>%s</Certificate><Certificate>%s</Certificate></CertificateChain></Key></Keybox></AndroidAttestation>", pem.EncodeToMemory(&pem.Block{Type: privateType, Bytes: kd}), pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: ld}), pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: rd})))
}
func fixture(t *testing.T, expired bool) []byte {
	t.Helper()
	return fixtureWith(t, fixtureOpts{Expired: expired})
}
func TestInspect(t *testing.T) {
	for _, expired := range []bool{false, true} {
		b := fixture(t, expired)
		h, e := inspect(b, time.Now())
		if e != nil {
			t.Fatal(e)
		}
		want := "valid"
		if expired {
			want = "expired"
		}
		if h.State != want || h.Serials[0] != "7" {
			t.Fatalf("%+v", h)
		}
	}
}
func TestRejectMalformed(t *testing.T) {
	for _, b := range [][]byte{nil, []byte("<Keybox/>"), []byte("<!DOCTYPE foo><AndroidAttestation/>"), append(fixture(t, false), []byte("<other/>")...), make([]byte, maxXML+1)} {
		if _, e := inspect(b, time.Now()); e == nil {
			t.Fatal("accepted invalid input")
		}
	}
}
func TestRejectMismatch(t *testing.T) {
	a, b := fixture(t, false), fixture(t, false)
	start := strings.Index(string(b), "<PrivateKey>")
	end := strings.Index(string(b), "</PrivateKey>")
	s := string(a)
	s = s[:strings.Index(s, "<PrivateKey>")] + string(b[start:end]) + s[strings.Index(s, "</PrivateKey>"):]
	if _, e := inspect([]byte(s), time.Now()); e == nil {
		t.Fatal("accepted key mismatch")
	}
}
func TestOfficialRoundTrip(t *testing.T) {
	data := fixture(t, false)
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
	got, e := decodeOfficial(b)
	if e != nil || string(got) != string(data) {
		t.Fatal(e)
	}
}
func TestLock(t *testing.T) {
	p := filepath.Join(t.TempDir(), "lock")
	a, e := lock(p)
	if e != nil {
		t.Fatal(e)
	}
	if b, e := lock(p); e == nil {
		b.Close()
		t.Fatal("double lock")
	}
	a.Close()
	b, e := lock(p)
	if e != nil {
		t.Fatal(e)
	}
	b.Close()
}
func TestAtomic(t *testing.T) {
	p := filepath.Join(t.TempDir(), "file")
	if e := atomic(p, []byte("old"), 0600); e != nil {
		t.Fatal(e)
	}
	if e := atomic(p, []byte("new"), 0600); e != nil {
		t.Fatal(e)
	}
	b, _ := os.ReadFile(p)
	if string(b) != "new" {
		t.Fatal("bad atomic")
	}
}
func TestURLPolicy(t *testing.T) {
	e := Engine{}
	for _, u := range []string{"http://github.com/a", "https://evil.example/a", "https://x@github.com/a"} {
		if _, err := e.get(context.Background(), u, 20); err == nil {
			t.Fatal("URL accepted")
		}
	}
}
func TestBackoffCap(t *testing.T) {
	for i := 0; i < 100; i++ {
		if backoff(i) > 12*time.Hour || backoff(i) < 30*time.Minute {
			t.Fatal("bad backoff")
		}
	}
}
func TestUnknownClock(t *testing.T) {
	h, e := inspect(fixture(t, false), time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC))
	if e != nil || h.State != "time_unknown" {
		t.Fatal(h, e)
	}
}
func TestCommitConflict(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	os.WriteFile(e.target(), []byte("original"), 0600)
	if err := e.install([]byte("replacement"), "wrong", generation(dir), false); err == nil {
		t.Fatal("lost update accepted")
	}
	b, _ := os.ReadFile(e.target())
	if string(b) != "original" {
		t.Fatal("changed")
	}
}

func TestUntrustedRoot(t *testing.T) {
	h, err := inspect(fixture(t, false), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if trusted(h) {
		t.Fatal("self-signed arbitrary root trusted")
	}
}

func TestAndroidTransaction(t *testing.T) {
	if !exists("/system/bin/chcon") {
		t.Skip("Android-only SELinux transaction test")
	}
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	before := fixture(t, true)
	after := fixture(t, false)
	if err := os.WriteFile(e.target(), before, 0644); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(before)
	if err := e.install(after, hex.EncodeToString(sum[:]), generation(dir), false); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(e.target())
	if err != nil || !bytes.Equal(got, after) {
		t.Fatal("commit mismatch", err)
	}
	if exists(filepath.Join(dir, "keybox.autopilot-backup.xml")) || exists(filepath.Join(dir, ".autopilot-transaction")) {
		t.Fatal("a completed install must leave no backup or transaction directory")
	}
	// Simulate crash after first rename with journal still present.
	td := filepath.Join(dir, ".autopilot-transaction")
	os.Mkdir(td, 0700)
	bp := filepath.Join(td, "before-0")
	os.WriteFile(bp, before, 0600)
	label, err := fileContext(e.target())
	if err != nil {
		t.Fatal(err)
	}
	tx := transaction{Entries: []transactionEntry{{Target: e.target(), Stage: filepath.Join(dir, ".autopilot-stage-test"), Backup: bp, Context: label, Mode: 0644, UID: 0, GID: 0, Existed: true}}}
	if err := writeJSON(filepath.Join(td, "journal.json"), tx); err != nil {
		t.Fatal(err)
	}
	if err := e.recoverTransaction(); err != nil {
		t.Fatal(err)
	}
	got, _ = os.ReadFile(e.target())
	if !bytes.Equal(got, before) {
		t.Fatal("recovery mismatch")
	}
}
func TestSecondaryRoundTrip(t *testing.T) {
	const shuffled = "1dgWnocayqxU3r6vA5lCIPYfHmkV08b4tz+KMsp2NQ9LRXihODwSj7BEFJ/ZuGTe"
	const std = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	source := fixture(t, false)
	b := []byte(base64.StdEncoding.EncodeToString(source))
	for i, c := range b {
		j := strings.IndexByte(std, c)
		if j >= 0 {
			b[i] = shuffled[j]
		}
	}
	result, err := decodeSecondary(b)
	if err != nil || !bytes.Equal(result, source) {
		t.Fatal("secondary decode", err)
	}
}
func TestCancelledHTTP(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	e := Engine{client: &http.Client{}}
	if _, err := e.get(ctx, "https://github.com/a", 20); err == nil {
		t.Fatal("ignored cancellation")
	}
}

type responseFunc func(*http.Request) (*http.Response, error)

func reply(status int, b []byte) *http.Response {
	return &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(bytes.NewReader(b))}
}
func secondaryEncode(data []byte) []byte {
	const shuffled = "1dgWnocayqxU3r6vA5lCIPYfHmkV08b4tz+KMsp2NQ9LRXihODwSj7BEFJ/ZuGTe"
	const std = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	b := []byte(base64.StdEncoding.EncodeToString(data))
	for i, c := range b {
		if j := strings.IndexByte(std, c); j >= 0 {
			b[i] = shuffled[j]
		}
	}
	return b
}
func trustFixture(t *testing.T, b []byte) {
	t.Helper()
	var doc Document
	xml.Unmarshal(b, &doc)
	chain := doc.Boxes[0].Keys[0].Certificates
	old := rootBundle
	rootBundle, _ = json.Marshal([]string{chain[len(chain)-1]})
	t.Cleanup(func() { rootBundle = old })
}
func TestSecondarySkips404(t *testing.T) {
	b := fixture(t, false)
	trustFixture(t, b)
	calls := []string{}
	e := Engine{}
	e.request = func(r *http.Request) (*http.Response, error) {
		calls = append(calls, r.URL.Path)
		switch r.URL.Path {
		case "/catalog":
			return reply(200, []byte(`{"entries":[{"source":"TAKR","version":"37","revoked":false,"softbanned":false},{"source":"TAKR","version":"36","revoked":false,"softbanned":false}]}`)), nil
		case "/key/TAKR/37":
			return reply(404, nil), nil
		default:
			return reply(200, secondaryEncode(b)), nil
		}
	}
	got, _, err := e.secondary(context.Background())
	if err != nil || !bytes.Equal(got, b) || len(calls) != 3 {
		t.Fatal(calls, err)
	}
}
func TestSecondaryBudget(t *testing.T) {
	n := 0
	e := Engine{}
	e.request = func(r *http.Request) (*http.Response, error) {
		if r.URL.Path == "/catalog" {
			entries := []map[string]any{}
			for i := 0; i < 100; i++ {
				entries = append(entries, map[string]any{"source": "TAKR", "version": fmt.Sprint(i), "revoked": false, "softbanned": false})
			}
			b, _ := json.Marshal(map[string]any{"entries": entries})
			return reply(200, b), nil
		}
		n++
		return reply(404, nil), nil
	}
	_, _, err := e.secondary(context.Background())
	if err == nil || n != 5 {
		t.Fatal(n, err)
	}
}
func TestRetryAfterAndConditional(t *testing.T) {
	n := 0
	e := Engine{}
	e.request = func(r *http.Request) (*http.Response, error) {
		n++
		r1 := reply(429, nil)
		r1.Header.Set("Retry-After", "8640000")
		return r1, nil
	}
	e.get(context.Background(), "https://github.com/a", 100)
	e.get(context.Background(), "https://github.com/b", 100)
	if n != 1 || time.Until(e.hostNext["github.com"]) > 24*time.Hour {
		t.Fatal("cooldown")
	}
	e = Engine{}
	e.request = func(r *http.Request) (*http.Response, error) {
		if r.Header.Get("If-None-Match") == "tag" {
			return reply(304, nil), nil
		}
		r1 := reply(200, []byte("cached"))
		r1.Header.Set("ETag", "tag")
		return r1, nil
	}
	for i := 0; i < 2; i++ {
		b, err := e.get(context.Background(), "https://rawbin.dpejoh.com/catalog", 100)
		if err != nil || string(b) != "cached" {
			t.Fatal(err)
		}
	}
}
func TestPayloadByteLimit(t *testing.T) {
	e := Engine{request: func(*http.Request) (*http.Response, error) { return reply(200, make([]byte, 101)), nil }}
	if _, err := e.get(context.Background(), "https://github.com/a", 100); err == nil {
		t.Fatal("byte cap ignored")
	}
}
func TestCappedBuffer(t *testing.T) {
	b := &cappedBuffer{limit: 10}
	if _, err := b.Write(make([]byte, 11)); err == nil || b.Len() != 0 {
		t.Fatal("cap")
	}
}

func TestConfigChangePreservesTarget(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	old := fixture(t, false)
	os.WriteFile(e.target(), old, 0600)
	sum := sha256.Sum256(old)
	gen := generation(dir)
	os.WriteFile(filepath.Join(dir, "disable-default-source"), nil, 0600)
	if err := e.install(fixture(t, false), hex.EncodeToString(sum[:]), gen, false); err == nil {
		t.Fatal("configuration race")
	}
	got, _ := os.ReadFile(e.target())
	if !bytes.Equal(got, old) {
		t.Fatal("changed target")
	}
}
func TestSameContentDoesNotInstall(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	old := fixture(t, false)
	os.WriteFile(e.target(), old, 0600)
	sum := sha256.Sum256(old)
	if err := e.install(old, hex.EncodeToString(sum[:]), generation(dir), false); !errors.Is(err, errUnchanged) {
		t.Fatal(err)
	}
	if exists(filepath.Join(dir, ".autopilot-transaction")) {
		t.Fatal("unnecessary transaction")
	}
}
func TestFailedSearchPreservesTarget(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir, request: func(*http.Request) (*http.Response, error) { return reply(404, nil), nil }}
	old := fixture(t, true)
	trustFixture(t, old)
	os.WriteFile(e.target(), old, 0600)
	e.timeCheck = func(context.Context) error { return nil }
	if err := e.cycle(context.Background(), false); err == nil {
		t.Fatal("expected failure")
	}
	got, _ := os.ReadFile(e.target())
	if !bytes.Equal(got, old) {
		t.Fatal("target lost")
	}
}
func TestSymlinkTargetRejected(t *testing.T) {
	dir := t.TempDir()
	actual := filepath.Join(dir, "real")
	os.WriteFile(actual, []byte("old"), 0600)
	os.Symlink(actual, filepath.Join(dir, "keybox.xml"))
	e := Engine{root: dir, ram: dir, brain: dir}
	if err := e.install([]byte("new"), "", generation(dir), false); err == nil {
		t.Fatal("symlink accepted")
	}
	got, _ := os.ReadFile(actual)
	if string(got) != "old" {
		t.Fatal("changed symlink destination")
	}
}
func TestJitterBound(t *testing.T) {
	for i := 0; i < 1000; i++ {
		d := jitter(12 * time.Hour)
		if d > 12*time.Hour || d < 108*time.Hour/10 {
			t.Fatal(d)
		}
	}
}
func TestSuspendClock(t *testing.T) {
	if !exists("/proc/uptime") {
		t.Skip("Linux-only boottime")
	}
	if bootSeconds() <= 0 {
		t.Fatal("invalid boottime")
	}
	if processStart(os.Getpid()) == "" {
		t.Fatal("process ownership unavailable")
	}
}

func TestRestartBackoffForgetsAHealthyRun(t *testing.T) {
	n, d := 0, time.Duration(0)
	for i := 1; i <= 40; i++ { // a worker that keeps crashing right away: 1, 2, ... 30 minutes, capped
		n, d = restartBackoff(n, time.Second)
	}
	if n != 40 || d != 30*time.Minute {
		t.Fatalf("cap: %d %v", n, d)
	}
	if n, d = restartBackoff(n, 3*time.Hour); n != 1 || d != time.Minute {
		t.Fatalf("a worker that ran for hours must restart the back-off: %d %v", n, d)
	}
	if n, d = restartBackoff(n, 9*time.Minute+59*time.Second); n != 2 || d != 2*time.Minute {
		t.Fatalf("under ten minutes still counts as a crash: %d %v", n, d)
	}
}

func TestSupervisorSurvivesAWorkerThatCannotStart(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "autopilot"), nil, 0600)
	e := Engine{root: dir, ram: dir, brain: dir, workerCommand: func() *exec.Cmd { return exec.Command(filepath.Join(dir, "no-such-binary")) }}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- e.supervise(ctx) }()
	select {
	case err := <-done:
		t.Fatalf("a failed fork/exec must not end the supervisor: %v", err)
	case <-time.After(300 * time.Millisecond):
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("supervisor did not stop on cancel while backing off")
	}
}

func TestSupervisorCancellationAndSingleton(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "autopilot"), nil, 0600)
	e := Engine{root: dir, ram: dir, brain: dir, workerCommand: func() *exec.Cmd { return exec.Command("sleep", "100") }}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- e.supervise(ctx) }()
	deadline := time.Now().Add(time.Second)
	for !held(filepath.Join(dir, "supervisor.lock")) {
		if time.Now().After(deadline) {
			t.Fatal("supervisor failed to acquire lock")
		}
		time.Sleep(time.Millisecond)
	}
	if err := e.supervise(ctx); err != nil {
		t.Fatal(err)
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("supervisor did not stop")
	}
	if held(filepath.Join(dir, "supervisor.lock")) {
		t.Fatal("lock leaked")
	}
}

func TestModuleDisableStopsEligibility(t *testing.T) {
	dir := t.TempDir()
	brain := t.TempDir()
	e := Engine{moduleRoot: dir, brain: brain}
	os.WriteFile(filepath.Join(brain, "autopilot"), nil, 0600)
	if !e.enabled() {
		t.Fatal("not enabled")
	}
	for _, flag := range []string{"disable", "remove"} {
		os.WriteFile(filepath.Join(dir, flag), nil, 0600)
		if e.enabled() {
			t.Fatal("module flag ignored", flag)
		}
		os.Remove(filepath.Join(dir, flag))
	}
	os.Remove(dir)
	if e.enabled() {
		t.Fatal("deleted module still enabled")
	}
}

func TestRecoveryPreflightsAllBackups(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	os.WriteFile(e.target(), []byte("current"), 0600)
	td := filepath.Join(dir, ".autopilot-transaction")
	os.Mkdir(td, 0700)
	first := filepath.Join(td, "before-0")
	os.WriteFile(first, []byte("old"), 0600)
	tx := transaction{Entries: []transactionEntry{{Target: e.target(), Stage: filepath.Join(dir, ".autopilot-stage-one"), Backup: first, Existed: true}, {Target: filepath.Join(dir, "keybox2.xml"), Stage: filepath.Join(dir, ".autopilot-stage-two"), Backup: filepath.Join(td, "missing"), Existed: true}}}
	writeJSON(filepath.Join(td, "journal.json"), tx)
	if err := e.recoverTransaction(); err == nil {
		t.Fatal("missing backup accepted")
	}
	got, _ := os.ReadFile(e.target())
	if string(got) != "current" {
		t.Fatal("partial rollback before preflight")
	}
	if !exists(filepath.Join(td, "journal.json")) {
		t.Fatal("journal lost")
	}
}
func TestCRLOnlyDoesNotFetchBeforeDeadline(t *testing.T) {
	dir := t.TempDir()
	old := fixture(t, true)
	trustFixture(t, old)
	os.WriteFile(filepath.Join(dir, "keybox.xml"), old, 0600)
	calls := 0
	e := Engine{root: dir, ram: dir, brain: dir, timeCheck: func(context.Context) error { return nil }, automaticFetchDue: bootSeconds() + 12*3600, request: func(r *http.Request) (*http.Response, error) {
		calls++
		if r.URL.Path != "/attestation/status" {
			t.Fatal("early replacement request", r.URL)
		}
		return reply(200, []byte(`{"entries":{}}`)), nil
	}}
	if err := e.cycle(context.Background(), true); err != nil {
		t.Fatal(err)
	}
	if calls != 1 {
		t.Fatal(calls)
	}
}

func TestNetworkClockPolicy(t *testing.T) {
	now := time.UnixMilli(1794065434746)
	boot := 653173.342
	good := "NetworkTimeSuggestion{mUnixEpochTime=UnixEpochTime{mElapsedRealtimeMillis=653173342, mUnixEpochTimeMillis=1794065434746}, mUncertaintyMillis=24,"
	if err := verifyNetworkTime(good, now, boot); err != nil {
		t.Fatal(err)
	}
	for _, at := range []time.Time{now.Add(24 * time.Hour), now.Add(-24 * time.Hour)} {
		if verifyNetworkTime(good, at, boot) == nil {
			t.Fatal("clock jump accepted")
		}
	}
	if verifyNetworkTime(good, now, boot+25*3600) == nil {
		t.Fatal("stale clock accepted")
	}
	if verifyNetworkTime("unsupported", now, boot) == nil {
		t.Fatal("unsupported output accepted")
	}
}

func TestRecoveryRejectsCorruptBackup(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	os.WriteFile(e.target(), []byte("current"), 0600)
	td := filepath.Join(dir, ".autopilot-transaction")
	os.Mkdir(td, 0700)
	p := filepath.Join(td, "before-0")
	os.WriteFile(p, []byte("corrupted"), 0600)
	tx := transaction{Version: 1, ID: "test", Entries: []transactionEntry{{Target: e.target(), Stage: filepath.Join(dir, ".autopilot-stage-one"), Backup: p, Existed: true, BackupSHA256: "incorrect", BackupBytes: 9}}}
	writeJSON(filepath.Join(td, "journal.json"), tx)
	if e.recoverTransaction() == nil {
		t.Fatal("corrupted backup accepted")
	}
	b, _ := os.ReadFile(e.target())
	if string(b) != "current" {
		t.Fatal("target changed")
	}
}

func TestConfigRevisionDetectsABA(t *testing.T) {
	dir := t.TempDir()
	e := Engine{ram: dir, brain: dir}
	before := generation(dir)
	if err := e.setFlag(context.Background(), "disable-default-source", true); err != nil {
		t.Fatal(err)
	}
	if err := e.setFlag(context.Background(), "disable-default-source", false); err != nil {
		t.Fatal(err)
	}
	if generation(dir) == before {
		t.Fatal("ABA not detected")
	}
}

func TestDiagnosticTailBoundAndClassification(t *testing.T) {
	d := &diagnosticTail{}
	d.Write(make([]byte, 20000))
	d.Write([]byte("panic: private-data-must-not-be-logged"))
	if len(d.data) > 8192 || d.class() != "panic" {
		t.Fatal("bad diagnostic tail")
	}
}

func TestSeventyTwoHourCRLAndSearchSeparation(t *testing.T) {
	dir := t.TempDir()
	old := fixture(t, true)
	trustFixture(t, old)
	os.WriteFile(filepath.Join(dir, "keybox.xml"), old, 0600)
	now := 1000000.0
	fetches := 0
	crls := 0
	e := Engine{root: dir, ram: dir, brain: dir, bootClock: func() float64 { return now }, timeCheck: func(context.Context) error { return nil }}
	e.request = func(r *http.Request) (*http.Response, error) {
		if r.URL.Path == "/attestation/status" {
			crls++
			v := reply(200, []byte(`{"entries":{}}`))
			v.Header.Set("Cache-Control", "max-age=1800")
			return v, nil
		}
		fetches++
		return reply(404, nil), nil
	}
	failures := 0
	for tick := 0; tick <= 144; tick++ {
		now = 1000000 + float64(tick*1800)
		due := e.automaticFetchDue
		e.searched = false
		err := e.cycle(context.Background(), true)
		if now < due && e.searched {
			t.Fatal("CRL bypassed search cooldown")
		}
		failures = e.recordSearchResult(err, failures)
	}
	if crls != 145 || fetches < 15 || fetches > 39 {
		t.Fatal("unexpected requests", crls, fetches)
	}
	got, _ := os.ReadFile(e.target())
	if !bytes.Equal(got, old) {
		t.Fatal("working file changed")
	}
}

func TestMain(m *testing.M) { diagnosticSink = func(string, string, int) {}; os.Exit(m.Run()) }

func TestRevocationUrgencyDoesNotResetRepeatedly(t *testing.T) {
	dir := t.TempDir()
	old := fixture(t, true)
	trustFixture(t, old)
	os.WriteFile(filepath.Join(dir, "keybox.xml"), old, 0600)
	now := 2000.0
	e := Engine{root: dir, ram: dir, brain: dir, bootClock: func() float64 { return now }, timeCheck: func(context.Context) error { return nil }, automaticFetchDue: 40000, lastSearchBoot: 1900, request: func(r *http.Request) (*http.Response, error) {
		if r.URL.Path == "/attestation/status" {
			return reply(200, []byte(`{"entries":{"7":{"status":"REVOKED"}}}`)), nil
		}
		return reply(404, nil), nil
	}}
	if err := e.cycle(context.Background(), true); err != nil || e.searched || e.automaticFetchDue != 3700 {
		t.Fatal(err, e.automaticFetchDue)
	}
	now = 3700
	e.searched = false
	err := e.cycle(context.Background(), true)
	if err == nil || !e.searched {
		t.Fatal("urgent search missing")
	}
	e.recordSearchResult(err, 3)
	deadline := e.automaticFetchDue
	now = 4000
	e.searched = false
	e.cycle(context.Background(), true)
	if e.searched || e.automaticFetchDue != deadline {
		t.Fatal("same revoke event bypassed cooldown")
	}
}
func TestStartupRecoveryBeforeFrameworkAndPowerGate(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	td := filepath.Join(dir, ".autopilot-transaction")
	os.Mkdir(td, 0700)
	tx := transaction{Entries: []transactionEntry{{Target: e.target(), Stage: filepath.Join(dir, ".autopilot-stage-one"), Backup: filepath.Join(td, "missing"), Existed: true}}}
	writeJSON(filepath.Join(td, "journal.json"), tx)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if e.daemon(ctx) == nil || e.status.Phase != "recovery_required" || e.status.Ready {
		t.Fatal("startup bypassed broken recovery", e.status.Phase)
	}
}

func TestEmergencyAnchorRecognitionSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	data := fixture(t, false)
	trustFixture(t, data)
	os.WriteFile(e.target(), data, 0600)
	sum := sha256.Sum256(data)
	hash := hex.EncodeToString(sum[:])
	if err := e.rememberAnchor(hash); err != nil {
		t.Fatal(err)
	}
	restarted := Engine{root: dir, ram: t.TempDir(), brain: dir}
	if !restarted.health().Anchor {
		t.Fatal("anchor lost on restart")
	}
	if restarted.isKnownAnchor(strings.Repeat("0", 64)) {
		t.Fatal("unrelated file considered anchor")
	}
}

func TestUpgradeFromLongLivedAnchorAllowsShorterValidReplacement(t *testing.T) {
	e := Engine{status: Status{Revocation: "fresh", Local: Health{State: "valid", Anchor: true, Fingerprint: "old", Expires: time.Now().Add(5 * 365 * 24 * time.Hour)}}}
	replacement := Health{State: "valid", Fingerprint: "new", Expires: time.Now().Add(48 * time.Hour)}
	if !e.eligible(replacement) {
		t.Fatal("anchor permanently blocks upgrade")
	}
	replacement.Anchor = true
	if e.eligible(replacement) {
		t.Fatal("anchor to anchor churn")
	}
	replacement.Anchor = false
	e.status.Revocation = "unknown"
	if e.eligible(replacement) {
		t.Fatal("uncertain replacement downgrades working anchor")
	}
}

func TestDisableDoesNotHidePendingRecoveryFailure(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	td := filepath.Join(dir, ".autopilot-transaction")
	os.Mkdir(td, 0700)
	tx := transaction{Entries: []transactionEntry{{Target: e.target(), Stage: filepath.Join(dir, ".autopilot-stage-one"), Backup: filepath.Join(td, "missing"), Existed: true}}}
	writeJSON(filepath.Join(td, "journal.json"), tx)
	if e.disable(context.Background()) == nil {
		t.Fatal("disable reported success with broken recovery")
	}
	if !exists(filepath.Join(td, "journal.json")) {
		t.Fatal("recovery evidence deleted")
	}
}
func TestAndroidDisableCompletesPendingRecovery(t *testing.T) {
	if !exists("/system/bin/chcon") {
		t.Skip("Android-only rollback labels")
	}
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	before := fixture(t, true)
	after := fixture(t, false)
	os.WriteFile(e.target(), after, 0644)
	contextName, err := fileContext(e.target())
	if err != nil {
		t.Fatal(err)
	}
	td := filepath.Join(dir, ".autopilot-transaction")
	os.Mkdir(td, 0700)
	bp := filepath.Join(td, "before-0")
	os.WriteFile(bp, before, 0600)
	tx := transaction{Entries: []transactionEntry{{Target: e.target(), Stage: filepath.Join(dir, ".autopilot-stage-one"), Backup: bp, Existed: true, Mode: 0644, Context: contextName, UID: 0, GID: 0}}}
	writeJSON(filepath.Join(td, "journal.json"), tx)
	if err = e.disable(context.Background()); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(e.target())
	if !bytes.Equal(got, before) || exists(filepath.Join(td, "journal.json")) {
		t.Fatal("disable left partial update")
	}
}

func TestLocalAuditDeadlineCoversExpiryAndRenewalBoundary(t *testing.T) {
	now := time.Now()
	for _, d := range []time.Duration{10 * time.Minute, 10 * time.Hour, 35 * time.Hour} {
		h := Health{State: "valid", Expires: now.Add(d)}
		got := localAuditDeadline(h, now)
		want := h.Expires
		if d > 24*time.Hour {
			want = h.Expires.Add(-24 * time.Hour)
		}
		if !got.Equal(want) {
			t.Fatal(d, got, want)
		}
	}
	if !localAuditDeadline(Health{State: "expired", Expires: now.Add(-time.Minute)}, now).IsZero() {
		t.Fatal("expired key creates repeated immediate deadline")
	}
}
func TestManualReplacementChangesAuditSignature(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir}
	os.WriteFile(e.target(), []byte("one"), 0600)
	before := e.targetSignature()
	tmp := filepath.Join(dir, "new")
	os.WriteFile(tmp, []byte("two"), 0600)
	os.Rename(tmp, e.target())
	if e.targetSignature() == before {
		t.Fatal("manual import not noticed")
	}
}

func TestRevokedCandidateHasDistinctDiagnostic(t *testing.T) {
	data := fixture(t, false)
	trustFixture(t, data)
	event := ""
	oldSink := diagnosticSink
	diagnosticSink = func(name, host string, code int) { event = name }
	defer func() { diagnosticSink = oldSink }()
	e := Engine{revoked: map[string]bool{"7": true}, request: func(*http.Request) (*http.Response, error) { return reply(200, secondaryEncode(data)), nil }}
	if _, _, err := e.candidate(context.Background(), "https://rawbin.dpejoh.com/key/TAKR/1", true); err == nil || event != "candidate_revoked" {
		t.Fatal("revocation reason lost", err, event)
	}
}

func TestAnchorIdentitySurvivesXMLReformatting(t *testing.T) {
	dir := t.TempDir()
	data := fixture(t, false)
	trustFixture(t, data)
	h, err := inspect(data, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	e := Engine{root: dir, ram: dir, brain: dir}
	if err = e.rememberAnchor(h.Identity); err != nil {
		t.Fatal(err)
	}
	reformatted := bytes.Replace(data, []byte("<Keybox>"), []byte("\n<Keybox>\n"), 1)
	os.WriteFile(e.target(), reformatted, 0600)
	got := e.health()
	if got.Identity != h.Identity || got.Fingerprint == h.Fingerprint || !got.Anchor {
		t.Fatal("formatting lost anchor identity")
	}
	h.Anchor = true
	e.status = Status{Local: h, Revocation: "fresh"}
	if e.eligible(got) {
		t.Fatal("formatting treated as anchor upgrade")
	}
}
func TestDuplicateAlgorithmsRejected(t *testing.T) {
	data := fixture(t, false)
	s := string(data)
	a := strings.Index(s, "<Key algorithm=")
	b := strings.Index(s, "</Key>") + len("</Key>")
	duplicated := strings.Replace(s, "</Keybox>", s[a:b]+"</Keybox>", 1)
	if _, err := inspect([]byte(duplicated), time.Now()); err == nil {
		t.Fatal("ambiguous duplicate keys accepted")
	}
}

func TestRejectAmbiguousXMLConsumerInterpretation(t *testing.T) {
	base := string(fixture(t, false))
	cases := []string{strings.Replace(base, "<NumberOfKeyboxes>1</NumberOfKeyboxes>", "<NumberOfKeyboxes>0</NumberOfKeyboxes><NumberOfKeyboxes>1</NumberOfKeyboxes>", 1), strings.Replace(base, `<Key algorithm="ecdsa">`, `<Key algorithm="rsa" algorithm="ecdsa">`, 1), strings.Replace(strings.Replace(base, "<AndroidAttestation>", `<x:AndroidAttestation xmlns:x="urn:unexpected">`, 1), "</AndroidAttestation>", "</x:AndroidAttestation>", 1), "garbage" + base, strings.Replace(base, "<NumberOfKeyboxes>1</NumberOfKeyboxes>", "<NumberOfKeyboxes>0<!--split-->1</NumberOfKeyboxes>", 1), strings.Replace(base, "-----BEGIN EC PRIVATE KEY-----", "-----BEGIN EC PRIVATE<!--split--> KEY-----", 1), strings.Replace(base, "<NumberOfKeyboxes>1</NumberOfKeyboxes>", "<NumberOfKeyboxes>\u00a01</NumberOfKeyboxes>", 1)}
	for i, data := range cases {
		if _, err := inspect([]byte(data), time.Now()); err == nil {
			t.Fatal("ambiguous XML accepted", i)
		}
	}
}

func TestUTF8BOMPreservesCryptographicIdentity(t *testing.T) {
	data := fixture(t, false)
	plain, err := inspect(data, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	withBOM := append([]byte{0xef, 0xbb, 0xbf}, data...)
	bom, err := inspect(withBOM, time.Now())
	if err != nil || plain.Identity != bom.Identity || plain.Fingerprint == bom.Fingerprint {
		t.Fatal("BOM handling inconsistent", err)
	}
}

func TestEndEntityCertificateCannotBecomeKeyboxSigner(t *testing.T) {
	data := fixture(t, false)
	var d Document
	if err := xml.Unmarshal(data, &d); err != nil {
		t.Fatal(err)
	}
	key := &d.Boxes[0].Keys[0]
	s, err := signer(key.Private)
	if err != nil {
		t.Fatal(err)
	}
	rootPEM, _ := pem.Decode(cleanPEM(key.Certificates[len(key.Certificates)-1]))
	root, _ := x509.ParseCertificate(rootPEM.Bytes)
	leafPEM, _ := pem.Decode(cleanPEM(key.Certificates[0]))
	leaf, _ := x509.ParseCertificate(leafPEM.Bytes)
	leaf.IsCA = false
	leaf.KeyUsage = x509.KeyUsageDigitalSignature
	der, err := x509.CreateCertificate(rand.Reader, leaf, root, s.Public(), s)
	if err != nil {
		t.Fatal(err)
	}
	key.Certificates[0] = string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
	bad, err := xml.Marshal(d)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = inspect(bad, time.Now()); err == nil {
		t.Fatal("non-CA certificate accepted as attestation signer")
	}
}

func TestMalformedCRLDoesNotEraseKnownRevocations(t *testing.T) {
	for _, body := range []string{`{"entries":{"7":{}}}`, `{"entries":{"7":{"status":"UNKNOWN"}}}`, `{"entries":{"07":{"status":"REVOKED"}}}`, `{"entries":{"XX":{"status":"REVOKED"}}}`} {
		e := Engine{revoked: map[string]bool{"7": true}, request: func(*http.Request) (*http.Response, error) { return reply(200, []byte(body)), nil }}
		e.crl(context.Background())
		if e.status.Revocation != "invalid_response" || !e.revoked["7"] || !e.crlAt.IsZero() {
			t.Fatal("invalid CRL treated as healthy", body)
		}
	}
}

func TestOversizedJournalRejectedBeforeRecovery(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	os.WriteFile(e.target(), []byte("current"), 0600)
	td := filepath.Join(dir, ".autopilot-transaction")
	os.Mkdir(td, 0700)
	journal := filepath.Join(td, "journal.json")
	f, err := os.OpenFile(journal, os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	f.Truncate(128 << 20)
	f.Close()
	if e.recoverTransaction() == nil {
		t.Fatal("oversized metadata accepted")
	}
	got, _ := os.ReadFile(e.target())
	if string(got) != "current" || !exists(journal) {
		t.Fatal("oversized journal changed state")
	}
}

func TestCorruptRevisionCannotPreventShutdown(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	os.WriteFile(filepath.Join(dir, "autopilot"), nil, 0600)
	os.WriteFile(filepath.Join(dir, ".autopilot-config-revision"), []byte("corrupted"), 0600)
	if err := e.disable(context.Background()); err != nil {
		t.Fatal(err)
	}
	if e.enabled() {
		t.Fatal("corrupt config kept updater enabled")
	}
	if e.setFlag(context.Background(), "autopilot", true) == nil {
		t.Fatal("corrupt generation silently reused")
	}
}

func TestCorruptRevisionBlocksInstallsButNotStop(t *testing.T) {
	dir := t.TempDir()
	e := Engine{root: dir, ram: dir, brain: dir}
	old := fixture(t, false)
	os.WriteFile(e.target(), old, 0600)
	os.WriteFile(filepath.Join(dir, ".autopilot-config-revision"), nil, 0600)
	sum := sha256.Sum256(old)
	if e.install(fixture(t, false), hex.EncodeToString(sum[:]), generation(dir), false) == nil {
		t.Fatal("corrupt config allowed install")
	}
	if err := e.disable(context.Background()); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(e.target())
	if !bytes.Equal(got, old) {
		t.Fatal("working file changed")
	}
}

func TestAnUnsetClockIsRetriedSoonThenLessOften(t *testing.T) {
	want := []time.Duration{5 * time.Minute, 10 * time.Minute, 20 * time.Minute, 40 * time.Minute, 80 * time.Minute, 2 * time.Hour, 2 * time.Hour}
	for i, w := range want {
		if got := failureRetry("time_unknown", i+1); got != w {
			t.Errorf("clock failure %d: %v, want %v", i+1, got, w)
		}
	}
	if failureRetry("waiting", 3) != 2*time.Hour || failureRetry("", 0) != 2*time.Hour {
		t.Fatal("any other failure waits two hours")
	}
}
