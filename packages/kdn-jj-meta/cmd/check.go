package cmd

import (
	"context"
	"fmt"
	"strings"

	"github.com/spf13/cobra"

	"kdn-jj-meta/internal/trailer"
)

type checkEntry struct {
	ChangeID string   `json:"change_id"`
	CommitID string   `json:"commit_id"`
	Mutable  bool     `json:"mutable"`
	Skipped  bool     `json:"skipped,omitempty"`
	Errors   []string `json:"errors"`
	Warnings []string `json:"warnings"`
}

type checkData struct {
	Revset       string       `json:"revset"`
	Require      []string     `json:"require"`
	Changes      []checkEntry `json:"changes"`
	ErrorCount   int          `json:"error_count"`
	WarningCount int          `json:"warning_count"`
}

func newCheckCmd(app *App) *cobra.Command {
	var (
		revset  string
		require []string
	)
	cmd := &cobra.Command{
		Use:   "check",
		Short: "Fail when a change is missing a required disclosure trailer",
		Long: "Check the changes a revset matches for the required disclosure trailers.\n\n" +
			"Assisted-by is always required. Pass --require coauthor for a project that also wants\n" +
			"the GitHub Co-authored-by convention. Use --revset 'main..@' as a pre-push gate.",
		RunE: func(cmd *cobra.Command, args []string) error {
			if revset == "" {
				revset = "@"
			}
			return app.check(revset, require)
		},
	}
	cmd.Flags().StringVar(&revset, "revset", "", "changes to check (default: @)")
	cmd.Flags().StringArrayVar(&require, "require", nil, "extra required trailer: coauthor")
	return cmd
}

func (a *App) check(revset string, require []string) error {
	wantCoauthor := false
	for _, name := range require {
		switch strings.ToLower(strings.TrimSpace(name)) {
		case "coauthor", "co-authored-by":
			wantCoauthor = true
		default:
			return fmt.Errorf("unknown requirement %q; use coauthor", name)
		}
	}
	changes, err := a.Runner.Changes(context.Background(), revset)
	if err != nil {
		return err
	}
	data := checkData{Revset: revset, Require: []string{}, Changes: []checkEntry{}}
	if wantCoauthor {
		data.Require = append(data.Require, "coauthor")
	}
	var issues []Issue
	for _, change := range changes {
		if strings.TrimSpace(change.Description) == "" {
			entry := checkEntry{
				ChangeID: change.ChangeID,
				CommitID: change.CommitID,
				Mutable:  !change.Immutable,
				Skipped:  true,
				Errors:   []string{},
				Warnings: []string{},
			}
			data.Changes = append(data.Changes, entry)
			if !a.JSON {
				fmt.Fprintf(a.Out, "%s  skipped (empty description)\n", shortID(entry.ChangeID))
			}
			continue
		}
		doc := trailer.Parse(change.Description)
		entry := checkEntry{
			ChangeID: change.ChangeID,
			CommitID: change.CommitID,
			Mutable:  !change.Immutable,
			Errors:   []string{},
			Warnings: []string{},
		}
		if !doc.Has("Assisted-by") {
			entry.Errors = append(entry.Errors, "missing Assisted-by")
		}
		if wantCoauthor && !doc.Has("Co-authored-by") {
			entry.Errors = append(entry.Errors, "missing Co-authored-by")
		}
		for _, message := range entry.Errors {
			issues = append(issues, Issue{Code: "missing-trailer", Message: message, ChangeID: change.ChangeID, Severity: "error"})
		}
		data.ErrorCount += len(entry.Errors)
		data.WarningCount += len(entry.Warnings)
		data.Changes = append(data.Changes, entry)
		if a.JSON {
			continue
		}
		if len(entry.Errors) == 0 {
			fmt.Fprintf(a.Out, "%s  ok\n", shortID(entry.ChangeID))
			continue
		}
		fmt.Fprintf(a.Out, "%s  %s\n", shortID(entry.ChangeID), strings.Join(entry.Errors, ", "))
	}
	if a.JSONL {
		items := make([]any, 0, len(data.Changes))
		for _, entry := range data.Changes {
			items = append(items, entry)
		}
		if err := a.writeJSONL(items); err != nil {
			return err
		}
	} else if a.JSON {
		if err := a.writeJSON("check", data, issues); err != nil {
			return err
		}
	}
	if data.ErrorCount > 0 {
		return &ExitError{Code: 1}
	}
	return nil
}
