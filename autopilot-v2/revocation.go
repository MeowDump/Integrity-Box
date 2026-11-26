package main

import (
	"context"
	"encoding/json"
	"strings"
	"time"
)

func (e *Engine) isRevoked(h Health) bool {
	for _, s := range h.Serials {
		if e.revoked[s] {
			return true
		}
	}
	for _, s := range h.serialsDec {
		if e.revoked[s] {
			return true
		}
	}
	return false
}

func (e *Engine) crl(ctx context.Context) {
	if !e.crlAt.IsZero() && e.uptime() >= e.crlBoot && e.uptime()-e.crlBoot < e.crlTTL.Seconds() {
		return
	}
	b, err := e.get(ctx, "https://android.googleapis.com/attestation/status", 4<<20)
	if err != nil {
		e.status.Revocation = "unknown_or_stale"
		return
	}
	var d struct {
		Entries map[string]struct {
			Status string `json:"status"`
		} `json:"entries"`
	}
	if json.Unmarshal(b, &d) != nil || d.Entries == nil {
		e.status.Revocation = "invalid_response"
		return
	}
	m := map[string]bool{}
	for s, v := range d.Entries {
		if s == "" || s[0] == '0' || strings.Trim(s, "0123456789abcdef") != "" || (v.Status != "REVOKED" && v.Status != "SUSPENDED") {
			e.status.Revocation = "invalid_response"
			logEvent("crl_invalid_schema", "android.googleapis.com", 200)
			return
		}
		m[s] = true
	}
	e.revoked = m
	e.crlAt = time.Now()
	e.crlBoot = e.uptime()
	e.crlTTL = e.cache["https://android.googleapis.com/attestation/status"].TTL
	if e.crlTTL == 0 {
		e.crlTTL = 12 * time.Hour
	}
	e.status.Revocation = "fresh"
	e.status.CRLChecked = time.Now()
	e.status.CRLUntil = time.Now().Add(e.crlTTL)
}
