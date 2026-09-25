// Package sops decrypts a raw/binary SOPS key file.
//
// The private keys of the tree are raw/binary SOPS files. `sops decrypt --output-type binary`
// writes the original bytes. See research § 3.
package sops

import (
	"fmt"
	"os"
	"os/exec"
)

// Decryptor decrypts one SOPS file to a destination path.
type Decryptor interface {
	// Decrypt writes the plaintext bytes of `sopsFile` to `dest` with mode 0400.
	Decrypt(sopsFile string, dest string) error
}

// Encryptor encrypts one plaintext file to a raw/binary SOPS file.
type Encryptor interface {
	// Encrypt writes the raw bytes of `plainFile` to `sopsFile` as a raw/binary SOPS file.
	Encrypt(plainFile string, sopsFile string) error
}

// CLI is the real decryptor and encryptor. It shells out to `sops`.
type CLI struct {
	// Verbose prints each command before it runs.
	Verbose bool
	// Logf receives one line per command when Verbose is set.
	Logf func(format string, args ...any)
	// ConfigPath is the `.sops.yaml` to read. Empty means `sops` searches from the working
	// directory, which is correct when the CLI runs at the tree root. A caller that runs from
	// another directory sets it.
	ConfigPath string
}

// configArgs returns the `--config` prefix, or nothing when no path is set.
func (c CLI) configArgs() []string {
	if c.ConfigPath == "" {
		return nil
	}
	return []string{"--config", c.ConfigPath}
}

// Decrypt runs `sops decrypt --output-type binary <sopsFile>` and writes the result to `dest`.
//
// A YubiKey-backed key prompts for the touch inside `sops` itself. The prompt is part of the sign
// flow, not a manual side step.
func (c CLI) Decrypt(sopsFile string, dest string) error {
	if c.Verbose && c.Logf != nil {
		c.Logf("sops decrypt --output-type binary %s > %s", sopsFile, dest)
	}
	args := append(c.configArgs(), "decrypt", "--output-type", "binary", sopsFile)
	cmd := exec.Command("sops", args...)
	cmd.Stdin = os.Stdin
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("sops decrypt %s: %w", sopsFile, err)
	}
	if err := os.WriteFile(dest, out, 0o400); err != nil {
		return fmt.Errorf("write %s: %w", dest, err)
	}
	return nil
}

// Encrypt runs `sops encrypt --output-type binary --filename-override <sopsFile> --output <sopsFile>`
// over `plainFile`.
//
// `--filename-override` makes SOPS select the `creation_rules` entry by the destination path, not by
// the temporary plaintext path. Without it, SOPS would match the generic rule and the per-host rule
// above it would never fire. See research § 3.
func (c CLI) Encrypt(plainFile string, sopsFile string) error {
	if c.Verbose && c.Logf != nil {
		c.Logf("sops encrypt --output-type binary --filename-override %s --output %s %s", sopsFile, sopsFile, plainFile)
	}
	args := append(c.configArgs(),
		"encrypt",
		"--output-type", "binary",
		"--filename-override", sopsFile,
		"--output", sopsFile,
		plainFile,
	)
	cmd := exec.Command("sops", args...)
	cmd.Stdin = os.Stdin
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("sops encrypt %s: %w", sopsFile, err)
	}
	return nil
}
