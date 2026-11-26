package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// PIFStatus is the "pif" block of status.json.
type PIFStatus struct {
	State       string    `json:"state"` // absent|invalid|banned|expired|expiring|ok|custom|off
	Mode        string    `json:"mode"`
	ID          string    `json:"id,omitempty"`
	Incremental string    `json:"incremental,omitempty"`
	Fingerprint string    `json:"fingerprint,omitempty"`
	Patch       string    `json:"patch,omitempty"`
	PatchFile   string    `json:"patch_file,omitempty"`
	PatchPair   string    `json:"patch_pair"` // match|mismatch|override|stock|missing|unknown|n/a
	Released    string    `json:"released,omitempty"`
	Expires     string    `json:"expires,omitempty"`
	Applied     string    `json:"applied"` // accepted|rejected|unknown|not_probed
	Evidence    string    `json:"evidence,omitempty"`
	Action      string    `json:"action,omitempty"` // last action: patch_synced, installed, none
	Reason      string    `json:"reason,omitempty"`
	Checked     time.Time `json:"checked"`
}

func (e *Engine) now() time.Time {
	if e.clock != nil {
		return e.clock()
	}
	return time.Now()
}

// customPatchMarker: an explicit user choice is a file Box-Brain/Custom-Patch/<date>. The Patch page of the WebUI that
// used to write it was removed in v48, so it is now created by hand.
func (e *Engine) customPatchMarker() bool {
	entries, err := os.ReadDir(filepath.Join(e.brain, "Custom-Patch"))
	return err == nil && len(entries) > 0
}

// pifJSONSource reports whether the module is fed by a JSON fingerprint instead of custom.pif.prop.
func (e *Engine) pifJSONSource() bool {
	for _, p := range []string{filepath.Join(e.moduleRoot, "custom.pif.json"), filepath.Join(e.moduleRoot, "pif.json"), filepath.Join(filepath.Dir(e.brain), "pif.json")} {
		if exists(p) {
			return true
		}
	}
	return false
}

// pifPropNames are the names the fingerprint file has had: the module's own name for it changed between
// releases (custom.pif.prop, later config.meow). The one that exists is used.
var pifPropNames = []string{"config.meow", "custom.pif.prop"}

// pifPropPath is the fingerprint file of the module. When neither name exists yet, the name follows the module
// directory: integrity-box ships config.meow, older module ids ship custom.pif.prop.
func (e *Engine) pifPropPath() string {
	if e.moduleRoot == "" {
		return ""
	}
	for _, name := range pifPropNames {
		if p := filepath.Join(e.moduleRoot, name); exists(p) {
			return p
		}
	}
	if filepath.Base(e.moduleRoot) == "integrity-box" {
		return filepath.Join(e.moduleRoot, "config.meow")
	}
	return filepath.Join(e.moduleRoot, "custom.pif.prop")
}

func (e *Engine) patchPath() string { return filepath.Join(e.root, "security_patch.txt") }

func (e *Engine) pifActive() bool {
	return e.pifPropPath() != "" && e.pifPolicy().Mode != "off"
}

// classifyPIF is pure so the decision table can be tested exhaustively.
func classifyPIF(f pifFile, perr error, absent bool, now time.Time, timeOK bool, pol PIFPolicy, banned map[string]bool) string {
	switch {
	case absent:
		return "absent"
	case perr != nil:
		return "invalid"
	case banned[f.Props["ID"]] || banned[f.Props["FINGERPRINT"]]:
		return "banned"
	}
	if exp := f.expiry(pol.Lifetime); timeOK && !exp.IsZero() {
		if !now.Before(exp) {
			return "expired"
		}
		if exp.Sub(now) < pol.RenewBefore {
			return "expiring"
		}
	}
	return "ok"
}

func readOptional(path string, limit int64) ([]byte, bool, error) {
	b, err := readLimited(path, limit)
	if os.IsNotExist(err) {
		return nil, true, nil
	}
	return b, false, err
}

// pifAudit reads both files and fills status.PIF. It never writes and never needs the network.
// timeOK says whether the clock is verified; without it expiry is not judged (fail closed).
func (e *Engine) pifAudit(timeOK bool) (pifFile, patchFile) {
	pol := e.pifPolicy()
	st := PIFStatus{Mode: pol.Mode, PatchPair: "n/a", Applied: e.status.PIF.Applied, Evidence: e.status.PIF.Evidence,
		Action: e.status.PIF.Action, Checked: e.now()}
	if st.Applied == "" {
		st.Applied = "not_probed"
	}
	defer func() { e.status.PIF = st }()
	if !e.pifActive() {
		st.State = "off"
		return pifFile{}, patchFile{Kind: "none"}
	}
	raw, absent, rerr := readOptional(e.pifPropPath(), pifMaxBytes)
	var f pifFile
	var perr error
	if !absent {
		perr = rerr
		if perr == nil {
			f, perr = parsePIF(raw)
		}
	}
	st.State = classifyPIF(f, perr, absent, e.now(), timeOK, pol, e.pifBanned)
	switch {
	case perr == nil && !absent && f.Props["RELEASE"] != "CANARY":
		st.State = "custom" // a stable/beta Pixel the user chose: a Canary lifetime says nothing about it, never replaced
	case absent && e.pifJSONSource():
		st.State = "custom" // the fingerprint comes from a JSON file: creating a .prop beside it would fight it
	}
	if perr != nil {
		st.Reason = perr.Error()
	}
	var pf patchFile
	if perr == nil && !absent {
		st.ID, st.Incremental, st.Fingerprint, st.Patch = f.Props["ID"], f.Props["INCREMENTAL"], f.Props["FINGERPRINT"], f.Props["SECURITY_PATCH"]
		if !f.Released.IsZero() {
			st.Released = f.Released.Format("2006-01-02")
		}
		if exp := f.expiry(pol.Lifetime); !exp.IsZero() {
			st.Expires = exp.Format("2006-01-02")
		}
		pb, pAbsent, perr2 := readOptional(e.patchPath(), 4096)
		switch {
		case perr2 != nil:
			pf = patchFile{Kind: "unknown"}
		case pAbsent:
			pf = patchFile{Kind: "none"}
		default:
			pf = parsePatchFile(pb)
		}
		st.PatchFile = pf.Value
		st.PatchPair = pf.pair(f.patch())
		if st.PatchPair == "mismatch" && e.customPatchMarker() {
			st.PatchPair = "override" // the user pinned this date (Custom-Patch marker): their decision wins, doctor warns
		}
	}
	return f, pf
}

// syncPatchTxt keeps Box-Brain/patch.txt equal to the fingerprint's patch date. The module's boot script restores
// security_patch.txt from that file on every boot, so a stale copy would bring the old date back after the engine
// replaced the fingerprint. Only an existing file is touched (it is the module's, not ours to create).
func (e *Engine) syncPatchTxt(date string) {
	p := filepath.Join(e.brain, "patch.txt")
	b, absent, err := readOptional(p, 64)
	if err != nil || absent || strings.TrimSpace(string(b)) == date {
		return
	}
	if err := atomic(p, []byte(date+"\n"), 0644); err != nil {
		logEvent("pif_patch_txt_failed", "local", 0)
	}
}

// pifSyncPatch repairs invariant I-PATCH without any network access: security_patch.txt is
// derived from the active fingerprint. Only a clear mismatch is touched; stock mode
// (system=prop), a missing or unreadable file are left alone.
func (e *Engine) pifSyncPatch(f pifFile, pf patchFile) error {
	pol := e.pifPolicy()
	if !e.pifActive() || pol.Mode != "auto" || !pol.SyncPatch || e.dryRun {
		return nil
	}
	if e.status.PIF.State == "absent" || e.status.PIF.State == "invalid" {
		return nil
	}
	if e.status.PIF.PatchPair == "match" {
		e.syncPatchTxt(f.patch()) // the pair is right, but the boot script's own copy of the date may be stale
		return nil
	}
	if e.status.PIF.PatchPair != "mismatch" {
		return nil
	}
	orig, absent, err := readOptional(e.patchPath(), 4096)
	if err != nil || absent {
		return err
	}
	want := pf.withPatch(orig, f.patch())
	if bytes.Equal(want, orig) {
		return nil
	}
	if err = e.writeFile(e.patchPath(), want, 0644); err != nil {
		e.pifSyncFails++
		e.status.PIF.Reason = "patch_sync_failed: " + err.Error()
		logEvent("pif_patch_sync_failed", "local", e.pifSyncFails)
		return err
	}
	// Prove it by reading the file back (never trust the write call).
	back, _, err := readOptional(e.patchPath(), 4096)
	if err != nil || !bytes.Equal(back, want) {
		e.pifSyncFails++
		return errors.New("patch file readback differs")
	}
	e.pifSyncFails = 0
	e.status.PIF.PatchPair = parsePatchFile(back).pair(f.patch())
	e.status.PIF.PatchFile = parsePatchFile(back).Value
	e.syncPatchTxt(f.patch())
	e.status.PIF.Action = "patch_synced"
	logEvent("pif_patch_synced", "local", 0)
	return nil
}

// writeFile is writeMeta, or the test seam standing in for it (a "successful" write that stored something else).
func (e *Engine) writeFile(path string, data []byte, mode os.FileMode) error {
	if e.pifWriter != nil {
		return e.pifWriter(path, data, mode)
	}
	return e.writeMeta(path, data, mode)
}

// writeMeta atomically replaces path keeping owner, group, mode (default defMode for a new
// file) and the SELinux context of the file it replaces. No copy of the old content remains.
func (e *Engine) writeMeta(path string, data []byte, defMode os.FileMode) error {
	uid, gid, mode, context := os.Getuid(), os.Getgid(), defMode, ""
	if st, err := os.Lstat(path); err == nil {
		if !st.Mode().IsRegular() {
			return errors.New("target is not a regular file")
		}
		mode = st.Mode().Perm()
		if sys, ok := st.Sys().(*syscall.Stat_t); ok {
			uid, gid = int(sys.Uid), int(sys.Gid)
		}
		read := e.contextOf
		if read == nil {
			read = fileContext
		}
		c, cerr := read(path)
		switch {
		case cerr == nil:
			context = c
		case e.strictContext:
			return errors.New("SELinux context of the file being replaced is unreadable")
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".autopilot-pif-")
	if err != nil {
		return err
	}
	name := f.Name()
	ok := false
	defer func() {
		f.Close()
		if !ok {
			os.Remove(name)
		}
	}()
	if _, err = f.Write(data); err != nil {
		return err
	}
	if err = f.Chown(uid, gid); err != nil {
		return err
	}
	if err = f.Chmod(mode); err != nil {
		return err
	}
	if context != "" {
		if err = label(name, context); err != nil {
			return err
		}
	}
	if err = f.Sync(); err != nil {
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	if err = os.Rename(name, path); err != nil {
		return err
	}
	ok = true
	return syncDir(filepath.Dir(path))
}

// pifDeadline is the next time the daemon should look at the fingerprint again (zero = no need,
// the daemon's own schedule is enough). Every daemon cycle costs a clock probe (a JVM start) and a
// key audit, so the contour wakes the daemon exactly when it has something to do and never polls:
//   - a pair mismatch that this contour may repair: soon (30 min);
//   - a fingerprint that needs replacing: at the next allowed search (6 h / backoff after a search), soon for the first try;
//   - a healthy fingerprint: when its renew window opens.
func (e *Engine) pifDeadline() time.Time {
	if !e.pifActive() {
		return time.Time{}
	}
	pol := e.pifPolicy()
	if pol.Mode != "auto" {
		return time.Time{} // manual: report only, nothing to do ahead of the daemon's own schedule
	}
	s := e.status.PIF
	now := e.now()
	soon := now.Add(30 * time.Minute)
	// Without a verified clock nothing about expiry or replacement can be decided, and a wake-up
	// cannot change that quickly: do not burn a cycle (and a JVM clock probe) every 30 minutes.
	later := now.Add(2 * time.Hour)
	clockOK := e.status.TimeState == "verified"
	if s.PatchPair == "mismatch" && pol.SyncPatch {
		if e.pifSyncFails > 0 {
			return now.Add(pifBackoff(e.pifSyncFails)) // an unwritable patch file is not retried every 30 minutes
		}
		return soon
	}
	switch s.State {
	case "banned", "expired", "expiring", "absent":
		if !clockOK {
			return later
		}
		if wait := e.pifSearchDue - e.uptime(); wait > 1800 {
			return now.Add(time.Duration(wait * float64(time.Second)))
		}
		return soon
	case "ok":
		if t, err := time.Parse("2006-01-02", s.Expires); err == nil {
			if d := t.Add(-pol.RenewBefore); d.After(now) {
				return d
			}
			if !clockOK {
				return later
			}
			return soon
		}
	}
	return time.Time{}
}

// cleanStale removes temp files of an interrupted writeMeta (power loss between CreateTemp and rename).
func cleanStale(dir string, age time.Duration) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, en := range entries {
		if !en.Type().IsRegular() || !strings.HasPrefix(en.Name(), ".autopilot-pif-") {
			continue
		}
		if info, err := en.Info(); err == nil && time.Since(info.ModTime()) > age {
			_ = os.Remove(filepath.Join(dir, en.Name()))
		}
	}
}
