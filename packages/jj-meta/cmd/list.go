package cmd

import (
	"context"
	"fmt"
	"strings"
	"text/tabwriter"

	"github.com/spf13/cobra"

	"jj-meta/internal/trailer"
)

type listEntry struct {
	ChangeID    string   `json:"change_id"`
	CommitID    string   `json:"commit_id"`
	Mutable     bool     `json:"mutable"`
	AssistedBy  []string `json:"assisted_by"`
	GeneratedBy []string `json:"generated_by"`
	SessionIDs  []string `json:"session_ids"`
	Harness     []string `json:"harness"`
	Model       []string `json:"model"`
	Missing     []string `json:"missing"`
}

func newListCmd(app *App) *cobra.Command {
	var (
		revset  string
		missing bool
	)
	cmd := &cobra.Command{
		Use:   "list",
		Short: "List changes with their trailer state",
		RunE: func(cmd *cobra.Command, args []string) error {
			if revset == "" {
				revset = "@"
			}
			return app.list(revset, missing)
		},
	}
	cmd.Flags().StringVar(&revset, "revset", "", "changes to inspect (default: @)")
	cmd.Flags().BoolVar(&missing, "missing", false, "only changes without Assisted-by")
	return cmd
}

func (a *App) list(revset string, missingOnly bool) error {
	changes, err := a.Runner.Changes(context.Background(), revset)
	if err != nil {
		return err
	}
	entries := make([]listEntry, 0, len(changes))
	for _, change := range changes {
		doc := trailer.Parse(change.Description)
		entry := listEntry{
			ChangeID:    change.ChangeID,
			CommitID:    change.CommitID,
			Mutable:     !change.Immutable,
			AssistedBy:  nonNil(doc.Values("Assisted-by")),
			GeneratedBy: nonNil(doc.Values("Generated-by")),
			SessionIDs:  nonNil(doc.Values("Session-Id")),
			Harness:     nonNil(doc.Values("Harness")),
			Model:       nonNil(doc.Values("Model")),
		}
		if !doc.Has("Assisted-by") && !doc.Has("Generated-by") {
			entry.Missing = append(entry.Missing, "Assisted-by")
		}
		if missingOnly && len(entry.Missing) == 0 {
			continue
		}
		entries = append(entries, entry)
	}
	if a.JSON {
		return a.writeJSON("list", map[string]any{"revset": revset, "changes": entries}, nil)
	}
	w := tabwriter.NewWriter(a.Out, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "CHANGE\tSTATE\tATTRIBUTION")
	for _, entry := range entries {
		fmt.Fprintf(w, "%s\t%s\t%s\n", shortID(entry.ChangeID), state(entry.Mutable), attributionSummary(entry))
	}
	return w.Flush()
}

func state(mutable bool) string {
	if mutable {
		return "mutable"
	}
	return "immutable"
}

func attributionSummary(entry listEntry) string {
	var parts []string
	parts = append(parts, entry.AssistedBy...)
	parts = append(parts, entry.GeneratedBy...)
	if len(parts) == 0 {
		parts = append(parts, "-")
	}
	out := strings.Join(parts, ", ")
	if len(entry.SessionIDs) > 0 {
		out += " (" + strings.Join(entry.SessionIDs, ", ") + ")"
	}
	return out
}

func nonNil(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}
