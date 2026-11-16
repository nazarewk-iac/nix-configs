// Package cmd holds the cobra command tree of kdn-jj-meta.
package cmd

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/spf13/cobra"

	"kdn-jj-meta/internal/jj"
)

// App is the shared state of one CLI run.
type App struct {
	JSON    bool
	Dir     string
	Version string
	Out     io.Writer
	Err     io.Writer
	Now     func() time.Time
	Getenv  func(string) string
	Skill   string
	Runner  jj.Runner
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

// Issue is one diagnostic of a JSON run.
type Issue struct {
	Code     string `json:"code"`
	Message  string `json:"message"`
	ChangeID string `json:"change_id,omitempty"`
	Severity string `json:"severity"`
}

// NewRoot builds the root command with the real output streams and the real jj binary.
func NewRoot(version, skill string) *cobra.Command {
	return NewRootWithApp(&App{
		Version: version,
		Skill:   skill,
		Out:     os.Stdout,
		Err:     os.Stderr,
		Now:     time.Now,
		Getenv:  os.Getenv,
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
	root := &cobra.Command{
		Use:   "kdn-jj-meta",
		Short: "Attribute jj changes to the agent session that produced them",
		Long: "kdn-jj-meta appends attribution trailers to the description of a mutable jj change.\n" +
			"It discovers the harness and session from the environment, adds only the lines that are\n" +
			"missing, deduplicates them, and never deletes or rewrites existing metadata.",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	jsonFlag := app.JSON
	dirFlag := app.Dir
	root.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
		app.JSON = jsonFlag
		app.Dir = dirFlag
		if cmd.Name() == "version" || cmd.Name() == "completion" || cmd.Name() == "help" {
			return nil
		}
		if app.Runner == nil {
			app.Runner = &jj.CLI{Dir: dirFlag}
		}
		return nil
	}
	flags := root.PersistentFlags()
	flags.BoolVar(&jsonFlag, "json", jsonFlag, "print machine-readable JSON")
	flags.StringVar(&dirFlag, "dir", dirFlag, "run jj in this directory")
	root.AddCommand(
		newAttributeCmd(app),
		newShowCmd(app),
		newListCmd(app),
		newCheckCmd(app),
		newSkillCmd(app),
		newVersionCmd(app),
	)
	return root
}

type envelope struct {
	SchemaVersion int     `json:"schema_version"`
	Command       string  `json:"command"`
	GeneratedAt   string  `json:"generated_at"`
	Data          any     `json:"data"`
	Issues        []Issue `json:"issues"`
}

func (a *App) writeJSON(command string, data any, issues []Issue) error {
	if data == nil {
		data = map[string]any{}
	}
	if issues == nil {
		issues = []Issue{}
	}
	enc := json.NewEncoder(a.Out)
	enc.SetIndent("", "  ")
	return enc.Encode(envelope{
		SchemaVersion: 1,
		Command:       command,
		GeneratedAt:   a.Now().Format(time.RFC3339),
		Data:          data,
		Issues:        issues,
	})
}

func (a *App) warnf(format string, args ...any) {
	fmt.Fprintf(a.Err, "kdn-jj-meta: warning: "+format+"\n", args...)
}

// AsExitError reports the explicit exit code of err, if any.
func AsExitError(err error) (*ExitError, bool) {
	var target *ExitError
	if errors.As(err, &target) {
		return target, true
	}
	return nil, false
}

// shortID prints the leading part of a change ID. jj accepts any unique prefix.
func shortID(id string) string {
	const width = 12
	if len(id) <= width {
		return id
	}
	return id[:width]
}
