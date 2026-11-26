package main

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// Sources of the fingerprint contour (design §5). Tier "archive" is the release asset set that
// MeowDump publishes next to the keybox tiers: meow.prop is the current Canary fingerprint and
// every banned-*.prop is a fingerprint the maintainer withdrew. Tier "google" is the independent
// generator (pif_google.go).
const (
	pifArchiveBase = "https://github.com/MeowDump/Integrity-Box/releases/download/archive/"
	pifReleaseAPI  = "https://api.github.com/repos/MeowDump/Integrity-Box/releases/tags/archive"
	pifMaxBanned   = 16  // banned-* files read per refresh
	pifMaxSet      = 256 // remembered denylist entries
)

var (
	pifBannedName     = regexp.MustCompile(`^banned-[a-z0-9._-]{1,60}\.prop$`)
	pifFallbackBanned = []string{"banned-october-meow.prop"} // when the release listing is unreachable (plus guessed month names)
	pifIDLine         = regexp.MustCompile(`(?m)^(ID|FINGERPRINT)=([A-Za-z0-9 ._:/+()-]{1,200})\s*$`)
)

func (e *Engine) pifBannedPath() string { return filepath.Join(e.brain, ".autopilot-pif-banned.json") }

// loadBanned restores the denylist remembered across reboots. Corruption reads as empty: this
// memory must never be able to block the updater.
func (e *Engine) loadBanned() {
	if e.pifBanned != nil {
		return
	}
	e.pifBanned = map[string]bool{}
	b, err := readLimited(e.pifBannedPath(), 64<<10)
	if err != nil {
		return
	}
	var list []string
	if json.Unmarshal(b, &list) != nil || len(list) > pifMaxSet {
		return
	}
	for _, v := range list {
		if pifValue.MatchString(v) {
			e.pifBanned[v] = true
		}
	}
	e.pifBannedKnown = true // a denylist read at least once earlier is remembered across reboots
}

// bannedNames lists banned-*.prop assets of the release in the API's own (upload) order and keeps
// the newest pifMaxBanned. A failed listing falls back to the one name known to exist; the bans
// already remembered are never dropped (see refreshBanned), so a rate-limited API only delays news.
func (e *Engine) bannedNames(ctx context.Context) (names []string, listed bool) {
	body, err := e.get(ctx, pifReleaseAPI, 256<<10)
	if err != nil {
		return e.guessBannedNames(), false
	}
	var rel struct {
		Assets []struct {
			Name string `json:"name"`
		} `json:"assets"`
	}
	if json.Unmarshal(body, &rel) != nil {
		return e.guessBannedNames(), false
	}
	seen := map[string]bool{}
	for _, a := range rel.Assets {
		if pifBannedName.MatchString(a.Name) && !seen[a.Name] {
			seen[a.Name] = true
			names = append(names, a.Name)
		}
	}
	if len(names) > pifMaxBanned {
		names = names[len(names)-pifMaxBanned:]
	}
	// A listing that worked but holds no banned-*.prop is a real answer ("nothing withdrawn yet"), not a failure.
	return names, true
}

// guessBannedNames is the best effort when the release listing cannot be read (rate limit, outage):
// the known October name plus the maintainer's naming scheme (banned-<month>-meow.prop) for this and the
// two previous months. A missing guess is a 404, which is harmless.
func (e *Engine) guessBannedNames() []string {
	out := append([]string(nil), pifFallbackBanned...)
	now := e.now()
	for back := 0; back < 3; back++ {
		name := "banned-" + strings.ToLower(time.Date(now.Year(), now.Month()-time.Month(back), 1, 0, 0, 0, 0, time.UTC).Month().String()) + "-meow.prop"
		if pifBannedName.MatchString(name) && name != pifFallbackBanned[0] {
			out = append(out, name)
		}
	}
	return out
}

// refreshBanned merges the maintainer's banned-*.prop files into the remembered denylist. A ban is a
// fact about a build: it is never forgotten because a file could not be read this time. At least
// one file must be readable, otherwise the refresh fails and the caller fails closed.
func (e *Engine) refreshBanned(ctx context.Context) error {
	e.loadBanned()
	fresh := map[string]bool{}
	read := 0
	names, listed := e.bannedNames(ctx)
	if listed && len(names) == 0 {
		e.pifBannedKnown = true // an authoritative empty list: nothing is withdrawn, remembered bans stay
		return nil
	}
	for _, name := range names {
		body, err := e.get(ctx, pifArchiveBase+name, pifMaxBytes)
		if err != nil {
			continue
		}
		read++
		for _, m := range pifIDLine.FindAllStringSubmatch(strings.ReplaceAll(string(body), "\r", ""), -1) {
			fresh[strings.TrimSpace(m[2])] = true
		}
	}
	if read == 0 {
		return errors.New("no banned list readable")
	}
	merged := make(map[string]bool, len(e.pifBanned)+len(fresh))
	for k := range e.pifBanned {
		merged[k] = true
	}
	for k := range fresh {
		merged[k] = true
	}
	if len(merged) > pifMaxSet {
		// The memory is full of old bans: keep what the source lists now (older builds are long expired).
		logEvent("pif_denylist_capped", "local", len(merged))
		merged = fresh
		if len(merged) > pifMaxSet {
			return errors.New("banned list too large")
		}
	}
	if listed {
		e.pifBannedKnown = true
	}
	changed := len(merged) != len(e.pifBanned)
	for k := range merged {
		changed = changed || !e.pifBanned[k]
	}
	if !changed {
		if !listed {
			return errors.New("release listing unavailable; guessed names only")
		}
		return nil
	}
	e.pifBanned = merged
	list := make([]string, 0, len(merged))
	for k := range merged {
		list = append(list, k)
	}
	sort.Strings(list)
	if err := writeJSON(e.pifBannedPath(), list); err != nil {
		return err
	}
	if !listed {
		// The bans that were readable are kept, but the refresh did NOT see the whole truth: report a
		// failure so that it is retried with a pause and never marks the denylist as known by itself.
		return errors.New("release listing unavailable; guessed names only")
	}
	return nil
}

// pifEligible decides whether cand may replace the installed fingerprint. Returns a reason when not.
func (e *Engine) pifEligible(cand, cur pifFile, curState string, now time.Time, pol PIFPolicy) (bool, string) {
	switch {
	case e.pifBanned[cand.Props["ID"]] || e.pifBanned[cand.Props["FINGERPRINT"]]:
		return false, "candidate_banned"
	case cur.Props["ID"] != "" && cand.Props["ID"] == cur.Props["ID"] && cand.Props["FINGERPRINT"] == cur.Props["FINGERPRINT"]:
		return false, "same_build"
	}
	// A candidate must be a user build with release keys: anything else does not pass Play Integrity, and once installed it
	// would be classed "custom" and never replaced. (Not part of parsePIF: a file already on the phone must still be judged
	// by the same rules as the shell doctor, which only checks that the fields agree.)
	// RELEASE=CANARY is required for the same reason: pifAudit treats any other release as a user-chosen custom build.
	if cand.Props["TYPE"] != "user" || cand.Props["TAGS"] != "release-keys" || cand.Props["RELEASE"] != "CANARY" {
		return false, "candidate_not_release_build"
	}
	// The patch is not taken on trust: it must not lie in the future beyond the next monthly patch
	// and must sit near the build date (canary-YYYYMM carries the YYYY-MM-05 patch).
	if pt, err := time.Parse("2006-01-02", cand.patch()); err != nil || pt.After(now.AddDate(0, 0, 62)) {
		return false, "candidate_patch_in_future"
	} else if rel := cand.releaseDate(); !rel.IsZero() && (pt.Before(rel.AddDate(0, 0, -35)) || pt.After(rel.AddDate(0, 0, 125))) {
		return false, "candidate_patch_far_from_build"
	}
	candExp := cand.expiry(pol.Lifetime)
	if candExp.IsZero() {
		return false, "candidate_undated" // no build date in the id: its age is unknowable
	}
	if !now.Before(candExp) {
		return false, "candidate_expired"
	}
	switch curState {
	case "banned", "expired", "absent":
		return true, "" // anything valid beats a withdrawn or dead fingerprint
	case "expiring", "ok":
		if curState == "ok" && !pol.FollowLatest {
			return false, "follow_latest_off"
		}
		curExp := cur.expiry(pol.Lifetime)
		if !curExp.IsZero() && !candExp.IsZero() && !candExp.After(curExp) {
			return false, "not_newer"
		}
		return true, ""
	}
	return false, "state_" + curState
}

// pifFindCandidate walks the configured sources in order and returns the first eligible candidate.
func (e *Engine) pifFindCandidate(ctx context.Context, cur pifFile, curState string, pol PIFPolicy) (*pifFile, string) {
	reason := "no_source"
	for _, src := range pol.Sources {
		var cand pifFile
		var err error
		switch src {
		case "archive":
			var body []byte
			if body, err = e.get(ctx, pifArchiveBase+"meow.prop", pifMaxBytes); err == nil {
				cand, err = parsePIF(body)
			}
		case "google":
			if e.uptime() < e.pifGoogleDue {
				continue // asked recently: the archive is polled more often than this source
			}
			e.pifGoogleDue = e.uptime() + pifGoogleEvery.Seconds()
			cand, err = e.pifGoogleCandidate(ctx, cur)
		default:
			continue
		}
		if err != nil {
			reason = src + "_unavailable"
			continue
		}
		// Dates inside remote content are not believed: they are derived from the build id.
		cand.Released, cand.Expires = time.Time{}, time.Time{}
		ok, why := e.pifEligible(cand, cur, curState, e.now(), pol)
		if ok {
			return &cand, ""
		}
		reason = src + ":" + why
	}
	return nil, reason
}
