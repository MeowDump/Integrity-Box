package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSecondaryTargetsNeverBlockTheMainKey(t *testing.T) {
	root, modules, brain := t.TempDir(), t.TempDir(), t.TempDir()
	e := &Engine{root: root, brain: brain, modulesRoot: modules, dataRoot: root}
	mk := func(p string) {
		if err := os.MkdirAll(p, 0700); err != nil {
			t.Fatal(err)
		}
	}
	flag := func(n string) {
		if err := os.WriteFile(filepath.Join(brain, n), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	if got := e.secondaryTargets(); len(got) != 0 {
		t.Fatalf("no flag, no target: %v", got)
	}
	flag("sim-key")
	flag("omk-key")
	mk(filepath.Join(modules, "teesim"))
	mk(filepath.Join(modules, "oh_my_keymint"))
	if got := e.secondaryTargets(); len(got) != 0 {
		t.Fatalf("modules without their data directory must be skipped, not fail the install: %v", got)
	}
	mk(filepath.Join(root, "data/adb/teesim"))
	mk(filepath.Join(root, "data/misc/keystore/omk"))
	if got := e.secondaryTargets(); len(got) != 2 {
		t.Fatalf("both ready: %v", got)
	}
	os.WriteFile(filepath.Join(modules, "teesim", "remove"), nil, 0600)
	os.WriteFile(filepath.Join(modules, "oh_my_keymint", "disable"), nil, 0600)
	if got := e.secondaryTargets(); len(got) != 0 {
		t.Fatalf("a module being removed or disabled is skipped: %v", got)
	}
	e.slot = "2"
	os.Remove(filepath.Join(modules, "teesim", "remove"))
	if got := e.secondaryTargets(); len(got) != 0 {
		t.Fatalf("a slot install never touches the other consumers: %v", got)
	}
}
