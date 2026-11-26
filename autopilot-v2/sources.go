package main

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/url"
	"sort"
	"strings"
	"time"
)

func decodeOfficial(b []byte) ([]byte, error) {
	var err error
	for i := 0; i < 10; i++ {
		b, err = base64.StdEncoding.DecodeString(strings.Join(strings.Fields(string(b)), ""))
		if err != nil {
			return nil, err
		}
		if len(b) > maxXML {
			return nil, errors.New("decode size")
		}
	}
	b, err = hex.DecodeString(strings.Join(strings.Fields(string(b)), ""))
	if err != nil {
		return nil, err
	}
	for i, c := range b {
		if c >= 'a' && c <= 'z' {
			b[i] = 'a' + (c-'a'+13)%26
		}
		if c >= 'A' && c <= 'Z' {
			b[i] = 'A' + (c-'A'+13)%26
		}
	}
	return b, nil
}

func decodeSecondary(b []byte) ([]byte, error) {
	const shuffled = "1dgWnocayqxU3r6vA5lCIPYfHmkV08b4tz+KMsp2NQ9LRXihODwSj7BEFJ/ZuGTe"
	const standard = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	b = []byte(strings.Join(strings.Fields(string(b)), ""))
	for i, c := range b {
		j := strings.IndexByte(shuffled, c)
		if j >= 0 {
			b[i] = standard[j]
		} else if c != '=' {
			return nil, errors.New("encoded character")
		}
	}
	return base64.StdEncoding.DecodeString(string(b))
}

func (e *Engine) candidate(ctx context.Context, u string, secondary bool) ([]byte, Health, error) {
	b, err := e.get(ctx, u, maxXML)
	if err != nil {
		return nil, Health{}, err
	}
	if secondary {
		b, err = decodeSecondary(b)
	} else {
		b, err = decodeOfficial(b)
	}
	if err != nil {
		return nil, Health{}, err
	}
	h, err := inspect(b, time.Now())
	if err != nil {
		return nil, h, err
	}
	address, _ := url.Parse(u)
	if err = checkConsumerFormat(b, strictProfile); err != nil {
		logEvent("candidate_incompatible", address.Hostname(), 0)
		return nil, h, err
	}
	if strings.HasSuffix(u, "/Megatron2") || e.isKnownAnchor(h.Identity) || e.isKnownAnchor(h.Fingerprint) {
		h.Anchor = true
	}
	if e.isRevoked(h) {
		logEvent("candidate_revoked", address.Hostname(), 0)
		return nil, h, errors.New("candidate revoked")
	}
	if h.State != "valid" || !trusted(h) {
		logEvent("candidate_invalid", address.Hostname(), 0)
		return nil, h, errors.New("candidate invalid or untrusted")
	}
	if e.isRejected(h.Fingerprint) {
		logEvent("candidate_rejected_before", address.Hostname(), 0)
		return nil, h, errors.New("candidate previously rejected by consumer")
	}
	return b, h, nil
}

func (e *Engine) secondary(ctx context.Context) ([]byte, Health, error) {
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	b, err := e.get(ctx, "https://rawbin.dpejoh.com/catalog", 1<<20)
	if err != nil {
		return nil, Health{}, err
	}
	var d struct {
		Entries []struct {
			Source  string          `json:"source"`
			Version json.RawMessage `json:"version"`
			Revoked *bool           `json:"revoked"`
			Soft    *bool           `json:"softbanned"`
			Serial  string          `json:"serial"`
			Expires *string         `json:"expires_at"`
		} `json:"entries"`
	}
	if err = json.Unmarshal(b, &d); err != nil {
		return nil, Health{}, err
	}
	// Longest-lived entries first; entries without a known expiry go last.
	catalogExpiry := func(p *string) time.Time {
		if p == nil {
			return time.Time{}
		}
		t, err := time.Parse(time.RFC3339, *p)
		if err != nil {
			return time.Time{}
		}
		return t
	}
	sort.SliceStable(d.Entries, func(i, j int) bool {
		return catalogExpiry(d.Entries[i].Expires).After(catalogExpiry(d.Entries[j].Expires))
	})
	// Round-robin sources rather than spending all slots on one publisher.
	groups := map[string][]string{}
	order := []string{}
	for _, v := range d.Entries {
		if v.Revoked == nil || v.Soft == nil || *v.Revoked || *v.Soft {
			continue
		}
		// The catalog spells serials like Google's list does, so both checks are free.
		if v.Serial != "" && e.revoked[v.Serial] {
			continue
		}
		if t := catalogExpiry(v.Expires); !t.IsZero() && t.Before(time.Now()) {
			continue
		}
		if !validSourceName(v.Source) {
			continue
		}
		var ver string
		if json.Unmarshal(v.Version, &ver) != nil {
			ver = string(v.Version)
		}
		if len(ver) == 0 || len(ver) > 40 || strings.ContainsAny(ver, "/\\\r\n") {
			continue
		}
		if _, ok := groups[v.Source]; !ok {
			order = append(order, v.Source)
		}
		groups[v.Source] = append(groups[v.Source], "https://rawbin.dpejoh.com/key/"+url.PathEscape(v.Source)+"/"+url.PathEscape(ver))
	}
	priority := e.sourcePriority()
	rank := func(s string) int {
		for i, name := range priority {
			if name == s {
				return i
			}
		}
		return len(priority)
	}
	sort.SliceStable(order, func(i, j int) bool { return rank(order[i]) < rank(order[j]) })
	urls := []string{}
	for round := 0; round < len(d.Entries); round++ {
		added := false
		for _, s := range order {
			if round < len(groups[s]) {
				urls = append(urls, groups[s][round])
				added = true
			}
		}
		if !added {
			break
		}
	}
	seen := map[string]bool{}
	start := e.cursor
	for i := 0; i < e.candidateBudget() && i < len(urls); i++ {
		idx := (start + i) % len(urls)
		e.cursor = (idx + 1) % len(urls)
		u := urls[idx]
		if seen[u] {
			continue
		}
		seen[u] = true
		b, h, err := e.candidate(ctx, u, true)
		if err == nil && e.eligible(h) {
			return b, h, nil
		}
		if ctx.Err() != nil {
			break
		}
	}
	return nil, Health{}, errors.New("secondary exhausted")
}

func (e *Engine) eligible(c Health) bool {
	h := e.status.Local
	if c.Fingerprint == h.Fingerprint || (h.Identity != "" && c.Identity == h.Identity && !c.Expires.After(h.Expires)) {
		return false
	}
	if h.State == "valid" && !e.isRevoked(h) && ((h.Anchor && (c.Anchor || e.status.Revocation != "fresh")) || (!h.Anchor && (c.Anchor || !c.Expires.After(h.Expires) || e.status.Revocation != "fresh"))) {
		return false
	}
	return true
}
