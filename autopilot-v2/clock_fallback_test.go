package main

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"
)

func TestVerifyHTTPDate(t *testing.T) {
	now := time.Now()
	header := func(d time.Duration) string { return now.Add(d).UTC().Format(http.TimeFormat) }
	for _, c := range []struct {
		name   string
		header string
		rtt    time.Duration
		ok     bool
	}{
		{"exact", header(0), time.Second, true},
		{"four minutes ahead", header(4 * time.Minute), time.Second, true},
		{"ten minutes ahead", header(10 * time.Minute), time.Second, false},
		{"ten minutes behind", header(-10 * time.Minute), time.Second, false},
		{"malformed", "yesterday", time.Second, false},
		{"slow response", header(0), 20 * time.Second, false},
	} {
		if err := verifyHTTPDate(c.header, now, c.rtt); (err == nil) != c.ok {
			t.Fatalf("%s: %v", c.name, err)
		}
	}
}

func TestProbeTimeFallsBackToAuthenticatedHTTPDate(t *testing.T) {
	for _, c := range []struct {
		name string
		skew time.Duration
		ok   bool
	}{{"agreeing", 0, true}, {"skewed", 30 * time.Minute, false}} {
		t.Run(c.name, func(t *testing.T) {
			e := Engine{networkClock: func(context.Context) error { return errors.New("Android network clock unavailable") }}
			e.request = func(*http.Request) (*http.Response, error) {
				r := reply(200, []byte(`{"entries":{}}`))
				r.Header.Set("Date", time.Now().Add(c.skew).UTC().Format(http.TimeFormat))
				return r, nil
			}
			err := e.probeTime(context.Background())
			if (err == nil) != c.ok {
				t.Fatal(err)
			}
			if c.ok && e.status.TimeSource != "https_date" {
				t.Fatal(e.status.TimeSource)
			}
		})
	}
}

func TestProbeTimeKeepsOriginalErrorWhenFallbackUnreachable(t *testing.T) {
	cause := errors.New("Android network clock unavailable")
	e := Engine{networkClock: func(context.Context) error { return cause }}
	e.request = func(*http.Request) (*http.Response, error) { return nil, errors.New("offline") }
	if err := e.probeTime(context.Background()); !errors.Is(err, cause) {
		t.Fatal(err)
	}
}
