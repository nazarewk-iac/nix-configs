package sshkeys

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/exec"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host"
)

// CertOptions tunes the certificate sync.
type CertOptions struct {
	// CertDir is the repo-relative directory holding the committed certificates
	// (default `hosts/<name>/certs`).
	CertDir string
	// TargetDir is the remote directory that holds the certificates (default `/etc/ssh`). Each
	// file is resolved through a symlink, so a preserved file is written at its target.
	TargetDir string
	// Reload reloads sshd after a write. The reload re-reads host keys and certificates, so a
	// renewed certificate takes effect without a restart and without a rebuild.
	Reload bool
}

// EnsureCerts deploys the public host certificates of one host next to its deployed keys.
//
// A certificate is public, so nothing is decrypted and the secret store is not involved. The
// deployed path is the one `sshd_config` names (`kdn.certificates.*.deployedCertPath`), which is
// what lets a renewal skip a rebuild: sign in the repo, copy, reload.
func EnsureCerts(repoRoot string, h *host.Host, upload bool, opts CertOptions) error {
	sshOptions := exec.SSHNoHostKeyChecking
	if opts.CertDir == "" {
		opts.CertDir = filepath.Join("hosts", h.Name, "certs")
	}
	if opts.TargetDir == "" {
		opts.TargetDir = "/etc/ssh"
	}

	matches, err := filepath.Glob(filepath.Join(repoRoot, opts.CertDir, "*-cert.pub"))
	if err != nil {
		return fmt.Errorf("EnsureCerts(%s): listing %s: %w", h.Name, opts.CertDir, err)
	}
	if len(matches) == 0 {
		return fmt.Errorf("EnsureCerts(%s): no *-cert.pub under %s", h.Name, opts.CertDir)
	}

	changed := false
	for _, certPath := range matches {
		name := filepath.Base(certPath)
		want, err := os.ReadFile(certPath)
		if err != nil {
			return fmt.Errorf("EnsureCerts(%s): reading %s: %w", h.Name, certPath, err)
		}
		remote := resolveRemotePath(h, sshOptions, filepath.Join(opts.TargetDir, name))

		// A certificate that does not certify the deployed key would be paired with the wrong
		// identity: sshd logs it and ignores it, so the host silently loses its certificate.
		if err := checkCertMatchesKey(h, sshOptions, opts.TargetDir, name, want); err != nil {
			return err
		}

		have, exists, err := exec.GetRemoteFileIfExists(h.Address, sshOptions, remote)
		if err != nil {
			return fmt.Errorf("EnsureCerts(%s): reading %s: %w", h.Name, remote, err)
		}
		if exists && bytes.Equal(bytes.TrimSpace(have), bytes.TrimSpace(want)) {
			fmt.Printf("%s: %s in sync\n", h.Name, remote)
			continue
		}
		if !exists {
			fmt.Printf("%s: %s MISSING\n", h.Name, remote)
		} else {
			fmt.Printf("%s: %s DIFFERS\n", h.Name, remote)
		}
		if !upload {
			continue
		}
		if err := uploadKey(h, sshOptions, remote, want); err != nil {
			return err
		}
		fmt.Printf("%s: %s uploaded\n", h.Name, remote)
		changed = true
	}

	if changed && opts.Reload {
		return reloadSSHD(h, sshOptions)
	}
	return nil
}

// checkCertMatchesKey compares the public key inside the certificate with the deployed private
// key. Both are reduced to the same fingerprint, so a certificate for another identity is refused
// before it reaches the host.
func checkCertMatchesKey(h *host.Host, sshOptions []string, targetDir, certName string, certData []byte) error {
	// `ssh_host_ed25519-cert.pub` certifies `ssh_host_ed25519_key`.
	keyName := strings.TrimSuffix(certName, "-cert.pub") + "_key"
	remoteKey := filepath.Join(targetDir, keyName)

	keyLine, err := exec.RemoteCommand(h.Address, sshOptions, "sudo", "ssh-keygen", "-y", "-f", remoteKey).Output()
	if err != nil {
		return fmt.Errorf("EnsureCerts(%s): reading the deployed key %s: %w", h.Name, remoteKey, err)
	}
	keyFP, err := publicKeyFingerprint(keyLine)
	if err != nil {
		return fmt.Errorf("EnsureCerts(%s): fingerprinting %s: %w", h.Name, remoteKey, err)
	}
	certFP, err := certificateKeyFingerprint(certData)
	if err != nil {
		return fmt.Errorf("EnsureCerts(%s): fingerprinting %s: %w", h.Name, certName, err)
	}
	if keyFP != certFP {
		return fmt.Errorf("EnsureCerts(%s): %s certifies %s, but the deployed key %s is %s; refusing to deploy",
			h.Name, certName, certFP, remoteKey, keyFP)
	}
	return nil
}

// publicKeyFingerprint returns the SHA256 fingerprint of an OpenSSH public key line.
func publicKeyFingerprint(line []byte) (string, error) {
	dir, err := os.MkdirTemp("", "kdnctl-pubkey-")
	if err != nil {
		return "", err
	}
	defer func() { _ = os.RemoveAll(dir) }()

	path := filepath.Join(dir, "key.pub")
	if err := os.WriteFile(path, line, 0o644); err != nil {
		return "", err
	}
	out, err := exec.LocalCommand("ssh-keygen", "-lf", path).Output()
	if err != nil {
		return "", err
	}
	fields := strings.Fields(string(out))
	if len(fields) < 2 {
		return "", fmt.Errorf("unexpected ssh-keygen output: %q", strings.TrimSpace(string(out)))
	}
	return fields[1], nil
}

// certificateKeyFingerprint returns the SHA256 fingerprint of the key a certificate certifies.
func certificateKeyFingerprint(certData []byte) (string, error) {
	dir, err := os.MkdirTemp("", "kdnctl-cert-")
	if err != nil {
		return "", err
	}
	defer func() { _ = os.RemoveAll(dir) }()

	path := filepath.Join(dir, "cert.pub")
	if err := os.WriteFile(path, certData, 0o644); err != nil {
		return "", err
	}
	out, err := exec.LocalCommand("ssh-keygen", "-L", "-f", path).Output()
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(out), "\n") {
		if !strings.Contains(line, "Public key:") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) == 0 {
			break
		}
		return fields[len(fields)-1], nil
	}
	return "", fmt.Errorf("no 'Public key:' line in ssh-keygen -L output")
}

// reloadSSHD validates the configuration and sends SIGHUP. A reload re-reads host keys and
// certificates, so it is enough for a renewed certificate and costs no connection.
func reloadSSHD(h *host.Host, sshOptions []string) error {
	if err := exec.RemoteCommand(h.Address, sshOptions, "sh", "-c", "command -v systemctl >/dev/null").Run(); err != nil {
		fmt.Printf("%s: no systemd on this host; reload sshd by hand\n", h.Name)
		return nil
	}
	if err := exec.RemoteCommand(h.Address, sshOptions, "sudo", "sshd", "-t").Run(); err != nil {
		return fmt.Errorf("EnsureCerts(%s): sshd -t rejected the configuration; not reloading: %w", h.Name, err)
	}
	if err := exec.RemoteCommand(h.Address, sshOptions, "sudo", "systemctl", "reload", "sshd").Run(); err != nil {
		return fmt.Errorf("EnsureCerts(%s): reloading sshd: %w", h.Name, err)
	}
	fmt.Printf("%s: sshd reloaded\n", h.Name)
	return nil
}

// HostsWithCerts lists, in sorted order, the hosts that have a committed SSH host certificate.
func HostsWithCerts(repoRoot string) ([]string, error) {
	matches, err := filepath.Glob(filepath.Join(repoRoot, "hosts", "*", "certs", "*-cert.pub"))
	if err != nil {
		return nil, err
	}
	seen := make(map[string]bool, len(matches))
	names := make([]string, 0, len(matches))
	for _, match := range matches {
		name := filepath.Base(filepath.Dir(filepath.Dir(match)))
		if seen[name] {
			continue
		}
		seen[name] = true
		names = append(names, name)
	}
	sort.Strings(names)
	return names, nil
}
