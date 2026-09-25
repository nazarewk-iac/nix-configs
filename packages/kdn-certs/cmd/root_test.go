package cmd

import (
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"kdn-certs/internal/decl"
)

// fakeEvaluator answers from fixed maps. A missing key returns an empty set. So the command tests
// need no flake and no nix. An attribute in `fail` returns an error, so a test can make one
// target's subtree fail.
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

// testRoot returns the tree root the command tests resolve certificate paths against. The root is
// the test's own temp dir, so a test can plant a committed certificate and prove `plan`/`status`
// read it.
func testRoot(t *testing.T) string {
	t.Helper()
	return t.TempDir()
}

// testCA returns the CA declaration every test certificate names.
func testCA() decl.CA {
	return decl.CA{
		Name:       "ca",
		Type:       "root",
		CommonName: "test root CA",
		Directory:  "data/ca",
		CertFile:   "ca.pub",
		KeyFile:    "ca.key",
		KeySource:  "external",
	}
}

// newTestApp builds the app over a fake evaluator and runs one command. The flake root is a temp
// dir, so the certificate read is deterministic.
func newTestApp(t *testing.T, args ...string) (*bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	out, errOut, _ := runTestApp(t, testRoot(t), nil, args...)
	return out, errOut
}

// runTestApp runs one command over the fake evaluator and returns the two streams plus the execute
// error. A caller that expects a non-zero exit reads the error; a caller that expects success uses
// `newTestApp`.
func runTestApp(t *testing.T, root string, fail map[string]bool, args ...string) (*bytes.Buffer, *bytes.Buffer, error) {
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
	names := `["host-a"]`
	if len(fail) > 0 {
		names = `["host-a","broken"]`
	}
	app := &App{
		Out: out,
		Err: errOut,
		In:  strings.NewReader(""),
		Evaluator: fakeEvaluator{
			names: map[string]string{"den.hosts": names},
			certs: map[string]decl.Certs{"denConfigurations.host-a.config": {"a": cert}},
			cas:   map[string]decl.CAs{"denConfigurations.host-a.config": {"ca": testCA()}},
			fail:  fail,
		},
	}
	rootCmd := NewRootWithApp(app)
	rootCmd.SetArgs(append(args, "--flake", root))
	rootCmd.SetOut(out)
	rootCmd.SetErr(errOut)
	err := rootCmd.Execute()
	return out, errOut, err
}

func TestPlanDryRunWritesNoFile(t *testing.T) {
	out, _ := newTestApp(t, "plan", "--dry-run")
	if !strings.Contains(out.String(), "a") {
		t.Errorf("plan output = %q, want the certificate name", out.String())
	}
}

func TestPlanJSON(t *testing.T) {
	out, _ := newTestApp(t, "plan", "--json")
	var response planResponse
	if err := json.Unmarshal(out.Bytes(), &response); err != nil {
		t.Fatalf("plan --json output is not JSON: %v\n%s", err, out.String())
	}
	if len(response.Entries) != 1 {
		t.Fatalf("plan --json returned %d entries, want 1", len(response.Entries))
	}
	if response.Entries[0].Name != "a" {
		t.Errorf("entry name = %q, want a", response.Entries[0].Name)
	}
}

func TestFlagParsing(t *testing.T) {
	out, _ := newTestApp(t, "plan", "--force", "--json", "--verbose")
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

// TestPlanReadsExistingCertificate proves the fixed bug: `plan` reads the committed certificate and
// reports `missing` only when the file is absent. A planted certificate with the declared CA common
// name reports no reason.
func TestPlanReadsExistingCertificate(t *testing.T) {
	root := testRoot(t)
	writeCert(t, root, "hosts/a/certs/a.pub", "test root CA")

	out, _, err := runTestApp(t, root, nil, "plan", "--json")
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	var response planResponse
	if err := json.Unmarshal(out.Bytes(), &response); err != nil {
		t.Fatalf("plan --json output is not JSON: %v\n%s", err, out.String())
	}
	if len(response.Entries) != 1 {
		t.Fatalf("plan returned %d entries, want 1", len(response.Entries))
	}
	if response.Entries[0].Reason != "" {
		t.Errorf("plan reason = %q, want no reason for a valid certificate", response.Entries[0].Reason)
	}
}

// TestStatusReadsExistingCertificate proves `status` reports `valid` for a committed certificate
// whose issuer matches the declared CA, instead of always reporting `missing`.
func TestStatusReadsExistingCertificate(t *testing.T) {
	root := testRoot(t)
	writeCert(t, root, "hosts/a/certs/a.pub", "test root CA")

	out, _, err := runTestApp(t, root, nil, "status", "--json")
	if err != nil {
		t.Fatalf("status: %v", err)
	}
	var response statusResponse
	if err := json.Unmarshal(out.Bytes(), &response); err != nil {
		t.Fatalf("status --json output is not JSON: %v\n%s", err, out.String())
	}
	if len(response.Entries) != 1 {
		t.Fatalf("status returned %d entries, want 1", len(response.Entries))
	}
	if response.Entries[0].State != "valid" {
		t.Errorf("status state = %q, want valid", response.Entries[0].State)
	}
}

// TestPlanToleratesAFailedTarget proves item 6c for `plan`: one target whose subtree fails does not
// hide the readable target, the failure is reported, and the command exits non-zero.
func TestPlanToleratesAFailedTarget(t *testing.T) {
	root := testRoot(t)
	fail := map[string]bool{"denConfigurations.broken.config": true}
	out, _, err := runTestApp(t, root, fail, "plan", "--json")
	if err == nil {
		t.Fatal("plan with a failed target returned no error, want a non-zero exit")
	}
	var response planResponse
	if err := json.Unmarshal(out.Bytes(), &response); err != nil {
		t.Fatalf("plan --json output is not JSON: %v\n%s", err, out.String())
	}
	if len(response.Entries) != 1 {
		t.Errorf("plan acted on %d entries, want the readable one", len(response.Entries))
	}
	if len(response.Failures) != 1 {
		t.Errorf("plan reported %d failures, want 1", len(response.Failures))
	}

	// The plain output names the failed target on the error stream.
	_, plainErr, plainExecuteErr := runTestApp(t, root, fail, "plan")
	if plainExecuteErr == nil {
		t.Fatal("plain plan with a failed target returned no error")
	}
	if !strings.Contains(plainErr.String(), "failed") {
		t.Errorf("plan stderr = %q, want the failure report", plainErr.String())
	}
}

// TestStatusToleratesAFailedTarget proves item 6c for `status`.
func TestStatusToleratesAFailedTarget(t *testing.T) {
	root := testRoot(t)
	fail := map[string]bool{"denConfigurations.broken.config": true}
	out, _, err := runTestApp(t, root, fail, "status", "--json")
	if err == nil {
		t.Fatal("status with a failed target returned no error, want a non-zero exit")
	}
	var response statusResponse
	if err := json.Unmarshal(out.Bytes(), &response); err != nil {
		t.Fatalf("status --json output is not JSON: %v\n%s", err, out.String())
	}
	if len(response.Entries) != 1 || len(response.Failures) != 1 {
		t.Errorf("status = %d entries, %d failures, want 1 and 1", len(response.Entries), len(response.Failures))
	}
}

// TestApplyToleratesAFailedTarget proves item 6c for `apply`: the dry run acts on the readable
// target, reports the failure in the JSON payload, and exits non-zero.
func TestApplyToleratesAFailedTarget(t *testing.T) {
	root := testRoot(t)
	fail := map[string]bool{"denConfigurations.broken.config": true}
	out, _, err := runTestApp(t, root, fail, "apply", "--dry-run", "--json")
	if err == nil {
		t.Fatal("apply with a failed target returned no error, want a non-zero exit")
	}
	var response applyResponse
	if err := json.Unmarshal(out.Bytes(), &response); err != nil {
		t.Fatalf("apply --json output is not JSON: %v\n%s", err, out.String())
	}
	if len(response.Result.Actions) != 1 {
		t.Errorf("apply acted on %d certificates, want the readable one", len(response.Result.Actions))
	}
	if len(response.Failures) != 1 {
		t.Errorf("apply reported %d failures, want 1", len(response.Failures))
	}
}

// TestDoctorToleratesAFailedTarget proves item 6c for `doctor`: the scan still runs and the command
// exits non-zero.
func TestDoctorToleratesAFailedTarget(t *testing.T) {
	root := testRoot(t)
	fail := map[string]bool{"denConfigurations.broken.config": true}
	out, _, err := runTestApp(t, root, fail, "doctor")
	if err == nil {
		t.Fatal("doctor with a failed target returned no error, want a non-zero exit")
	}
	if !strings.Contains(out.String(), "data/ca") {
		t.Errorf("doctor output = %q, want the CA directory scan", out.String())
	}
}

// writeCert plants a self-signed certificate at `rel` under `root`, with `issuerCN` as its issuer.
func writeCert(t *testing.T, root string, rel string, issuerCN string) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: issuerCN},
		Issuer:       pkix.Name{CommonName: issuerCN},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o644); err != nil {
		t.Fatal(err)
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
