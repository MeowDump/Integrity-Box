package main

import (
	"context"
	"net/http"
	"os"
	"strings"
	"testing"
)

func flashFixture(t *testing.T) []byte {
	t.Helper()
	b, err := os.ReadFile("testdata/flashstation_bluejay.json")
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// Live data of 2026-11-16 (trimmed): the newest Canary of bluejay_beta is ZP11.261016.008, and a
// NEWER non-Canary preview (DP11.261030.003) sits at the end of the list and must be ignored.
func TestNewestCanaryIgnoresNonCanaryPreviews(t *testing.T) {
	b, err := newestCanary(flashFixture(t), "bluejay_beta")
	if err != nil {
		t.Fatal(err)
	}
	if b.ReleaseCandidateName != "ZP11.261016.008" || b.BuildID != "16754936" {
		t.Fatalf("picked %+v", b)
	}
	if _, err = newestCanary(flashFixture(t), "nosuch_beta"); err == nil {
		t.Fatal("an unknown product must fail")
	}
}

// Cross-check against the maintainer's published file: generating from Google's metadata must
// reproduce meow.prop field for field.
func TestGeneratedFingerprintEqualsTheMaintainersFile(t *testing.T) {
	b, err := newestCanary(flashFixture(t), "bluejay_beta")
	if err != nil {
		t.Fatal(err)
	}
	got, err := googleCandidateFrom(b, pifFile{Props: map[string]string{}})
	if err != nil {
		t.Fatal(err)
	}
	want := mustPIF(t, novemberMeow)
	for k, v := range want.Props {
		if got.Props[k] != v {
			t.Errorf("%s: generated %q, maintainer %q", k, got.Props[k], v)
		}
	}
	if len(got.Props) != len(want.Props) {
		t.Errorf("field sets differ: %v vs %v", got.Props, want.Props)
	}
}

func TestGoogleCandidateRejectsWhatItCannotName(t *testing.T) {
	ok := flashBuild{Product: "cubs_beta", BuildID: "16484274", ReleaseCandidateName: "ZP11.260918.007"}
	ok.PreviewMetadata.ReleaseTrackVersionName = "Canary 202610"
	if _, err := googleCandidateFrom(ok, pifFile{Props: map[string]string{}}); err == nil {
		t.Fatal("an unknown product without an installed file of that product has no model")
	}
	cur := mustPIF(t, octoberPIF) // installed product cubs_beta, MODEL Pixel 11, SDK 37
	got, err := googleCandidateFrom(ok, cur)
	if err != nil || got.Props["MODEL"] != "Pixel 11" || got.Props["DEVICE_INITIAL_SDK_INT"] != "37" || got.Props["SECURITY_PATCH"] != "2026-10-05" {
		t.Fatalf("the installed product keeps its model and SDK: %v %v", got.Props, err)
	}
	bad := ok
	bad.Product = "x; rm -rf /"
	if _, err := googleCandidateFrom(bad, cur); err == nil {
		t.Fatal("product shape must be validated")
	}
	bad = ok
	bad.PreviewMetadata.ReleaseTrackVersionName = "Beta 3"
	if _, err := googleCandidateFrom(bad, cur); err == nil {
		t.Fatal("only Canary tracks")
	}
}

func TestNewestCanaryValidatesEveryField(t *testing.T) {
	mk := func(name, build string, canary, active bool, track string) string {
		a, c := "false", "false"
		if active {
			a = "true"
		}
		if canary {
			c = "true"
		}
		return `{"flashstationBuild":[{"product":"bluejay_beta","buildId":"` + build + `","releaseCandidateName":"` + name +
			`","previewMetadata":{"releaseTrackVersionName":"` + track + `","canary":` + c + `,"active":` + a + `}}]}`
	}
	cases := map[string]string{
		"inactive":        mk("ZP11.261016.008", "16754936", true, false, "Canary 202611"),
		"not canary":      mk("ZP11.261016.008", "16754936", false, true, "Canary 202611"),
		"bad build id":    mk("ZP11.261016.008", "16754936;id", true, true, "Canary 202611"),
		"bad name":        mk("../../x", "16754936", true, true, "Canary 202611"),
		"bad track":       mk("ZP11.261016.008", "16754936", true, true, "Canary latest"),
		"not json":        "<html>",
		"empty":           `{"flashstationBuild":[]}`,
		"track with year": mk("ZP11.261016.008", "16754936", true, true, "Canary 20261"),
	}
	for name, body := range cases {
		if _, err := newestCanary([]byte(body), "bluejay_beta"); err == nil {
			t.Errorf("%s: must be rejected", name)
		}
	}
}

const flashPage = `<html><body data-client-config="%.@.1,null,&quot;AIzaSyD-bwHpMvFCN3PfRN4Txsw_ECg_iptNfMQ&quot;,&quot;1006-x.apps.googleusercontent.com&quot;"></body></html>`

func googleNet(t *testing.T, m *maintainFixture) (referer *string) {
	t.Helper()
	station := string(flashFixture(t))
	seen := ""
	m.net.files[pifFlashPage] = flashPage
	prev := m.e.request
	m.e.request = func(r *http.Request) (*http.Response, error) {
		u := r.URL.String()
		if strings.HasPrefix(u, "https://content-flashstation-pa.googleapis.com/v1/builds?") {
			seen = r.Header.Get("Referer")
			if !strings.Contains(u, "product=bluejay_beta") || !strings.Contains(u, "key=AIzaSyD-bwHpMvFCN3PfRN4Txsw_ECg_iptNfMQ") {
				return reply(400, nil), nil
			}
			return reply(200, []byte(station)), nil
		}
		return prev(r)
	}
	return &seen
}

func TestMaintainFromGoogleWhenTheMaintainerIsSilent(t *testing.T) {
	m := newMaintain(t, octoberPIF, "all=2026-10-05\n")
	// the installed file is the October cubs fingerprint; the maintainer's feed is down, Google answers for bluejay only
	m.e.policy.PIF.Sources = []string{"archive", "google"}
	m.net.files = map[string]string{} // archive: everything 404
	referer := googleNet(t, m)
	m.e.pifBanned = map[string]bool{"ZP11.260918.007": true}
	m.e.pifBannedKnown, m.e.pifBannedDue = true, 1e12
	// installed product is cubs_beta: the API call asks for cubs_beta, which the fixture lacks -> google unavailable, file untouched
	before := m.propText()
	m.maintain(true)
	if m.propText() != before || !strings.Contains(m.e.status.PIF.Reason, "google_unavailable") {
		t.Fatalf("no cubs build in the answer must leave the file alone: %q", m.e.status.PIF.Reason)
	}
	// installed product bluejay_beta (the maintainer's file): Google replaces it with the newest canary
	old := strings.NewReplacer("ZP11.261016.008", "ZP11.260821.010", "16754936", "16290768", "SECURITY_PATCH=2026-11-05", "SECURITY_PATCH=2026-09-05").Replace(novemberMeow)
	m2 := newMaintain(t, old, "all=2026-09-05\n")
	m2.e.policy.PIF.Sources = []string{"archive", "google"}
	m2.net.files = map[string]string{}
	referer = googleNet(t, m2)
	m2.e.pifBanned = map[string]bool{"ZP11.260821.010": true}
	m2.e.pifBannedKnown, m2.e.pifBannedDue = true, 1e12
	m2.maintain(true)
	s := m2.e.status.PIF
	if s.ID != "ZP11.261016.008" || s.Action != "installed" || s.PatchPair != "match" || s.Patch != "2026-11-05" {
		t.Fatalf("google install: %+v", s)
	}
	if m2.patchText() != "all=2026-11-05\n" || *referer != "https://flash.android.com" {
		t.Fatalf("patch %q referer %q", m2.patchText(), *referer)
	}
	if s.Applied != "accepted" {
		t.Fatalf("probe: %s/%s", s.Applied, s.Evidence)
	}
}

func TestGoogleSourceFailsClosed(t *testing.T) {
	m := newMaintain(t, octoberPIF, "all=2026-10-05\n")
	e := m.e
	ctx := context.Background()
	m.net.files[pifFlashPage] = "<html>no key here</html>"
	if _, err := e.pifGoogleCandidate(ctx, mustPIF(t, novemberMeow)); err == nil || !strings.Contains(err.Error(), "api key") {
		t.Fatalf("a page without an API key: %v", err)
	}
	m.net.down = true
	if _, err := e.pifGoogleCandidate(ctx, mustPIF(t, novemberMeow)); err == nil {
		t.Fatal("offline must fail")
	}
}

// Several ACTIVE canaries: the newest track wins, then the highest build id, whatever the list order.
func TestNewestCanaryOrdersByTrackThenBuild(t *testing.T) {
	entry := func(name, build, track string) string {
		return `{"product":"bluejay_beta","buildId":"` + build + `","releaseCandidateName":"` + name +
			`","previewMetadata":{"releaseTrackVersionName":"` + track + `","canary":true,"active":true}}`
	}
	body := `{"flashstationBuild":[` + strings.Join([]string{
		entry("ZP11.261016.008", "16754936", "Canary 202611"),
		entry("ZP11.260918.007", "16484274", "Canary 202610"),
		entry("ZP11.261020.001", "16800000", "Canary 202611"),
		entry("ZP11.250101.001", "99999999999", "Canary 202501"),
	}, ",") + `]}`
	b, err := newestCanary([]byte(body), "bluejay_beta")
	if err != nil || b.BuildID != "16800000" {
		t.Fatalf("got %+v %v, want the highest build of the newest track", b, err)
	}
}

// The product comes from the installed file; a hostile value there must never reach the file we render.
func TestGoogleCandidateValidatesTheProductEvenWhenTheInstalledFileNamesIt(t *testing.T) {
	b := flashBuild{Product: "bluejay_beta;id", BuildID: "16754936", ReleaseCandidateName: "ZP11.261016.008"}
	b.PreviewMetadata.ReleaseTrackVersionName = "Canary 202611"
	cur := pifFile{Props: map[string]string{"PRODUCT": "bluejay_beta;id", "MODEL": "Pixel 6a", "DEVICE_INITIAL_SDK_INT": "32"}}
	if _, err := googleCandidateFrom(b, cur); err == nil {
		t.Fatal("a product that is not [a-z0-9]_beta must be refused before any file is built")
	}
}
