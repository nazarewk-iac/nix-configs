// Package sshkeys keeps a host's SSH identity in sync with the encrypted copy in the repo.
//
// Why: an installer-generated host key lives in RAM until something writes it down, and a host
// that restores it from a sops secret inherits a boot-time dependency on that secret. On
// 2026-11-04 a transient TPM failure in the first seconds of boot left brys with no host key and
// therefore no sshd, reachable only over the KVM.
//
// So the key is moved OUT of the boot path: it is encrypted at rest in the repo (sops, or pass
// when that store is the configured one), and this command syncs it on demand. The comparison is
// on the DECRYPTED bytes, so a second run is a no-op and a rotated key uploads once.
package sshkeys

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/exec"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/repo"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/secrets"
)

// defaultKeyTypes are the identities sshd uses on these hosts. ed25519 alone would be enough,
// but the installer generates both and an operator may still connect with an RSA client.
var defaultKeyTypes = []string{"ed25519", "rsa"}

// targetDir is where the host keeps the keys between reboots. It matches what
// `kdnctl host bootstrap` writes and what the host configuration links from /etc/ssh.
const targetDir = "/nix/persist/sys/data/etc/ssh"

// Options tunes where the keys come from and which of them to sync.
type Options struct {
	// SecretDir is the repo-relative directory holding the encrypted keys
	// (`hosts/<name>/ssh-keys`, or `hosts/<name>/certs` for the SSH CA leaf key).
	SecretDir string
	// KeyTypes defaults to ed25519 and rsa.
	KeyTypes []string
}

func secretPath(h *host.Host, opts Options, keyType, suffix string) string {
	return fmt.Sprintf("%s/ssh_host_%s_key%s", opts.SecretDir, keyType, suffix)
}

// Ensure syncs every key type into the host. With `upload == false` it only reports what differs.
func Ensure(r *repo.Repo, h *host.Host, s secrets.SecretStorage, upload bool, opts Options) error {
	sshOptions := exec.SSHNoHostKeyChecking
	if opts.SecretDir == "" {
		opts.SecretDir = fmt.Sprintf("hosts/%s/ssh-keys", h.Name)
	}
	keyTypes := opts.KeyTypes
	if len(keyTypes) == 0 {
		keyTypes = defaultKeyTypes
	}

	for _, keyType := range keyTypes {
		for _, suffix := range []string{"", ".pub"} {
			path := secretPath(h, opts, keyType, suffix)
			remotePath := fmt.Sprintf("%s/ssh_host_%s_key%s", targetDir, keyType, suffix)

			if !s.Exists(path) {
				if suffix == ".pub" {
					// Not every source stores the public half; it is derivable from the private one.
					fmt.Printf("%s: %s not in the store, skipped\n", h.Name, path)
					continue
				}
				// First run for this host: adopt what the machine already uses, so the repo
				// records the identity that clients have in their known_hosts. Publishing the key
				// would otherwise change the host identity on every reinstall.
				if !upload {
					return fmt.Errorf("Ensure(%s): %s is not in the secret store; run again with --upload to import the host's current key", h.Name, path)
				}
				have, err := exec.GetRemoteFile(h.Address, sshOptions, remotePath)
				if err != nil {
					return fmt.Errorf("Ensure(%s): importing %s from the host: %w", h.Name, remotePath, err)
				}
				if err := s.EncryptBytes(path, have); err != nil {
					return fmt.Errorf("Ensure(%s): storing %s in the secret store: %w", h.Name, path, err)
				}
				fmt.Printf("%s: imported %s into the secret store (%s)\n", h.Name, remotePath, shortHash(have))
				continue
			}
			want, err := s.DecryptBytes(path)
			if err != nil {
				return fmt.Errorf("Ensure(%s): decrypting %s: %w", h.Name, path, err)
			}

			have, err := exec.GetRemoteFile(h.Address, sshOptions, remotePath)
			if err != nil {
				return fmt.Errorf("Ensure(%s): reading %s: %w", h.Name, remotePath, err)
			}

			if bytes.Equal(bytes.TrimSpace(have), bytes.TrimSpace(want)) {
				fmt.Printf("%s: %s in sync (%s)\n", h.Name, remotePath, shortHash(want))
				continue
			}
			fmt.Printf("%s: %s DIFFERS (host %s, repo %s)\n", h.Name, remotePath, shortHash(have), shortHash(want))
			if !upload {
				continue
			}
			if err := uploadKey(h, sshOptions, remotePath, want); err != nil {
				return err
			}
			fmt.Printf("%s: %s uploaded\n", h.Name, remotePath)
		}
	}
	return nil
}

// uploadKey writes through a temporary file and renames, so a dropped connection cannot leave a
// half-written private key where sshd will read it. Mode follows the file type: 0400 for the
// private half, 0444 for the public one.
func uploadKey(h *host.Host, sshOptions []string, remotePath string, data []byte) error {
	mode := "0400"
	if strings.HasSuffix(remotePath, ".pub") {
		mode = "0444"
	}

	// `exec.RemoteCommand` shell-quotes EVERY argument and appends them as one ssh command word,
	// so a script built from many arguments arrives as separate words and silently does nothing.
	// Pass the script as a single argument, and let it read the key from stdin: a private key
	// must never appear in a process list or in an ssh command line.
	tmpPath := remotePath + ".kdnctl-tmp"
	script := fmt.Sprintf(
		"set -eu; mkdir -p %q; umask 077; cat > %q; chmod %s %q; mv -f %q %q",
		filepath.Dir(remotePath), tmpPath, mode, tmpPath, tmpPath, remotePath,
	)
	proc := exec.RemoteCommand(h.Address, sshOptions, "sudo", "sh", "-c", script)
	proc.Cmd.Stdin = bytes.NewReader(data)
	var stderr bytes.Buffer
	proc.Cmd.Stderr = &stderr
	if err := proc.Run(); err != nil {
		return fmt.Errorf("uploadKey(%s, %s): %w: %s", h.Name, remotePath, err, strings.TrimSpace(stderr.String()))
	}
	return nil
}

func shortHash(data []byte) string {
	sum := sha256.Sum256(bytes.TrimSpace(data))
	return hex.EncodeToString(sum[:4])
}
