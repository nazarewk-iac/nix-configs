package cmd

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"kdn-certs/internal/decl"
)

// fakeEvaluator answers from fixed maps. A missing key returns an empty set. So the command tests
// need no flake and no nix.
type fakeEvaluator struct {
	names map[string]string
	certs map[string]decl.Certs
	cas   map[string]decl.CAs
}

func (f fakeEvaluator) EvalJSON(attr string, apply string) ([]byte, error) {
	switch {
	case strings.Contains(apply, "attrNames"):
		if value, ok := f.names[attr]; ok {
			return []byte(value), nil
		}
		return []byte("[]"), nil
	case strings.Contains(apply, `"certificates"`):
		if value, ok := f.certs[attr]; ok {
			return json.Marshal(value)
		}
		return []byte("{}"), nil
	default:
		if value, ok := f.cas[attr]; ok {
			return json.Marshal(value)
		}
		return []byte("{}"), nil
	}
}

func newTestApp(t *testing.T, args ...string) (*bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	out := &bytes.Buffer{}
	errOut := &bytes.Buffer{}
	cert := decl.Cert{
		CA:         "ca",
		Type:       "tls-server",
		CommonName: "example.invalid",
		Directory:  "hosts/a/certs",
		CertFile:   "a.pub",
		KeyFile:    "a.key",
	}
	app := &App{
		Out: out,
		Err: errOut,
		In:  strings.NewReader(""),
		Evaluator: fakeEvaluator{
			names: map[string]string{"den.hosts": `["host-a"]`},
			certs: map[string]decl.Certs{"denConfigurations.host-a.config": {"a": cert}},
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

func TestPlanDryRunWritesNoFile(t *testing.T) {
	out, _ := newTestApp(t, "plan", "--flake", ".", "--dry-run")
	if !strings.Contains(out.String(), "a") {
		t.Errorf("plan output = %q, want the certificate name", out.String())
	}
}

func TestPlanJSON(t *testing.T) {
	out, _ := newTestApp(t, "plan", "--json")
	var entries []planEntry
	if err := json.Unmarshal(out.Bytes(), &entries); err != nil {
		t.Fatalf("plan --json output is not JSON: %v\n%s", err, out.String())
	}
	if len(entries) != 1 {
		t.Fatalf("plan --json returned %d entries, want 1", len(entries))
	}
	if entries[0].Name != "a" {
		t.Errorf("entry name = %q, want a", entries[0].Name)
	}
}

func TestFlagParsing(t *testing.T) {
	out, _ := newTestApp(t, "plan", "--flake", ".", "--force", "--json", "--verbose")
	if !strings.Contains(out.String(), "forced") {
		t.Errorf("plan --force output = %q, want the forced reason", out.String())
	}
}

func TestStatus(t *testing.T) {
	out, _ := newTestApp(t, "status")
	if !strings.Contains(out.String(), "a") {
		t.Errorf("status output = %q, want the certificate name", out.String())
	}
}

func TestHelpListsCommands(t *testing.T) {
	root := NewRoot()
	help := root.UsageString()
	for _, name := range []string{"plan", "apply", "ca", "ssh", "status", "doctor"} {
		if !strings.Contains(help, name) {
			t.Errorf("help does not name %q:\n%s", name, help)
		}
	}
}
