// Package cmd holds the cobra command tree of kdn-certs.
package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"

	"kdn-certs/internal/certinfo"
	"kdn-certs/internal/decl"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/generate"
	"kdn-certs/internal/mismatch"
	"kdn-certs/internal/smallstep"
	"kdn-certs/internal/sops"
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
	// SSHSigner signs an SSH user or host certificate. A test injects a fake, so the suite needs no
	// `ssh-keygen` and no CA.
	SSHSigner smallstep.SSHSigner
	// Signer generates keys and creates or signs TLS certificates. A test injects a fake, so the
	// suite needs no `step` and no CA.
	Signer smallstep.Signer
	// Decryptor decrypts a SOPS CA key. A test injects a fake, so the suite needs no `sops`.
	Decryptor sops.Decryptor
	// Encryptor SOPS-encrypts a managed private key. A test injects a fake, so the suite needs no
	// `sops`.
	Encryptor sops.Encryptor
}

// signer returns the injected TLS signer, or the real `step` driver.
func (a *App) signer() smallstep.Signer {
	if a.Signer != nil {
		return a.Signer
	}
	return smallstep.StepCLI{Verbose: a.Options.Verbose, Logf: a.Logf}
}

// encryptor returns the injected encryptor, or the real `sops` driver.
func (a *App) encryptor() sops.Encryptor {
	if a.Encryptor != nil {
		return a.Encryptor
	}
	return sops.CLI{Verbose: a.Options.Verbose, Logf: a.Logf}
}

// sshSigner returns the injected SSH signer, or the real `ssh-keygen` driver.
func (a *App) sshSigner() smallstep.SSHSigner {
	if a.SSHSigner != nil {
		return a.SSHSigner
	}
	return smallstep.StepCLI{Verbose: a.Options.Verbose, Logf: a.Logf}
}

// decryptor returns the injected decryptor, or the real `sops` driver.
func (a *App) decryptor() sops.Decryptor {
	if a.Decryptor != nil {
		return a.Decryptor
	}
	return sops.CLI{Verbose: a.Options.Verbose, Logf: a.Logf}
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

// loadTargets walks the flake. A target whose subtree fails to evaluate is reported through the
// returned Result, not as an error, so the caller still acts on the readable targets.
func (a *App) loadTargets() (walk.Result, error) {
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

// reportFailures prints each failed target to the error stream. It runs before the command output,
// so a partial run names what it skipped. `--json` keeps the failures in the machine-readable
// payload instead, so this print is skipped there.
func (a *App) reportFailures(failures []walk.Failure) {
	if len(failures) == 0 {
		return
	}
	for _, failure := range failures {
		fmt.Fprintf(a.Err, "target %s failed: %s\n", failure.Target, failure.Error)
	}
}

// existingCert reads the committed public certificate of one certificate declaration. A missing
// file returns nil, which `mismatch.Decide` reads as "no certificate yet". The read is pure Go, so
// `plan` and `status` report the same reason `apply` does.
func (a *App) existingCert(cert decl.Cert) (*certinfo.Info, error) {
	rel := filepath.Join(cert.Directory, cert.CertFile)
	abs := rel
	if !filepath.IsAbs(rel) {
		abs = filepath.Join(a.Options.Flake, rel)
	}
	return certinfo.Read(abs)
}

// decide returns the regeneration reason of one certificate, reading the committed certificate the
// same way `apply` does. `caCommonName` is the declared common name of the signing CA, which the
// caller reads from the merged CA graph.
func (a *App) decide(cert decl.Cert, caCommonName string, force bool) (mismatch.Reason, error) {
	existing, err := a.existingCert(cert)
	if err != nil {
		return mismatch.ReasonNone, err
	}
	return mismatch.Decide(cert, existing, caCommonName, force)
}

// planEntry is one line of the plan output.
type planEntry struct {
	Name     string `json:"name"`
	CA       string `json:"ca"`
	Type     string `json:"type"`
	CertPath string `json:"certPath"`
	Reason   string `json:"reason"`
}

// printPlan prints the plan as JSON or as a table. The failures join the JSON payload, so a machine
// reader sees which targets were skipped.
func (a *App) printPlan(entries []planEntry, failures []walk.Failure) error {
	if a.Options.JSON {
		encoder := json.NewEncoder(a.Out)
		encoder.SetIndent("", "  ")
		return encoder.Encode(planResponse{Entries: entries, Failures: failures})
	}

	a.reportFailures(failures)

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

// failuresError returns one aggregate error when a target failed, or nil when every target was
// readable. The command still printed the readable work before this error, so the exit code is 1
// and the partial action stands.
func failuresError(failures []walk.Failure) error {
	if len(failures) == 0 {
		return nil
	}
	return walk.Result{Failures: failures}.Err()
}

// printApplyJSON prints the apply result as JSON.
func (a *App) printApplyJSON(out generate.Result) error {
	encoder := json.NewEncoder(a.Out)
	encoder.SetIndent("", "  ")
	return encoder.Encode(out)
}

// dedupCerts walks the flake and returns the deduplicated certificate set plus the per-target
// failures of the walk. The caller decides whether a failure becomes a non-zero exit.
func (a *App) dedupCerts() (dedup.Result, []walk.Failure, error) {
	result, err := a.loadTargets()
	if err != nil {
		return dedup.Result{}, nil, err
	}
	return dedup.Merge(result.Targets), result.Failures, nil
}
