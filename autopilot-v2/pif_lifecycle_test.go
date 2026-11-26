package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

// A time machine for the whole contour: months of daemon cycles (one every 2 hours) against a
// maintainer who publishes a Canary every 28 days with a varying delay, withdraws the old one,
// sometimes goes silent, and a Google backend that sometimes answers. After every simulated day the
// invariants of an autonomous system are checked.

type canaryBuild struct {
	date      time.Time // build date (the date inside the build id)
	published time.Time // when the maintainer / Google made it available
}

func (b canaryBuild) id() string { return "ZP11." + b.date.Format("060102") + ".008" }
func (b canaryBuild) incremental() string {
	return fmt.Sprintf("%d", 16000000+int(b.date.Unix()/86400-20000)*1000)
}
func (b canaryBuild) patch() string {
	n := time.Date(b.date.Year(), b.date.Month()+1, 5, 0, 0, 0, 0, time.UTC)
	return n.Format("2006-01-02")
}
func (b canaryBuild) fingerprint() string {
	return "google/bluejay_beta/bluejay:CANARY/" + b.id() + "/" + b.incremental() + ":user/release-keys"
}
func (b canaryBuild) file() string {
	return "MANUFACTURER=Google\nMODEL=Pixel 6a\nFINGERPRINT=" + b.fingerprint() + "\nBRAND=google\nPRODUCT=bluejay_beta\nDEVICE=bluejay\nRELEASE=CANARY\nID=" +
		b.id() + "\nINCREMENTAL=" + b.incremental() + "\nTYPE=user\nTAGS=release-keys\nSECURITY_PATCH=" + b.patch() + "\nDEVICE_INITIAL_SDK_INT=32\n"
}

// feed builds the published history: a build every 28 days, each published `lags[i]` days late.
func feed(first time.Time, lags []int) []canaryBuild {
	var out []canaryBuild
	for i, l := range lags {
		d := first.AddDate(0, 0, 28*i)
		out = append(out, canaryBuild{date: d, published: d.AddDate(0, 0, l)})
	}
	return out
}

type world struct {
	builds        []canaryBuild
	maintainerEnd time.Time // the maintainer publishes nothing after this instant (zero = never stops)
	banLag        time.Duration
	googleUp      bool
	now           time.Time
	outageFrom    time.Time // every network request fails in [outageFrom, outageTo)
	outageTo      time.Time
}

func (w *world) visible() []canaryBuild {
	var v []canaryBuild
	for _, b := range w.builds {
		if !b.published.After(w.now) && (w.maintainerEnd.IsZero() || !b.published.After(w.maintainerEnd)) {
			v = append(v, b)
		}
	}
	return v
}

func (w *world) googleBuilds() []canaryBuild {
	var v []canaryBuild
	for _, b := range w.builds {
		if !b.date.After(w.now) { // Google has it from the build date on
			v = append(v, b)
		}
	}
	return v
}

func (w *world) handle(r *http.Request) (*http.Response, error) {
	u := r.URL.String()
	if !w.outageFrom.IsZero() && !w.now.Before(w.outageFrom) && w.now.Before(w.outageTo) {
		return nil, os.ErrDeadlineExceeded
	}
	switch {
	case u == pifReleaseAPI:
		vis := w.visible()
		type asset struct {
			Name string `json:"name"`
		}
		var rel struct {
			Assets []asset `json:"assets"`
		}
		rel.Assets = append(rel.Assets, asset{"meow.prop"})
		for i := 0; i+1 < len(vis); i++ {
			if w.now.Sub(vis[i+1].published) >= w.banLag { // the older build is withdrawn banLag after its successor appears
				rel.Assets = append(rel.Assets, asset{"banned-" + strings.ToLower(vis[i].date.Format("jan060102")) + ".prop"})
			}
		}
		b, _ := json.Marshal(rel)
		return reply(200, b), nil
	case u == pifArchiveBase+"meow.prop":
		if vis := w.visible(); len(vis) > 0 {
			return reply(200, []byte(vis[len(vis)-1].file())), nil
		}
	case strings.HasPrefix(u, pifArchiveBase+"banned-"):
		for _, b := range w.visible() {
			if strings.EqualFold(pifArchiveBase+"banned-"+strings.ToLower(b.date.Format("jan060102"))+".prop", u) {
				return reply(200, []byte(b.file())), nil
			}
		}
	case u == pifFlashPage:
		if w.googleUp {
			return reply(200, []byte(flashPage)), nil
		}
		return nil, os.ErrDeadlineExceeded
	case strings.HasPrefix(u, "https://content-flashstation-pa.googleapis.com/v1/builds?"):
		if !w.googleUp {
			return nil, os.ErrDeadlineExceeded
		}
		var items []string
		gb := w.googleBuilds()
		for i, b := range gb {
			items = append(items, fmt.Sprintf(`{"product":"bluejay_beta","buildId":"%s","releaseCandidateName":"%s","previewMetadata":{"releaseTrackVersionName":"Canary %s","canary":true,"active":%v}}`,
				b.incremental(), b.id(), b.date.AddDate(0, 1, 0).Format("200601"), i == len(gb)-1))
		}
		return reply(200, []byte(`{"flashstationBuild":[`+strings.Join(items, ",")+`]}`)), nil
	}
	return reply(404, nil), nil
}

type dayStats struct {
	meowGets, apiGets, googleGets int
}

func runWorld(t *testing.T, w *world, days int, installed canaryBuild, userKey string, cfg func(m *maintainFixture)) (installs []string, finalState PIFStatus) {
	t.Helper()
	text := installed.file() + "\n# Configuration\nspoofBuild=1\n" + userKey + "\n"
	m := newMaintain(t, text, "all="+installed.patch()+"\n")
	if cfg != nil {
		cfg(m)
	}
	m.net.down = false
	w.now = time.Date(2026, 11, 16, 0, 0, 0, 0, time.UTC)
	m.e.clock = func() time.Time { return w.now }
	uptime := 100000.0
	m.e.bootClock = func() float64 { return uptime }
	m.e.request = func(r *http.Request) (*http.Response, error) {
		m.net.hits[r.URL.String()]++
		return w.handle(r)
	}
	m.net.hits = map[string]int{}
	lastID := installed.id()
	var prev dayStats
	for day := 0; day < days; day++ {
		for step := 0; step < 12; step++ { // a daemon cycle every 2 hours
			m.maintain(true)
			w.now = w.now.Add(2 * time.Hour)
			uptime += 2 * 3600
		}
		// ---- invariants at the end of the day
		cur, err := parsePIF([]byte(m.propText()))
		if err != nil {
			t.Fatalf("day %d: the fingerprint file is invalid: %v\n%s", day, err, m.propText())
		}
		if pair := parsePatchFile([]byte(m.patchText())).pair(cur.patch()); pair != "match" {
			t.Fatalf("day %d: the patch pair is %s (patch file %q, fingerprint patch %s)", day, pair, m.patchText(), cur.patch())
		}
		if !strings.Contains(m.propText(), userKey) || !strings.Contains(m.propText(), "spoofBuild=1") {
			t.Fatalf("day %d: the user's configuration was lost:\n%s", day, m.propText())
		}
		if id := cur.Props["ID"]; id != lastID {
			if id < lastID { // ZP11.YYMMDD: lexical order = date order
				t.Fatalf("day %d: moved BACK from %s to %s", day, lastID, id)
			}
			installs = append(installs, id)
			lastID = id
		}
		if m.e.pifBanned[cur.Props["ID"]] {
			// allowed only while nothing better exists
			for _, b := range w.visible() {
				if b.id() > cur.Props["ID"] && !m.e.pifBanned[b.id()] && w.now.Sub(b.published) > 24*time.Hour && !b.date.AddDate(0, 0, 42).Before(w.now) {
					t.Fatalf("day %d: still on banned %s although %s has been available for over a day", day, cur.Props["ID"], b.id())
				}
			}
		}
		now := dayStats{m.net.hits[pifArchiveBase+"meow.prop"], m.net.hits[pifReleaseAPI], m.net.hits[pifFlashPage]}
		if d := now.meowGets - prev.meowGets; d > 5 {
			t.Fatalf("day %d: %d candidate fetches in one day (the throttle is broken)", day, d)
		}
		if d := now.apiGets - prev.apiGets; d > 5 {
			t.Fatalf("day %d: %d release-listing requests in one day", day, d)
		}
		if d := now.googleGets - prev.googleGets; d > 5 {
			t.Fatalf("day %d: %d Flash Tool requests in one day", day, d)
		}
		prev = now
		if m.e.scope != "" {
			t.Fatalf("day %d: the cooldown scope leaked", day)
		}
	}
	if m, _ := filepathGlob(m.dir); len(m) != 0 {
		t.Fatalf("stray temp files: %v", m)
	}
	return installs, m.e.status.PIF
}

func filepathGlob(dir string) ([]string, error) {
	var out []string
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".autopilot-pif-") && e.Name() != ".autopilot-pif-banned.json" {
			out = append(out, e.Name())
		}
	}
	return out, nil
}

// A healthy maintainer with realistic delays: the contour follows every build, always before the old
// one dies, never goes back, and the pair never drifts.
func TestLifecycleFollowsAPunctualMaintainer(t *testing.T) {
	first := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	w := &world{builds: feed(first, []int{0, 3, 9, 2, 14, 1, 5, 2}), banLag: 48 * time.Hour}
	installs, st := runWorld(t, w, 150, w.builds[0], "myOwnKey=7", func(m *maintainFixture) { m.e.policy.PIF.Sources = []string{"archive"} })
	if len(installs) < 4 {
		t.Fatalf("150 days with 28-day builds should give at least 4 replacements, got %v", installs)
	}
	if st.State == "expired" || st.State == "banned" {
		t.Fatalf("final state %s with a working maintainer", st.State)
	}
}

// The maintainer vanishes for good (he warned about delays): without Google the fingerprint expires
// harmlessly, with Google as the fallback the system keeps itself alive on its own.
func TestLifecycleSurvivesASilentMaintainerOnlyWithTheGoogleFallback(t *testing.T) {
	first := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	silent := func(googleOn bool) (*world, []string, PIFStatus) {
		w := &world{builds: feed(first, []int{0, 3, 9, 2, 14, 1}), banLag: 48 * time.Hour, googleUp: googleOn,
			maintainerEnd: time.Date(2026, 11, 20, 0, 0, 0, 0, time.UTC)}
		src := []string{"archive"}
		if googleOn {
			src = []string{"archive", "google"}
		}
		inst, st := runWorld(t, w, 130, w.builds[0], "myOwnKey=7", func(m *maintainFixture) { m.e.policy.PIF.Sources = src })
		return w, inst, st
	}
	_, inst, st := silent(false)
	// the only build published before the maintainer went silent (2026-11-20) may be installed; nothing after it
	if len(inst) > 1 || (len(inst) == 1 && inst[0] != "ZP11.261113.008") {
		t.Fatalf("without a source nothing newer can be installed: %v", inst)
	}
	if st.State != "expired" {
		t.Fatalf("the unreplaced fingerprint must be reported expired, got %s", st.State)
	}
	_, inst, st = silent(true)
	if len(inst) < 3 {
		t.Fatalf("Google alone should have supplied the following builds, got %v", inst)
	}
	if st.State == "expired" || st.State == "banned" {
		t.Fatalf("final state %s with Google answering", st.State)
	}
}

// Everything is down for six weeks: bounded traffic, no writes, no drift, and recovery afterwards.
func TestLifecycleRidesOutAnOutageAndRecovers(t *testing.T) {
	first := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	w := &world{builds: feed(first, []int{0, 3, 9, 2, 14, 1, 5}), banLag: 48 * time.Hour, googleUp: true,
		outageFrom: time.Date(2026, 12, 1, 0, 0, 0, 0, time.UTC), outageTo: time.Date(2027, 1, 12, 0, 0, 0, 0, time.UTC)}
	installs, st := runWorld(t, w, 150, w.builds[0], "k=1", func(m *maintainFixture) {
		m.e.policy.PIF.Sources = []string{"archive", "google"}
	})
	if len(installs) < 3 {
		t.Fatalf("the system must follow the builds again after the outage, got %v", installs)
	}
	if st.State == "expired" || st.State == "banned" {
		t.Fatalf("final state %s after the outage", st.State)
	}
}
