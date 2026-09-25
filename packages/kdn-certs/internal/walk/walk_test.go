package walk

import (
	"encoding/json"
	"strings"
	"testing"

	"kdn-certs/internal/decl"
)

// fakeEvaluator answers from fixed maps. A missing key returns an empty set, exactly as the real
// `builtins.attrByPath … { }` apply expression does. So the suite needs no flake and no nix.
//
// The apply expression selects the shape: a name list, a cert set or a CA set.
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

func TestWalkToleratesMissingOptions(t *testing.T) {
	e := fakeEvaluator{
		names: map[string]string{"den.hosts": `["host-a"]`},
	}
	targets, err := Walk(e)
	if err != nil {
		t.Fatal(err)
	}
	if len(targets) != 1 {
		t.Fatalf("Walk returned %d targets, want 1", len(targets))
	}
	if len(targets[0].Certs) != 0 || len(targets[0].CAs) != 0 {
		t.Errorf("Walk target = %+v, want empty sets", targets[0])
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
	targets, err := Walk(e)
	if err != nil {
		t.Fatal(err)
	}
	if len(targets) != 1 {
		t.Fatalf("Walk returned %d targets, want 1", len(targets))
	}
	if targets[0].Certs["a"].CommonName != "example.invalid" {
		t.Errorf("cert common name = %q, want example.invalid", targets[0].Certs["a"].CommonName)
	}
	if targets[0].CAs["ca"].CommonName != "root CA" {
		t.Errorf("CA common name = %q, want root CA", targets[0].CAs["ca"].CommonName)
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
