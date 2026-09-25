package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/dag"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/generate"
	"kdn-certs/internal/smallstep"
	"kdn-certs/internal/sops"
	"kdn-certs/internal/walk"
)

// newApplyCmd builds `kdn-certs apply`.
func newApplyCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "apply",
		Short: "Generate or regenerate every certificate",
		Long:  "Generate or regenerate every declared certificate. Decrypt the CA key on demand, sign each leaf, and SOPS-encrypt the private key.",
		RunE: func(cmd *cobra.Command, args []string) error {
			targets, err := app.loadTargets()
			if err != nil {
				return err
			}

			cas, err := walk.MergeCAs(targets)
			if err != nil {
				return err
			}
			// The topological sort validates the graph: a cycle and a dangling parent are hard
			// errors. The leaves are processed in the deterministic dedup order, so a second run
			// with no change writes nothing.
			if _, err := dag.Sort(cas); err != nil {
				return err
			}

			result := dedup.Merge(targets)

			deps := generate.Deps{
				Root:      app.Options.Flake,
				Signer:    smallstep.StepCLI{Verbose: app.Options.Verbose, Logf: app.Logf},
				Decryptor: sops.CLI{Verbose: app.Options.Verbose, Logf: app.Logf},
				Encryptor: sops.CLI{Verbose: app.Options.Verbose, Logf: app.Logf},
				Force:     app.Options.Force,
				DryRun:    app.Options.DryRun,
				Logf:      app.Logf,
			}

			out, err := generate.Run(cas, result, deps)
			if err != nil {
				return err
			}

			if app.Options.JSON {
				return app.printApplyJSON(out)
			}
			if app.Options.DryRun {
				entries := make([]planEntry, 0, len(out.Actions))
				for _, action := range out.Actions {
					entries = append(entries, planEntry{
						Name:     action.Name,
						CA:       action.CA,
						Type:     action.Type,
						CertPath: action.CertPath,
						Reason:   string(action.Reason),
					})
				}
				return app.printPlan(entries)
			}

			fmt.Fprintf(app.Out, "generated %d of %d certificates\n", out.Generated, len(out.Actions))
			return nil
		},
	}
}
