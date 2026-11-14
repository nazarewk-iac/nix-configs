package cmd

import (
	"os"

	"github.com/spf13/cobra"

	"kdn-journal/internal/journal"
	"kdn-journal/internal/task"
	"kdn-journal/internal/tui"
)

func newTUICmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "tui",
		Short: "Browse tasks and sessions interactively",
		RunE: func(cmd *cobra.Command, args []string) error {
			tree, err := app.loadTree()
			if err != nil {
				return err
			}
			store, err := app.loadStore()
			if err != nil {
				return err
			}
			return tui.Run(tui.Deps{
				Root:   app.Root,
				Tree:   tree,
				Store:  store,
				Width:  app.Width,
				Height: 30,
				Editor: os.Getenv("EDITOR"),
				Reload: func() (*task.Tree, *journal.Store, error) {
					tree, err := task.Load(app.Root)
					if err != nil {
						return nil, nil, err
					}
					store, err := journal.Load(app.Root)
					if err != nil {
						return nil, nil, err
					}
					return tree, store, nil
				},
			})
		},
	}
}
