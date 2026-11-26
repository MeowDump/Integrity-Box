package main

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type diagnosticTail struct{ data []byte }

func (d *diagnosticTail) Write(p []byte) (int, error) {
	n := len(p)
	if len(p) > 8192 {
		p = p[len(p)-8192:]
	}
	if len(d.data)+len(p) > 8192 {
		d.data = append([]byte(nil), d.data[len(d.data)-(8192-len(p)):]...)
	}
	d.data = append(d.data, p...)
	return n, nil
}
func (d *diagnosticTail) class() string {
	s := string(d.data)
	if strings.Contains(s, "panic:") {
		return "panic"
	}
	if strings.Contains(s, "fatal error:") {
		return "runtime_fatal"
	}
	if len(s) > 0 {
		return "worker_error"
	}
	return "no_stderr"
}

var diagnosticSink func(string, string, int)

func logEvent(event, host string, code int) {
	if diagnosticSink != nil {
		diagnosticSink(event, host, code)
		return
	}
	if !exists("/system/bin/log") {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	_ = exec.CommandContext(ctx, "/system/bin/log", "-p", "i", "-t", "BoxAutoPilot", fmt.Sprintf("event=%s host=%s code=%d", event, host, code)).Run()
}
