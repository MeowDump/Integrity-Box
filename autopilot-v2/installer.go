package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// errUnchanged reports that the candidate is byte-identical to the installed file.
var errUnchanged = errors.New("unchanged")

type transactionEntry struct {
	Target, Stage, Backup, Context string
	Mode                           uint32
	UID, GID                       int
	Existed                        bool
	BackupSHA256                   string
	BackupBytes                    int
}
type transaction struct {
	Version int
	ID      string
	Entries []transactionEntry
}

func safeRegular(path string, missing bool) error {
	st, err := os.Lstat(path)
	if os.IsNotExist(err) && missing {
		return nil
	}
	if err != nil {
		return err
	}
	if !st.Mode().IsRegular() {
		return errors.New("target is not a regular file")
	}
	return nil
}
func fileContext(path string) (string, error) {
	// ls receives fixed absolute paths as arguments; context is never executed.
	b, err := exec.Command("ls", "-Zd", path).Output()
	if err != nil {
		return "", err
	}
	fields := strings.Fields(string(b))
	for _, s := range fields {
		if strings.HasPrefix(s, "u:object_r:") && !strings.ContainsAny(s, "\r\n") {
			return s, nil
		}
	}
	return "", errors.New("SELinux context unavailable")
}
func label(path, context string) error {
	out, err := exec.Command("chcon", context, path).CombinedOutput()
	if err != nil {
		return fmt.Errorf("chcon: %s: %w", out, err)
	}
	return nil
}
func syncDir(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}
func stageTarget(p string, b []byte, mode os.FileMode, uid, gid int, context string) (string, error) {
	f, err := os.CreateTemp(filepath.Dir(p), ".autopilot-stage-")
	if err != nil {
		return "", err
	}
	name := f.Name()
	ok := false
	defer func() {
		f.Close()
		if !ok {
			os.Remove(name)
		}
	}()
	if _, err = f.Write(b); err != nil {
		return "", err
	}
	if err = f.Chown(uid, gid); err != nil {
		return "", err
	}
	if err = f.Chmod(mode); err != nil {
		return "", err
	}
	if err = label(name, context); err != nil {
		return "", err
	}
	if err = f.Sync(); err != nil {
		return "", err
	}
	if err = f.Close(); err != nil {
		return "", err
	}
	ok = true
	return name, nil
}
func (e *Engine) recoverTransaction() error {
	dir := filepath.Join(e.root, ".autopilot-transaction")
	journal := filepath.Join(dir, "journal.json")
	// Earlier versions left a copy of the replaced key next to the target. Backups exist only
	// inside a transaction, so remove it on every pass, whatever the journal state (it holds a
	// private key).
	_ = os.Remove(filepath.Join(e.root, "keybox.autopilot-backup.xml"))
	b, err := readLimited(journal, 64<<10)
	if os.IsNotExist(err) {
		for _, base := range []string{e.root, "/data/adb/teesim", "/data/misc/keystore/omk"} {
			files, _ := filepath.Glob(filepath.Join(base, ".autopilot-stage-*"))
			for _, p := range files {
				if er := os.Remove(p); er != nil && !os.IsNotExist(er) {
					return er
				}
			}
		}
		return os.RemoveAll(dir)
	}
	if err != nil {
		return err
	}
	var tx transaction
	if err = json.Unmarshal(b, &tx); err != nil {
		return err
	}
	if tx.Version < 0 || tx.Version > 1 || tx.Version == 1 && tx.ID == "" || len(tx.Entries) == 0 || len(tx.Entries) > 3 {
		return errors.New("invalid transaction")
	}
	allowed := map[string]bool{filepath.Join(e.root, "keybox.xml"): true, filepath.Join(e.root, "keybox2.xml"): true, filepath.Join(e.root, "keybox3.xml"): true, "/data/adb/teesim/keybox.xml": true, "/data/misc/keystore/omk/keybox.xml": true}
	for _, v := range tx.Entries {
		if !allowed[v.Target] || filepath.Dir(v.Backup) != dir || filepath.Dir(v.Stage) != filepath.Dir(v.Target) || !strings.HasPrefix(filepath.Base(v.Stage), ".autopilot-stage-") {
			return errors.New("invalid recovery paths")
		}
		if v.Existed {
			data, er := readKey(v.Backup)
			if er != nil {
				return fmt.Errorf("recovery backup preflight: %w", er)
			}
			if tx.Version == 1 {
				if v.BackupBytes != len(data) || v.BackupSHA256 != sha256Hex(data) {
					return errors.New("recovery backup checksum mismatch")
				}
			}
		}
	}
	for _, v := range tx.Entries {
		if v.Existed {
			data, er := readKey(v.Backup)
			if er != nil {
				return er
			}
			name, er := stageTarget(v.Target, data, os.FileMode(v.Mode), v.UID, v.GID, v.Context)
			if er != nil {
				return er
			}
			if er = os.Rename(name, v.Target); er != nil {
				return er
			}
		} else {
			if er := os.Remove(v.Target); er != nil && !os.IsNotExist(er) {
				return er
			}
		}
		if er := syncDir(filepath.Dir(v.Target)); er != nil {
			return er
		}
		_ = os.Remove(v.Stage)
	}
	if err = os.Remove(journal); err != nil {
		return err
	}
	if err = syncDir(dir); err != nil {
		return err
	}
	return os.RemoveAll(dir)
}
func (e *Engine) install(data []byte, expected, gen string, automatic bool) error {
	if e.dryRun {
		return nil
	}
	f, err := lock(filepath.Join(e.ram, "write.lock"))
	if err != nil {
		return err
	}
	defer f.Close()
	if err = e.recoverTransaction(); err != nil {
		return fmt.Errorf("transaction recovery: %w", err)
	}
	configLock, configErr := e.configLock(context.Background())
	if configErr != nil {
		return configErr
	}
	defer configLock.Close()
	if _, revisionErr := configRevision(e.brain); revisionErr != nil {
		return errors.New("invalid configuration revision")
	}
	if generation(e.brain) != gen || automatic && !e.enabled() {
		return errors.New("configuration changed")
	}
	if err = safeRegular(e.target(), true); err != nil {
		return err
	}
	old, err := readKey(e.target())
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if sha256Hex(old) != expected {
		return errors.New("target changed during search")
	}
	if bytes.Equal(old, data) {
		return errUnchanged
	}
	if e.status.Source == "Megatron2" {
		health, inspectErr := inspect(data, time.Now())
		if inspectErr != nil {
			return inspectErr
		}
		if err = e.rememberAnchor(health.Identity); err != nil {
			return err
		}
	}
	paths := append([]string{e.target()}, e.secondaryTargets()...)
	dir := filepath.Join(e.root, ".autopilot-transaction")
	if err = os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	tx := transaction{Version: 1, ID: fmt.Sprintf("%d-%d", os.Getpid(), time.Now().UnixNano())}
	committed := false
	journalWritten := false
	defer func() {
		if !journalWritten || committed {
			for _, v := range tx.Entries {
				_ = os.Remove(v.Stage)
			}
			_ = os.RemoveAll(dir)
		}
	}()
	for i, p := range paths {
		if err = safeRegular(p, true); err != nil {
			return err
		}
		v := transactionEntry{Target: p, Backup: filepath.Join(dir, fmt.Sprintf("before-%d", i)), Mode: 0600, UID: 0, GID: 0, Existed: exists(p)}
		contextPath := filepath.Dir(p)
		if v.Existed {
			contextPath = p
			st, er := os.Stat(p)
			if er != nil {
				return er
			}
			v.Mode = uint32(st.Mode().Perm())
			ss := st.Sys().(*syscall.Stat_t)
			v.UID = int(ss.Uid)
			v.GID = int(ss.Gid)
			before, er := readKey(p)
			if er != nil {
				return er
			}
			v.BackupSHA256 = sha256Hex(before)
			v.BackupBytes = len(before)
			if er = atomic(v.Backup, before, 0600); er != nil {
				return er
			}
		} else if i == 0 {
			v.Mode = 0644
		}
		v.Context, err = fileContext(contextPath)
		if err != nil {
			return err
		}
		v.Stage, err = stageTarget(p, data, os.FileMode(v.Mode), v.UID, v.GID, v.Context)
		if err != nil {
			return err
		}
		tx.Entries = append(tx.Entries, v)
	}
	latest, readErr := readKey(e.target())
	if readErr != nil && !os.IsNotExist(readErr) {
		return readErr
	}
	if !bytes.Equal(latest, old) {
		return errors.New("target changed during staging")
	}
	if err = writeJSON(filepath.Join(dir, "journal.json"), tx); err != nil {
		return err
	}
	journalWritten = true
	// Cancellation/disable before commit preserves old state. Once commit starts it
	// finishes or rolls back all targets; cancellation cannot interrupt this phase.
	if generation(e.brain) != gen || automatic && !e.enabled() {
		re := e.recoverTransaction()
		return fmt.Errorf("configuration changed before commit; rollback: %v", re)
	}
	for _, v := range tx.Entries {
		if err = os.Rename(v.Stage, v.Target); err == nil {
			err = syncDir(filepath.Dir(v.Target))
		}
		if err != nil {
			re := e.recoverTransaction()
			return fmt.Errorf("commit failed: %v; rollback: %v", err, re)
		}
	}
	for _, v := range tx.Entries {
		got, er := readKey(v.Target)
		if er != nil || !bytes.Equal(got, data) {
			re := e.recoverTransaction()
			return fmt.Errorf("post-commit mismatch; rollback: %v", re)
		}
	}
	// The new key is live and verified. If the journal cannot be removed, it would make the next
	// recovery pass silently roll the key back, so settle that now and report a consistent failure.
	if err = os.Remove(filepath.Join(dir, "journal.json")); err != nil && !os.IsNotExist(err) {
		re := e.recoverTransaction()
		return fmt.Errorf("journal removal failed; rollback: %v", re)
	}
	if err = syncDir(dir); err != nil {
		logEvent("journal_sync_failed", "local", 0) // durability of a deletion only: the key itself is committed
	}
	committed = true
	if er := writeJSON(filepath.Join(e.ram, "installed-source.json"), installedRecord{sha256Hex(data), e.status.Source}); er != nil {
		logEvent("source_metadata_write_failed", "local", 0)
	}
	return nil
}

type installedRecord struct{ Fingerprint, Source string }

func (e *Engine) installedSource(fingerprint string) string {
	b, er := readLimited(filepath.Join(e.ram, "installed-source.json"), 8192)
	if er != nil {
		return "unknown"
	}
	var r installedRecord
	if json.Unmarshal(b, &r) != nil || r.Fingerprint != fingerprint {
		return "unknown"
	}
	switch r.Source {
	case "secondary", "Megatron", "Megatron2", "manual_import":
		return r.Source
	}
	return "unknown"
}

// secondaryTargets: the other consumers (TEE Simulator, OhMyKeyMint) the user asked to keep in step with the main key.
// A consumer that is disabled, being removed or has no directory yet (it creates it on its first start) is skipped:
// it must never make the install of the main Tricky Store key fail.
func (e *Engine) secondaryTargets() []string {
	if e.slot != "" {
		return nil
	}
	var out []string
	for _, v := range []struct{ flag, module, target string }{{"sim-key", "teesim", "/data/adb/teesim/keybox.xml"}, {"omk-key", "oh_my_keymint", "/data/misc/keystore/omk/keybox.xml"}} {
		if !exists(filepath.Join(e.brain, v.flag)) {
			continue
		}
		mod := filepath.Join(e.modules(), v.module)
		if !exists(mod) || exists(filepath.Join(mod, "disable")) || exists(filepath.Join(mod, "remove")) {
			continue
		}
		target := filepath.Join(e.dataRoot, v.target)
		if st, err := os.Stat(filepath.Dir(target)); err != nil || !st.IsDir() {
			logEvent("secondary_target_unavailable", v.module, 0)
			continue
		}
		out = append(out, target)
	}
	return out
}
