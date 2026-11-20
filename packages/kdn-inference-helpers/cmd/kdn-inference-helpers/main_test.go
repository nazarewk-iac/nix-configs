package main

import "testing"

func TestParsePositionalThenFlagsAcceptsBothOrders(t *testing.T) {
	known := map[string]bool{"--port": true, "--manager": true}
	cases := []struct {
		args      []string
		profile   string
		port      string
		expectErr bool
	}{
		{[]string{"max", "--port", "10009"}, "max", "10009", false},
		{[]string{"--port", "10009", "max"}, "max", "10009", false},
		{[]string{"qfn-colo", "--port", "10010", "--manager", "http://x"}, "qfn-colo", "10010", false},
		{[]string{"max", "--bogus", "1"}, "", "", true},
		{[]string{"max", "--port"}, "", "", true},
		{[]string{"a", "b"}, "", "", true},
	}
	for _, c := range cases {
		profile, flags, err := parsePositionalThenFlags(c.args, known)
		if c.expectErr {
			if err == nil {
				t.Fatalf("%v: expected an error", c.args)
			}
			continue
		}
		if err != nil {
			t.Fatalf("%v: %v", c.args, err)
		}
		if profile != c.profile || flags["--port"] != c.port {
			t.Fatalf("%v -> profile=%q port=%q", c.args, profile, flags["--port"])
		}
	}
}
