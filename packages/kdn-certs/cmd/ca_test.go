package cmd

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"kdn-certs/internal/decl"
)

// newCATestApp builds an App whose fake evaluator declares one managed CA and one external CA.
func newCATestApp(t *testing.T, args ...string) (*bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	out := &bytes.Buffer{}
	errOut := &bytes.Buffer{}
	app := &App{
		Out: out,
		Err: errOut,
		In:  strings.NewReader(""),
		Evaluator: fakeEvaluator{
			names: map[string]string{"den.hosts": `["host-a"]`},
			cas: map[string]decl.CAs{"denConfigurations.host-a.config": {
				"kdn": {
					Type:       "root",
					CommonName: "KDN certificates root CA",
					Directory:  "data/ca",
					CertFile:   "kdn.crt",
					KeyFile:    "kdn.key",
					KeySource:  "managed",
				},
				"legacy": {
					Type:       "root",
					CommonName: "KDN LLM CA",
					Directory:  "data/ca",
					CertFile:   "ca.pub",
					KeyFile:    "ca.key",
					KeySource:  "external",
				},
			}},
		},
	}
	root := NewRootWithApp(app)
	root.SetArgs(args)
	root.SetOut(out)
	root.SetErr(errOut)
	if err := root.Execute(); err != nil {
		t.Fatalf("execute %v: %v", args, err)
	}
	return out, errOut
}

func TestCAInitDryRunListsCAs(t *testing.T) {
	out, _ := newCATestApp(t, "ca", "init", "--flake", ".", "--dry-run")
	text := out.String()
	if !strings.Contains(text, "kdn") {
		t.Errorf("ca init output = %q, want the managed CA name", text)
	}
	if !strings.Contains(text, "external key, left alone") {
		t.Errorf("ca init output = %q, want the external CA left alone", text)
	}
	if strings.Contains(text, "created 1 of 2") {
		t.Errorf("dry run reported a creation: %q", text)
	}
}

func TestCAInitJSON(t *testing.T) {
	out, _ := newCATestApp(t, "ca", "init", "--json", "--dry-run")
	var result struct {
		Actions []struct {
			Name      string `json:"name"`
			KeySource string `json:"keySource"`
			Reason    string `json:"reason"`
		} `json:"Actions"`
		Created int `json:"Created"`
	}
	if err := json.Unmarshal(out.Bytes(), &result); err != nil {
		t.Fatalf("ca init --json output is not JSON: %v\n%s", err, out.String())
	}
	if len(result.Actions) != 2 {
		t.Fatalf("ca init --json returned %d actions, want 2", len(result.Actions))
	}
	if result.Created != 1 {
		t.Errorf("created = %d, want 1", result.Created)
	}
}
