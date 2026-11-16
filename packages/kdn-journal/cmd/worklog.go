package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"kdn-journal/internal/render"
	"kdn-journal/internal/worklog"
)

func newWorklogCmd(app *App) *cobra.Command {
	var (
		track     string
		tail      int
		raw       bool
		printPath bool
	)
	cmd := &cobra.Command{
		Use:   "worklog <path>",
		Short: "Parse and show one worklog",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			path, err := resolveWorklogPath(app.Root, args[0], track)
			if err != nil {
				return err
			}
			if printPath {
				_, err := fmt.Fprintln(app.Out, path)
				return err
			}
			if raw {
				data, err := os.ReadFile(path)
				if err != nil {
					return err
				}
				_, err = app.Out.Write(data)
				return err
			}
			wl, err := worklog.ParseFile(path)
			if err != nil {
				return err
			}
			if app.JSONL {
				return app.writeJSONL([]any{wl})
			}
			if app.JSON {
				return app.writeJSON("worklog", map[string]any{"worklog": wl}, nil)
			}
			return render.Worklog(app.Out, app.renderOptions(false, tail), wl, tail)
		},
	}
	cmd.Flags().StringVar(&track, "track", "", "select worklog-<track>.md")
	cmd.Flags().IntVar(&tail, "tail", 10, "number of entries to print")
	cmd.Flags().BoolVar(&raw, "raw", false, "print the file unchanged")
	cmd.Flags().BoolVar(&printPath, "print-path", false, "print the resolved path and exit")
	return cmd
}

func resolveWorklogPath(root, arg, track string) (string, error) {
	if !filepath.IsAbs(arg) {
		arg = filepath.Join(root, arg)
	}
	info, err := os.Stat(arg)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return arg, nil
	}
	var candidates []string
	if track != "" {
		name := strings.TrimSuffix(track, ".md")
		name = strings.TrimPrefix(name, "worklog-")
		candidates = []string{
			filepath.Join(arg, "worklog-"+name+".md"),
			filepath.Join(arg, name+".md"),
		}
	} else {
		candidates = []string{
			filepath.Join(arg, "worklog.md"),
			filepath.Join(arg, ".worklog.md"),
		}
	}
	for _, path := range candidates {
		if fileExists(path) {
			return path, nil
		}
	}
	return "", fmt.Errorf("no worklog in %s; tried %s", arg, strings.Join(candidates, ", "))
}
