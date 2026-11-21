package main

import "testing"

func TestParseSpecAppleTag(t *testing.T) {
	s := parseSpec("anji+apple")
	if s.host != "anji" {
		t.Fatalf("host = %q, want anji", s.host)
	}
	if !s.apple {
		t.Fatal("apple tag was not recognised")
	}
}

func TestTargetPortAppleTag(t *testing.T) {
	e := Edge{Port: 2222}
	if got := targetPort(e, spec{}); got != 2222 {
		t.Errorf("default target port = %d, want 2222", got)
	}
	if got := targetPort(e, spec{apple: true}); got != 22 {
		t.Errorf("apple target port = %d, want 22", got)
	}
}
