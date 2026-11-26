package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func held(path string) bool {
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return false
	}
	defer f.Close()
	err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	if err == nil {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		return false
	}
	return errors.Is(err, syscall.EWOULDBLOCK)
}

type owner struct {
	PID   int
	Start string
	Exe   string
}

func processStart(pid int) string {
	b, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat")
	if err != nil {
		return ""
	}
	s := string(b)
	i := strings.LastIndex(s, ") ")
	if i < 0 {
		return ""
	}
	parts := strings.Fields(s[i+2:])
	if len(parts) < 20 {
		return ""
	}
	return parts[19]
}
func signalSupervisor(ram string) {
	b, err := readLimited(filepath.Join(ram, "supervisor.json"), 4096)
	if err != nil {
		return
	}
	var o owner
	if json.Unmarshal(b, &o) != nil || o.PID <= 1 || o.Start == "" || processStart(o.PID) != o.Start {
		return
	}
	exe, err := os.Readlink("/proc/" + strconv.Itoa(o.PID) + "/exe")
	if err != nil || exe != o.Exe {
		return
	}
	cmd, _ := os.ReadFile("/proc/" + strconv.Itoa(o.PID) + "/cmdline")
	if !strings.Contains(string(cmd), "\x00supervise\x00") {
		return
	}
	_ = syscall.Kill(o.PID, syscall.SIGTERM)
}

// restartBackoff: one more crash lengthens the wait (1 min per crash, at most 30), but a worker that ran for
// 10 minutes or more was healthy, so its next crash starts the back-off over.
func restartBackoff(crashes int, ranFor time.Duration) (int, time.Duration) {
	if ranFor >= 10*time.Minute {
		crashes = 0
	}
	crashes++
	delay := time.Duration(crashes) * time.Minute
	if delay > 30*time.Minute {
		delay = 30 * time.Minute
	}
	return crashes, delay
}

func (e *Engine) supervise(ctx context.Context) error {
	f, err := lock(filepath.Join(e.ram, "supervisor.lock"))
	if err != nil {
		return nil
	}
	defer f.Close()
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err = writeJSON(filepath.Join(e.ram, "supervisor.json"), owner{os.Getpid(), processStart(os.Getpid()), exe}); err != nil {
		return err
	}
	defer os.Remove(filepath.Join(e.ram, "supervisor.json"))
	crashes := 0
	for e.enabled() && ctx.Err() == nil {
		child := exec.Command(exe, "daemon")
		if e.workerCommand != nil {
			child = e.workerCommand()
		}
		child.Stdin = nil
		child.Stdout = nil
		tail := &diagnosticTail{}
		child.Stderr = tail
		if err = child.Start(); err != nil {
			// fork/exec can fail under memory pressure: that is a crash like any other, not the end of the supervisor
			var delay time.Duration
			crashes, delay = restartBackoff(crashes, 0)
			logEvent("worker_start_failed", "local", crashes)
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(delay):
			}
			continue
		}
		started := e.now()
		done := make(chan error, 1)
		go func() { done <- child.Wait() }()
		timer := time.NewTicker(60 * time.Second)
		finished := false
		stopping := false
		stopAt := time.Time{}
		cancelled := ctx.Done()
		for !finished {
			select {
			case <-cancelled:
				cancelled = nil
				if !stopping {
					_ = child.Process.Signal(syscall.SIGTERM)
					stopping = true
					stopAt = time.Now()
					timer.Reset(time.Second)
				}
			case childErr := <-done:
				if childErr != nil && exists("/system/bin/log") {
					code := -1
					var exit *exec.ExitError
					if errors.As(childErr, &exit) {
						code = exit.ExitCode()
					}
					_ = exec.Command("/system/bin/log", "-p", "w", "-t", "BoxAutoPilot", fmt.Sprintf("worker exited; code=%d; stopping=%t; class=%s", code, stopping, tail.class())).Run()
				}
				finished = true
			case <-timer.C:
				if !stopping && (!e.enabled() || ctx.Err() != nil) {
					_ = child.Process.Signal(syscall.SIGTERM)
					stopping = true
					stopAt = time.Now()
					timer.Reset(time.Second)
				}
				// Preserve a hung transaction for recovery; never overlap a replacement.
				if stopping && time.Since(stopAt) > 30*time.Second {
					_ = child.Process.Kill()
				}
			}
		}
		timer.Stop()
		if !e.enabled() || ctx.Err() != nil {
			return nil
		}
		var delay time.Duration
		crashes, delay = restartBackoff(crashes, e.now().Sub(started))
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(delay):
		}
	}
	return nil
}

func (e *Engine) disable(ctx context.Context) error {
	if err := e.setFlag(ctx, "autopilot", false); err != nil {
		return err
	}
	signalSupervisor(e.ram)
	deadline := time.Now().Add(35 * time.Second)
	for held(filepath.Join(e.ram, "supervisor.lock")) || held(filepath.Join(e.ram, "daemon.lock")) {
		if time.Now().After(deadline) {
			return errors.New("stop still pending")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(250 * time.Millisecond):
		}
	}
	f, err := lock(filepath.Join(e.ram, "write.lock"))
	if err != nil {
		return err
	}
	defer f.Close()
	if err = e.recoverTransaction(); err != nil {
		return fmt.Errorf("stopped; recovery still required: %w", err)
	}
	return nil
}
