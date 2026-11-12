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
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/exec"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/repo"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/secrets"
)

// defaultKeyTypes are the identities sshd uses on these hosts. ed25519 alone would be enough,
// but the installer generates both and an operator may still connect with an RSA client.
var defaultKeyTypes = []string{"ed25519", "rsa"}

// fallbackTargetDir is where the managed key lives on a host: `kdn.certificates.*.deployedDirectory`.
const fallbackTargetDir = "/etc/ssh/kdn"

// persistTargetDir is the same directory as the impermanence module backs it. The deployed
// directory is a bind mount, so a write before the first activation would land on the ephemeral
// root and be hidden by the mount. The backing directory is the durable location in both states.
const persistTargetDir = "/nix/persist/sys/data/etc/ssh/kdn"

// Options tunes where the keys come from and which of them to sync.
type Options struct {
	// SecretDir is the repo-relative directory holding the encrypted keys
	// (`hosts/<name>/ssh-keys`, or `hosts/<name>/certs` for the SSH CA leaf key).
	SecretDir string
	// KeyTypes defaults to ed25519 and rsa.
	KeyTypes []string
	// TargetDir is the remote directory that holds the keys. Empty means "detect": follow
	// `/etc/ssh/kdn`, so a symlink into `/nix/persist` is written at its target.
	TargetDir string
}

// resolveTargetDir picks the remote directory to write. The deployed directory is a bind mount on
// an impermanence host, and a bind mount is not a symlink, so it cannot be followed. Prefer the
// persistence backing directory when the host has one: a deploy that happens before the mount
// exists then still lands in durable storage instead of the ephemeral root.
func resolveTargetDir(h *host.Host, opts Options, sshOptions []string) (string, error) {
	if opts.TargetDir != "" {
		return opts.TargetDir, nil
	}
	if out, err := exec.RemoteCommand(h.Address, sshOptions, "sudo", "readlink", "-f", fallbackTargetDir).Output(); err == nil {
		if resolved := strings.TrimSpace(string(out)); resolved != "" && resolved != fallbackTargetDir {
			return resolved, nil
		}
	}
	if err := exec.RemoteCommand(h.Address, sshOptions, "sudo", "test", "-d", filepath.Dir(persistTargetDir)).Run(); err == nil {
		return persistTargetDir, nil
	}
	return fallbackTargetDir, nil
}

// HostsWithKeys lists, in sorted order, the hosts that have a committed SSH host key in the
// repository, and separately the hosts whose key is only a symlink into the local `secrets/`
// store. It is the "all hosts" set of `host ensure ssh-host-keys`: the committed state decides
// which hosts are in scope, so a host without a key is never touched. A symlinked key is the older
// local-only layout — it works with an explicit `--hostname`, but it is not part of the fleet state
// this command reconciles, and such a host is usually retired.
func HostsWithKeys(repoRoot string) (hosts []string, localOnly []string, err error) {
	matches, err := filepath.Glob(filepath.Join(repoRoot, "hosts", "*", "ssh-keys", "*.sops"))
	if err != nil {
		return nil, nil, err
	}
	seen := make(map[string]bool, len(matches))
	seenLocal := make(map[string]bool, len(matches))
	for _, match := range matches {
		// `<root>/hosts/<name>/ssh-keys/<file>.sops`
		name := filepath.Base(filepath.Dir(filepath.Dir(match)))
		info, statErr := os.Lstat(match)
		if statErr != nil {
			return nil, nil, statErr
		}
		if !info.Mode().IsRegular() {
			if !seenLocal[name] {
				seenLocal[name] = true
				localOnly = append(localOnly, name)
			}
			continue
		}
		if seen[name] {
			continue
		}
		seen[name] = true
		hosts = append(hosts, name)
	}
	sort.Strings(hosts)
	sort.Strings(localOnly)
	return hosts, localOnly, nil
}

// equalKey compares two key files. For a public key only the type and the base64 body matter: the
// comment differs (`root@briv` on the host, nothing from `ssh-keygen -y`), and comparing whole
// lines would report a difference on every run.
func equalKey(a, b []byte, public bool) bool {
	left, right := strings.TrimSpace(string(a)), strings.TrimSpace(string(b))
	if !public {
		return left == right
	}
	l, r := strings.Fields(left), strings.Fields(right)
	if len(l) < 2 || len(r) < 2 {
		return false
	}
	return l[0] == r[0] && l[1] == r[1]
}

// derivePublicKey returns the OpenSSH public line of a private key. `ssh-keygen` reads a file, so
// the key goes through a private temporary file that is removed before returning.
func derivePublicKey(private []byte) ([]byte, error) {
	dir, err := os.MkdirTemp("", "kdnctl-sshkey-")
	if err != nil {
		return nil, err
	}
	defer func() { _ = os.RemoveAll(dir) }()

	path := filepath.Join(dir, "key")
	if err := os.WriteFile(path, private, 0o600); err != nil {
		return nil, err
	}
	out, err := exec.LocalCommand("ssh-keygen", "-y", "-f", path).Output()
	if err != nil {
		return nil, fmt.Errorf("ssh-keygen -y: %w", err)
	}
	return bytes.TrimSpace(out), nil
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
	targetDir, err := resolveTargetDir(h, opts, sshOptions)
	if err != nil {
		return fmt.Errorf("Ensure(%s): resolving the remote key directory: %w", h.Name, err)
	}

	for _, keyType := range keyTypes {
		privatePath := secretPath(h, opts, keyType, "")
		remotePrivate := fmt.Sprintf("%s/ssh_host_%s_key", targetDir, keyType)

		// The private half is the source of truth. When the store does not have it yet, adopt what
		// the machine already uses, so the repo records the identity that clients have in their
		// known_hosts. Publishing the key would otherwise change the host identity on a reinstall.
		var wantPrivate []byte
		if !s.Exists(privatePath) {
			if !upload {
				return fmt.Errorf("Ensure(%s): %s is not in the secret store; run again with --upload to import the host's current key", h.Name, privatePath)
			}
			have, err := exec.GetRemoteFile(h.Address, sshOptions, remotePrivate)
			if err != nil {
				return fmt.Errorf("Ensure(%s): importing %s from the host: %w", h.Name, remotePrivate, err)
			}
			if err := s.EncryptBytes(privatePath, have); err != nil {
				return fmt.Errorf("Ensure(%s): storing %s in the secret store: %w", h.Name, privatePath, err)
			}
			fmt.Printf("%s: imported %s into the secret store (%s)\n", h.Name, remotePrivate, shortHash(have))
			wantPrivate = have
		} else {
			wantPrivate, err = s.DecryptBytes(privatePath)
			if err != nil {
				return fmt.Errorf("Ensure(%s): decrypting %s: %w", h.Name, privatePath, err)
			}
		}

		// A key pair must never be half-deployed: a stale `.pub` next to a fresh private key is a
		// misleading file on the host. Derive the public half when the store does not carry it.
		publicPath := secretPath(h, opts, keyType, ".pub")
		var wantPublic []byte
		if s.Exists(publicPath) {
			wantPublic, err = s.DecryptBytes(publicPath)
			if err != nil {
				return fmt.Errorf("Ensure(%s): decrypting %s: %w", h.Name, publicPath, err)
			}
		} else {
			wantPublic, err = derivePublicKey(wantPrivate)
			if err != nil {
				return fmt.Errorf("Ensure(%s): deriving the public half of %s: %w", h.Name, privatePath, err)
			}
		}

		halves := []struct {
			remote string
			want   []byte
			public bool
		}{
			{remotePrivate, wantPrivate, false},
			{remotePrivate + ".pub", wantPublic, true},
		}
		for _, half := range halves {
			have, exists, err := exec.GetRemoteFileIfExists(h.Address, sshOptions, half.remote)
			if err != nil {
				return fmt.Errorf("Ensure(%s): reading %s: %w", h.Name, half.remote, err)
			}
			if exists && equalKey(have, half.want, half.public) {
				fmt.Printf("%s: %s in sync (%s)\n", h.Name, half.remote, shortHash(half.want))
				continue
			}
			if !exists {
				fmt.Printf("%s: %s MISSING\n", h.Name, half.remote)
			} else {
				fmt.Printf("%s: %s DIFFERS (host %s, repo %s)\n", h.Name, half.remote, shortHash(have), shortHash(half.want))
			}
			if !upload {
				continue
			}
			if err := uploadKey(h, sshOptions, half.remote, half.want); err != nil {
				return err
			}
			fmt.Printf("%s: %s uploaded\n", h.Name, half.remote)
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
