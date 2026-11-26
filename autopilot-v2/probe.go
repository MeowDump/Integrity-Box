package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	ConsumerAccepted = "accepted"
	ConsumerRejected = "rejected"
	ConsumerUnknown  = "unknown"
)

// ConsumerStatus is published in status.json. "unknown" means the outcome could not be
// observed on this device; it is never treated as a failure and never causes a rollback.
type ConsumerStatus struct {
	ID       string    `json:"id"`
	Required bool      `json:"required"`
	Present  bool      `json:"present"`
	State    string    `json:"state"`    // accepted | rejected | unknown
	Evidence string    `json:"evidence"` // why that state was chosen
	Checked  time.Time `json:"checked"`
}

type consumerSpec struct {
	ID         string
	Required   bool
	Modules    []string // Magisk module ids that provide this consumer
	Tag        string   // log tag the consumer writes under
	Rejections []*regexp.Regexp
}

var trickyStore = consumerSpec{
	ID: "tricky_store", Required: true, Modules: []string{"tricky_store"}, Tag: "TrickyStore",
	Rejections: []*regexp.Regexp{regexp.MustCompile(`Load Keybox failed`), regexp.MustCompile(`valid keybox\.xml was not present`)},
}

func (c consumerSpec) rejects(line string) bool {
	if !strings.Contains(line, c.Tag) {
		return false
	}
	for _, r := range c.Rejections {
		if r.MatchString(line) {
			return true
		}
	}
	return false
}

func (e *Engine) modules() string {
	if e.modulesRoot != "" {
		return e.modulesRoot
	}
	return "/data/adb/modules"
}

// consumerPresent reports whether the consumer is installed and enabled. A directory
// that carries target.txt is accepted for forks that keep the same file contract.
func (e *Engine) consumerPresent(spec consumerSpec) (bool, string) {
	declared := false
	for _, id := range spec.Modules {
		dir := filepath.Join(e.modules(), id)
		if !exists(dir) {
			continue
		}
		declared = true
		if !exists(filepath.Join(dir, "disable")) && !exists(filepath.Join(dir, "remove")) {
			return true, "module"
		}
	}
	if declared {
		// A disabled module leaves target.txt behind; that is not a live consumer.
		return false, "module_disabled"
	}
	if exists(filepath.Join(e.root, "target.txt")) {
		return true, "directory"
	}
	return false, "not_installed"
}

// logChannel abstracts the platform log. Devices without logcat get no channel and the
// probe degrades to "unknown" instead of guessing.
type logChannel interface {
	Mark(ctx context.Context, nonce string) error
	Lines(ctx context.Context) ([]string, error)
}

type androidLog struct{}

func (androidLog) Mark(ctx context.Context, nonce string) error {
	if !exists("/system/bin/log") {
		return errors.New("log binary missing")
	}
	return exec.CommandContext(ctx, "/system/bin/log", "-p", "i", "-t", "BoxAutoPilot", "probe="+nonce).Run()
}
func (androidLog) Lines(ctx context.Context) ([]string, error) {
	if !exists("/system/bin/logcat") {
		return nil, errors.New("logcat missing")
	}
	cmd := exec.CommandContext(ctx, "/system/bin/logcat", "-d", "-v", "uid,threadtime", "-t", "2000")
	out := &cappedBuffer{limit: 1 << 20}
	cmd.Stdout = out
	if err := cmd.Run(); err != nil {
		return nil, err
	}
	return rootLines(strings.Split(out.String(), "\n")), nil
}

// rootLines keeps only what root wrote (format "MM-DD HH:MM:SS.mmm UID PID TID P TAG: msg"). Tricky
// Store runs as root, while any app can write a line with any tag; an unprivileged forgery of a
// rejection must not roll back a good keybox. Our own marker is written by this root process.
func rootLines(lines []string) []string {
	var keep []string
	for _, l := range lines {
		if f := strings.Fields(l); len(f) > 3 && (f[2] == "root" || f[2] == "0") {
			keep = append(keep, l)
		}
	}
	return keep
}

type probeResult struct{ State, Evidence string }

func newNonce() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func linesAfterMarker(lines []string, nonce string) ([]string, bool) {
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.Contains(lines[i], "probe="+nonce) {
			return lines[i+1:], true
		}
	}
	return nil, false
}

// reloadTrigger opens the keybox for append and closes it without writing. That delivers
// CLOSE_WRITE to a consumer watching the directory, making it re-read the file, while the
// content, mtime and inode stay unchanged.
func reloadTrigger(path string) func() error {
	return func() error {
		f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0)
		if err != nil {
			return err
		}
		return f.Close()
	}
}

// probeConsumer asks the consumer to reload and reads its verdict from the log. A marker
// written first proves the log channel works: without it silence is not evidence.
func probeConsumer(ctx context.Context, spec consumerSpec, logs logChannel, trigger func() error, settle, poll time.Duration) probeResult {
	nonce := newNonce()
	if err := logs.Mark(ctx, nonce); err != nil {
		return probeResult{ConsumerUnknown, "no_log_channel"}
	}
	if err := trigger(); err != nil {
		return probeResult{ConsumerUnknown, "trigger_failed"}
	}
	deadline := time.Now().Add(settle)
	for {
		lines, err := logs.Lines(ctx)
		if err != nil {
			return probeResult{ConsumerUnknown, "no_log_channel"}
		}
		after, seen := linesAfterMarker(lines, nonce)
		if seen {
			for _, l := range after {
				if spec.rejects(l) {
					return probeResult{ConsumerRejected, "rejection_logged"}
				}
			}
		}
		if time.Now().After(deadline) {
			if seen {
				return probeResult{ConsumerAccepted, "no_rejection_logged"}
			}
			return probeResult{ConsumerUnknown, "marker_not_visible"}
		}
		select {
		case <-ctx.Done():
			return probeResult{ConsumerUnknown, "cancelled"}
		case <-time.After(poll):
		}
	}
}

func (e *Engine) runProbe(ctx context.Context) probeResult {
	var logs logChannel = androidLog{}
	if e.logs != nil {
		logs = e.logs
	}
	settle, poll := e.probeSettleTime(), e.probePoll
	if poll == 0 {
		poll = 250 * time.Millisecond
	}
	return probeConsumer(ctx, e.consumer(), logs, reloadTrigger(e.target()), settle, poll)
}

// auditConsumer refreshes status.Consumer and demotes a local key the consumer refused.
// With probe=false (dry run) the keybox is never touched.
func (e *Engine) auditConsumer(ctx context.Context, probe bool) {
	spec := e.consumer()
	present, how := e.consumerPresent(spec)
	st := ConsumerStatus{ID: spec.ID, Required: spec.Required, Present: present, State: ConsumerUnknown, Evidence: how, Checked: time.Now()}
	h := e.status.Local
	switch {
	case !present:
	case h.State != "valid":
		st.Evidence = "local_key_not_valid"
	case e.isRejected(h.Fingerprint):
		st.State, st.Evidence = ConsumerRejected, "remembered_rejection"
	case !probe:
		st.State, st.Evidence = e.lastConsumerState()
	case h.Fingerprint != e.lastProbeFingerprint || e.uptime()-e.lastProbeBoot >= e.probeInterval().Seconds():
		res := e.runProbe(ctx)
		st.State, st.Evidence = res.State, res.Evidence
		e.lastProbeFingerprint, e.lastProbeBoot = h.Fingerprint, e.uptime()
		if res.State == ConsumerRejected {
			_ = e.rememberRejected(h.Fingerprint)
		}
	default:
		st.State, st.Evidence = e.lastConsumerState()
	}
	e.status.Consumer = st
	if st.State == ConsumerRejected && e.status.Local.State == "valid" {
		e.status.Local.State = "consumer_rejected"
	}
}

// lastConsumerState is the previous published verdict, never an empty state.
func (e *Engine) lastConsumerState() (string, string) {
	if e.status.Consumer.State == "" {
		return ConsumerUnknown, "not_probed"
	}
	return e.status.Consumer.State, e.status.Consumer.Evidence
}

// afterInstallDecision maps a post-commit probe to an action. Only a confirmed rejection
// changes anything; an unobservable consumer keeps the new file.
func afterInstallDecision(res probeResult, previous Health, hadPrevious bool) string {
	if res.State != ConsumerRejected {
		return "keep"
	}
	if hadPrevious && previous.State == "valid" {
		return "rollback"
	}
	return "keep_rejected"
}

// verifyInstalled probes the consumer after a commit and reverts when it refuses the file.
// Restoring the previous key is cleanup of our own write, so it deliberately does not depend on
// whether autopilot is still enabled.
func (e *Engine) verifyInstalled(ctx context.Context, installed []byte, installedHealth, previous Health, previousBytes []byte) string {
	spec := e.consumer()
	if present, _ := e.consumerPresent(spec); !present {
		return "keep"
	}
	res := e.runProbe(ctx)
	e.lastProbeFingerprint, e.lastProbeBoot = installedHealth.Fingerprint, e.uptime()
	e.status.Consumer = ConsumerStatus{ID: spec.ID, Required: spec.Required, Present: true, State: res.State, Evidence: res.Evidence, Checked: time.Now()}
	decision := afterInstallDecision(res, previous, len(previousBytes) > 0)
	if decision == "keep" {
		return decision
	}
	_ = e.rememberRejected(installedHealth.Fingerprint)
	e.status.Phase = "consumer_rejected"
	logEvent("consumer_rejected_install", spec.ID, 0)
	if decision == "rollback" {
		source := e.status.Source
		e.status.Source = "rollback" // not a tier: no anchor memory, no provenance claim
		err := e.install(previousBytes, sha256Hex(installed), generation(e.brain), false)
		e.status.Source = source
		if err != nil {
			logEvent("rollback_failed", "local", 0)
			e.status.Local.State = "consumer_rejected"
			return "keep_rejected"
		}
		e.status.Local = e.health()
		return "rolled_back"
	}
	e.status.Local.State = "consumer_rejected"
	return "keep_rejected"
}
