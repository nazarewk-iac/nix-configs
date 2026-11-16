package cmd

import (
	"github.com/spf13/cobra"

	"kdn-okf/internal/okf"
	"kdn-okf/internal/tui"
)

func newTUICmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "tui",
		Short: "Browse the bundle interactively",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.load()
			if err != nil {
				return err
			}
			return tui.Run(tui.Deps{
				Bundle: result.Bundle,
				Width:  app.Width,
				Reload: func() (*okf.Bundle, error) {
					next, err := app.load()
					if err != nil {
						return nil, err
					}
					return next.Bundle, nil
				},
			})
		},
	}
}
