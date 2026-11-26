package main

import (
	"path/filepath"
	"time"
)

type Status struct {
	InstalledSource string         `json:"installed_source"`
	Ready           bool           `json:"ready"`
	NextSearch      time.Time      `json:"next_search_due"`
	NextCRL         time.Time      `json:"next_crl_due"`
	TimeState       string         `json:"time_state"`
	TimeSource      string         `json:"time_source"`
	ConfigNotes     []string       `json:"config_notes,omitempty"`
	CRLChecked      time.Time      `json:"crl_checked"`
	CRLUntil        time.Time      `json:"crl_valid_until"`
	Enabled         bool           `json:"desired_enabled"`
	Running         bool           `json:"running"`
	Phase           string         `json:"phase"`
	Local           Health         `json:"local"`
	Consumer        ConsumerStatus `json:"consumer"`
	PIF             PIFStatus      `json:"pif"`
	Revocation      string         `json:"revocation_state"`
	Integrity       string         `json:"integrity_verdict"`
	Reason          string         `json:"reason"`
	Next            time.Time      `json:"next_due"`
	Source          string         `json:"source"`
	PID             int            `json:"pid"`
	Heartbeat       time.Time      `json:"heartbeat"`
}

func (e *Engine) publish() {
	if e.noPublish {
		return
	}
	e.status.Enabled = e.enabled()
	e.status.NextSearch = time.Time{}
	e.status.NextCRL = time.Time{}
	if e.automaticFetchDue > e.uptime() {
		e.status.NextSearch = time.Now().Add(time.Duration((e.automaticFetchDue - e.uptime()) * float64(time.Second)))
	}
	if !e.crlAt.IsZero() {
		e.status.NextCRL = time.Now().Add(time.Duration((e.crlBoot + e.crlTTL.Seconds() - e.uptime()) * float64(time.Second)))
	}
	e.status.Heartbeat = time.Now()
	if err := writeJSON(filepath.Join(e.ram, "status.json"), e.status); err != nil {
		if time.Since(e.statusErrorAt) > 30*time.Minute {
			logEvent("status_write_failed", "local", 0)
			e.statusErrorAt = time.Now()
		}
	} else {
		e.statusErrorAt = time.Time{}
	}
}
