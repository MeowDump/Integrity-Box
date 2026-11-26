// AutoPilot: bounded retrieval, strict parsing and single-writer installation.
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"syscall"
	"time"
)

func main() {
	syscall.Umask(0077)
	debug.SetMemoryLimit(32 << 20)
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "commands: inspect PATH | status | daemon | run-once")
		os.Exit(2)
	}
	if os.Args[1] == "inspect" && len(os.Args) == 3 {
		b, err := readKey(os.Args[2])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		h, err := inspect(b, time.Now())
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		_ = json.NewEncoder(os.Stdout).Encode(h)
		return
	}
	e := Engine{root: "/data/adb/tricky_store", ram: "/dev/.box_brain_v2", brain: "/data/adb/Box-Brain", requireConsumer: true, strictContext: true}
	if exe, er := os.Executable(); er == nil {
		e.moduleRoot = filepath.Clean(filepath.Join(filepath.Dir(exe), "../../.."))
	}
	if os.Args[1] == "status" {
		b, err := readLimited(filepath.Join(e.ram, "status.json"), 64<<10)
		if err != nil {
			_ = json.NewEncoder(os.Stdout).Encode(Status{Enabled: e.enabled(), Local: e.health(), Integrity: "not_measured", Phase: "not_started", TimeState: "unknown", Revocation: "unknown", Consumer: ConsumerStatus{State: ConsumerUnknown, Evidence: "not_started"}})
			return
		}
		var st Status
		if json.Unmarshal(b, &st) == nil {
			if st.TimeState == "" {
				st.TimeState = "unknown"
			}
			if st.Consumer.State == "" {
				st.Consumer.State, st.Consumer.Evidence = ConsumerUnknown, "not_probed"
			}
			st.Enabled = e.enabled()
			st.Running = held(filepath.Join(e.ram, "daemon.lock"))
			st.Ready = st.Ready && st.Running
			st.Local = e.health()
			st.InstalledSource = e.installedSource(st.Local.Fingerprint)
			if st.Revocation == "fresh" && (time.Now().After(st.CRLUntil) || time.Now().Before(st.CRLChecked)) {
				st.Revocation = "stale"
			}
			_ = json.NewEncoder(os.Stdout).Encode(st)
		}
		return
	}
	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "root required")
		os.Exit(1)
	}
	if st, er := os.Lstat(e.ram); er == nil && (!st.IsDir() || st.Mode()&os.ModeSymlink != 0) {
		fmt.Fprintln(os.Stderr, "unsafe runtime directory")
		os.Exit(1)
	}
	if err := os.MkdirAll(e.ram, 0700); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	// Android uses native curl and its trust store; avoid loading a second CA pool.
	if !exists("/system/bin/curl") {
		roots, _ := x509.SystemCertPool()
		if roots == nil {
			roots = x509.NewCertPool()
		}
		files, _ := filepath.Glob("/system/etc/security/cacerts/*")
		for _, p := range files {
			b, er := os.ReadFile(p)
			if er == nil {
				roots.AppendCertsFromPEM(b)
			}
		}
		e.client = &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}, DialContext: (&net.Dialer{Timeout: 4 * time.Second}).DialContext, TLSHandshakeTimeout: 4 * time.Second, Proxy: http.ProxyFromEnvironment, DisableCompression: true, MaxIdleConns: 2, IdleConnTimeout: 30 * time.Second}, CheckRedirect: func(r *http.Request, via []*http.Request) error {
			if len(via) >= 5 || r.URL.Scheme != "https" || !allowedHost(r.URL.Hostname()) {
				return errors.New("redirect policy")
			}
			return nil
		}}

	}
	e.status = Status{Integrity: "not_measured", Revocation: "unknown", Phase: "starting", TimeState: "unknown"}
	signals := []os.Signal{syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP}
	if os.Args[1] == "supervise" || os.Args[1] == "daemon" {
		signals = signals[:2] // handling SIGHUP would undo the SIG_IGN that nohup gives the long-running processes
	}
	ctx, cancel := signal.NotifyContext(context.Background(), signals...)
	defer cancel()
	var err error
	switch os.Args[1] {
	case "clock-status":
		err = e.checkTime(ctx)
		_ = json.NewEncoder(os.Stdout).Encode(map[string]string{"time_state": e.status.TimeState})
	case "configure":
		if len(os.Args) != 4 || (os.Args[3] != "on" && os.Args[3] != "off") {
			err = errors.New("configure FLAG on|off required")
			break
		}
		err = e.setFlag(ctx, os.Args[2], os.Args[3] == "on")
	case "disable":
		err = e.disable(ctx)
	case "supervise":
		err = e.supervise(ctx)
	case "daemon":
		err = e.daemon(ctx)
	case "import":
		if len(os.Args) < 3 || len(os.Args) > 4 {
			err = errors.New("import requires a path and optional slot")
			break
		}
		if len(os.Args) == 4 {
			switch os.Args[3] {
			case "1":
			case "2":
				e.slot = "keybox2.xml"
			case "3":
				e.slot = "keybox3.xml"
			default:
				err = errors.New("invalid slot")
			}
		}
		if err == nil {
			err = e.importKey(ctx, os.Args[2])
		}
	case "probe":
		e.dryRun = true
		e.ram = filepath.Join(e.ram, "probe")
		if er := os.MkdirAll(e.ram, 0700); er != nil {
			fmt.Fprintln(os.Stderr, er)
			os.Exit(1)
		}
		err = e.cycle(ctx, false)
		e.publish()
		_ = json.NewEncoder(os.Stdout).Encode(e.status)
	case "fetch":
		if len(os.Args) != 3 || (os.Args[2] != "secondary" && os.Args[2] != "Megatron" && os.Args[2] != "Megatron2") {
			err = errors.New("invalid tier")
			break
		}
		e.forcedTier = os.Args[2]
		err = e.cycle(ctx, false)
		e.publish()
	case "pif-refresh":
		// One fingerprint-contour pass (the Action button and the daemon share this code). It never
		// touches the daemon's status file. Exit 3 means "pif_mode=off": the caller may use its legacy
		// path; exit 4 means "busy": the caller must NOT fall back (the legacy path would pick a random Pixel).
		e.noPublish = true
		e.reloadPolicy()
		if e.pifPolicy().Mode == "off" || e.pifPropPath() == "" {
			fmt.Println("pif: disabled (pif_mode=off)")
			os.Exit(3)
		}
		var searchLock *os.File
		var lerr error
		for i := 0; i < 60; i++ { // a daemon cycle takes seconds: wait for it instead of failing
			if searchLock, lerr = lock(filepath.Join(e.ram, "search.lock")); lerr == nil {
				break
			}
			select {
			case <-ctx.Done():
				lerr = ctx.Err()
			case <-time.After(time.Second):
			}
			if ctx.Err() != nil { // SIGTERM/SIGINT: stop waiting instead of spinning through the remaining attempts
				fmt.Println("pif: interrupted")
				os.Exit(4)
			}
		}
		if lerr != nil {
			fmt.Println("pif: busy (another AutoPilot cycle is still running)")
			os.Exit(4)
		}
		_ = e.checkTime(ctx) // the audit and the patch repair need no clock; replacements do
		e.pifMaintain(ctx, false)
		searchLock.Close()
		s := e.status.PIF
		fmt.Printf("pif: state=%s id=%s patch=%s pair=%s applied=%s action=%s reason=%s\n", s.State, s.ID, s.Patch, s.PatchPair, s.Applied, s.Action, s.Reason)
	case "run-once":
		err = e.cycle(ctx, false)
		e.publish()
	default:
		err = errors.New("unknown command")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
