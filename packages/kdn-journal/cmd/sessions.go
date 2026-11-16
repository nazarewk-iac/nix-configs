package cmd

import (
	"strings"

	"github.com/spf13/cobra"

	"kdn-journal/internal/journal"
	"kdn-journal/internal/render"
)

func newSessionsCmd(app *App) *cobra.Command {
	var (
		harness string
		limit   int
		all     bool
	)
	cmd := &cobra.Command{
		Use:     "sessions",
		Aliases: []string{"journals"},
		Short:   "List agent session journals",
		RunE: func(cmd *cobra.Command, args []string) error {
			store, err := app.loadStore()
			if err != nil {
				return err
			}
			sessions := store.Sessions
			if harness != "" {
				filtered := make([]*journal.Session, 0, len(sessions))
				for _, session := range sessions {
					if strings.EqualFold(session.Harness, harness) {
						filtered = append(filtered, session)
					}
				}
				sessions = filtered
			}
			if app.JSONL {
				items := make([]any, 0, len(sessions))
				for _, session := range sessions {
					items = append(items, session)
				}
				return app.writeJSONL(items)
			}
			if app.JSON {
				return app.writeJSON("sessions", map[string]any{"sessions": sessions}, nil)
			}
			return render.Sessions(app.Out, app.renderOptions(all, 0), sessions, limit)
		},
	}
	cmd.Flags().StringVar(&harness, "harness", "", "only this harness (opencode, pi, claude, codex)")
	cmd.Flags().IntVar(&limit, "limit", 20, "maximum sessions to print")
	cmd.Flags().BoolVar(&all, "all", false, "print every session")
	return cmd
}
