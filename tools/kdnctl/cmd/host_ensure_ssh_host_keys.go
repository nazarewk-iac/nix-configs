package cmd

import (
	"github.com/spf13/cobra"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host/sshkeys"
)

var (
	uploadSSHHostKeys bool
	sshKeysSecretDir  string
	sshKeysTypes      []string
)

var hostEnsureSSHHostKeysCmd = &cobra.Command{
	Use:     "ssh-host-keys",
	Aliases: []string{"sshk"},
	Short:   "Sync a host's SSH host keys from the encrypted copy in this repo",
	Long: `Reads the encrypted SSH host keys for the host from the secret store, compares them with
the keys on the host, and uploads the decrypted key only when they differ.

The comparison is on decrypted bytes, so a second run is a no-op. Without --upload only the
difference is reported.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return sshkeys.Ensure(repository, host, secretStorage, uploadSSHHostKeys, sshkeys.Options{
			SecretDir: sshKeysSecretDir,
			KeyTypes:  sshKeysTypes,
		})
	},
}

func init() {
	hostEnsureCmd.AddCommand(hostEnsureSSHHostKeysCmd)
	hostEnsureSSHHostKeysCmd.Flags().BoolVar(&uploadSSHHostKeys, "upload", true, "upload the decrypted key when it differs from the host copy")
	hostEnsureSSHHostKeysCmd.Flags().StringVar(&sshKeysSecretDir, "secret-dir", "", "repo-relative directory holding the encrypted keys (default hosts/<name>/ssh-keys)")
	hostEnsureSSHHostKeysCmd.Flags().StringSliceVar(&sshKeysTypes, "key-type", nil, "key types to sync (default ed25519,rsa)")
}
