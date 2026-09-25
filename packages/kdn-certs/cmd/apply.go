package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/dag"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/mismatch"
	"kdn-certs/internal/walk"
)

// newApplyCmd builds `kdn-certs apply`.
func newApplyCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "apply",
		Short: "Generate or regenerate every certificate",
		Long:  "Generate or regenerate every declared certificate. Start step-ca on demand and tear it down after.",
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

			result := dedup.Merge(targets)
			entries := make([]planEntry, 0, len(result.Certs))
			for _, cert := range result.Sorted() {
				reason, err := mismatch.Decide(cert, nil, cert.CA, app.Options.Force)
				if err != nil {
					return err
				}
				entries = append(entries, planEntry{
					Name:     cert.Name,
					CA:       cert.CA,
					Type:     cert.Type,
					CertPath: cert.Directory + "/" + cert.CertFile,
					Reason:   string(reason),
				})
			}

			if app.Options.DryRun {
				if app.Options.Verbose {
					fmt.Fprintf(app.Err, "CA order: %v\n", order)
				}
				return app.printPlan(entries)
			}

			// The generation itself is driven by the `step` signer. It stays out of the dry run.
			return fmt.Errorf("apply: generation is not wired yet; run with --dry-run to see the plan")
		},
	}
}
