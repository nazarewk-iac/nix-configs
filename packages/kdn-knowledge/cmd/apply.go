package cmd

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"kdn-knowledge/internal/apply"
	"kdn-knowledge/internal/dream"
	"kdn-knowledge/internal/store"
)

type applySummary struct {
	Proposal   string       `json:"proposal"`
	Bundle     string       `json:"bundle"`
	Written    []string     `json:"written"`
	Skipped    []apply.Skip `json:"skipped"`
	RolledBack bool         `json:"rolled_back"`
	Validation string       `json:"validation,omitempty"`
	Confirmed  bool         `json:"confirmed"`
}

func (a *App) runApply(args []string) error {
	fs := flag.NewFlagSet("apply", flag.ContinueOnError)
	fs.SetOutput(a.errOut)
	a.commonFlags(fs)
	var proposalDir string
	var yes bool
	fs.StringVar(&proposalDir, "proposal", "", "proposal directory (default: the newest one)")
	fs.BoolVar(&yes, "yes", false, "confirm the copy into the bundle")
	if err := a.parse(fs, args); err != nil {
		return err
	}
	cfg, err := a.prepare()
	if err != nil {
		return err
	}
	if proposalDir == "" {
		proposalDir, err = newestProposal(cfg.Store)
		if err != nil {
			return err
		}
	}
	planPath := filepath.Join(proposalDir, "plan.json")
	var plan dream.Plan
	if err := store.ReadJSON(planPath, &plan); err != nil {
		return &ExitError{Code: 1, Err: fmt.Errorf("cannot read %s: %w", planPath, err)}
	}
	summary := applySummary{
		Proposal: proposalDir,
		Bundle:   cfg.Bundle,
		Written:  []string{},
		Skipped:  []apply.Skip{},
	}
	if !yes {
		a.progressf("apply: %d actions in %s; pass --yes to copy them into %s",
			len(plan.Actions), proposalDir, cfg.Bundle)
		return &ExitError{Code: 1, Err: errors.New(
			"apply needs --yes: it writes into the memory bundle, which has one writer")}
	}
	summary.Confirmed = true

	result, err := apply.Run(cfg.Bundle, proposalDir, &plan)
	summary.Written = result.Written
	summary.Skipped = result.Skipped
	summary.RolledBack = result.RolledBack
	summary.Validation = result.Validation
	if err != nil {
		return &ExitError{Code: 1, Err: err}
	}
	return a.emit("apply", fmt.Sprintf("apply: %d written, %d skipped, bundle %s",
		len(result.Written), len(result.Skipped), cfg.Bundle), summary)
}

// newestProposal returns the newest directory under proposals/.
func newestProposal(st *store.Store) (string, error) {
	entries, err := os.ReadDir(st.ProposalsDir())
	if err != nil {
		return "", err
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			names = append(names, entry.Name())
		}
	}
	if len(names) == 0 {
		return "", &ExitError{Code: 1, Err: errors.New("no proposal directory; run dream first")}
	}
	sort.Strings(names)
	return filepath.Join(st.ProposalsDir(), names[len(names)-1]), nil
}
