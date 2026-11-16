package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newVersionCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print the version",
		RunE: func(cmd *cobra.Command, args []string) error {
			if app.JSON {
				return app.writeJSON("version", map[string]string{"version": app.Version}, nil)
			}
			fmt.Fprintf(app.Out, "kdn-jj-meta %s\n", app.Version)
			return nil
		},
	}
}
