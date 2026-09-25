package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/mismatch"
)

// newStatusCmd builds `kdn-certs status`.
func newStatusCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Report each certificate as valid, expiring or mismatched",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.dedupCerts()
			if err != nil {
				return err
			}
			for _, cert := range result.Sorted() {
				reason, err := mismatch.Decide(cert, nil, cert.CA, false)
				if err != nil {
					return err
				}
				state := "valid"
				if reason != mismatch.ReasonNone {
					state = string(reason)
				}
				fmt.Fprintf(app.Out, "%s\t%s\t%s\n", cert.Name, cert.Type, state)
			}
			return nil
		},
	}
}
