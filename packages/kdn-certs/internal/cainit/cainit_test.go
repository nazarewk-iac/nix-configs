package cainit_test

import (
	"os"
	"path/filepath"
	"testing"

	"kdn-certs/internal/cainit"
	"kdn-certs/internal/decl"
	"kdn-certs/internal/smallstep"
)

// fakeSigner records the calls and writes placeholder files, so the loop needs no `step`.
type fakeSigner struct {
	generated []string
	created   []smallstep.CARequest
}

func (f *fakeSigner) GenerateKey(keyOut string) error {
	f.generated = append(f.generated, keyOut)
	return os.WriteFile(keyOut, []byte("KEY"), 0o600)
}

func (f *fakeSigner) CreateCA(req smallstep.CARequest) error {
	f.created = append(f.created, req)
	return os.WriteFile(req.CertPath, []byte("CERT"), 0o600)
}

// fakeDecryptor writes a placeholder plaintext key.
type fakeDecryptor struct {
	decrypted []string
}

func (f *fakeDecryptor) Decrypt(sopsFile string, dest string) error {
	f.decrypted = append(f.decrypted, sopsFile)
	return os.WriteFile(dest, []byte("PARENT"), 0o400)
}

// fakeEncryptor records the encrypted paths and writes a placeholder.
type fakeEncryptor struct {
	encrypted []string
}

func (f *fakeEncryptor) Encrypt(plainFile string, sopsFile string) error {
	f.encrypted = append(f.encrypted, sopsFile)
	return os.WriteFile(sopsFile, []byte("SOPS"), 0o600)
}

func deps(t *testing.T, root string, dryRun bool) (cainit.Deps, *fakeSigner, *fakeDecryptor, *fakeEncryptor) {
	t.Helper()
	signer := &fakeSigner{}
	dec := &fakeDecryptor{}
	enc := &fakeEncryptor{}
	return cainit.Deps{
		Root:      root,
		Signer:    signer,
		Decryptor: dec,
		Encryptor: enc,
		DryRun:    dryRun,
		Logf:      t.Logf,
	}, signer, dec, enc
}

func TestRunCreatesManagedRoot(t *testing.T) {
	root := t.TempDir()
	deps, signer, _, enc := deps(t, root, false)

	cas := decl.CAs{
		"kdn": {
			Name:       "kdn",
			Type:       "root",
			CommonName: "KDN certificates root CA",
			Directory:  "data/ca",
			CertFile:   "kdn.crt",
			KeyFile:    "kdn.key",
			KeySource:  "managed",
		},
	}

	out, err := cainit.Run(cas, deps)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if out.Created != 1 {
		t.Fatalf("created %d, want 1", out.Created)
	}
	if len(signer.generated) != 1 {
		t.Errorf("generated %d keys, want 1", len(signer.generated))
	}
	if len(signer.created) != 1 {
		t.Fatalf("created %d CAs, want 1", len(signer.created))
	}
	if signer.created[0].ParentCert != "" {
		t.Errorf("root CA names a parent cert %q, want none", signer.created[0].ParentCert)
	}
	if len(enc.encrypted) != 1 {
		t.Fatalf("encrypted %d keys, want 1", len(enc.encrypted))
	}
	if _, err := os.Stat(filepath.Join(root, "data/ca/kdn.crt")); err != nil {
		t.Errorf("public certificate missing: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "data/ca/kdn.key.sops")); err != nil {
		t.Errorf("sops key missing: %v", err)
	}
}

func TestRunLeavesExternalCAAlone(t *testing.T) {
	root := t.TempDir()
	deps, signer, _, enc := deps(t, root, false)

	cas := decl.CAs{
		"kdn": {
			Name:       "kdn",
			Type:       "root",
			CommonName: "KDN LLM CA",
			Directory:  "data/ca",
			CertFile:   "ca.pub",
			KeyFile:    "ca.key",
			KeySource:  "external",
		},
	}

	out, err := cainit.Run(cas, deps)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if out.Created != 0 {
		t.Errorf("created %d, want 0", out.Created)
	}
	if len(signer.generated) != 0 || len(enc.encrypted) != 0 {
		t.Errorf("external CA was touched: generated=%d encrypted=%d", len(signer.generated), len(enc.encrypted))
	}
}

func TestRunSkipsExistingCertificate(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "data/ca"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "data/ca/kdn.crt"), []byte("CERT"), 0o644); err != nil {
		t.Fatal(err)
	}

	deps, signer, _, _ := deps(t, root, false)
	cas := decl.CAs{
		"kdn": {
			Name:       "kdn",
			Type:       "root",
			CommonName: "KDN certificates root CA",
			Directory:  "data/ca",
			CertFile:   "kdn.crt",
			KeyFile:    "kdn.key",
			KeySource:  "managed",
		},
	}

	out, err := cainit.Run(cas, deps)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if out.Created != 0 {
		t.Errorf("created %d, want 0 (idempotent)", out.Created)
	}
	if len(signer.generated) != 0 {
		t.Errorf("regenerated an existing CA: %d keys", len(signer.generated))
	}
}

func TestRunForceRegenerates(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "data/ca"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "data/ca/kdn.crt"), []byte("CERT"), 0o644); err != nil {
		t.Fatal(err)
	}

	deps, signer, _, _ := deps(t, root, false)
	deps.Force = true
	cas := decl.CAs{
		"kdn": {
			Name:       "kdn",
			Type:       "root",
			CommonName: "KDN certificates root CA",
			Directory:  "data/ca",
			CertFile:   "kdn.crt",
			KeyFile:    "kdn.key",
			KeySource:  "managed",
		},
	}

	out, err := cainit.Run(cas, deps)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if out.Created != 1 {
		t.Errorf("created %d, want 1 (forced)", out.Created)
	}
	if len(signer.generated) != 1 {
		t.Errorf("generated %d keys, want 1", len(signer.generated))
	}
}

func TestRunDryRunWritesNoFile(t *testing.T) {
	root := t.TempDir()
	deps, signer, _, enc := deps(t, root, true)

	cas := decl.CAs{
		"kdn": {
			Name:       "kdn",
			Type:       "root",
			CommonName: "KDN certificates root CA",
			Directory:  "data/ca",
			CertFile:   "kdn.crt",
			KeyFile:    "kdn.key",
			KeySource:  "managed",
		},
	}

	out, err := cainit.Run(cas, deps)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if out.Created != 1 {
		t.Fatalf("dry run reported %d, want 1", out.Created)
	}
	if len(signer.generated) != 0 || len(enc.encrypted) != 0 {
		t.Errorf("dry run touched the CA: generated=%d encrypted=%d", len(signer.generated), len(enc.encrypted))
	}
	if _, err := os.Stat(filepath.Join(root, "data/ca/kdn.crt")); !os.IsNotExist(err) {
		t.Errorf("dry run wrote a certificate: %v", err)
	}
}

func TestRunIntermediateUsesParent(t *testing.T) {
	root := t.TempDir()
	deps, signer, dec, _ := deps(t, root, false)

	parent := "kdn"
	cas := decl.CAs{
		"kdn": {
			Name:       "kdn",
			Type:       "root",
			CommonName: "KDN certificates root CA",
			Directory:  "data/ca",
			CertFile:   "kdn.crt",
			KeyFile:    "kdn.key",
			KeySource:  "managed",
		},
		"sub": {
			Name:       "sub",
			Type:       "intermediate",
			Parent:     &parent,
			CommonName: "KDN sub CA",
			Directory:  "data/ca",
			CertFile:   "sub.crt",
			KeyFile:    "sub.key",
			KeySource:  "managed",
		},
	}

	out, err := cainit.Run(cas, deps)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if out.Created != 2 {
		t.Fatalf("created %d, want 2", out.Created)
	}
	if len(dec.decrypted) != 1 {
		t.Fatalf("decrypted %d parent keys, want 1", len(dec.decrypted))
	}
	if filepath.Base(dec.decrypted[0]) != "kdn.key.sops" {
		t.Errorf("decrypted %q, want the parent key", dec.decrypted[0])
	}
	// The intermediate is created second, after the root.
	if len(signer.created) != 2 {
		t.Fatalf("created %d CAs, want 2", len(signer.created))
	}
	last := signer.created[1]
	if last.ParentCert == "" || last.ParentKey == "" {
		t.Errorf("intermediate names no parent: %+v", last)
	}
}

func TestRunRejectsCycle(t *testing.T) {
	root := t.TempDir()
	deps, _, _, _ := deps(t, root, false)

	a, b := "b", "a"
	cas := decl.CAs{
		"a": {
			Name:       "a",
			Type:       "intermediate",
			Parent:     &a,
			CommonName: "a",
			Directory:  "data/ca",
			CertFile:   "a.crt",
			KeyFile:    "a.key",
			KeySource:  "managed",
		},
		"b": {
			Name:       "b",
			Type:       "intermediate",
			Parent:     &b,
			CommonName: "b",
			Directory:  "data/ca",
			CertFile:   "b.crt",
			KeyFile:    "b.key",
			KeySource:  "managed",
		},
	}

	if _, err := cainit.Run(cas, deps); err == nil {
		t.Fatal("Run accepted a cycle, want an error")
	}
}

func TestRunRejectsDanglingParent(t *testing.T) {
	root := t.TempDir()
	deps, _, _, _ := deps(t, root, false)

	parent := "missing"
	cas := decl.CAs{
		"sub": {
			Name:       "sub",
			Type:       "intermediate",
			Parent:     &parent,
			CommonName: "KDN sub CA",
			Directory:  "data/ca",
			CertFile:   "sub.crt",
			KeyFile:    "sub.key",
			KeySource:  "managed",
		},
	}

	if _, err := cainit.Run(cas, deps); err == nil {
		t.Fatal("Run accepted a dangling parent, want an error")
	}
}
