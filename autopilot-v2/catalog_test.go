package main

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"
)

// The catalog already says which entries are expired or listed by Google, so those
// must never cost a download, and the longest-lived entry of a source goes first.
func TestSecondaryPrefiltersByCatalogMetadata(t *testing.T) {
	stamp := func(d time.Duration) string { return time.Now().Add(d).UTC().Format(time.RFC3339) }
	catalog := fmt.Sprintf(`{"entries":[
	 {"source":"TAKR","version":"1","revoked":false,"softbanned":false,"serial":"aa","expires_at":%q},
	 {"source":"TAKR","version":"2","revoked":false,"softbanned":false,"serial":"bb","expires_at":%q},
	 {"source":"TAKR","version":"3","revoked":false,"softbanned":false,"serial":"cc","expires_at":%q},
	 {"source":"TAKR","version":"4","revoked":false,"softbanned":false,"serial":"dd","expires_at":%q},
	 {"source":"mirvora","version":"1","revoked":false,"softbanned":false,"serial":"9957835445052538031","expires_at":null}]}`,
		stamp(-time.Hour), stamp(24*time.Hour), stamp(240*time.Hour), stamp(480*time.Hour))
	e := Engine{revoked: map[string]bool{"dd": true}} // v4 is listed by Google
	calls := []string{}
	e.request = func(r *http.Request) (*http.Response, error) {
		if r.URL.Path == "/catalog" {
			return reply(200, []byte(catalog)), nil
		}
		calls = append(calls, r.URL.Path)
		return reply(404, nil), nil
	}
	_, _, err := e.secondary(context.Background())
	want := []string{"/key/TAKR/3", "/key/mirvora/1", "/key/TAKR/2"}
	if err == nil || fmt.Sprint(calls) != fmt.Sprint(want) {
		t.Fatalf("calls=%v want %v (err %v)", calls, want, err)
	}
}
