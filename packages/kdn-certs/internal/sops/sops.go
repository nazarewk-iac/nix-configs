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

// CLI is the real decryptor. It shells out to `sops`.
type CLI struct {
	// Verbose prints each command before it runs.
	Verbose bool
	// Logf receives one line per command when Verbose is set.
	Logf func(format string, args ...any)
}

// Decrypt runs `sops decrypt --output-type binary <sopsFile>` and writes the result to `dest`.
//
// A YubiKey-backed key prompts for the touch inside `sops` itself. The prompt is part of the sign
// flow, not a manual side step.
func (c CLI) Decrypt(sopsFile string, dest string) error {
	if c.Verbose && c.Logf != nil {
		c.Logf("sops decrypt --output-type binary %s > %s", sopsFile, dest)
	}
	cmd := exec.Command("sops", "decrypt", "--output-type", "binary", sopsFile)
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
