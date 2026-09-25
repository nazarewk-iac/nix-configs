package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// newSSHCmd builds `kdn-certs ssh`.
func newSSHCmd(app *App) *cobra.Command {
	sshCmd := &cobra.Command{
		Use:   "ssh",
		Short: "SSH certificate helpers",
	}

	sshCmd.AddCommand(
		&cobra.Command{
			Use:   "login <host>",
			Short: "Generate an SSH user certificate to connect to a host",
			Long:  "Generate an SSH user certificate to connect to a host. Pick the SSH CA and set the principals.",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				host := args[0]
				result, err := app.dedupCerts()
				if err != nil {
					return err
				}
				for _, cert := range result.Sorted() {
					if cert.Type == "ssh-user" && cert.Name == host {
						fmt.Fprintf(app.Out, "ssh -i %s %s\n", cert.KeyFile, host)
						return nil
					}
				}
				return fmt.Errorf("no ssh-user certificate named %q", host)
			},
		},
	)

	return sshCmd
}
