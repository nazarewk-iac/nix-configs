package cmd

import (
	"github.com/spf13/cobra"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host/sshkeys"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/secrets"
)

var (
	uploadSSHHostKeys bool
	sshKeysSecretDir  string
	sshKeysTypes      []string
	sshKeysTargetDir  string
)

var hostEnsureSSHHostKeysCmd = &cobra.Command{
	Use:     "ssh-host-keys",
	Aliases: []string{"sshk"},
	Short:   "Sync a host's SSH host keys from the encrypted copy in this repo",
	Long: `Reads the encrypted SSH host keys for the host from the secret store, compares them with
the keys on the host, and uploads the decrypted key only when they differ.

The comparison is on decrypted bytes, so a second run is a no-op. Without --upload only the
difference is reported.

The keys are read from the REPOSITORY ('hosts/<name>/ssh-keys'), not from the 'secrets/' store.
An SSH host key is part of the host's identity and is committed next to the host, like its
certificate; 'secrets/' holds the local, uncommitted copies that the other commands use.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// A repository-rooted store, so `--secret-dir` (default `hosts/<name>/ssh-keys`) means
		// what it says. The shared `secretStorage` prepends `secrets/`, which is right for the
		// uncommitted store and wrong for the committed per-host keys. A path that is a symlink
		// into `secrets/` still resolves, so the older layout keeps working.
		store := secrets.NewSopsSecretStorage(repository.Root)
		return sshkeys.Ensure(repository, host, store, uploadSSHHostKeys, sshkeys.Options{
			SecretDir: sshKeysSecretDir,
			KeyTypes:  sshKeysTypes,
			TargetDir: sshKeysTargetDir,
		})
	},
}

func init() {
	hostEnsureCmd.AddCommand(hostEnsureSSHHostKeysCmd)
	hostEnsureSSHHostKeysCmd.Flags().BoolVar(&uploadSSHHostKeys, "upload", false, "write the decrypted key to the host when it differs (off by default: on this fleet /etc/ssh/ssh_host_ed25519_key is the SOPS age identity, and replacing it breaks sops on that host)")
	hostEnsureSSHHostKeysCmd.Flags().StringVar(&sshKeysSecretDir, "secret-dir", "", "repo-relative directory holding the encrypted keys (default hosts/<name>/ssh-keys)")
	// The fleet's host identity and its CA certificate are ed25519. `rsa` stays available through
	// `--key-type` for the older hosts that still carry an RSA pair.
	hostEnsureSSHHostKeysCmd.Flags().StringSliceVar(&sshKeysTypes, "key-type", []string{"ed25519"}, "key types to sync")
	hostEnsureSSHHostKeysCmd.Flags().StringVar(&sshKeysTargetDir, "target-dir", "", "remote directory holding the keys (default: the target of /etc/ssh/ssh_host_ed25519_key when it is a symlink under /nix/persist, else /etc/ssh)")
}
