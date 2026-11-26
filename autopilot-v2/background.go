package main

import (
	"os"
	"path/filepath"
	"strconv"
	"syscall"
)

// Linux scheduling/cpuset controls are per thread. Apply to this process's
// existing threads; future threads inherit their creator's restrictions.
func applyBackground() {
	for pass := 0; pass < 2; pass++ {
		threads, err := os.ReadDir("/proc/self/task")
		if err != nil {
			return
		}
		for _, thread := range threads {
			tid, err := strconv.Atoi(thread.Name())
			if err != nil || tid <= 0 {
				continue
			}
			_ = syscall.Setpriority(syscall.PRIO_PROCESS, tid, 15)
			for _, path := range []string{"/dev/cpuset/background/tasks", "/dev/cpuset/system-background/tasks"} {
				f, err := os.OpenFile(filepath.Clean(path), os.O_WRONLY, 0)
				if err != nil {
					continue
				}
				_, err = f.WriteString(strconv.Itoa(tid))
				f.Close()
				if err == nil {
					break
				}
			}
		}
	}
}
