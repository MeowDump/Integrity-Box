package main

import (
	"context"
	"errors"
	"math"
	"net/http"
	"os/exec"
	"regexp"
	"strconv"
	"time"
)

var networkClockPattern = regexp.MustCompile(`^NetworkTimeSuggestion\{mUnixEpochTime=UnixEpochTime\{mElapsedRealtimeMillis=([0-9]+), mUnixEpochTimeMillis=([0-9]+)\}, mUncertaintyMillis=([0-9]+),`)

func verifyNetworkTime(output string, now time.Time, boot float64) error {
	if math.IsNaN(boot) || math.IsInf(boot, 0) || boot < 0 {
		return errors.New("BOOTTIME unavailable")
	}
	m := networkClockPattern.FindStringSubmatch(output)
	if m == nil {
		return errors.New("network time unavailable")
	}
	sample, _ := strconv.ParseInt(m[1], 10, 64)
	epoch, _ := strconv.ParseInt(m[2], 10, 64)
	uncertainty, _ := strconv.ParseInt(m[3], 10, 64)
	age := boot*1000 - float64(sample)
	if age >= -10 && age < 0 {
		age = 0
	}
	if age < 0 || age > float64((24*time.Hour)/time.Millisecond) || uncertainty > 60000 {
		return errors.New("network time stale or uncertain")
	}
	expected := float64(epoch) + age
	if math.Abs(float64(now.UnixMilli())-expected) > float64((5*time.Minute)/time.Millisecond) {
		return errors.New("system clock disagrees with network time")
	}
	return nil
}

// verifyHTTPDate accepts the Date header of a TLS-authenticated response when it agrees
// with the system clock. It is the fallback for devices without Android's network-time
// service; a badly wrong clock also breaks TLS validation, so the fallback fails closed.
func verifyHTTPDate(header string, now time.Time, rtt time.Duration) error {
	t, err := http.ParseTime(header)
	if err != nil {
		return errors.New("HTTP date unavailable")
	}
	if rtt < 0 || rtt > 15*time.Second {
		return errors.New("HTTP date sample too slow")
	}
	if d := now.Sub(t); d < -5*time.Minute-rtt || d > 5*time.Minute+rtt {
		return errors.New("system clock disagrees with HTTP date")
	}
	return nil
}
func (e *Engine) probeTime(ctx context.Context) error {
	if e.timeCheck != nil {
		return e.timeCheck(ctx)
	}
	e.status.TimeSource = "" // never leave the source of an earlier success next to a failure
	check := e.probeNetworkClock
	if e.networkClock != nil {
		check = e.networkClock
	}
	err := check(ctx)
	if err == nil {
		e.status.TimeSource = "android_network_time"
		return nil
	}
	if _, getErr := e.get(ctx, "https://android.googleapis.com/attestation/status", 4<<20); getErr != nil {
		return err
	}
	if dateErr := verifyHTTPDate(e.lastDate, time.Now(), e.lastDateRTT); dateErr != nil {
		return dateErr
	}
	e.status.TimeSource = "https_date"
	return nil
}
func (e *Engine) probeNetworkClock(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "/system/bin/cmd", "time_detector", "get_network_time")
	out := &cappedBuffer{limit: 8192}
	cmd.Stdout = out
	if err := cmd.Run(); err != nil {
		return errors.New("Android network clock unavailable")
	}
	return verifyNetworkTime(out.String(), time.Now(), bootSeconds())
}

func (e *Engine) checkTime(ctx context.Context) error {
	err := e.probeTime(ctx)
	e.timeFresh = true
	e.status.TimeState = "verified"
	if err != nil {
		e.status.TimeState = "unknown_or_disagrees"
	}
	return err
}
