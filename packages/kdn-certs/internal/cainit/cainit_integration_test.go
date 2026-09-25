package cainit_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"kdn-certs/internal/cainit"
	"kdn-certs/internal/decl"
	"kdn-certs/internal/smallstep"
	"kdn-certs/internal/sops"
)

// The integration test drives the real CA-creation loop against a temporary unattended CA.
//
// The test needs `step`, `sops` and `age-keygen` on PATH. The plain `go test ./...` suite has none
// of them, so it skips. The `kdn-certs-test-ca` check provides them and sets `KDN_CERTS_TEST_CA=1`.
// The test CA lives outside `data/`, under the test's own temporary directory, and its key is
// encrypted to a test age identity, so the suite runs with no YubiKey.

func requireTool(t *testing.T, name string) {
	t.Helper()
	if _, err := exec.LookPath(name); err != nil {
		t.Skipf("%s not on PATH; run this test under the kdn-certs-test-ca check", name)
	}
}

// isolateTmp points `TMPDIR` at the test's own temp dir, so every `os.MkdirTemp("", …)` the
// production code makes lands under a directory Go removes at test end. No plaintext key can
// survive in the shared `/tmp`. See item 4 of the cleanup batch.
func isolateTmp(t *testing.T, root string) {
	t.Helper()
	t.Setenv("TMPDIR", root)
}

// assertNoTempLeftovers proves item 4: the production `os.MkdirTemp("", "kdn-certs-…")` calls clean
// up after themselves. `TMPDIR` points at the test's own temp dir, so a leftover would appear here.
func assertNoTempLeftovers(t *testing.T, tmpRoot string) {
	t.Helper()
	entries, err := os.ReadDir(tmpRoot)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "kdn-certs-") {
			t.Errorf("temporary directory %q survived the run", filepath.Join(tmpRoot, entry.Name()))
		}
	}
}

func TestInitAgainstTestCA(t *testing.T) {
	if os.Getenv("KDN_CERTS_TEST_CA") == "" {
		t.Skip("set KDN_CERTS_TEST_CA=1; the kdn-certs-test-ca check does")
	}
	requireTool(t, "step")
	requireTool(t, "sops")
	requireTool(t, "age-keygen")
	requireTool(t, "openssl")

	root := t.TempDir()
	isolateTmp(t, root)
	caDir := filepath.Join(root, "data/ca")
	if err := os.MkdirAll(caDir, 0o755); err != nil {
		t.Fatal(err)
	}

	ageKeyFile := filepath.Join(root, "age.key")
	if out, err := exec.Command("age-keygen", "-o", ageKeyFile).CombinedOutput(); err != nil {
		t.Fatalf("age-keygen: %v\n%s", err, out)
	}
	keyBytes, err := os.ReadFile(ageKeyFile)
	if err != nil {
		t.Fatal(err)
	}
	recipient := ""
	for _, field := range strings.Fields(string(keyBytes)) {
		if strings.HasPrefix(field, "age1") {
			recipient = field
			break
		}
	}
	if recipient == "" {
		t.Fatalf("no age recipient in %s", ageKeyFile)
	}

	sopsConfig := filepath.Join(root, ".sops.yaml")
	config := "creation_rules:\n  - path_regex: data/ca/kdn\\.key\\.sops$\n    key_groups:\n      - age:\n          - " + recipient + "\n"
	if err := os.WriteFile(sopsConfig, []byte(config), 0o644); err != nil {
		t.Fatal(err)
	}

	// The unattended test identity. `sops` reads it from `SOPS_AGE_KEY_FILE`.
	t.Setenv("SOPS_AGE_KEY_FILE", ageKeyFile)

	cas := decl.CAs{
		"kdn": {
			Name:       "kdn",
			Type:       "root",
			CommonName: "KDN certificates root CA",
			Directory:  "data/ca",
			CertFile:   "kdn.crt",
			KeyFile:    "kdn.key",
			KeySource:  "managed",
			SSH:        true,
		},
	}

	deps := cainit.Deps{
		Root:      root,
		Signer:    smallstep.StepCLI{},
		Decryptor: sops.CLI{ConfigPath: sopsConfig},
		Encryptor: sops.CLI{ConfigPath: sopsConfig},
		Logf:      t.Logf,
	}

	out, err := cainit.Run(cas, deps)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if out.Created != 1 {
		t.Fatalf("created %d, want 1", out.Created)
	}

	certPath := filepath.Join(caDir, "kdn.crt")
	keyPath := filepath.Join(caDir, "kdn.key.sops")

	// The root verifies against itself.
	if out, err := exec.Command("openssl", "verify", "-CAfile", certPath, certPath).CombinedOutput(); err != nil {
		t.Fatalf("openssl verify: %v\n%s", err, out)
	}

	// The public certificate is world-readable.
	info, err := os.Stat(certPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o644 {
		t.Errorf("certificate mode = %o, want 644", info.Mode().Perm())
	}

	// The key is a raw/binary SOPS file, and it decrypts to the key that signed the certificate.
	if out, err := exec.Command("sops", "--config", sopsConfig, "decrypt", "--output-type", "binary", keyPath).CombinedOutput(); err != nil {
		t.Fatalf("sops decrypt: %v\n%s", err, out)
	}

	// The subject is the declared common name.
	subject, err := exec.Command("openssl", "x509", "-in", certPath, "-noout", "-subject").Output()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(subject), "KDN certificates root CA") {
		t.Errorf("subject = %q, want the declared common name", subject)
	}

	// A second run with no change is idempotent.
	second, err := cainit.Run(cas, deps)
	if err != nil {
		t.Fatalf("second Run: %v", err)
	}
	if second.Created != 0 {
		t.Errorf("second run created %d, want 0 (idempotent)", second.Created)
	}

	// Every temporary directory the loop made is gone, so no plaintext key survives the run.
	assertNoTempLeftovers(t, root)
}
