package cmd

import (
	"errors"
	"fmt"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	hostmod "github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host/sshkeys"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/secrets"
)

var (
	uploadSSHHostKeys bool
	sshKeysSecretDir  string
	sshKeysTypes      []string
	sshKeysTargetDir  string
	sshKeysAllHosts   bool
)

var hostEnsureSSHHostKeysCmd = &cobra.Command{
	Use:     "ssh-host-keys",
	Aliases: []string{"sshk"},
	Short:   "Sync a host's SSH host keys from the encrypted copy in this repo",
	Long: `Reads the encrypted SSH host keys for the host from the repository, compares them with the
keys on the host, and writes the decrypted key only when they differ and --upload is given.

The comparison is on decrypted bytes, so a second run is a no-op. Without --upload only the
difference is reported.

The keys are read from the REPOSITORY ('hosts/<name>/ssh-keys'), not from the 'secrets/' store.
An SSH host key is part of the host's identity and is committed next to the host, like its
certificate; 'secrets/' holds the local, uncommitted copies that the other commands use.

--all reconciles every host that has a committed key, which is the local state deciding the set.
A host that fails is reported and the run continues; the exit status is non-zero if any failed.
Give a host whose name does not resolve an address in the config file:

    [hosts.briv]
    address = "192.168.73.103"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// A repository-rooted store, so `--secret-dir` (default `hosts/<name>/ssh-keys`) means
		// what it says. The shared `secretStorage` prepends `secrets/`, which is right for the
		// uncommitted store and wrong for the committed per-host keys. A path that is a symlink
		// into `secrets/` still resolves, so the older layout keeps working.
		store := secrets.NewSopsSecretStorage(repository.Root)
		opts := sshkeys.Options{
			SecretDir: sshKeysSecretDir,
			KeyTypes:  sshKeysTypes,
			TargetDir: sshKeysTargetDir,
		}

		if !sshKeysAllHosts {
			return sshkeys.Ensure(repository, host, store, uploadSSHHostKeys, opts)
		}

		names, localOnly, err := sshkeys.HostsWithKeys(repository.Root)
		if err != nil {
			return fmt.Errorf("listing hosts with a committed SSH key: %w", err)
		}
		if len(localOnly) > 0 {
			fmt.Printf("skipping %s: the key is a symlink into the local secrets/ store, not a committed key; pass --hostname to reconcile one explicitly\n", strings.Join(localOnly, ", "))
		}
		if len(names) == 0 {
			return errors.New("no host has a committed SSH host key under hosts/*/ssh-keys")
		}

		var errs []error
		for _, name := range names {
			h := hostmod.New(name, hostAddress(name))
			if err := sshkeys.Ensure(repository, h, store, uploadSSHHostKeys, opts); err != nil {
				errs = append(errs, fmt.Errorf("%s: %w", name, err))
			}
		}
		fmt.Printf("%d host(s) reconciled, %d failed\n", len(names), len(errs))
		return errors.Join(errs...)
	},
}

// hostAddress reads `hosts.<name>.address` from the config file and falls back to the name. The
// fleet has hosts whose DNS name points at an address this machine cannot reach (a NetBird name,
// or `oams` resolving to a loopback alias), so the address is data, not a convention.
func hostAddress(name string) string {
	if address := viper.GetString("hosts." + name + ".address"); address != "" {
		return address
	}
	return name
}

func init() {
	hostEnsureCmd.AddCommand(hostEnsureSSHHostKeysCmd)
	// The write is explicit: on this fleet an existing /etc/ssh/ssh_host_ed25519_key is the SOPS
	// age identity, and replacing it by accident would lock the host out of its own secrets.
	hostEnsureSSHHostKeysCmd.Flags().BoolVar(&uploadSSHHostKeys, "upload", false, "write the decrypted key to the host when it differs")
	hostEnsureSSHHostKeysCmd.Flags().StringVar(&sshKeysSecretDir, "secret-dir", "", "repo-relative directory holding the encrypted keys (default hosts/<name>/ssh-keys)")
	// The fleet's host identity and its CA certificate are ed25519. `rsa` stays available through
	// `--key-type` for the older hosts that still carry an RSA pair.
	hostEnsureSSHHostKeysCmd.Flags().StringSliceVar(&sshKeysTypes, "key-type", []string{"ed25519"}, "key types to sync")
	hostEnsureSSHHostKeysCmd.Flags().StringVar(&sshKeysTargetDir, "target-dir", "", "remote directory holding the keys (default: the target of /etc/ssh/kdn, so a preserved directory is written at its target)")
	hostEnsureSSHHostKeysCmd.Flags().BoolVar(&sshKeysAllHosts, "all", false, "reconcile every host that has a committed key under hosts/*/ssh-keys")
}
