package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

// dirFootprint counts regular files and bytes under dir: a leak of temp files or an ever growing state file shows here.
func dirFootprint(t *testing.T, dir string) (files int, bytes int64) {
	t.Helper()
	_ = filepath.Walk(dir, func(_ string, info os.FileInfo, err error) error {
		if err == nil && info.Mode().IsRegular() {
			files++
			bytes += info.Size()
		}
		return nil
	})
	return
}

func heapInUse() uint64 {
	runtime.GC()
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	return m.HeapAlloc
}

// A long-running daemon must not grow: many simulated search cycles (a banned fingerprint with no replacement, i.e.
// the busiest state, one pass every hour for about a month) leave the heap, the in-memory tables and the state
// directories at the same size.
func TestLongRunDoesNotGrowMemoryOrFiles(t *testing.T) {
	m := bannedNoReplacement(t)
	m.e.policy.PIF.Sources = []string{"archive", "google"}
	googleNet(t, m)
	clock := 100000.0
	m.e.bootClock = func() float64 { return clock }
	step := func(n int) {
		for i := 0; i < n; i++ {
			clock += (time.Hour + time.Minute).Seconds()
			m.maintain(true)
		}
	}
	step(60) // warm up: caches filled, denylist remembered
	heapBefore := heapInUse()
	filesBefore, bytesBefore := dirFootprint(t, filepath.Dir(m.prop))
	ramFiles, ramBytes := dirFootprint(t, m.e.ram)
	brainFiles, brainBytes := dirFootprint(t, m.e.brain)
	cacheBefore, hostBefore, bannedBefore := len(m.e.cache), len(m.e.hostNext), len(m.e.pifBanned)

	step(300) // about 12 days of hourly passes

	if grown := int64(heapInUse()) - int64(heapBefore); grown > 1<<20 {
		t.Fatalf("heap grew by %d bytes over 300 cycles", grown)
	}
	if f, b := dirFootprint(t, filepath.Dir(m.prop)); f != filesBefore || b != bytesBefore {
		t.Fatalf("module dir changed: %d files / %d bytes -> %d / %d", filesBefore, bytesBefore, f, b)
	}
	if f, b := dirFootprint(t, m.e.ram); f != ramFiles || b > ramBytes+4096 {
		t.Fatalf("RAM dir grew: %d files / %d bytes -> %d / %d", ramFiles, ramBytes, f, b)
	}
	if f, b := dirFootprint(t, m.e.brain); f != brainFiles || b > brainBytes+4096 {
		t.Fatalf("Box-Brain grew: %d files / %d bytes -> %d / %d", brainFiles, brainBytes, f, b)
	}
	if len(m.e.cache) != cacheBefore || len(m.e.hostNext) != hostBefore || len(m.e.pifBanned) != bannedBefore {
		t.Fatalf("tables grew: cache %d->%d hosts %d->%d banned %d->%d", cacheBefore, len(m.e.cache), hostBefore, len(m.e.hostNext), bannedBefore, len(m.e.pifBanned))
	}
}
