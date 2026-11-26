package main

import (
	"encoding/json"
	"path/filepath"
	"strings"
)

const maxRejected = 64

func (e *Engine) rejectedPath() string { return filepath.Join(e.brain, ".autopilot-rejected.json") }

// rejectedFingerprints reads the advisory memory of files a consumer refused. Corruption
// reads as empty: this memory must never be able to block the updater.
func (e *Engine) rejectedFingerprints() []string {
	b, err := readLimited(e.rejectedPath(), 8192)
	if err != nil {
		return nil
	}
	var hashes []string
	if json.Unmarshal(b, &hashes) != nil || len(hashes) > maxRejected {
		return nil
	}
	valid := hashes[:0]
	for _, h := range hashes {
		if len(h) == 64 && strings.Trim(h, "0123456789abcdef") == "" {
			valid = append(valid, h)
		}
	}
	return valid
}
func (e *Engine) isRejected(fingerprint string) bool {
	for _, h := range e.rejectedFingerprints() {
		if h == fingerprint {
			return true
		}
	}
	return false
}

// rememberRejected appends a fingerprint, evicting the oldest entry when full.
func (e *Engine) rememberRejected(fingerprint string) error {
	hashes := e.rejectedFingerprints()
	for _, h := range hashes {
		if h == fingerprint {
			return nil
		}
	}
	hashes = append(hashes, fingerprint)
	if len(hashes) > maxRejected {
		hashes = hashes[len(hashes)-maxRejected:]
	}
	return writeJSON(e.rejectedPath(), hashes)
}
