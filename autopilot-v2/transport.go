package main

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

func allowedHost(host string) bool {
	return host == "rawbin.dpejoh.com" || host == "github.com" || host == "release-assets.githubusercontent.com" || host == "objects.githubusercontent.com" || host == "android.googleapis.com" || host == "api.github.com" || host == "flash.android.com" || host == "content-flashstation-pa.googleapis.com" || extraAllowedHosts[host]
}

func cacheTTL(header string) time.Duration {
	ttl := 12 * time.Hour
	for _, part := range strings.Split(header, ",") {
		part = strings.TrimSpace(part)
		if strings.HasPrefix(part, "max-age=") {
			v, err := strconv.Atoi(strings.TrimPrefix(part, "max-age="))
			if err == nil && v >= 0 && v < 43200 {
				ttl = time.Duration(v) * time.Second
			}
		}
	}
	if ttl < 30*time.Minute {
		ttl = 30 * time.Minute
	}
	return ttl
}

type cacheEntry struct {
	TTL            time.Duration
	Body           []byte
	ETag, Modified string
}

func (e *Engine) get(ctx context.Context, address string, limit int64) ([]byte, error) {
	return e.getHeaders(ctx, address, limit, nil)
}

// getHeaders is get with extra request headers (never credentials: the Flash Tool API wants a Referer).
func (e *Engine) getHeaders(ctx context.Context, address string, limit int64, extra http.Header) ([]byte, error) {
	u, err := url.Parse(address)
	if err != nil || u.Scheme != "https" || !allowedHost(u.Hostname()) || u.User != nil || u.Port() != "" && u.Port() != "443" {
		return nil, errors.New("URL policy")
	}
	if e.hostNext == nil {
		e.hostNext = map[string]time.Time{}
	}
	if time.Now().Before(e.hostNext[e.scope+u.Hostname()]) {
		return nil, errors.New("host cooldown")
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	headers := http.Header{}
	for k, v := range extra {
		headers[k] = v
	}
	cached := e.cache[address]
	if cached.ETag != "" {
		headers.Set("If-None-Match", cached.ETag)
	}
	if cached.Modified != "" {
		headers.Set("If-Modified-Since", cached.Modified)
	}
	var response *http.Response
	started := time.Now()
	if e.request != nil {
		req, er := http.NewRequestWithContext(ctx, "GET", address, nil)
		if er != nil {
			return nil, er
		}
		req.Header = headers
		response, err = e.request(req)
	} else if exists("/system/bin/curl") {
		response, err = nativeHTTP(ctx, address, limit, headers)
	} else {
		req, er := http.NewRequestWithContext(ctx, "GET", address, nil)
		if er != nil {
			return nil, er
		}
		req.Header = headers
		if e.client == nil {
			return nil, errors.New("HTTP backend unavailable")
		}
		response, err = e.client.Do(req)
	}
	if err != nil {
		logEvent("transport_failed", u.Hostname(), 0)
		return nil, err
	}
	defer response.Body.Close()
	e.lastDate, e.lastDateRTT = response.Header.Get("Date"), time.Since(started)
	if response.StatusCode == 304 && cached.Body != nil {
		return cached.Body, nil
	}
	if response.StatusCode == 429 || response.StatusCode == 503 {
		delay := 30 * time.Minute
		value := response.Header.Get("Retry-After")
		if seconds, er := strconv.Atoi(value); er == nil && seconds > 0 {
			delay = time.Duration(seconds) * time.Second
		} else if at, er := http.ParseTime(value); er == nil {
			delay = time.Until(at)
		}
		if delay < 30*time.Minute {
			delay = 30 * time.Minute
		}
		if delay > 24*time.Hour {
			delay = 24 * time.Hour
		}
		e.hostNext[e.scope+u.Hostname()] = time.Now().Add(delay)
	}
	if response.StatusCode != 200 {
		logEvent("http_rejected", u.Hostname(), response.StatusCode)
		return nil, fmt.Errorf("HTTP %d", response.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
	if int64(len(body)) > limit {
		return nil, errors.New("response too large")
	}
	if err != nil {
		return nil, err
	}
	if strings.HasSuffix(u.Path, "/catalog") || strings.HasSuffix(u.Path, "/status") {
		if e.cache == nil {
			e.cache = map[string]cacheEntry{}
		}
		e.cache[address] = cacheEntry{Body: body, ETag: response.Header.Get("ETag"), Modified: response.Header.Get("Last-Modified"), TTL: cacheTTL(response.Header.Get("Cache-Control"))}
	}
	return body, nil
}

// Native Android curl uses bionic/netd DNS; static Linux Go DNS does not.
type cappedBuffer struct {
	bytes.Buffer
	limit int
}

func (b *cappedBuffer) Write(p []byte) (int, error) {
	if b.Len()+len(p) > b.limit {
		return 0, errors.New("HTTP output limit")
	}
	return b.Buffer.Write(p)
}

// curlArgs: --http1.1 because the response is parsed with net/http.ReadResponse, which rejects an "HTTP/2 200" status line.
func curlArgs(limit int64) []string {
	return []string{"--disable", "--silent", "--show-error", "--include", "--http1.1", "--raw", "--connect-timeout", "4", "--max-time", "10", "--max-filesize", strconv.FormatInt(limit, 10), "--proto", "=https"}
}

func nativeHTTP(ctx context.Context, address string, limit int64, headers http.Header) (*http.Response, error) {
	for redirect := 0; redirect < 5; redirect++ {
		u, err := url.Parse(address)
		if err != nil || u.Scheme != "https" || u.User != nil || !allowedHost(u.Hostname()) || u.Port() != "" && u.Port() != "443" {
			return nil, errors.New("redirect policy")
		}
		args := curlArgs(limit)
		for name, values := range headers {
			for _, value := range values {
				if !strings.ContainsAny(value, "\r\n") {
					args = append(args, "--header", name+": "+value)
				}
			}
		}
		args = append(args, "--", address)
		cmd := exec.CommandContext(ctx, "/system/bin/curl", args...)
		output := &cappedBuffer{limit: int(limit) + 65536}
		cmd.Stdout = output
		if err = cmd.Run(); err != nil {
			return nil, fmt.Errorf("native HTTP failed: %w", err)
		}
		response, err := http.ReadResponse(bufio.NewReader(bytes.NewReader(output.Bytes())), nil)
		if err != nil {
			return nil, err
		}
		response.Request = &http.Request{URL: u}
		if response.StatusCode >= 300 && response.StatusCode <= 399 && response.StatusCode != 304 {
			location, err := response.Location()
			response.Body.Close()
			if err != nil {
				return nil, err
			}
			address = location.String()
			continue
		}
		return response, nil
	}
	return nil, errors.New("redirect count")
}
