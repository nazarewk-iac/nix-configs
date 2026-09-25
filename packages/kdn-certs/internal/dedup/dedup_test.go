package dedup

import (
	"testing"

	"kdn-certs/internal/decl"
)

func TestMergeKeepsFirst(t *testing.T) {
	first := decl.Cert{
		CA:         "ca",
		Type:       "tls-server",
		CommonName: "example.invalid",
		Directory:  "hosts/a/certs",
		CertFile:   "a.pub",
	}
	second := first
	second.KeyFile = "different.key"

	targets := []decl.Target{
		{Name: "one", Certs: decl.Certs{"a": first}},
		{Name: "two", Certs: decl.Certs{"b": second}},
	}

	result := Merge(targets)
	if len(result.Certs) != 1 {
		t.Fatalf("Merge kept %d certificates, want 1", len(result.Certs))
	}
	if len(result.Duplicates) != 1 {
		t.Fatalf("Merge reported %d duplicates, want 1", len(result.Duplicates))
	}
	if result.Duplicates[0].Target != "two" {
		t.Errorf("duplicate target = %q, want two", result.Duplicates[0].Target)
	}
}

func TestMergeDistinctKeys(t *testing.T) {
	a := decl.Cert{CA: "ca", Type: "tls-server", CommonName: "a", Directory: "d", CertFile: "a.pub"}
	b := decl.Cert{CA: "ca", Type: "tls-server", CommonName: "b", Directory: "d", CertFile: "b.pub"}
	targets := []decl.Target{{Name: "one", Certs: decl.Certs{"a": a, "b": b}}}
	result := Merge(targets)
	if len(result.Certs) != 2 {
		t.Fatalf("Merge kept %d certificates, want 2", len(result.Certs))
	}
	if len(result.Duplicates) != 0 {
		t.Fatalf("Merge reported %d duplicates, want 0", len(result.Duplicates))
	}
}

func TestSortedDeterministic(t *testing.T) {
	a := decl.Cert{CA: "ca", Type: "tls-server", CommonName: "b", Directory: "d", CertFile: "b.pub"}
	b := decl.Cert{CA: "ca", Type: "tls-server", CommonName: "a", Directory: "d", CertFile: "a.pub"}
	result := Merge([]decl.Target{{Name: "one", Certs: decl.Certs{"b": a, "a": b}}})
	sorted := result.Sorted()
	if len(sorted) != 2 {
		t.Fatalf("Sorted returned %d certificates, want 2", len(sorted))
	}
	if sorted[0].CommonName != "a" {
		t.Errorf("Sorted[0] = %q, want a", sorted[0].CommonName)
	}
}
