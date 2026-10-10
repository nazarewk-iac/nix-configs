package mismatch

import (
	"testing"
	"time"

	"kdn-certs/internal/decl"
)

func ptr(s string) *string { return &s }

func TestDecideMissing(t *testing.T) {
	cert := decl.Cert{CA: "ca"}
	reason, err := Decide(cert, nil, "ca", false)
	if err != nil {
		t.Fatal(err)
	}
	if reason != ReasonMissing {
		t.Errorf("Decide(nil existing) = %q, want %q", reason, ReasonMissing)
	}
}

func TestDecideForced(t *testing.T) {
	cert := decl.Cert{CA: "ca"}
	existing := &Existing{NotBefore: time.Now(), IssuerCN: "ca"}
	reason, err := Decide(cert, existing, "ca", true)
	if err != nil {
		t.Fatal(err)
	}
	if reason != ReasonForced {
		t.Errorf("Decide(force) = %q, want %q", reason, ReasonForced)
	}
}

func TestDecideStale(t *testing.T) {
	cert := decl.Cert{CA: "ca", MinGenerationDate: ptr("2026-09-01")}
	existing := &Existing{
		NotBefore: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC),
		IssuerCN:  "ca",
	}
	reason, err := Decide(cert, existing, "ca", false)
	if err != nil {
		t.Fatal(err)
	}
	if reason != ReasonStale {
		t.Errorf("Decide(stale) = %q, want %q", reason, ReasonStale)
	}
}

func TestDecideIssuerMismatch(t *testing.T) {
	cert := decl.Cert{CA: "ca"}
	existing := &Existing{
		NotBefore: time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC),
		IssuerCN:  "other-ca",
	}
	reason, err := Decide(cert, existing, "ca", false)
	if err != nil {
		t.Fatal(err)
	}
	if reason != ReasonIssuer {
		t.Errorf("Decide(issuer mismatch) = %q, want %q", reason, ReasonIssuer)
	}
}

func TestDecideCurrent(t *testing.T) {
	cert := decl.Cert{CA: "ca", MinGenerationDate: ptr("2026")}
	existing := &Existing{
		NotBefore: time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC),
		IssuerCN:  "ca",
	}
	reason, err := Decide(cert, existing, "ca", false)
	if err != nil {
		t.Fatal(err)
	}
	if reason != ReasonNone {
		t.Errorf("Decide(current) = %q, want %q", reason, ReasonNone)
	}
}

// TestDecideSSHSkipsIssuer proves an OpenSSH certificate is never regenerated on an issuer mismatch:
// it carries no issuer common name, so the issuer test cannot apply. Sub-task 008.
func TestDecideSSHSkipsIssuer(t *testing.T) {
	cert := decl.Cert{CA: "ca", Type: "ssh-host"}
	existing := &Existing{
		NotBefore: time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC),
		IssuerCN:  "",
		IsSSH:     true,
	}
	reason, err := Decide(cert, existing, "ca", false)
	if err != nil {
		t.Fatal(err)
	}
	if reason != ReasonNone {
		t.Errorf("Decide(ssh, CA named %q) = %q, want %q", "ca", reason, ReasonNone)
	}
}

// TestDecideSSHStillStale proves the staleness test still fires for an SSH certificate: skipping the
// issuer check must not make an SSH leaf immune to rotation by `minGenerationDate`.
func TestDecideSSHStillStale(t *testing.T) {
	cert := decl.Cert{CA: "ca", Type: "ssh-host", MinGenerationDate: ptr("2026-07-01")}
	existing := &Existing{
		NotBefore: time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC),
		IsSSH:     true,
	}
	reason, err := Decide(cert, existing, "ca", false)
	if err != nil {
		t.Fatal(err)
	}
	if reason != ReasonStale {
		t.Errorf("Decide(ssh, stale) = %q, want %q", reason, ReasonStale)
	}
}
