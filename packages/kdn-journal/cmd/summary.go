package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"kdn-journal/internal/board"
	"kdn-journal/internal/journal"
	"kdn-journal/internal/render"
	"kdn-journal/internal/task"
)

func newSummaryCmd(app *App) *cobra.Command {
	var (
		sessionFlag string
		taskFlag    string
		all         bool
		track       string
		tail        int
		full        bool
		limit       int
	)
	cmd := &cobra.Command{
		Use:   "summary",
		Short: "Print where the work stands",
		Long:  "Print the newest session (or --session), its main board, one line per track board, the last worklog headings and, with --task, a task pair.",
		RunE: func(cmd *cobra.Command, args []string) error {
			store, err := app.loadStore()
			if err != nil {
				return err
			}
			if all {
				sessions := store.Sessions
				if !full && limit > 0 && len(sessions) > limit {
					sessions = sessions[:limit]
				}
				if app.JSON {
					return app.writeJSON("summary", map[string]any{"sessions": sessions}, nil)
				}
				return render.Sessions(app.Out, app.renderOptions(full, tail), sessions, limit)
			}
			session, matches, err := selectSession(store, sessionFlag)
			if err != nil {
				return err
			}
			if session == nil {
				return fmt.Errorf("no sessions found under %s", filepath.Join(app.Root, ".cache", "agents"))
			}
			var taskItem *task.Task
			if taskFlag != "" {
				tree, err := app.loadTree()
				if err != nil {
					return err
				}
				taskItem, err = tree.Find(taskFlag)
				if err != nil {
					return err
				}
			}
			if app.JSON {
				data := map[string]any{"session": session}
				if taskItem != nil {
					data["task"] = taskItem
				}
				return app.writeJSON("summary", data, nil)
			}
			o := app.renderOptions(full, tail)
			o.RunCount = len(matches)
			if track != "" {
				b, err := findTrack(session, track)
				if err != nil {
					return err
				}
				return render.Board(app.Out, o, b)
			}
			return render.Summary(app.Out, o, session, taskItem)
		},
	}
	cmd.Flags().StringVar(&sessionFlag, "session", "", "session directory, id, id prefix, or id@YYYYMMDD")
	cmd.Flags().StringVar(&taskFlag, "task", "", "task directory or slug to include")
	cmd.Flags().BoolVar(&all, "all", false, "one compact line per session, newest first")
	cmd.Flags().StringVar(&track, "track", "", "show one board-<track>.md in full")
	cmd.Flags().IntVar(&tail, "tail", 5, "number of worklog headings to print")
	cmd.Flags().BoolVar(&full, "full", false, "remove item and worklog limits")
	cmd.Flags().IntVar(&limit, "limit", 20, "maximum sessions for --all")
	return cmd
}

func selectSession(store *journal.Store, selector string) (*journal.Session, []*journal.Session, error) {
	if selector == "" {
		if id := os.Getenv("OPENCODE_SESSION_ID"); id != "" {
			if session, matches, err := store.Find(id); err == nil {
				return session, matches, nil
			}
		}
		return store.Newest(), nil, nil
	}
	return store.Find(selector)
}

func findTrack(session *journal.Session, name string) (*board.Board, error) {
	name = strings.TrimSuffix(name, ".md")
	name = strings.TrimPrefix(name, "board-")
	for _, b := range session.Boards {
		base := strings.TrimSuffix(filepath.Base(b.Path), ".md")
		if base == "board-"+name || base == name {
			return b, nil
		}
	}
	var names []string
	for _, b := range session.Boards {
		names = append(names, filepath.Base(b.Path))
	}
	return nil, fmt.Errorf("track %q not found; boards: %s", name, strings.Join(names, ", "))
}
