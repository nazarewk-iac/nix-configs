package cmd

import (
	"context"
	"fmt"
	"strings"
	"text/tabwriter"

	"github.com/spf13/cobra"

	"kdn-journal/internal/atuin"
	"kdn-journal/internal/jjmeta"
	"kdn-journal/internal/sessionid"
	"kdn-journal/internal/task"
)

type backfillOptions struct {
	revset string
	dryRun bool
}

type backfillEntry struct {
	ChangeID   string `json:"change_id"`
	SessionID  string `json:"session_id,omitempty"`
	Harness    string `json:"harness,omitempty"`
	Model      string `json:"model,omitempty"`
	Source     string `json:"source,omitempty"`
	Attributed bool   `json:"attributed"`
	Reason     string `json:"reason,omitempty"`
}

type backfillData struct {
	Revset     string          `json:"revset"`
	DryRun     bool            `json:"dry_run"`
	Attributed []backfillEntry `json:"attributed"`
	Unchanged  []backfillEntry `json:"unchanged"`
	Skipped    []backfillEntry `json:"skipped"`
	Failed     []backfillEntry `json:"failed"`
}

func newSessionBackfillCmd(app *App, opts *sessionOptions) *cobra.Command {
	var bf backfillOptions
	cmd := &cobra.Command{
		Use:   "backfill",
		Short: "Attribute mutable changes from the recorded sessions",
		Long: "Map each change to a session and attribute it through kdn-jj-meta.\n\n" +
			"The session comes from a sidecar that records the change ID first, then from the Atuin\n" +
			"Thread whose interval covers the change's author time. A change with no session, and a\n" +
			"change with an empty description, are skipped. --session restricts the backfill to one\n" +
			"session ID.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.sessionBackfill(bf, *opts)
		},
	}
	cmd.Flags().StringVar(&bf.revset, "revset", "mutable()", "changes to backfill")
	cmd.Flags().BoolVar(&bf.dryRun, "dry-run", false, "print the plan and change nothing")
	return cmd
}

func (a *App) sessionBackfill(bf backfillOptions, opts sessionOptions) error {
	ctx := context.Background()
	changes, err := a.JJ.Changes(ctx, bf.revset)
	if err != nil {
		return err
	}
	entries, err := sessionid.LoadAll(a.Root)
	if err != nil {
		return err
	}
	var issues []task.Issue
	for _, entry := range entries {
		if entry.Err != nil {
			issues = append(issues, warningIssue("sidecar-corrupt", entry.Err.Error()))
		}
	}
	var threads []atuin.Thread
	if a.Atuin.Available() {
		threads, err = a.Atuin.List(ctx)
		if err != nil {
			issues = append(issues, warningIssue("atuin-unavailable", err.Error()))
			threads = nil
		}
	} else {
		issues = append(issues, warningIssue("atuin-unavailable",
			"atuin is not on PATH; only the sidecar mappings are used"))
	}
	want := strings.TrimSpace(opts.session)
	data := backfillData{
		Revset:     bf.revset,
		DryRun:     bf.dryRun,
		Attributed: []backfillEntry{},
		Unchanged:  []backfillEntry{},
		Skipped:    []backfillEntry{},
		Failed:     []backfillEntry{},
	}
	for _, change := range changes {
		entry := backfillEntry{ChangeID: change.ChangeID}
		if strings.TrimSpace(change.Description) == "" {
			entry.Reason = "empty description"
			data.Skipped = append(data.Skipped, entry)
			continue
		}
		if a.matchSidecar(entries, threads, change.ChangeID, want, &entry) {
			// matched
		} else if len(threads) > 0 {
			at, err := atuin.ParseTime(change.Timestamp)
			if err == nil {
				match := atuin.FindAt(threads, a.Root, at)
				switch match.How {
				case atuin.MatchTime:
					if want == "" || match.Thread.SessionID == want {
						entry.SessionID = match.Thread.SessionID
						entry.Harness = match.Thread.Harness
						entry.Model = match.Thread.Model
						entry.Source = atuin.MatchTime
					}
				case atuin.MatchAmbiguous:
					entry.Reason = "several sessions overlap"
				}
			}
		}
		if entry.SessionID == "" {
			if entry.Reason == "" {
				entry.Reason = "no session covers the commit time"
			}
			data.Skipped = append(data.Skipped, entry)
			continue
		}
		if bf.dryRun {
			data.Attributed = append(data.Attributed, entry)
			continue
		}
		if !a.JJMeta.Available() {
			entry.Reason = "kdn-jj-meta is not on PATH"
			data.Failed = append(data.Failed, entry)
			continue
		}
		result, err := a.JJMeta.Attribute(ctx, change.ChangeID, jjmeta.Options{
			Session: entry.SessionID,
			Harness: entry.Harness,
			Model:   entry.Model,
		})
		if err != nil {
			entry.Reason = err.Error()
			data.Failed = append(data.Failed, entry)
			continue
		}
		if len(result.Added) == 0 {
			entry.Reason = "already complete"
			data.Unchanged = append(data.Unchanged, entry)
			continue
		}
		entry.Attributed = true
		data.Attributed = append(data.Attributed, entry)
	}
	if a.JSONL {
		var items []any
		for _, entry := range data.Attributed {
			items = append(items, jsonlBackfill("attributed", entry))
		}
		for _, entry := range data.Unchanged {
			items = append(items, jsonlBackfill("unchanged", entry))
		}
		for _, entry := range data.Skipped {
			items = append(items, jsonlBackfill("skipped", entry))
		}
		for _, entry := range data.Failed {
			items = append(items, jsonlBackfill("failed", entry))
		}
		return a.writeJSONL(items)
	}
	if a.JSON {
		return a.writeJSON("session backfill", data, issues)
	}
	verb := "attributed"
	if bf.dryRun {
		verb = "matched"
	}
	fmt.Fprintf(a.Out, "revset %s: %d changes\n", bf.revset, len(changes))
	fmt.Fprintf(a.Out, "  %s %d\n", verb, len(data.Attributed))
	if bf.dryRun {
		fmt.Fprintln(a.Out, "  (kdn-jj-meta adds only the trailers a change is missing)")
	} else {
		fmt.Fprintf(a.Out, "  unchanged %d\n", len(data.Unchanged))
	}
	fmt.Fprintf(a.Out, "  skipped %d\n", len(data.Skipped))
	fmt.Fprintf(a.Out, "  failed %d\n", len(data.Failed))
	printBackfillEntries(a, "skipped", data.Skipped)
	printBackfillEntries(a, "failed", data.Failed)
	printIssues(a, issues)
	return nil
}

// matchSidecar fills entry from the first sidecar that records the change ID. When the sidecar
// carries no Atuin model, the thread with the same session ID supplies it.
func (a *App) matchSidecar(entries []sessionid.Entry, threads []atuin.Thread, changeID, want string, entry *backfillEntry) bool {
	for _, session := range entries {
		if session.Sidecar == nil || !session.Sidecar.MatchesChange(changeID) {
			continue
		}
		if want != "" && session.Sidecar.SessionID != want {
			continue
		}
		entry.SessionID = session.Sidecar.SessionID
		entry.Harness = session.Sidecar.Harness
		entry.Model = session.Sidecar.Atuin.Model
		if entry.Model == "" {
			if thread, ok := atuin.FindSession(threads, session.Sidecar.SessionID); ok {
				entry.Model = thread.Model
			}
		}
		entry.Source = "sidecar"
		return true
	}
	return false
}

type jsonlBackfillEntry struct {
	State string `json:"state"`
	backfillEntry
}

func jsonlBackfill(state string, entry backfillEntry) jsonlBackfillEntry {
	return jsonlBackfillEntry{State: state, backfillEntry: entry}
}

func printBackfillEntries(a *App, title string, entries []backfillEntry) {
	if len(entries) == 0 {
		return
	}
	fmt.Fprintf(a.Out, "%s:\n", title)
	w := tabwriter.NewWriter(a.Out, 0, 0, 2, ' ', 0)
	for _, entry := range entries {
		fmt.Fprintf(w, "  %s\t%s\n", entry.ChangeID, entry.Reason)
	}
	_ = w.Flush()
}
