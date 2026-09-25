package cmd

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"kdn-certs/internal/decl"
	"kdn-certs/internal/smallstep"
	"kdn-certs/internal/walk"
)

// sshLoginOptions holds the `ssh login` flags.
type sshLoginOptions struct {
	// User is the remote login name the certificate is valid for. The default is the local login
	// name, which is what `ssh` presents.
	User string
	// Lifetime is the OpenSSH validity interval of the certificate. The default is short, so a
	// stolen interactive certificate expires.
	Lifetime string
	// Key is the local private key path. A key that exists is reused; a missing one is generated.
	Key string
}

// newSSHCmd builds `kdn-certs ssh`.
func newSSHCmd(app *App) *cobra.Command {
	opts := sshLoginOptions{}

	sshCmd := &cobra.Command{
		Use:   "ssh",
		Short: "SSH certificate helpers",
	}

	loginCmd := &cobra.Command{
		Use:   "login <host>",
		Short: "Generate an SSH user certificate to connect to a host",
		Long:  "Generate an SSH user certificate to connect to a host. Pick the SSH CA and set the principals.",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return runSSHLogin(app, args[0], opts)
		},
	}
	loginCmd.Flags().StringVar(&opts.User, "user", "", "remote login name the certificate is valid for (default: the local login name)")
	loginCmd.Flags().StringVar(&opts.Lifetime, "lifetime", "+8h", "OpenSSH validity interval of the certificate, for example +8h or +30d")
	loginCmd.Flags().StringVar(&opts.Key, "key", "~/.ssh/id_ed25519", "local private key path; an existing key is reused")

	sshCmd.AddCommand(loginCmd)

	return sshCmd
}

// runSSHLogin does the five steps of design § 7.3:
//
//  1. Read the target host and its SSH CA from the certificate declarations.
//  2. Generate a user key pair, or reuse a named one.
//  3. Sign a user certificate with the SSH CA, with the target's login names and the short
//     interactive lifetime.
//  4. Prompt for the YubiKey touch inside the SOPS decrypt of the CA key.
//  5. Write the certificate next to the key and print the `ssh` command.
func runSSHLogin(app *App, host string, opts sshLoginOptions) error {
	targets, err := app.loadTargets()
	if err != nil {
		return err
	}
	app.reportFailures(targets.Failures)

	// Step 1. The target is a declared `ssh-host` leaf. Its `ca` is the SSH CA.
	cas, err := walk.MergeCAs(targets.Targets)
	if err != nil {
		return err
	}
	cert, ok := findSSHHost(targets.Targets, host)
	if !ok {
		if err := failuresError(targets.Failures); err != nil {
			return err
		}
		return fmt.Errorf("no ssh-host certificate names host %q", host)
	}
	ca, ok := cas[cert.CA]
	if !ok {
		return fmt.Errorf("ssh-host certificate %q names CA %q, which is not declared", host, cert.CA)
	}
	if !ca.SSH {
		return fmt.Errorf("CA %q does not sign SSH certificates (`ssh = true` is not set)", cert.CA)
	}

	// Step 2. Reuse an existing key, or generate one.
	keyPath := expandHome(app, opts.Key)
	pubPath := keyPath + ".pub"
	if _, err := os.Stat(keyPath); err != nil {
		if err := os.MkdirAll(filepath.Dir(keyPath), 0o700); err != nil {
			return fmt.Errorf("create %s: %w", filepath.Dir(keyPath), err)
		}
		if err := app.sshSigner().GenerateSSHKey(keyPath); err != nil {
			return err
		}
	}

	// The principal. The default is the local login name, which is what `ssh` presents.
	principal := opts.User
	if principal == "" {
		principal = localUser()
	}

	// Step 4. The CA private key is SOPS-sourced. `sops` prompts for the YubiKey touch inside the
	// decrypt. A timeout surfaces as a clear error.
	tmpDir, err := os.MkdirTemp("", "kdn-certs-ssh-")
	if err != nil {
		return fmt.Errorf("create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	caKeyPlain := filepath.Join(tmpDir, "ca.key")
	caKeySops := filepath.Join(app.Options.Flake, ca.Directory, ca.KeyFile+".sops")
	if err := app.decryptor().Decrypt(caKeySops, caKeyPlain); err != nil {
		return err
	}

	// Step 3. Sign the user certificate.
	req := smallstep.SSHCertRequest{
		KeyID:      principal + "@" + host,
		Principals: []string{principal},
		Validity:   opts.Lifetime,
		Host:       false,
		PubKeyPath: pubPath,
		CAKeyPath:  caKeyPlain,
	}
	if err := app.sshSigner().SignSSH(req); err != nil {
		return err
	}

	// Step 5. Print the `ssh` command. `ssh-keygen -s` writes `<pub without .pub>-cert.pub`.
	certPath := strings.TrimSuffix(pubPath, ".pub") + "-cert.pub"
	fmt.Fprintf(app.Out, "ssh -i %s %s\n", keyPath, host)
	fmt.Fprintf(app.Err, "certificate: %s\n", certPath)
	return nil
}

// findSSHHost returns the first `ssh-host` leaf whose common name or principals name `host`.
func findSSHHost(targets []decl.Target, host string) (decl.Cert, bool) {
	for _, target := range targets {
		for _, cert := range target.Certs {
			if cert.Type != "ssh-host" {
				continue
			}
			if cert.CommonName != host && !contains(cert.Principals, host) {
				continue
			}
			return cert, true
		}
	}
	return decl.Cert{}, false
}

// contains reports whether `values` holds `want`.
func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

// localUser returns the local login name, or `root` when it cannot be read.
func localUser() string {
	if current, err := user.Current(); err == nil && current.Username != "" {
		return current.Username
	}
	if name := os.Getenv("USER"); name != "" {
		return name
	}
	return "root"
}

// expandHome expands a leading `~/` against the current user's home directory.
func expandHome(app *App, path string) string {
	if !strings.HasPrefix(path, "~/") {
		return path
	}
	home := os.Getenv("HOME")
	if home == "" {
		if current, err := user.Current(); err == nil {
			home = current.HomeDir
		}
	}
	return filepath.Join(home, strings.TrimPrefix(path, "~/"))
}
