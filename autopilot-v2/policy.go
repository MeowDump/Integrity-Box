package main

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Policy holds the tunable behaviour of the engine. The compiled code is the mechanism;
// everything that changes often (which sources first, how many candidates, thresholds, the
// consumer's log wording) lives in /data/adb/Box-Brain/autopilot.conf, so it can be changed
// without rebuilding. Values are clamped to safe bounds: the file can tune the engine but
// cannot switch off a safety invariant (HTTPS only, verified chains, atomic installs).
type Policy struct {
	CandidateBudget int
	SourcePriority  []string
	RenewBefore     time.Duration
	ProbeInterval   time.Duration
	ProbeSettle     time.Duration
	ExtraHosts      []string
	Consumer        ConsumerOverride
	PIF             PIFPolicy
}

// PIFPolicy tunes the fingerprint contour (pif*.go). Mode "off" disables the contour entirely,
// "manual" only reports (no writes), "auto" repairs the patch pair and replaces bad fingerprints.
type PIFPolicy struct {
	Mode         string
	RenewBefore  time.Duration
	FollowLatest bool
	SyncPatch    bool
	Probe        bool
	ProbeWait    time.Duration
	Lifetime     time.Duration
	Sources      []string
}

func defaultPIFPolicy() PIFPolicy {
	return PIFPolicy{Mode: "auto", RenewBefore: 72 * time.Hour, SyncPatch: true, Probe: true, ProbeWait: 15 * time.Second,
		Lifetime: 42 * 24 * time.Hour, Sources: []string{"archive", "google"}}
}

// ConsumerOverride replaces fields of the built-in Tricky Store description.
type ConsumerOverride struct {
	Modules    []string
	Tag        string
	Rejections []string
	compiled   []*regexp.Regexp
}

const (
	policyMaxBytes = 16 << 10
	policyMaxLines = 200
	policyMaxNotes = 10
)

var (
	moduleIDPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)
	logTagPattern   = regexp.MustCompile(`^[A-Za-z0-9._-]{1,23}$`)
	hostPattern     = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$`)
)

func defaultPolicy() Policy {
	return Policy{
		CandidateBudget: 5,
		SourcePriority:  []string{"TAKR", "@Xiaomi_Lei_Jun", "@Samsung_Jae_Yong", "Yuri"},
		RenewBefore:     24 * time.Hour,
		ProbeInterval:   6 * time.Hour,
		ProbeSettle:     5 * time.Second,
		PIF:             defaultPIFPolicy(),
	}
}

func splitList(v string) []string {
	out := []string{}
	for _, part := range strings.Split(v, ",") {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, part)
		}
	}
	return out
}

func onOff(key, value string, current bool, note func(string, ...any)) bool {
	switch strings.ToLower(value) {
	case "on", "true", "1", "yes":
		return true
	case "off", "false", "0", "no":
		return false
	}
	note("%s: use on or off", key)
	return current
}

func validSourceName(s string) bool {
	return s != "" && len(s) <= 80 && !strings.ContainsAny(s, "/\\\r\n")
}

// parsePolicy never fails: invalid or unsafe lines are skipped (or clamped) and reported in
// notes, so a damaged file degrades to the defaults instead of stopping the updater.
func parsePolicy(text string) (Policy, []string) {
	p := defaultPolicy()
	notes := []string{}
	note := func(format string, a ...any) {
		if len(notes) < policyMaxNotes {
			notes = append(notes, fmt.Sprintf(format, a...))
		}
	}
	if len(text) > policyMaxBytes {
		note("configuration larger than %d bytes ignored", policyMaxBytes)
		return defaultPolicy(), notes
	}
	lines := strings.Split(text, "\n")
	if len(lines) > policyMaxLines {
		note("configuration longer than %d lines ignored", policyMaxLines)
		return defaultPolicy(), notes
	}
	number := func(key, value string, lo, hi int, current int) int {
		n, err := strconv.Atoi(value)
		if err != nil {
			note("%s: not a number", key)
			return current
		}
		if n < lo || n > hi {
			note("%s: %d clamped to %d..%d", key, n, lo, hi)
			if n < lo {
				return lo
			}
			return hi
		}
		return n
	}
	for _, raw := range lines {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq < 0 {
			note("line without '=' ignored")
			continue
		}
		key, value := strings.ToLower(strings.TrimSpace(line[:eq])), strings.TrimSpace(line[eq+1:])
		switch key {
		case "candidate_budget":
			p.CandidateBudget = number(key, value, 1, 10, p.CandidateBudget)
		case "renew_before_hours":
			p.RenewBefore = time.Duration(number(key, value, 6, 168, int(p.RenewBefore/time.Hour))) * time.Hour
		case "probe_interval_hours":
			p.ProbeInterval = time.Duration(number(key, value, 1, 48, int(p.ProbeInterval/time.Hour))) * time.Hour
		case "probe_settle_seconds":
			p.ProbeSettle = time.Duration(number(key, value, 1, 15, int(p.ProbeSettle/time.Second))) * time.Second
		case "source_priority":
			list := []string{}
			for _, s := range splitList(value) {
				if validSourceName(s) {
					list = append(list, s)
				} else {
					note("source_priority: invalid name ignored")
				}
			}
			if len(list) > 16 {
				list = list[:16]
			}
			if len(list) > 0 {
				p.SourcePriority = list
			}
		case "pif_mode":
			switch strings.ToLower(value) {
			case "auto", "manual", "off":
				p.PIF.Mode = strings.ToLower(value)
			default:
				note("pif_mode: use auto, manual or off")
			}
		case "pif_renew_before_hours":
			p.PIF.RenewBefore = time.Duration(number(key, value, 24, 336, int(p.PIF.RenewBefore/time.Hour))) * time.Hour
		case "pif_lifetime_days":
			p.PIF.Lifetime = time.Duration(number(key, value, 14, 90, int(p.PIF.Lifetime/(24*time.Hour)))) * 24 * time.Hour
		case "pif_probe_wait_seconds":
			p.PIF.ProbeWait = time.Duration(number(key, value, 5, 30, int(p.PIF.ProbeWait/time.Second))) * time.Second
		case "pif_follow_latest":
			p.PIF.FollowLatest = onOff(key, value, p.PIF.FollowLatest, note)
		case "pif_sync_patch":
			p.PIF.SyncPatch = onOff(key, value, p.PIF.SyncPatch, note)
		case "pif_probe":
			p.PIF.Probe = onOff(key, value, p.PIF.Probe, note)
		case "pif_sources":
			list := []string{}
			for _, s := range splitList(strings.ToLower(value)) {
				if s == "archive" || s == "google" {
					list = append(list, s)
				} else {
					note("pif_sources: %q ignored (archive, google)", s)
				}
			}
			if len(list) > 0 {
				p.PIF.Sources = list
			}
		case "extra_hosts":
			list := []string{}
			for _, h := range splitList(value) {
				h = strings.ToLower(h)
				if len(h) <= 253 && hostPattern.MatchString(h) && net.ParseIP(h) == nil {
					list = append(list, h)
				} else {
					note("extra_hosts: %q is not a plain DNS name", h)
				}
			}
			if len(list) > 8 {
				list = list[:8]
			}
			p.ExtraHosts = list
		case "consumer.tricky_store.modules":
			list := []string{}
			for _, m := range splitList(value) {
				if moduleIDPattern.MatchString(m) && m != "." && m != ".." {
					list = append(list, m)
				} else {
					note("consumer modules: invalid id ignored")
				}
			}
			p.Consumer.Modules = list
		case "consumer.tricky_store.tag":
			if logTagPattern.MatchString(value) {
				p.Consumer.Tag = value
			} else {
				note("consumer tag: invalid value ignored")
			}
		case "consumer.tricky_store.rejection":
			re, err := regexp.Compile(value)
			switch {
			case value == "" || len(value) > 200 || err != nil:
				note("consumer rejection: invalid pattern ignored")
			case len(value) < 4 || re.MatchString(""):
				note("consumer rejection: pattern too broad, ignored")
			case len(p.Consumer.compiled) >= 8:
				note("consumer rejection: at most 8 patterns")
			default:
				p.Consumer.Rejections = append(p.Consumer.Rejections, value)
				p.Consumer.compiled = append(p.Consumer.compiled, re)
			}
		default:
			note("unknown key %q ignored", key)
		}
	}
	return p, notes
}

func (e *Engine) policyPath() string { return filepath.Join(e.brain, "autopilot.conf") }

// policySignature changes whenever the configuration file is created, edited or removed,
// so the daemon can run a cycle soon after an edit instead of waiting for the next due time.
func (e *Engine) policySignature() string {
	st, err := os.Lstat(e.policyPath())
	if err != nil {
		return "absent"
	}
	return fmt.Sprintf("%d:%d", st.Size(), st.ModTime().UnixNano())
}

// renewWindow and extraAllowedHosts back free functions; applyPolicy keeps them in step.
var (
	renewWindow       = 24 * time.Hour
	extraAllowedHosts = map[string]bool{}
)

// reloadPolicy re-reads the configuration; called at the start of every cycle.
func (e *Engine) reloadPolicy() {
	e.status.ConfigNotes = nil
	defer e.resetRejectionsOnConsumerPolicyChange()
	b, err := readLimited(e.policyPath(), policyMaxBytes+1)
	switch {
	case err == nil:
		e.policy, e.status.ConfigNotes = parsePolicy(string(b))
	case strings.Contains(err.Error(), "byte limit"):
		e.policy = defaultPolicy()
		e.status.ConfigNotes = []string{fmt.Sprintf("configuration larger than %d bytes ignored", policyMaxBytes)}
	default: // absent or unreadable: defaults
		e.policy = defaultPolicy()
	}
	e.applyPolicy()
}

// A refusal may have come from a pattern that was too broad. When the consumer description
// changes, remembered refusals are forgotten so the new description gets a fresh verdict.
func (e *Engine) resetRejectionsOnConsumerPolicyChange() {
	o := e.policy.Consumer
	sig := strings.Join(o.Modules, ",") + "|" + o.Tag + "|" + strings.Join(o.Rejections, "\x00")
	if e.consumerSigSet && sig != e.consumerSig {
		_ = os.Remove(e.rejectedPath())
	}
	e.consumerSig, e.consumerSigSet = sig, true
}

func (e *Engine) applyPolicy() {
	renewWindow = e.renewBefore()
	hosts := map[string]bool{}
	for _, h := range e.policy.ExtraHosts {
		hosts[h] = true
	}
	extraAllowedHosts = hosts
}

// Accessors are safe on a zero Engine: unset values fall back to the defaults.
func (e *Engine) candidateBudget() int {
	if e.policy.CandidateBudget > 0 {
		return e.policy.CandidateBudget
	}
	return defaultPolicy().CandidateBudget
}
func (e *Engine) sourcePriority() []string {
	if len(e.policy.SourcePriority) > 0 {
		return e.policy.SourcePriority
	}
	return defaultPolicy().SourcePriority
}

// pifPolicy returns the effective fingerprint policy; an Engine without a loaded policy
// (unit tests, first cycle) gets the defaults.
func (e *Engine) pifPolicy() PIFPolicy {
	if e.policy.PIF.Mode == "" {
		return defaultPIFPolicy()
	}
	return e.policy.PIF
}

func (e *Engine) renewBefore() time.Duration {
	if e.policy.RenewBefore > 0 {
		return e.policy.RenewBefore
	}
	return defaultPolicy().RenewBefore
}
func (e *Engine) probeInterval() time.Duration {
	if e.policy.ProbeInterval > 0 {
		return e.policy.ProbeInterval
	}
	return defaultPolicy().ProbeInterval
}
func (e *Engine) probeSettleTime() time.Duration {
	if e.probeSettle > 0 { // test override
		return e.probeSettle
	}
	if e.policy.ProbeSettle > 0 {
		return e.policy.ProbeSettle
	}
	return defaultPolicy().ProbeSettle
}

// consumer returns the built-in Tricky Store description with configured overrides.
func (e *Engine) consumer() consumerSpec {
	c := trickyStore
	o := e.policy.Consumer
	if len(o.Modules) > 0 {
		c.Modules = o.Modules
	}
	if o.Tag != "" {
		c.Tag = o.Tag
	}
	if len(o.compiled) > 0 {
		c.Rejections = o.compiled
	}
	return c
}
