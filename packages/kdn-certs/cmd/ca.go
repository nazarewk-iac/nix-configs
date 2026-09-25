package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/cainit"
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
			Long:  "Initialize the CA DAG from the top: root first, then each intermediate. Generate each managed key, create the self-signed root or the intermediate, write the public certificate, and SOPS-encrypt the private key. An external CA is left alone.",
			RunE: func(cmd *cobra.Command, args []string) error {
				return runCAInit(app)
			},
		},
		&cobra.Command{
			Use:   "sign <cert>",
			Short: "Sign one leaf certificate",
			Long:  "Sign one leaf. Prompt for the YubiKey touch when the CA key needs it.",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				result, failures, err := app.dedupCerts()
				if err != nil {
					return err
				}
				app.reportFailures(failures)
				for _, cert := range result.Sorted() {
					if cert.Name == args[0] {
						fmt.Fprintf(app.Out, "sign %s with CA %s\n", cert.Name, cert.CA)
						return failuresError(failures)
					}
				}
				if err := failuresError(failures); err != nil {
					return err
				}
				return fmt.Errorf("no certificate named %q", args[0])
			},
		},
	)

	return caCmd
}

// runCAInit walks the CA graph and creates every managed CA.
func runCAInit(app *App) error {
	targets, err := app.loadTargets()
	if err != nil {
		return err
	}
	cas, err := walk.MergeCAs(targets.Targets)
	if err != nil {
		return err
	}
	// The topological sort validates the graph: a cycle and a dangling parent are hard errors.
	if _, err := dag.Sort(cas); err != nil {
		return err
	}

	deps := cainit.Deps{
		Root:      app.Options.Flake,
		Signer:    app.signer(),
		Decryptor: app.decryptor(),
		Encryptor: app.encryptor(),
		Force:     app.Options.Force,
		DryRun:    app.Options.DryRun,
		Logf:      app.Logf,
	}

	out, err := cainit.Run(cas, deps)
	if err != nil {
		return err
	}

	if app.Options.JSON {
		encoder := json.NewEncoder(app.Out)
		encoder.SetIndent("", "  ")
		return encoder.Encode(out)
	}

	app.reportFailures(targets.Failures)
	for _, action := range out.Actions {
		fmt.Fprintf(app.Out, "%s\t%s\t%s\t%s\n", action.Name, action.Type, action.CommonName, action.Reason)
	}
	if app.Options.DryRun {
		return failuresError(targets.Failures)
	}
	fmt.Fprintf(app.Out, "created %d of %d CAs\n", out.Created, len(out.Actions))
	return failuresError(targets.Failures)
}
