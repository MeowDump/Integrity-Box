package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"syscall"
)

func exists(p string) bool { _, e := os.Stat(p); return e == nil }

func writeJSON(p string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return atomic(p, b, 0600)
}

func atomic(p string, data []byte, mode os.FileMode) error {
	f, err := os.CreateTemp(filepath.Dir(p), ".autopilot-*")
	if err != nil {
		return err
	}
	n := f.Name()
	defer os.Remove(n)
	if err = f.Chmod(mode); err == nil {
		_, err = f.Write(data)
	}
	if err == nil {
		err = f.Sync()
	}
	ce := f.Close()
	if err == nil {
		err = ce
	}
	if err != nil {
		return err
	}
	if err = os.Rename(n, p); err != nil {
		return err
	}
	return syncDir(filepath.Dir(p))
}

// sha256Hex is the lowercase hex SHA-256 used for every file fingerprint and pin in the engine.
func sha256Hex(b []byte) string {
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

func lock(p string) (*os.File, error) {
	f, err := os.OpenFile(p, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
}

func readLimited(path string, limit int64) ([]byte, error) {
	if er := safeRegular(path, false); er != nil {
		return nil, er
	}
	f, er := os.Open(path)
	if er != nil {
		return nil, er
	}
	defer f.Close()
	st, er := f.Stat()
	if er != nil {
		return nil, er
	}
	if st.Size() > limit {
		return nil, errors.New("file byte limit")
	}
	b, er := io.ReadAll(io.LimitReader(f, limit+1))
	if int64(len(b)) > limit {
		return nil, errors.New("file byte limit")
	}
	return b, er
}

func readKey(path string) ([]byte, error) { return readLimited(path, maxXML) }
