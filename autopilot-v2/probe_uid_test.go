package main

import "testing"

func TestOnlyRootLogLinesAreEvidence(t *testing.T) {
	in := []string{
		"11-18 06:14:24.178 root  2088  2088 E TrickyStore: Load Keybox failed",
		"11-18 06:14:24.178 0  2088  2088 E TrickyStore: Load Keybox failed",
		"11-18 06:14:24.178 10391  5676  5676 E TrickyStore: Load Keybox failed",
		"11-18 06:14:24.178 shell 17810 20826 E TrickyStore: Load Keybox failed",
		"",
	}
	if got := rootLines(in); len(got) != 2 || got[0] != in[0] || got[1] != in[1] {
		t.Fatalf("only the root lines may stay: %q", got)
	}
}
