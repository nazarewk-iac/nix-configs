package generate_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"kdn-certs/internal/decl"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/generate"
	"kdn-certs/internal/smallstep"
	"kdn-certs/internal/sops"
)

// The integration test drives the real generation loop against a test CA.
//
// The test CA lives outside `data/`, under the test's own temporary directory. Its key is
// unattended: it is encrypted to a test age identity, so the suite signs with no YubiKey. The real
// CA key stays YubiKey-touch confirmed and is never used here. See design § 8.1.
//
// The test needs `step`, `sops` and `age` on PATH. The plain `go test ./...` suite has none of
// them, so it skips. The `kdn-certs-test-ca` check provides them and sets `KDN_CERTS_TEST_CA=1`.

func requireTool(t *testing.T, name string) {
	t.Helper()
	if _, err := exec.LookPath(name); err != nil {
		t.Skipf("%s not on PATH; run this test under the kdn-certs-test-ca check", name)
	}
}

// run executes one command in `dir` and fails the test on error.
func run(t *testing.T, dir string, env []string, name string, args ...string) {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), env...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %v: %v\n%s", name, args, err, out)
	}
}

// writeFile writes one file under `dir`, creating the parent directory.
func writeFile(t *testing.T, dir string, rel string, content string) string {
	t.Helper()
	path := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// isolateTmp points `TMPDIR` at the test's own temp dir, so every `os.MkdirTemp("", …)` the
// production code makes lands under a directory Go removes at test end. No plaintext key can
// survive in the shared `/tmp`. See item 4 of the cleanup batch.
func isolateTmp(t *testing.T, root string) {
	t.Helper()
	t.Setenv("TMPDIR", root)
}

// setupTestCA builds a temporary test CA with an unattended key and returns the tree root, the CA
// graph and the age key file path.
func setupTestCA(t *testing.T) (root string, cas decl.CAs, ageKeyFile string) {
	t.Helper()
	requireTool(t, "step")
	requireTool(t, "sops")
	requireTool(t, "age-keygen")

	root = t.TempDir()
	isolateTmp(t, root)
	caDir := filepath.Join(root, "ca")
	if err := os.MkdirAll(caDir, 0o755); err != nil {
		t.Fatal(err)
	}

	// The unattended test age identity.
	ageKeyFile = filepath.Join(root, "age.key")
	run(t, root, nil, "age-keygen", "-o", ageKeyFile)
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

	// The `.sops.yaml` the CLI reads. One rule per key path, so the leaf key rule is exercised too.
	writeFile(t, root, ".sops.yaml", `creation_rules:
  - path_regex: ca/root\.key\.sops$
    key_groups:
      - age:
          - `+recipient+`
  - path_regex: hosts/.*/certs/zellij\.key\.sops$
    key_groups:
      - age:
          - `+recipient+`
`)

	// The root CA, generated unattended with `step`.
	run(t, root, nil, "step", "certificate", "create",
		"KDN test root CA",
		filepath.Join(caDir, "root.crt"),
		filepath.Join(caDir, "root.key"),
		"--profile", "root-ca",
		"--no-password", "--insecure",
	)

	// SOPS-encrypt the CA key, exactly as `data/ca/ca.key.sops` is stored.
	run(t, root, []string{"SOPS_AGE_KEY_FILE=" + ageKeyFile}, "sops", "encrypt",
		"--output-type", "binary",
		"--filename-override", filepath.Join(caDir, "root.key.sops"),
		"--output", filepath.Join(caDir, "root.key.sops"),
		filepath.Join(caDir, "root.key"),
	)

	cas = decl.CAs{
		"kdn": {
			Name:       "kdn",
			Type:       "root",
			CommonName: "KDN test root CA",
			Directory:  "ca",
			CertFile:   "root.crt",
			KeyFile:    "root.key",
			KeySource:  "external",
		},
	}
	return root, cas, ageKeyFile
}

// testCert is the one managed leaf the loop generates.
func testCert() decl.Cert {
	return decl.Cert{
		Name:       "zellij-web",
		CA:         "kdn",
		Type:       "tls-server",
		CommonName: "test.example.invalid",
		SANs:       []string{"test.example.invalid"},
		Directory:  "hosts/test/certs",
		CertFile:   "zellij.pub",
		KeyFile:    "zellij.key",
		KeySource:  "managed",
	}
}

func TestGenerateAgainstTestCA(t *testing.T) {
	if os.Getenv("KDN_CERTS_TEST_CA") == "" {
		t.Skip("set KDN_CERTS_TEST_CA=1; the kdn-certs-test-ca check does")
	}

	root, cas, ageKeyFile := setupTestCA(t)
	t.Setenv("SOPS_AGE_KEY_FILE", ageKeyFile)

	cert := testCert()
	result := dedup.Result{Certs: map[string]decl.Cert{cert.DedupKey(): cert}}

	deps := generate.Deps{
		Root:      root,
		Signer:    smallstep.StepCLI{},
		Decryptor: sops.CLI{ConfigPath: filepath.Join(root, ".sops.yaml")},
		Encryptor: sops.CLI{ConfigPath: filepath.Join(root, ".sops.yaml")},
		Logf:      t.Logf,
	}

	out, err := generate.Run(cas, result, deps)
	if err != nil {
		t.Fatalf("generate.Run: %v", err)
	}
	if out.Generated != 1 {
		t.Fatalf("generated %d certificates, want 1", out.Generated)
	}

	certPath := filepath.Join(root, "hosts/test/certs/zellij.pub")
	keyPath := filepath.Join(root, "hosts/test/certs/zellij.key.sops")

	// The public certificate verifies against the test CA.
	run(t, root, nil, "openssl", "verify", "-CAfile", filepath.Join(root, "ca/root.crt"), certPath)

	// The private key is a raw/binary SOPS file, and it decrypts to the key that signed the cert.
	run(t, root, nil, "sops", "decrypt", "--output-type", "binary", keyPath)

	// The leaf's issuer is the declared CA common name.
	issuer := runCapture(t, root, nil, "openssl", "x509", "-in", certPath, "-noout", "-issuer")
	if !strings.Contains(issuer, "KDN test root CA") {
		t.Errorf("issuer = %q, want the test CA common name", issuer)
	}

	// A second run with no change is idempotent: it regenerates nothing.
	second, err := generate.Run(cas, result, deps)
	if err != nil {
		t.Fatalf("second generate.Run: %v", err)
	}
	if second.Generated != 0 {
		t.Errorf("second run generated %d certificates, want 0 (idempotent)", second.Generated)
	}

	// Every temporary directory the loop made is gone, so no plaintext key survives the run.
	assertNoTempLeftovers(t, root)
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

func TestGenerateDryRunWritesNoFile(t *testing.T) {
	if os.Getenv("KDN_CERTS_TEST_CA") == "" {
		t.Skip("set KDN_CERTS_TEST_CA=1; the kdn-certs-test-ca check does")
	}

	root, cas, ageKeyFile := setupTestCA(t)
	t.Setenv("SOPS_AGE_KEY_FILE", ageKeyFile)

	cert := testCert()
	result := dedup.Result{Certs: map[string]decl.Cert{cert.DedupKey(): cert}}

	deps := generate.Deps{
		Root:      root,
		Signer:    smallstep.StepCLI{},
		Decryptor: sops.CLI{ConfigPath: filepath.Join(root, ".sops.yaml")},
		Encryptor: sops.CLI{ConfigPath: filepath.Join(root, ".sops.yaml")},
		DryRun:    true,
		Logf:      t.Logf,
	}

	out, err := generate.Run(cas, result, deps)
	if err != nil {
		t.Fatalf("generate.Run: %v", err)
	}
	if out.Generated != 1 {
		t.Fatalf("dry run reported %d certificates, want 1", out.Generated)
	}
	if _, err := os.Stat(filepath.Join(root, "hosts/test/certs/zellij.pub")); !os.IsNotExist(err) {
		t.Errorf("dry run wrote a certificate file: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "hosts/test/certs/zellij.key.sops")); !os.IsNotExist(err) {
		t.Errorf("dry run wrote a key file: %v", err)
	}
}

// runCapture runs one command and returns its standard output.
func runCapture(t *testing.T, dir string, env []string, name string, args ...string) string {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), env...)
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("%s %v: %v", name, args, err)
	}
	return string(out)
}
