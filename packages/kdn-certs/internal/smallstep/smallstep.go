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
	// GenerateKey writes a new private key to `keyOut`.
	GenerateKey(keyOut string) error
	// SignLeaf signs `csr`-equivalent options into `certOut` with the CA key.
	SignLeaf(req LeafRequest) error
	// CreateCA creates a self-signed root or an intermediate.
	CreateCA(req CARequest) error
}

// LeafRequest is one leaf signing request.
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

// GenerateKey writes an EC P-256 private key to `keyOut`.
func (s StepCLI) GenerateKey(keyOut string) error {
	return s.run("step", "crypto", "keypair", "ecdsa", "--curve", "P-256", keyOut, keyOut+".pub")
}

// SignLeaf signs one leaf certificate.
func (s StepCLI) SignLeaf(req LeafRequest) error {
	args := []string{
		"certificate", "create",
		req.CommonName,
		req.CertPath,
		req.KeyPath,
		"--ca", req.CACertPath,
		"--ca-key", req.CAKeyPath,
	}
	if len(req.SANs) > 0 {
		args = append(args, "--san", strings.Join(req.SANs, ","))
	}
	if req.Type == "ssh-user" || req.Type == "ssh-host" {
		args = append(args, "--ssh")
		if len(req.Principals) > 0 {
			args = append(args, "--principal", strings.Join(req.Principals, ","))
		}
	}
	return s.run("step", args...)
}

// CreateCA creates a root or an intermediate CA.
func (s StepCLI) CreateCA(req CARequest) error {
	args := []string{
		"certificate", "create",
		req.CommonName,
		req.CertPath,
		req.KeyPath,
		"--profile", "root-ca",
	}
	if req.Type == "intermediate" {
		args = []string{
			"certificate", "create",
			req.CommonName,
			req.CertPath,
			req.KeyPath,
			"--profile", "intermediate-ca",
			"--ca", req.ParentCert,
			"--ca-key", req.ParentKey,
		}
	}
	return s.run("step", args...)
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
