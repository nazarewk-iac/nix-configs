package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/decl"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/walk"
)

// planResponse is the `plan --json` payload. It carries the readable plan entries and the per-target
// failures, so a machine reader sees both.
type planResponse struct {
	Entries  []planEntry    `json:"entries"`
	Failures []walk.Failure `json:"failures"`
}

// newPlanCmd builds `kdn-certs plan`.
func newPlanCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "plan",
		Short: "Walk every target and print what would be generated",
		Long:  "Walk every declaration site, enumerate and deduplicate the declarations, and print what would change.",
		RunE: func(cmd *cobra.Command, args []string) error {
			targets, err := app.loadTargets()
			if err != nil {
				return err
			}
			cas, err := walk.MergeCAs(targets.Targets)
			if err != nil {
				return err
			}
			result := dedup.Merge(targets.Targets)

			entries, err := planEntries(app, result, cas)
			if err != nil {
				return err
			}

			if app.Options.Verbose {
				for _, duplicate := range result.Duplicates {
					fmt.Fprintf(app.Err, "duplicate %s in %s, dropped\n", duplicate.Name, duplicate.Target)
				}
			}

			if err := app.printPlan(entries, targets.Failures); err != nil {
				return err
			}
			return failuresError(targets.Failures)
		},
	}
}

// planEntries decides the reason of every deduplicated certificate, reading the committed
// certificate the same way `apply` does. So a valid certificate reports `""`, not `missing`.
func planEntries(app *App, result dedup.Result, cas decl.CAs) ([]planEntry, error) {
	entries := make([]planEntry, 0, len(result.Certs))
	for _, cert := range result.Sorted() {
		ca, ok := cas[cert.CA]
		if !ok {
			return nil, fmt.Errorf("certificate %q names CA %q, which is not declared", cert.Name, cert.CA)
		}
		reason, err := app.decide(cert, ca.CommonName, app.Options.Force)
		if err != nil {
			return nil, err
		}
		entries = append(entries, planEntry{
			Name:     cert.Name,
			CA:       cert.CA,
			Type:     cert.Type,
			CertPath: cert.Directory + "/" + cert.CertFile,
			Reason:   string(reason),
		})
	}
	return entries, nil
}
