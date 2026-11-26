package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"
)

func (e *Engine) configLock(ctx context.Context) (*os.File, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	for {
		f, err := lock(filepath.Join(e.ram, "config.lock"))
		if err == nil {
			return f, nil
		}
		select {
		case <-ctx.Done():
			return nil, errors.New("configuration busy")
		case <-time.After(50 * time.Millisecond):
		}
	}
}

// configFlags are the user switches under Box-Brain that the engine owns; generation() fingerprints the same list.
var configFlags = []string{"autopilot", "disable-default-source", "omk-key", "sim-key"}

func (e *Engine) setFlag(ctx context.Context, name string, on bool) error {
	if !slices.Contains(configFlags, name) {
		return errors.New("unsupported configuration flag")
	}
	f, err := e.configLock(ctx)
	if err != nil {
		return err
	}
	defer f.Close()
	if exists(filepath.Join(e.brain, name)) == on {
		return nil
	}
	if err = os.MkdirAll(e.brain, 0700); err != nil {
		return err
	}
	fail := func(cause error) error {
		if name == "autopilot" && !on {
			logEvent("shutdown_without_config_revision", "local", 0)
			removeErr := os.Remove(filepath.Join(e.brain, name))
			if os.IsNotExist(removeErr) {
				return nil
			}
			return removeErr
		}
		return cause
	}
	path := filepath.Join(e.brain, ".autopilot-config-revision")
	n, err := configRevision(e.brain)
	if err != nil {
		return fail(err)
	}
	if n == ^uint64(0) {
		return fail(errors.New("configuration revision exhausted"))
	}
	// Revision first: a failed flag write may invalidate work, never authorize stale work.
	if err = atomic(path, []byte(fmt.Sprint(n+1)), 0600); err != nil {
		return fail(err)
	}
	if on {
		return atomic(filepath.Join(e.brain, name), nil, 0600)
	}
	return os.Remove(filepath.Join(e.brain, name))
}

func configRevision(brain string) (uint64, error) {
	b, err := readLimited(filepath.Join(brain, ".autopilot-config-revision"), 64)
	if os.IsNotExist(err) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	if len(b) == 0 {
		return 0, errors.New("empty configuration revision")
	}
	return strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
}
