// Package smallstep drives the `step` and `step-ca` commands.
//
// smallstep runs offline. `step certificate create --ca … --ca-key …` signs a leaf with no network
// and no listening port, so the lifecycle needs no long-lived daemon. See design § 6.
package smallstep

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Signer signs a certificate and generates a key. The interface keeps the CLI testable with no
// `step` binary and no CA.
type Signer interface {
	// GenerateKey writes a new unencrypted EC P-256 private key to `keyOut`. The caller SOPS-encrypts
	// it immediately, so the plaintext key is never committed.
	GenerateKey(keyOut string) error
	// SignLeaf signs the key at `req.KeyPath` into `req.CertPath` with the CA key.
	SignLeaf(req LeafRequest) error
	// CreateCA creates a self-signed root or an intermediate.
	CreateCA(req CARequest) error
}

// SSHSigner signs an SSH user or host certificate. `ssh-keygen -s` is the OpenSSH-native signer: it
// reads the CA private key directly and needs no `ca.json` and no provisioner. So an SSH sign works
// with the same SOPS-sourced CA key the TLS signer uses.
type SSHSigner interface {
	// GenerateSSHKey writes a new unencrypted ed25519 private key to `keyOut`, with its public key
	// at `keyOut+".pub"`.
	GenerateSSHKey(keyOut string) error
	// SignSSH signs the public key at `req.PubKeyPath` and writes the certificate next to it.
	SignSSH(req SSHCertRequest) error
}

// SSHCertRequest is one SSH certificate signing request.
//
// `ssh-keygen -s` writes `<PubKeyPath without .pub>-cert.pub`. The caller reads that path.
type SSHCertRequest struct {
	// KeyID is the certificate identity, for example `alice@example`.
	KeyID string
	// Principals are the login names (user cert) or host names (host cert) the certificate is valid
	// for.
	Principals []string
	// Validity is an OpenSSH validity interval, for example `+8h` or `+30d`.
	Validity string
	// Host makes a host certificate instead of a user certificate.
	Host bool
	// PubKeyPath is the public key to sign.
	PubKeyPath string
	// CAKeyPath is the decrypted SSH CA private key.
	CAKeyPath string
}

// LeafRequest is one leaf signing request.
//
// `KeyPath` is an existing private key. The caller generates it (when `keySource = "managed"`) or
// decrypts it (when `keySource = "external"`) before the sign call. `step certificate create` then
// signs that key with `--key`, so the CLI owns the key bytes and can SOPS-encrypt them.
type LeafRequest struct {
	CommonName string
	SANs       []string
	Principals []string
	Type       string
	KeyPath    string
	CertPath   string
	CACertPath string
	CAKeyPath  string
}

// CARequest is one CA creation request.
type CARequest struct {
	CommonName string
	Type       string
	KeyPath    string
	CertPath   string
	ParentCert string
	ParentKey  string
}

// StepCLI is the real signer. It shells out to `step`.
type StepCLI struct {
	// Verbose prints each command before it runs.
	Verbose bool
	// Logf receives one line per command when Verbose is set.
	Logf func(format string, args ...any)
}

// run executes one command and returns its combined output.
func (s StepCLI) run(name string, args ...string) error {
	if s.Verbose && s.Logf != nil {
		s.Logf("%s %s", name, strings.Join(args, " "))
	}
	cmd := exec.Command(name, args...)
	cmd.Stdin = os.Stdin
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s %s: %w", name, strings.Join(args, " "), err)
	}
	return nil
}

// GenerateKey writes an unencrypted EC P-256 private key to `keyOut`, with its public key at
// `keyOut+".pub"`.
//
// `--no-password --insecure` keeps the key unencrypted, so the caller can SOPS-encrypt it at once.
// The plaintext file lives in a temporary directory and never reaches the tree.
func (s StepCLI) GenerateKey(keyOut string) error {
	return s.run(
		"step", "crypto", "keypair",
		"--kty", "EC",
		"--curve", "P-256",
		"--no-password",
		"--insecure",
		keyOut+".pub",
		keyOut,
	)
}

// SignLeaf signs the existing private key at `req.KeyPath` into `req.CertPath`.
//
// `--key` names the leaf key, so `step` signs the caller's key bytes instead of generating its own.
// The caller then owns those bytes and SOPS-encrypts them. This is the only `step certificate
// create` form that both accepts an existing key and needs no `step-kms-plugin`.
//
// A `tls-server` or `tls-client` leaf uses this call. An SSH leaf needs the `step ca` SSH
// provisioner, which sub-task 005 owns; this call refuses it loudly instead of running a wrong
// command.
func (s StepCLI) SignLeaf(req LeafRequest) error {
	if req.Type == "ssh-user" || req.Type == "ssh-host" {
		return fmt.Errorf("ssh leaf %q: the SSH sign flow is sub-task 005, not the TLS signer", req.CommonName)
	}

	args := []string{
		"certificate", "create",
		req.CommonName,
		req.CertPath,
		"--key", req.KeyPath,
		"--ca", req.CACertPath,
		"--ca-key", req.CAKeyPath,
	}
	// `--san` takes one value per flag. A comma-joined list is read as one DNS name, so repeat the
	// flag instead.
	for _, san := range req.SANs {
		args = append(args, "--san", san)
	}
	return s.run("step", args...)
}

// CreateCA creates a root or an intermediate CA from an existing key.
//
// `--key` names the caller's key, so `step` signs those bytes instead of generating its own. The
// caller then owns the key and SOPS-encrypts it. `--no-password --insecure` keeps the key
// unencrypted, so the plaintext lives only in the caller's temporary directory. See design § 3.1.
func (s StepCLI) CreateCA(req CARequest) error {
	args := []string{
		"certificate", "create",
		req.CommonName,
		req.CertPath,
		"--key", req.KeyPath,
		"--profile", "root-ca",
		"--no-password",
		"--insecure",
	}
	if req.Type == "intermediate" {
		args = []string{
			"certificate", "create",
			req.CommonName,
			req.CertPath,
			"--key", req.KeyPath,
			"--profile", "intermediate-ca",
			"--ca", req.ParentCert,
			"--ca-key", req.ParentKey,
			"--no-password",
			"--insecure",
		}
	}
	return s.run("step", args...)
}

// GenerateSSHKey writes an unencrypted ed25519 private key to `keyOut`, with its public key at
// `keyOut+".pub"`. `ssh-keygen` is the OpenSSH-native tool, so the key is an OpenSSH key and the
// user certificate can be presented by `ssh` with no conversion.
func (s StepCLI) GenerateSSHKey(keyOut string) error {
	return s.run("ssh-keygen", "-t", "ed25519", "-N", "", "-q", "-f", keyOut)
}

// SignSSH signs the public key at `req.PubKeyPath` with the SSH CA key at `req.CAKeyPath`.
//
// `ssh-keygen -s <ca> -I <key-id> -n <principals> -V <validity> <pub>` writes
// `<pub without .pub>-cert.pub`. `-h` makes a host certificate. This route needs no `ca.json` and
// no provisioner, so it signs with the same SOPS-sourced CA key the TLS signer uses.
func (s StepCLI) SignSSH(req SSHCertRequest) error {
	args := []string{
		"-s", req.CAKeyPath,
		"-I", req.KeyID,
		"-V", req.Validity,
	}
	if len(req.Principals) > 0 {
		args = append(args, "-n", strings.Join(req.Principals, ","))
	}
	if req.Host {
		args = append(args, "-h")
	}
	args = append(args, req.PubKeyPath)
	return s.run("ssh-keygen", args...)
}

// Zombie is one leftover process or stale PID file that `doctor` found.
type Zombie struct {
	// Kind is `process` or `pidfile`.
	Kind string
	// Detail names the process or the file.
	Detail string
}

// FindZombies scans the process table for a `step-ca` process and the CA directory for a stale PID
// file. It reports each hit. See design § 6.
func FindZombies(caDir string) ([]Zombie, error) {
	var found []Zombie

	// The process table. `pgrep` exits 1 when it finds nothing, which is not an error here.
	out, err := exec.Command("pgrep", "-a", "step-ca").Output()
	if err == nil {
		for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
			if line == "" {
				continue
			}
			found = append(found, Zombie{Kind: "process", Detail: line})
		}
	}

	// The stale PID file.
	pidFile := filepath.Join(caDir, "step-ca.pid")
	if _, err := os.Stat(pidFile); err == nil {
		found = append(found, Zombie{Kind: "pidfile", Detail: pidFile})
	}

	return found, nil
}

// RemoveZombies removes each hit. A process is killed, and a PID file is deleted.
func RemoveZombies(zombies []Zombie) error {
	for _, zombie := range zombies {
		switch zombie.Kind {
		case "process":
			pid := strings.Fields(zombie.Detail)
			if len(pid) == 0 {
				continue
			}
			if err := exec.Command("kill", pid[0]).Run(); err != nil {
				return fmt.Errorf("kill %s: %w", pid[0], err)
			}
		case "pidfile":
			if err := os.Remove(zombie.Detail); err != nil {
				return fmt.Errorf("remove %s: %w", zombie.Detail, err)
			}
		}
	}
	return nil
}
