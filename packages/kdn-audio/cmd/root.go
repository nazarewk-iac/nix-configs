// Package cmd holds the cobra command tree of kdn-audio.
package cmd

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"kdn-audio/internal/audio"
	"kdn-audio/internal/bluetooth"
	"kdn-audio/internal/pipewire"
	"kdn-audio/internal/tui"
)

// App is the shared state of one CLI run.
type App struct {
	Out     io.Writer
	Err     io.Writer
	Version string
	JSON    bool
	IsTTY   bool
	Now     func() time.Time
	Manager *audio.Manager
	// LookPath resolves an executable. Tests replace it.
	LookPath func(string) (string, error)
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

// NewRoot builds the command tree with the real clients.
func NewRoot(version string) *cobra.Command {
	return NewRootWithApp(&App{
		Out:     os.Stdout,
		Err:     os.Stderr,
		Version: version,
		IsTTY:   term.IsTerminal(int(os.Stdout.Fd())),
		Now:     time.Now,
	})
}

// NewRootWithApp builds the command tree over a caller-supplied App. Tests replace the clients.
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
	if app.LookPath == nil {
		app.LookPath = exec.LookPath
	}
	if app.Manager == nil {
		app.Manager = audio.New(pipewire.CLI{}, bluetooth.CLI{})
	}
	app.Manager.Now = app.Now
	if app.Manager.Log == nil {
		app.Manager.Log = func(format string, args ...any) {
			fmt.Fprintf(app.Err, "kdn-audio: "+format+"\n", args...)
		}
	}

	root := &cobra.Command{
		Use:   "kdn-audio",
		Short: "Join several audio outputs into one virtual output",
		Long: `kdn-audio plays the same audio on several outputs at once.

An output is a device that makes sound. A join is one extra output that feeds all of its
members. Joining changes no routing: the audio that plays now stays where it plays, and the
default output does not change unless you ask for it.

In one minute:
  kdn-audio devices
  kdn-audio create --name "Both Ears" Earmuffs "JBL Endurance Peak 4"
  kdn-audio unlink-all

Run kdn-audio with no arguments for the full-screen list, or
` + "`kdn-audio intro`" + ` for the plain-language guide.

Every command works on the PipeWire graph directly. Devices are named by a stable id: a
Bluetooth address, an ALSA card and profile, or a node name.`,
		Example: `  kdn-audio                                      # wizard
  kdn-audio devices
  kdn-audio create --name "Both Ears" Earmuffs JBL
  kdn-audio profiles list
  kdn-audio unlink-all`,
		SilenceUsage:  true,
		SilenceErrors: true,
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			// The completion command has one subcommand per shell, so its own name is "bash",
			// not "completion". The command path is the stable test.
			switch {
			case cmd.Name() == "version", cmd.Name() == "help":
				return nil
			case strings.HasPrefix(cmd.CommandPath(), "kdn-audio completion"):
				return nil
			}
			if _, err := app.LookPath("pw-dump"); err != nil {
				return fmt.Errorf("pw-dump is not in PATH; is PipeWire running?")
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) > 0 {
				return fmt.Errorf("unknown command %q", args[0])
			}
			if !app.IsTTY {
				return cmd.Help()
			}
			return tui.Run(app.Manager)
		},
	}
	root.PersistentFlags().BoolVar(&app.JSON, "json", false, "print machine-readable JSON")
	root.AddCommand(
		newDevicesCmd(app),
		newShowCmd(app),
		newCreateCmd(app),
		newRemoveCmd(app),
		newUnlinkAllCmd(app),
		newStatusCmd(app),
		newConnectCmd(app),
		newProfilesCmd(app),
		newDaemonCmd(app),
		newIntroCmd(app),
		newTUICmd(app),
		newHostCmd(app),
		newVersionCmd(app),
	)
	return root
}

type envelope struct {
	SchemaVersion int    `json:"schema_version"`
	Command       string `json:"command"`
	GeneratedAt   string `json:"generated_at"`
	Data          any    `json:"data"`
}

func (a *App) writeJSON(command string, data any) error {
	if data == nil {
		data = map[string]any{}
	}
	encoder := json.NewEncoder(a.Out)
	encoder.SetIndent("", "  ")
	return encoder.Encode(envelope{
		SchemaVersion: 1,
		Command:       command,
		GeneratedAt:   a.Now().Format(time.RFC3339),
		Data:          data,
	})
}

// AsExitError reports the explicit exit code of err, if any.
func AsExitError(err error) (*ExitError, bool) {
	var target *ExitError
	if errors.As(err, &target) {
		return target, true
	}
	return nil, false
}
