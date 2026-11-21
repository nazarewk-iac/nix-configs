package main

import "testing"

func TestParseSpecRecoveryTags(t *testing.T) {
	for _, tag := range []string{"apple", "recovery"} {
		s := parseSpec("anji+" + tag)
		if s.host != "anji" {
			t.Fatalf("%s: host = %q, want anji", tag, s.host)
		}
		if !s.recovery {
			t.Fatalf("%s tag was not recognised", tag)
		}
	}
}

func TestTargetPortRecoveryTag(t *testing.T) {
	e := Edge{Port: 2222}
	if got := targetPort(e, spec{}); got != 2222 {
		t.Errorf("default target port = %d, want 2222", got)
	}
	if got := targetPort(e, spec{recovery: true}); got != 22 {
		t.Errorf("recovery target port = %d, want 22", got)
	}
}
