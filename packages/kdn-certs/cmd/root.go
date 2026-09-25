// Package cmd holds the cobra command tree of kdn-certs.
package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"

	"kdn-certs/internal/decl"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/generate"
	"kdn-certs/internal/walk"
)

// Options holds the global flags, shared by every command.
type Options struct {
	// Flake is the flake to walk.
	Flake string
	// DryRun prints the actions and changes nothing.
	DryRun bool
	// Force regenerates every certificate.
	Force bool
	// JSON prints machine-readable output.
	JSON bool
	// Verbose prints each `nix eval` and each `step` command.
	Verbose bool
}

// App is the shared state of one CLI run.
type App struct {
	Options Options
	// Out is the standard output stream.
	Out io.Writer
	// Err is the standard error stream.
	Err io.Writer
	// In is the standard input stream.
	In io.Reader
	// Evaluator reads the declarations. A test injects a fake, so the suite needs no flake.
	Evaluator walk.Evaluator
}

// Logf prints one verbose line to the error stream.
func (a *App) Logf(format string, args ...any) {
	fmt.Fprintf(a.Err, format+"\n", args...)
}

// NewRoot builds the root command and every sub-command.
func NewRoot() *cobra.Command {
	return NewRootWithApp(&App{Out: os.Stdout, Err: os.Stderr, In: os.Stdin})
}

// NewRootWithApp builds the root command over a caller-supplied App. A test injects a fake
// evaluator and captures the output streams.
func NewRootWithApp(app *App) *cobra.Command {
	root := &cobra.Command{
		Use:           "kdn-certs",
		Short:         "Declarative certificate manager",
		Long:          "kdn-certs walks the certificate declarations of a flake, deduplicates them, and drives smallstep to generate and rotate them.",
		SilenceUsage:  true,
		SilenceErrors: true,
	}

	flags := root.PersistentFlags()
	flags.StringVar(&app.Options.Flake, "flake", ".", "the flake to walk")
	flags.BoolVar(&app.Options.DryRun, "dry-run", false, "print the actions and change nothing")
	flags.BoolVar(&app.Options.Force, "force", false, "regenerate every certificate")
	flags.BoolVar(&app.Options.JSON, "json", false, "print machine-readable output")
	flags.BoolVar(&app.Options.Verbose, "verbose", false, "print each nix eval and each step command")

	root.AddCommand(
		newPlanCmd(app),
		newApplyCmd(app),
		newCACmd(app),
		newSSHCmd(app),
		newStatusCmd(app),
		newDoctorCmd(app),
	)
	return root
}

// loadTargets walks the flake and merges the CA graph.
func (a *App) loadTargets() ([]decl.Target, error) {
	evaluator := a.Evaluator
	if evaluator == nil {
		evaluator = walk.NixEvaluator{
			Flake:   a.Options.Flake,
			Verbose: a.Options.Verbose,
			Logf:    a.Logf,
		}
	}
	return walk.Walk(evaluator)
}

// planEntry is one line of the plan output.
type planEntry struct {
	Name     string `json:"name"`
	CA       string `json:"ca"`
	Type     string `json:"type"`
	CertPath string `json:"certPath"`
	Reason   string `json:"reason"`
}

// printPlan prints the plan as JSON or as a table.
func (a *App) printPlan(entries []planEntry) error {
	if a.Options.JSON {
		encoder := json.NewEncoder(a.Out)
		encoder.SetIndent("", "  ")
		return encoder.Encode(entries)
	}

	if len(entries) == 0 {
		fmt.Fprintln(a.Out, "no certificates declared")
		return nil
	}

	header := lipgloss.NewStyle().Bold(true)
	fmt.Fprintf(a.Out, "%s\n", header.Render(fmt.Sprintf("%-24s %-16s %-12s %s", "NAME", "CA", "TYPE", "REASON")))
	for _, entry := range entries {
		fmt.Fprintf(a.Out, "%-24s %-16s %-12s %s\n", entry.Name, entry.CA, entry.Type, entry.Reason)
	}
	return nil
}

// printApplyJSON prints the apply result as JSON.
func (a *App) printApplyJSON(out generate.Result) error {
	encoder := json.NewEncoder(a.Out)
	encoder.SetIndent("", "  ")
	return encoder.Encode(out)
}

// dedupCerts walks the flake and returns the deduplicated certificate set.
func (a *App) dedupCerts() (dedup.Result, error) {
	targets, err := a.loadTargets()
	if err != nil {
		return dedup.Result{}, err
	}
	return dedup.Merge(targets), nil
}
