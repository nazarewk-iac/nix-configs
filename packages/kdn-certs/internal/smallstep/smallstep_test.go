package smallstep_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"kdn-certs/internal/smallstep"
)

// The SSH integration test drives the OpenSSH-native signer against a test CA.
//
// The test CA lives under the test's own temporary directory, outside `data/`. Its key is
// unattended, so the suite signs with no YubiKey. The real CA key stays YubiKey-touch confirmed and
// is never used here. See design § 8.1.
//
// The test needs `ssh-keygen` and `openssl` on PATH. The plain `go test ./...` suite has neither, so
// it skips. The `kdn-certs-test-ca` check provides them and sets `KDN_CERTS_TEST_CA=1`.

func requireTool(t *testing.T, name string) {
	t.Helper()
	if _, err := exec.LookPath(name); err != nil {
		t.Skipf("%s not on PATH; run this test under the kdn-certs-test-ca check", name)
	}
}

func TestSignSSHAgainstTestCA(t *testing.T) {
	if os.Getenv("KDN_CERTS_TEST_CA") == "" {
		t.Skip("set KDN_CERTS_TEST_CA=1; the kdn-certs-test-ca check does")
	}
	requireTool(t, "ssh-keygen")
	requireTool(t, "openssl")

	root := t.TempDir()
	caKey := filepath.Join(root, "ca.key")
	caCert := filepath.Join(root, "ca.crt")

	// A test CA key and a self-signed certificate, exactly as `data/ca` stores the real pair.
	if out, err := exec.Command("openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", caKey).CombinedOutput(); err != nil {
		t.Fatalf("openssl ecparam: %v\n%s", err, out)
	}
	if out, err := exec.Command("openssl", "req", "-x509", "-new", "-key", caKey, "-subj", "/CN=KDN test SSH CA", "-days", "3650", "-out", caCert).CombinedOutput(); err != nil {
		t.Fatalf("openssl req: %v\n%s", err, out)
	}

	signer := smallstep.StepCLI{}

	// A user certificate.
	userKey := filepath.Join(root, "id_ed25519")
	if err := signer.GenerateSSHKey(userKey); err != nil {
		t.Fatalf("GenerateSSHKey: %v", err)
	}
	if err := signer.SignSSH(smallstep.SSHCertRequest{
		KeyID:      "alice@example.invalid",
		Principals: []string{"alice"},
		Validity:   "+1h",
		PubKeyPath: userKey + ".pub",
		CAKeyPath:  caKey,
	}); err != nil {
		t.Fatalf("SignSSH user: %v", err)
	}

	userCert := userKey + "-cert.pub"
	list := inspect(t, userCert)
	if !strings.Contains(list, "user certificate") {
		t.Errorf("certificate is not a user certificate:\n%s", list)
	}
	if !strings.Contains(list, "alice") {
		t.Errorf("certificate does not name the principal:\n%s", list)
	}

	// A host certificate.
	hostKey := filepath.Join(root, "ssh_host_ed25519_key")
	if err := signer.GenerateSSHKey(hostKey); err != nil {
		t.Fatalf("GenerateSSHKey host: %v", err)
	}
	if err := signer.SignSSH(smallstep.SSHCertRequest{
		KeyID:      "host.example.invalid",
		Principals: []string{"host.example.invalid"},
		Validity:   "+30d",
		Host:       true,
		PubKeyPath: hostKey + ".pub",
		CAKeyPath:  caKey,
	}); err != nil {
		t.Fatalf("SignSSH host: %v", err)
	}
	hostList := inspect(t, hostKey+"-cert.pub")
	if !strings.Contains(hostList, "host certificate") {
		t.Errorf("certificate is not a host certificate:\n%s", hostList)
	}
}

// inspect runs `ssh-keygen -L -f <cert>` and returns its output.
func inspect(t *testing.T, certPath string) string {
	t.Helper()
	out, err := exec.Command("ssh-keygen", "-L", "-f", certPath).CombinedOutput()
	if err != nil {
		t.Fatalf("ssh-keygen -L %s: %v\n%s", certPath, err, out)
	}
	return string(out)
}
