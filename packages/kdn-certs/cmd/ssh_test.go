package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"kdn-certs/internal/decl"
	"kdn-certs/internal/smallstep"
)

// fakeSSHSigner records the requests it received and writes a certificate file, so the command test
// needs no `ssh-keygen` and no CA.
type fakeSSHSigner struct {
	generated []string
	signed    []smallstep.SSHCertRequest
}

func (f *fakeSSHSigner) GenerateSSHKey(keyOut string) error {
	f.generated = append(f.generated, keyOut)
	if err := os.MkdirAll(filepath.Dir(keyOut), 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(keyOut, []byte("fake private key\n"), 0o600); err != nil {
		return err
	}
	return os.WriteFile(keyOut+".pub", []byte("ssh-ed25519 AAAA fake\n"), 0o644)
}

func (f *fakeSSHSigner) SignSSH(req smallstep.SSHCertRequest) error {
	f.signed = append(f.signed, req)
	certPath := strings.TrimSuffix(req.PubKeyPath, ".pub") + "-cert.pub"
	return os.WriteFile(certPath, []byte("ssh-ed25519-cert-v01@openssh.com AAAA fake\n"), 0o644)
}

// fakeDecryptor writes a placeholder CA key, so the command test needs no `sops`.
type fakeDecryptor struct {
	decrypted []string
}

func (f *fakeDecryptor) Decrypt(sopsFile string, dest string) error {
	f.decrypted = append(f.decrypted, sopsFile)
	return os.WriteFile(dest, []byte("fake CA key\n"), 0o400)
}

// sshLoginApp builds an App with a declared SSH CA and an `ssh-host` leaf, and the two fakes.
func sshLoginApp(t *testing.T, args ...string) (*fakeSSHSigner, *fakeDecryptor, string, string) {
	t.Helper()
	out := &strings.Builder{}
	errOut := &strings.Builder{}
	home := t.TempDir()

	hostCert := decl.Cert{
		Name:       "host",
		CA:         "kdn",
		Type:       "ssh-host",
		CommonName: "alpha.example.invalid",
		Principals: []string{"alpha.example.invalid"},
		Directory:  "hosts/alpha/certs",
		CertFile:   "host.pub",
		KeyFile:    "host.key",
		KeySource:  "managed",
	}
	ca := decl.CA{
		Name:       "kdn",
		Type:       "root",
		CommonName: "KDN root CA",
		Directory:  "data/ca",
		CertFile:   "ca.pub",
		KeyFile:    "ca.key",
		KeySource:  "external",
		SSH:        true,
	}

	signer := &fakeSSHSigner{}
	decryptor := &fakeDecryptor{}
	app := &App{
		Out:       out,
		Err:       errOut,
		In:        strings.NewReader(""),
		SSHSigner: signer,
		Decryptor: decryptor,
		Evaluator: fakeEvaluator{
			names: map[string]string{"den.hosts": `["alpha"]`},
			certs: map[string]decl.Certs{"denConfigurations.alpha.config": {"host": hostCert}},
			cas:   map[string]decl.CAs{"denConfigurations.alpha.config": {"kdn": ca}},
		},
	}
	root := NewRootWithApp(app)
	root.SetArgs(append(args, "--key", filepath.Join(home, "id_ed25519")))
	root.SetOut(out)
	root.SetErr(errOut)
	if err := root.Execute(); err != nil {
		t.Fatalf("execute %v: %v", args, err)
	}
	return signer, decryptor, out.String(), errOut.String()
}

func TestSSHLoginGeneratesKeyAndSigns(t *testing.T) {
	signer, decryptor, out, _ := sshLoginApp(t, "ssh", "login", "alpha.example.invalid", "--user", "alice")
	if len(signer.generated) != 1 {
		t.Fatalf("generated %d keys, want 1", len(signer.generated))
	}
	if len(signer.signed) != 1 {
		t.Fatalf("signed %d certificates, want 1", len(signer.signed))
	}
	req := signer.signed[0]
	if len(req.Principals) != 1 || req.Principals[0] != "alice" {
		t.Errorf("principals = %v, want [alice]", req.Principals)
	}
	if req.Host {
		t.Errorf("host = true, want a user certificate")
	}
	if req.Validity != "+8h" {
		t.Errorf("validity = %q, want the default +8h", req.Validity)
	}
	if len(decryptor.decrypted) != 1 || !strings.HasSuffix(decryptor.decrypted[0], "data/ca/ca.key.sops") {
		t.Errorf("decrypted = %v, want the CA key path", decryptor.decrypted)
	}
	if !strings.Contains(out, "ssh -i ") || !strings.Contains(out, "alpha.example.invalid") {
		t.Errorf("output = %q, want an ssh command", out)
	}
}

func TestSSHLoginReusesAnExistingKey(t *testing.T) {
	out := &strings.Builder{}
	errOut := &strings.Builder{}
	home := t.TempDir()
	keyPath := filepath.Join(home, "id_ed25519")
	if err := os.WriteFile(keyPath, []byte("existing key\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	hostCert := decl.Cert{
		Name:       "host",
		CA:         "kdn",
		Type:       "ssh-host",
		CommonName: "alpha.example.invalid",
		Directory:  "hosts/alpha/certs",
		CertFile:   "host.pub",
		KeyFile:    "host.key",
		KeySource:  "managed",
	}
	ca := decl.CA{Name: "kdn", Type: "root", CommonName: "KDN root CA", Directory: "data/ca", CertFile: "ca.pub", KeyFile: "ca.key", KeySource: "external", SSH: true}

	signer := &fakeSSHSigner{}
	app := &App{
		Out:       out,
		Err:       errOut,
		In:        strings.NewReader(""),
		SSHSigner: signer,
		Decryptor: &fakeDecryptor{},
		Evaluator: fakeEvaluator{
			names: map[string]string{"den.hosts": `["alpha"]`},
			certs: map[string]decl.Certs{"denConfigurations.alpha.config": {"host": hostCert}},
			cas:   map[string]decl.CAs{"denConfigurations.alpha.config": {"kdn": ca}},
		},
	}
	root := NewRootWithApp(app)
	root.SetArgs([]string{"ssh", "login", "alpha.example.invalid", "--key", keyPath})
	root.SetOut(out)
	root.SetErr(errOut)
	if err := root.Execute(); err != nil {
		t.Fatalf("execute: %v", err)
	}
	if len(signer.generated) != 0 {
		t.Errorf("generated %d keys, want 0 (the key exists)", len(signer.generated))
	}
	if len(signer.signed) != 1 {
		t.Errorf("signed %d certificates, want 1", len(signer.signed))
	}
}

func TestSSHLoginRejectsAnUnknownHost(t *testing.T) {
	out := &strings.Builder{}
	errOut := &strings.Builder{}
	app := &App{
		Out:       out,
		Err:       errOut,
		In:        strings.NewReader(""),
		SSHSigner: &fakeSSHSigner{},
		Decryptor: &fakeDecryptor{},
		Evaluator: fakeEvaluator{names: map[string]string{"den.hosts": `[]`}},
	}
	root := NewRootWithApp(app)
	root.SetArgs([]string{"ssh", "login", "no-such-host"})
	root.SetOut(out)
	root.SetErr(errOut)
	err := root.Execute()
	if err == nil {
		t.Fatal("ssh login on an unknown host returned no error")
	}
	if !strings.Contains(err.Error(), "no ssh-host certificate") {
		t.Errorf("error = %q, want a missing-host message", err)
	}
}

func TestSSHLoginRejectsANonSSHCA(t *testing.T) {
	out := &strings.Builder{}
	errOut := &strings.Builder{}
	hostCert := decl.Cert{Name: "host", CA: "kdn", Type: "ssh-host", CommonName: "alpha.example.invalid", Directory: "hosts/alpha/certs", CertFile: "host.pub", KeyFile: "host.key", KeySource: "managed"}
	ca := decl.CA{Name: "kdn", Type: "root", CommonName: "KDN root CA", Directory: "data/ca", CertFile: "ca.pub", KeyFile: "ca.key", KeySource: "external", SSH: false}
	app := &App{
		Out:       out,
		Err:       errOut,
		In:        strings.NewReader(""),
		SSHSigner: &fakeSSHSigner{},
		Decryptor: &fakeDecryptor{},
		Evaluator: fakeEvaluator{
			names: map[string]string{"den.hosts": `["alpha"]`},
			certs: map[string]decl.Certs{"denConfigurations.alpha.config": {"host": hostCert}},
			cas:   map[string]decl.CAs{"denConfigurations.alpha.config": {"kdn": ca}},
		},
	}
	root := NewRootWithApp(app)
	root.SetArgs([]string{"ssh", "login", "alpha.example.invalid"})
	root.SetOut(out)
	root.SetErr(errOut)
	err := root.Execute()
	if err == nil {
		t.Fatal("ssh login on a non-SSH CA returned no error")
	}
	if !strings.Contains(err.Error(), "does not sign SSH certificates") {
		t.Errorf("error = %q, want a non-SSH-CA message", err)
	}
}
