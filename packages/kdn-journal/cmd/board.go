package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"kdn-journal/internal/board"
	"kdn-journal/internal/render"
)

func newBoardCmd(app *App) *cobra.Command {
	var (
		track     string
		raw       bool
		printPath bool
	)
	cmd := &cobra.Command{
		Use:   "board <path>",
		Short: "Parse and show one board",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			path, err := resolveBoardPath(app.Root, args[0], track)
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
			b, err := board.ParseFile(path)
			if err != nil {
				return err
			}
			if app.JSONL {
				return app.writeJSONL([]any{b})
			}
			if app.JSON {
				return app.writeJSON("board", map[string]any{"board": b}, nil)
			}
			return render.Board(app.Out, app.renderOptions(false, 0), b)
		},
	}
	cmd.Flags().StringVar(&track, "track", "", "select board-<track>.md")
	cmd.Flags().BoolVar(&raw, "raw", false, "print the file unchanged")
	cmd.Flags().BoolVar(&printPath, "print-path", false, "print the resolved path and exit")
	return cmd
}

func resolveBoardPath(root, arg, track string) (string, error) {
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
		name = strings.TrimPrefix(name, "board-")
		candidates = []string{
			filepath.Join(arg, "board-"+name+".md"),
			filepath.Join(arg, name+".md"),
		}
	} else {
		candidates = []string{
			filepath.Join(arg, "board.md"),
			filepath.Join(arg, ".board.md"),
		}
	}
	for _, path := range candidates {
		if fileExists(path) {
			return path, nil
		}
	}
	return "", fmt.Errorf("no board in %s; tried %s", arg, strings.Join(candidates, ", "))
}
