package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/dag"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/generate"
	"kdn-certs/internal/walk"
)

// applyResponse is the `apply --json` payload. It carries the generation result and the per-target
// failures, so a machine reader sees both.
type applyResponse struct {
	Result   generate.Result `json:"result"`
	Failures []walk.Failure  `json:"failures"`
}

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

			cas, err := walk.MergeCAs(targets.Targets)
			if err != nil {
				return err
			}
			// The topological sort validates the graph: a cycle and a dangling parent are hard
			// errors. The leaves are processed in the deterministic dedup order, so a second run
			// with no change writes nothing.
			if _, err := dag.Sort(cas); err != nil {
				return err
			}

			result := dedup.Merge(targets.Targets)

			deps := generate.Deps{
				Root:      app.Options.Flake,
				Signer:    app.signer(),
				Decryptor: app.decryptor(),
				Encryptor: app.encryptor(),
				Force:     app.Options.Force,
				DryRun:    app.Options.DryRun,
				Logf:      app.Logf,
			}

			out, err := generate.Run(cas, result, deps)
			if err != nil {
				return err
			}

			if app.Options.JSON {
				encoder := json.NewEncoder(app.Out)
				encoder.SetIndent("", "  ")
				if err := encoder.Encode(applyResponse{Result: out, Failures: targets.Failures}); err != nil {
					return err
				}
				return failuresError(targets.Failures)
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
				if err := app.printPlan(entries, targets.Failures); err != nil {
					return err
				}
				return failuresError(targets.Failures)
			}

			app.reportFailures(targets.Failures)
			fmt.Fprintf(app.Out, "generated %d of %d certificates\n", out.Generated, len(out.Actions))
			return failuresError(targets.Failures)
		},
	}
}
