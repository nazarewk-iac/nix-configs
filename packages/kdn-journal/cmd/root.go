// Package cmd holds the cobra command tree of kdn-journal.
package cmd

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"kdn-journal/internal/atuin"
	"kdn-journal/internal/jjmeta"
	"kdn-journal/internal/jjrun"
	"kdn-journal/internal/journal"
	"kdn-journal/internal/render"
	"kdn-journal/internal/task"
)

// App is the shared state of one CLI run.
type App struct {
	Root    string
	JSON    bool
	NoColor bool
	Width   int
	Version string
	Out     io.Writer
	Err     io.Writer
	Now     func() time.Time
	// Getenv reads the environment. Tests replace it.
	Getenv func(string) string

	// Integration seams. A nil field means the real implementation.
	JJ     jjrun.Runner
	Atuin  atuin.Runner
	JJMeta jjmeta.Attributor
}

// ExitError carries an explicit process exit code.
type ExitError struct {
	Code int
	Err  error
}

func (e *ExitError) Error() string {
	if e.Err != nil {
		return e.Err.Error()
	}
	return fmt.Sprintf("exit %d", e.Code)
}

func (e *ExitError) Unwrap() error { return e.Err }

// NewRoot builds the root command with the real output streams.
func NewRoot(version string) *cobra.Command {
	return NewRootWithApp(&App{
		Version: version,
		Out:     os.Stdout,
		Err:     os.Stderr,
		Width:   100,
		Now:     time.Now,
	})
}

// NewRootWithApp builds the root command over a caller-supplied App.
func NewRootWithApp(app *App) *cobra.Command {
	if app.Out == nil {
		app.Out = os.Stdout
	}
	if app.Err == nil {
		app.Err = os.Stderr
	}
	if app.Now == nil {
		app.Now = time.Now
	}
	if app.Getenv == nil {
		app.Getenv = os.Getenv
	}
	if app.JJ == nil {
		app.JJ = &jjrun.CLI{}
	}
	if app.Atuin == nil {
		app.Atuin = &atuin.CLI{}
	}
	if app.JJMeta == nil {
		app.JJMeta = jjmeta.New("")
	}
	if app.Width <= 0 {
		app.Width = 100
	}
	root := &cobra.Command{
		Use:           "kdn-journal",
		Short:         "Browse repository tasks and agent journals",
		Long:          "kdn-journal reads docs/tasks and .cache/agents, prints a compact summary of where the work stands, and browses tasks, boards and worklogs in a TUI.",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	rootFlag := app.Root
	jsonFlag := app.JSON
	noColorFlag := app.NoColor
	widthFlag := app.Width
	root.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
		app.Root = rootFlag
		app.JSON = jsonFlag
		app.NoColor = noColorFlag
		app.Width = widthFlag
		if cmd.Name() == "version" || strings.HasPrefix(cmd.CommandPath(), "kdn-journal completion") {
			return nil
		}
		return app.resolveRoot()
	}
	flags := root.PersistentFlags()
	flags.StringVar(&rootFlag, "root", rootFlag, "repository root (default: walk up from the current directory)")
	flags.BoolVar(&jsonFlag, "json", jsonFlag, "print machine-readable JSON")
	flags.BoolVar(&noColorFlag, "no-color", noColorFlag, "disable color")
	flags.IntVar(&widthFlag, "width", widthFlag, "output width in columns")
	root.AddCommand(
		newSummaryCmd(app),
		newSessionsCmd(app),
		newSessionCmd(app),
		newAtuinCmd(app),
		newTasksCmd(app),
		newTaskCmd(app),
		newBoardCmd(app),
		newWorklogCmd(app),
		newDoctorCmd(app),
		newTUICmd(app),
		newVersionCmd(app),
	)
	return root
}

func (a *App) resolveRoot() error {
	if a.Root != "" {
		abs, err := filepath.Abs(a.Root)
		if err != nil {
			return err
		}
		if info, err := os.Stat(abs); err != nil || !info.IsDir() {
			return fmt.Errorf("root %q is not a directory", a.Root)
		}
		a.Root = abs
		return nil
	}
	start, err := os.Getwd()
	if err != nil {
		return err
	}
	dir := start
	for {
		if isDir(filepath.Join(dir, "docs", "tasks")) {
			a.Root = dir
			return nil
		}
		if fileExists(filepath.Join(dir, "flake.nix")) &&
			(isDir(filepath.Join(dir, ".jj")) || isDir(filepath.Join(dir, ".git"))) {
			a.Root = dir
			return nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return fmt.Errorf("no repository root found from %s; pass --root", start)
		}
		dir = parent
	}
}

func (a *App) loadTree() (*task.Tree, error) {
	return task.Load(a.Root)
}

func (a *App) loadStore() (*journal.Store, error) {
	return journal.Load(a.Root)
}

func (a *App) renderOptions(full bool, tail int) render.Options {
	return render.Defaults(render.Options{
		Width: a.Width,
		Full:  full,
		Color: a.color(),
		Tail:  tail,
		Now:   a.Now(),
	})
}

func (a *App) color() bool {
	if a.NoColor || a.JSON || os.Getenv("NO_COLOR") != "" {
		return false
	}
	file, ok := a.Out.(*os.File)
	if !ok {
		return false
	}
	return term.IsTerminal(int(file.Fd()))
}

type envelope struct {
	SchemaVersion int          `json:"schema_version"`
	Command       string       `json:"command"`
	Root          string       `json:"root"`
	GeneratedAt   string       `json:"generated_at"`
	Data          any          `json:"data"`
	Issues        []task.Issue `json:"issues"`
}

func (a *App) writeJSON(command string, data any, issues []task.Issue) error {
	if data == nil {
		data = map[string]any{}
	}
	if issues == nil {
		issues = []task.Issue{}
	}
	env := envelope{
		SchemaVersion: 1,
		Command:       command,
		Root:          a.Root,
		GeneratedAt:   a.Now().Format(time.RFC3339),
		Data:          data,
		Issues:        issues,
	}
	enc := json.NewEncoder(a.Out)
	enc.SetIndent("", "  ")
	return enc.Encode(env)
}

func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

// AsExitError reports the explicit exit code of err, if any.
func AsExitError(err error) (*ExitError, bool) {
	var target *ExitError
	if errors.As(err, &target) {
		return target, true
	}
	return nil, false
}
