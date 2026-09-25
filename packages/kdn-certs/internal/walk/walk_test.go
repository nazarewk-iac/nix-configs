package walk

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"kdn-certs/internal/decl"
)

// fakeEvaluator answers from fixed maps. A missing key returns an empty set, exactly as the real
// `builtins.attrByPath … { }` apply expression does. So the suite needs no flake and no nix.
//
// The apply expression selects the shape: a name list, a cert set or a CA set. An attribute in
// `fail` returns an error, so a test can make one target's subtree fail.
type fakeEvaluator struct {
	names map[string]string
	certs map[string]decl.Certs
	cas   map[string]decl.CAs
	fail  map[string]bool
}

func (f fakeEvaluator) EvalJSON(attr string, apply string) ([]byte, error) {
	if f.fail[attr] {
		return nil, fmt.Errorf("nix eval %s: fake failure", attr)
	}
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

func TestWalkToleratesMissingOptions(t *testing.T) {
	e := fakeEvaluator{
		names: map[string]string{"den.hosts": `["host-a"]`},
	}
	result, err := Walk(e)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Targets) != 1 {
		t.Fatalf("Walk returned %d targets, want 1", len(result.Targets))
	}
	if len(result.Targets[0].Certs) != 0 || len(result.Targets[0].CAs) != 0 {
		t.Errorf("Walk target = %+v, want empty sets", result.Targets[0])
	}
	if len(result.Failures) != 0 {
		t.Errorf("Walk returned %d failures, want 0", len(result.Failures))
	}
}

// TestWalkContinuesAfterOneTargetFails proves the tolerance rule of item 6c: one target whose
// subtree evaluation fails does not hide the readable targets, and the failure is reported.
func TestWalkContinuesAfterOneTargetFails(t *testing.T) {
	good := decl.Cert{
		CA:         "ca",
		Type:       "tls-server",
		CommonName: "good.example.invalid",
		Directory:  "hosts/good/certs",
		CertFile:   "good.pub",
		KeyFile:    "good.key",
	}
	e := fakeEvaluator{
		names: map[string]string{"den.hosts": `["good","broken"]`},
		certs: map[string]decl.Certs{"denConfigurations.good.config": {"good": good}},
		fail:  map[string]bool{"denConfigurations.broken.config": true},
	}
	result, err := Walk(e)
	if err != nil {
		t.Fatalf("Walk returned an error, want the readable targets: %v", err)
	}
	if len(result.Targets) != 1 || result.Targets[0].Name != "denConfigurations.good" {
		t.Fatalf("Walk targets = %+v, want the readable good target", result.Targets)
	}
	if len(result.Failures) != 1 {
		t.Fatalf("Walk failures = %+v, want one failure", result.Failures)
	}
	if result.Failures[0].Target != "denConfigurations.broken" {
		t.Errorf("failure target = %q, want the broken target", result.Failures[0].Target)
	}
	if err := result.Err(); err == nil {
		t.Error("Result.Err() = nil, want an aggregate error")
	}
}

func TestWalkReadsDeclarations(t *testing.T) {
	cert := decl.Cert{
		CA:         "ca",
		Type:       "tls-server",
		CommonName: "example.invalid",
		Directory:  "hosts/a/certs",
		CertFile:   "a.pub",
		KeyFile:    "a.key",
	}
	ca := decl.CA{Type: "root", CommonName: "root CA"}

	e := fakeEvaluator{
		names: map[string]string{"den.hosts": `["host-a"]`},
		certs: map[string]decl.Certs{"denConfigurations.host-a.config": {"a": cert}},
		cas:   map[string]decl.CAs{"denConfigurations.host-a.config": {"ca": ca}},
	}
	result, err := Walk(e)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Targets) != 1 {
		t.Fatalf("Walk returned %d targets, want 1", len(result.Targets))
	}
	if result.Targets[0].Certs["a"].CommonName != "example.invalid" {
		t.Errorf("cert common name = %q, want example.invalid", result.Targets[0].Certs["a"].CommonName)
	}
	if result.Targets[0].CAs["ca"].CommonName != "root CA" {
		t.Errorf("CA common name = %q, want root CA", result.Targets[0].CAs["ca"].CommonName)
	}
}

func TestMergeCAsConflict(t *testing.T) {
	a := decl.CA{Type: "root", CommonName: "root A"}
	b := decl.CA{Type: "root", CommonName: "root B"}
	targets := []decl.Target{
		{Name: "one", CAs: decl.CAs{"ca": a}},
		{Name: "two", CAs: decl.CAs{"ca": b}},
	}
	if _, err := MergeCAs(targets); err == nil {
		t.Error("MergeCAs(conflict) succeeded, want error")
	}
}

func TestMergeCAsAgreement(t *testing.T) {
	a := decl.CA{Type: "root", CommonName: "root A"}
	targets := []decl.Target{
		{Name: "one", CAs: decl.CAs{"ca": a}},
		{Name: "two", CAs: decl.CAs{"ca": a}},
	}
	merged, err := MergeCAs(targets)
	if err != nil {
		t.Fatal(err)
	}
	if len(merged) != 1 {
		t.Fatalf("MergeCAs returned %d CAs, want 1", len(merged))
	}
}
