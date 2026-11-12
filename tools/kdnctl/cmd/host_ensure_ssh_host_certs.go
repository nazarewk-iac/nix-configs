package cmd

import (
	"errors"
	"fmt"

	"github.com/spf13/cobra"

	hostmod "github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host/sshkeys"
)

var (
	uploadSSHHostCerts bool
	sshCertsDir        string
	sshCertsTargetDir  string
	sshCertsAllHosts   bool
	sshCertsReload     bool
)

var hostEnsureSSHHostCertsCmd = &cobra.Command{
	Use:     "ssh-host-certs",
	Aliases: []string{"sshcert"},
	Short:   "Sync a host's SSH host certificates from the repository",
	Long: `Reads the public host certificates committed under hosts/<name>/certs, compares them with the
copies on the host, and writes the ones that differ when --upload is given. Nothing is decrypted:
a certificate is public.

The target is the path sshd names, /etc/ssh/<name>-cert.pub, which is preserved on an impermanence
host. After a write the command validates the configuration with sshd -t and reloads sshd, so a
renewed certificate takes effect with no restart, no rebuild and no dropped connection.

Before writing, the certificate's public key is compared with the deployed private key. A
certificate for another identity is refused, because sshd would log it and silently ignore it.

--all reconciles every host that has a committed certificate; a failing host is reported and the
run continues.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		opts := sshkeys.CertOptions{
			CertDir:   sshCertsDir,
			TargetDir: sshCertsTargetDir,
			Reload:    sshCertsReload,
		}

		if !sshCertsAllHosts {
			return sshkeys.EnsureCerts(repository.Root, host, uploadSSHHostCerts, opts)
		}

		names, err := sshkeys.HostsWithCerts(repository.Root)
		if err != nil {
			return fmt.Errorf("listing hosts with a committed SSH certificate: %w", err)
		}
		if len(names) == 0 {
			return errors.New("no host has a committed SSH host certificate under hosts/*/certs")
		}

		var errs []error
		for _, name := range names {
			h := hostmod.New(name, hostAddress(name))
			if err := sshkeys.EnsureCerts(repository.Root, h, uploadSSHHostCerts, opts); err != nil {
				errs = append(errs, fmt.Errorf("%s: %w", name, err))
			}
		}
		fmt.Printf("%d host(s) reconciled, %d failed\n", len(names), len(errs))
		return errors.Join(errs...)
	},
}

func init() {
	hostEnsureCmd.AddCommand(hostEnsureSSHHostCertsCmd)
	hostEnsureSSHHostCertsCmd.Flags().BoolVar(&uploadSSHHostCerts, "upload", false, "write the certificate to the host when it differs")
	hostEnsureSSHHostCertsCmd.Flags().StringVar(&sshCertsDir, "cert-dir", "", "repo-relative directory holding the certificates (default hosts/<name>/certs)")
	hostEnsureSSHHostCertsCmd.Flags().StringVar(&sshCertsTargetDir, "target-dir", "", "remote directory holding the certificates (default /etc/ssh; a symlink is followed)")
	hostEnsureSSHHostCertsCmd.Flags().BoolVar(&sshCertsReload, "reload", true, "reload sshd after writing a certificate")
	hostEnsureSSHHostCertsCmd.Flags().BoolVar(&sshCertsAllHosts, "all", false, "reconcile every host that has a committed certificate")
}
