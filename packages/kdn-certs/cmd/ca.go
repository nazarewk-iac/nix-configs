package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/dag"
	"kdn-certs/internal/walk"
)

// newCACmd builds `kdn-certs ca`.
func newCACmd(app *App) *cobra.Command {
	caCmd := &cobra.Command{
		Use:   "ca",
		Short: "Manage the CA graph",
	}

	caCmd.AddCommand(
		&cobra.Command{
			Use:   "init",
			Short: "Initialize the CA graph from the top",
			Long:  "Initialize the CA DAG from the top: root first, then each intermediate.",
			RunE: func(cmd *cobra.Command, args []string) error {
				targets, err := app.loadTargets()
				if err != nil {
					return err
				}
				cas, err := walk.MergeCAs(targets)
				if err != nil {
					return err
				}
				order, err := dag.Sort(cas)
				if err != nil {
					return err
				}
				for _, name := range order {
					fmt.Fprintf(app.Out, "%s\t%s\t%s\n", name, cas[name].Type, cas[name].CommonName)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "sign <cert>",
			Short: "Sign one leaf certificate",
			Long:  "Sign one leaf. Prompt for the YubiKey touch when the CA key needs it.",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				result, err := app.dedupCerts()
				if err != nil {
					return err
				}
				for _, cert := range result.Sorted() {
					if cert.Name == args[0] {
						fmt.Fprintf(app.Out, "sign %s with CA %s\n", cert.Name, cert.CA)
						return nil
					}
				}
				return fmt.Errorf("no certificate named %q", args[0])
			},
		},
	)

	return caCmd
}
