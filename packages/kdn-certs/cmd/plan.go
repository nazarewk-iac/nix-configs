package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/mismatch"
)

// newPlanCmd builds `kdn-certs plan`.
func newPlanCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "plan",
		Short: "Walk every target and print what would be generated",
		Long:  "Walk every declaration site, enumerate and deduplicate the declarations, and print what would change.",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.dedupCerts()
			if err != nil {
				return err
			}

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

			if app.Options.Verbose {
				for _, duplicate := range result.Duplicates {
					fmt.Fprintf(app.Err, "duplicate %s in %s, dropped\n", duplicate.Name, duplicate.Target)
				}
			}

			return app.printPlan(entries)
		},
	}
}
