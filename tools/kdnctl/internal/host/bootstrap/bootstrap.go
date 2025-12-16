package bootstrap

import (
	"bufio"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/errors"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/exec"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host/luks"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/repo"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/secrets"
)

func Bootstrap(r *repo.Repo, h *host.Host, s secrets.SecretStorage, extraArgs []string) error {
	deployCmd := []string{
		"nixos-anywhere",
		"--phases", "disko,install",
		"--flake", fmt.Sprintf("%s#%s", r.Root, h.Name),
	}
	sshOptions := exec.SSHNoHostKeyChecking

	config, err := h.GatherConfig(r)
	if err != nil {
		return fmt.Errorf("Host.Bootstrap(%s): gathering config: %w", h.Name, err)
	}

	tmp, err := os.MkdirTemp("", fmt.Sprintf("kdnctl-host-bootstrap-%s-*", h.Name))
	err = errors.JoinIf(err, err, "Host.Bootstrap(%s): creating temporary directory", h.Name)

	if err == nil {
		defer func() {
			if err := os.RemoveAll(tmp); err != nil {
				slog.Error("failed to clean up temporary directory", "path", tmp, "error", err)
			}
		}()
	}
	if err := luks.EnsureLUKSKeyfilesForHost(r, h, s); err != nil {
		return fmt.Errorf("Host.Bootstrap(%s): initializing LUKS keyfiles: %w", h.Name, err)
	}

	for _, volume := range config.LUKSVolumes {
		secretPath := luks.KeyFileKey(h, volume.Name)
		data, e := s.DecryptBytes(secretPath)
		if e != nil {
			err = errors.JoinIf(err, e, "decrypting LUKS keyfile")
			break
		}
		tmpPath := filepath.Join(tmp, fmt.Sprintf("%s.key", volume.Name))
		if e = os.WriteFile(tmpPath, data, 0o600); e != nil {
			err = errors.JoinIf(err, e, "writing to temporary LUKS keyfile")
			break
		}
		deployCmd = append(deployCmd, "--disk-encryption-keys", volume.KeyFile, tmpPath)
	}
	if err != nil {
		return fmt.Errorf("Host.Bootstrap(%s): preparing keyFiles: %w", h.Name, err)
	}

	hostKeyPattern := "/etc/ssh/ssh_host_%s_key%s"
	hostKeys := map[string]string{}
	hostKeyPaths := map[string]string{
		"rsa-priv":     fmt.Sprintf(hostKeyPattern, "rsa", ""),
		"rsa-pub":      fmt.Sprintf(hostKeyPattern, "rsa", ".pub"),
		"ed25519-priv": fmt.Sprintf(hostKeyPattern, "ed25519", ""),
		"ed25519-pub":  fmt.Sprintf(hostKeyPattern, "ed25519", ".pub"),
	}
	{
		// fill-in keys based on their paths
		for key, keyPath := range hostKeyPaths {
			data, err := exec.GetRemoteFile(h.Address, sshOptions, keyPath)
			if err != nil {
				return fmt.Errorf("Host.Bootstrap(%s): fetching SSH host key: %w", h.Name, err)
			}
			hostKeys[key] = strings.TrimSpace(string(data))
		}
	}

	{
		// store the ssh host keys into repo
		// TODO: restore those instead of reusing installer generated keys
		sshKeysPath := filepath.Join("hosts", h.Name, "ssh-keys")
		if err := os.MkdirAll(sshKeysPath, 0o755); err != nil {
			return fmt.Errorf("Host.Bootstrap(%s): creating local SSH host keys directory: %w", h.Name, err)
		}
		for key, data := range hostKeys {
			keyPath := hostKeyPaths[key]
			fileName := filepath.Base(keyPath)
			if strings.HasSuffix(keyPath, ".pub") {
				err = os.WriteFile(filepath.Join(r.Root, sshKeysPath, fileName), []byte(data), 0o644)
				if err != nil {
					return fmt.Errorf("Host.Bootstrap(%s): persisting %s public key to the repository: %w", h.Name, key, err)
				}
			} else {
				err = s.Encrypt(filepath.Join(sshKeysPath, fileName), data)
				if err != nil {
					return fmt.Errorf("Host.Bootstrap(%s): persisting %s private key to the repository: %w", h.Name, key, err)
				}
			}
		}
	}
	{
		// retrieve convert to Age key and add it to `.sops.yaml`
		proc := exec.LocalCommand("ssh-to-age")
		proc.Stdin = strings.NewReader(hostKeys["ed25519-pub"])

		data, err := proc.Output()
		if err != nil {
			return fmt.Errorf("Host.Bootstrap(%s): ssh-to-age: %w", h.Name, err)
		}
		ageKey := string(data[:len(data)-1])

		addedLines, err := LinesInFile(filepath.Join(r.Root, ".sops.yaml"),
			&LinesInFileEntry{
				Before: "SSH-KEYS-DEFINITION-INSERT-ABOVE",
				Line:   fmt.Sprintf("    %[1]s: {age: [&ssh-%[1]s %[2]s]}", h.Name, ageKey),
				Search: fmt.Sprintf("&ssh-%[1]s ", h.Name),
			},
			&LinesInFileEntry{
				Before: "SSH-KEYS-USAGE-INSERT-ABOVE",
				Line:   fmt.Sprintf("          - *ssh-%[1]s", h.Name),
				Search: fmt.Sprintf("- *ssh-%[1]s", h.Name),
			},
		)
		if err != nil {
			return fmt.Errorf("Host.Bootstrap(%s): registering SSH keys in .sops.yaml: %w", h.Name, err)
		}
		if len(addedLines) > 0 || true {
			slog.Warn("added new entries to .sops.yaml", "lines", addedLines)
			if err := secrets.SopsUpdateKeys(r.Root); err != nil {
				return fmt.Errorf("Host.Bootstrap(%s): rotating SOPS files: %w", h.Name, err)
			}
		}
	}

	// TODO: add keys to be picked up by known-hosts.sh
	deployCmd = append(deployCmd, extraArgs...)
	deployCmd = append(deployCmd, h.Address)
	if err := exec.LocalCommand(deployCmd...).Run(); err != nil {
		return fmt.Errorf("Host.Bootstrap(%s): deploying: %w", h.Name, err)
	}

	{
		// copy-over the NixOS installer's (autogenerated) SSH keys into the resulting machine
		persistentDir := "/mnt/nix/persist/sys/data/etc/ssh"
		if err = exec.RemoteCommand(h.Address, sshOptions, "sudo", "mkdir", "-p", persistentDir).Run(); err != nil {
			return fmt.Errorf("Host.Bootstrap(%s): creating persistent SSH configuration directory: %w", h.Name, err)
		}
		sourceDirPattern := "/etc/ssh/ssh_host_%s_key%s"
		cpArgs := []string{
			"sudo", "cp",
			fmt.Sprintf(sourceDirPattern, "rsa", ""),
			fmt.Sprintf(sourceDirPattern, "rsa", ".pub"),
			fmt.Sprintf(sourceDirPattern, "ed25519", ""),
			fmt.Sprintf(sourceDirPattern, "ed25519", ".pub"),
			persistentDir,
		}
		if err = exec.RemoteCommand(h.Address, sshOptions, cpArgs...).Run(); err != nil {
			return fmt.Errorf("Host.Bootstrap(%s): persisting SSH keys: %w", h.Name, err)
		}
	}
	{ // systemd-cryptenroll for TPM2 keys
		for _, volume := range config.LUKSVolumes {
			err := exec.RemoteCommand(h.Address, sshOptions,
				"sudo", "systemd-cryptenroll",
				fmt.Sprintf("--unlock-key-file=%s", volume.KeyFile),
				"--tpm2-device=auto",
				volume.HeaderPath,
			).Run()
			if err != nil {
				return fmt.Errorf("Host.Bootstrap(%s): generating LUKS key with TPM2 for %s: %w", h.Name, volume.Name, err)
			}
		}
	}
	{ // TODO: detect whether YubiKey is inserted and register it with LUKS
	}
	{ // backup LUKS headers
		for _, volume := range config.LUKSVolumes {
			data, err := exec.RemoteCommand(h.Address, sshOptions, "sudo", "bash", "-c",
				// luksHeaderBackup does not support writing to stdout
				strings.ReplaceAll(`
					tempdir="$(mktemp -d /tmp/kdn-luks-header-backup.XXXXXX)"
					mkdir -p "$tempdir"
					chmod 700 "$tempdir"
					trap 'rm -rf "$tempdir" || :' EXIT

					set -xeEuo pipefail
					cryptsetup luksHeaderBackup --batch-mode --header="$1" --header-backup-file="$tempdir/header" "$2"
					cat "$tempdir/header"
				`, "\t", ""),
				"dump-header-to-stdout.sh",
				volume.HeaderPath,
				volume.CryptsetupName,
			).Output()
			if err != nil {
				return fmt.Errorf("Host.Bootstrap(%s): fetching LUKS header for %s: %w", h.Name, volume.Name, err)
			}
			keyPath := filepath.Join("hosts", h.Name, "luks", fmt.Sprintf("%s.header", volume.Name))
			if err := s.EncryptBytes(keyPath, data); err != nil {
				return fmt.Errorf("Host.Bootstrap(%s): persisting LUKS header for %s: %w", h.Name, volume.Name, err)
			}
		}
	}
	return nil
}

type LinesInFileEntry struct {
	Before string
	// After string
	Search string
	Line   string
}

func LinesInFile(path string, entries ...*LinesInFileEntry) (added []string, err error) {
	// TODO: finish split into
	byInsertBefore := map[string][]*LinesInFileEntry{}
	found := map[string]bool{}

	for _, entry := range entries {
		byInsertBefore[entry.Before] = append(byInsertBefore[entry.Before], entry)
		found[entry.Search] = false
	}
	input, err := os.Open(path)
	if err != nil {
		return added, fmt.Errorf("LinesInFile(%s): opening input file: %w", path, err)
	}
	defer func() {
		if err := input.Close(); err != nil {
			slog.Error("failed to close the input file", "path", path, "err", err)
		}
	}()
	scanner := bufio.NewScanner(input)

	var outputBuilder strings.Builder

	for scanner.Scan() {
		line := scanner.Text()

	handlePatterns:
		for insertBeforePattern, inserts := range byInsertBefore {
			for _, insert := range inserts {
				if !strings.Contains(line, insert.Search) {
					continue
				}
				found[insert.Search] = true
				// replace line with a new content
				if line != insert.Line {
					added = append(added, insert.Line)
					line = insert.Line
				}
				continue handlePatterns
			}
			if !strings.Contains(line, insertBeforePattern) {
				continue handlePatterns
			}
			for _, insert := range inserts {
				if found[insert.Search] {
					continue
				}
				found[insert.Search] = true
				added = append(added, insert.Line)
				outputBuilder.WriteString(insert.Line)
				outputBuilder.WriteString("\n")
			}
		}
		outputBuilder.WriteString(line)
		outputBuilder.WriteString("\n")
	}
	if len(added) == 0 {
		return
	}
	err = os.WriteFile(path, []byte(outputBuilder.String()), 0o640)
	if err != nil {
		return added, fmt.Errorf("LinesInFile(%s): error writing output: %w", path, err)
	}
	return
}
