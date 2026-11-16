package cmd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"kdn-journal/internal/atuin"
	"kdn-journal/internal/jjmeta"
	"kdn-journal/internal/jjrun"
	"kdn-journal/internal/sessionid"
	"kdn-journal/internal/task"
)

// sessionOptions holds the identity overrides shared by the session subcommands.
type sessionOptions struct {
	session string
	harness string
	model   string
}

func newSessionCmd(app *App) *cobra.Command {
	opts := &sessionOptions{}
	cmd := &cobra.Command{
		Use:   "session",
		Short: "Record the agent session identity and its jj changes",
		Long: "Record the running agent session in .cache/agents/<session>/session.json, map jj\n" +
			"changes to it, and link it to an Atuin Thread. The sidecar is local and git-ignored.\n" +
			"jj and Atuin are optional: every read still works without them.",
	}
	flags := cmd.PersistentFlags()
	flags.StringVar(&opts.session, "session", "", "session ID (default: detect from the environment)")
	flags.StringVar(&opts.harness, "harness", "", "agent harness (default: detect from the environment)")
	flags.StringVar(&opts.model, "model", "", "model name and version (default: detect from the environment or Atuin)")
	cmd.AddCommand(
		newSessionInitCmd(app, opts),
		newSessionRecordChangeCmd(app, opts),
		newSessionRecordCommitCmd(app, opts),
		newSessionChangesCmd(app, opts),
		newSessionAtuinCmd(app, opts),
	)
	return cmd
}

func newSessionInitCmd(app *App, opts *sessionOptions) *cobra.Command {
	var taskSelector string
	cmd := &cobra.Command{
		Use:   "init",
		Short: "Create or update the session sidecar",
		RunE: func(cmd *cobra.Command, args []string) error {
			id, err := app.resolveIdentity(*opts)
			if err != nil {
				return err
			}
			sidecar, path, issues, err := app.openSidecar(id)
			if err != nil {
				return err
			}
			if taskSelector != "" {
				treeData, err := app.loadTree()
				if err != nil {
					return err
				}
				item, err := treeData.Find(taskSelector)
				if err != nil {
					return err
				}
				sidecar.Task = item.RelDir
			}
			if app.JJ.Available() {
				if change, err := app.JJ.WorkingCopyChange(context.Background()); err != nil {
					issues = append(issues, warningIssue("jj-working-copy", err.Error()))
				} else {
					sidecar.JJ.WorkingCopyChange = change
				}
			} else {
				issues = append(issues, warningIssue("jj-unavailable", "jj is not on PATH; no working-copy change recorded"))
			}
			if err := sidecar.Save(path); err != nil {
				return err
			}
			if app.JSON {
				return app.writeJSON("session init", map[string]any{
					"session": sidecar,
					"dir":     filepath.Dir(path),
					"sidecar": path,
				}, issues)
			}
			fmt.Fprintf(app.Out, "session %s (%s)\n", sidecar.SessionID, sidecar.Harness)
			fmt.Fprintf(app.Out, "dir     %s\n", filepath.Dir(path))
			if sidecar.Task != "" {
				fmt.Fprintf(app.Out, "task    %s\n", sidecar.Task)
			}
			if sidecar.JJ.WorkingCopyChange != "" {
				fmt.Fprintf(app.Out, "jj @    %s\n", sidecar.JJ.WorkingCopyChange)
			}
			printIssues(app, issues)
			return nil
		},
	}
	cmd.Flags().StringVar(&taskSelector, "task", "", "task directory or slug to record")
	return cmd
}

func newSessionRecordChangeCmd(app *App, opts *sessionOptions) *cobra.Command {
	return &cobra.Command{
		Use:   "record-change <change-id>",
		Short: "Record a jj change and attribute it through jj-meta",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			changeID := strings.TrimSpace(args[0])
			if changeID == "" {
				return fmt.Errorf("empty change ID")
			}
			id, err := app.resolveIdentity(*opts)
			if err != nil {
				return err
			}
			sidecar, path, issues, err := app.openSidecar(id)
			if err != nil {
				return err
			}
			recorded := sidecar.AddChange(changeID)
			if err := sidecar.Save(path); err != nil {
				return err
			}
			attributed := false
			model := id.Model
			if model == "" {
				model = app.atuinModel(context.Background(), id)
			}
			switch {
			case !app.JJMeta.Available():
				issues = append(issues, warningIssue("jj-meta-unavailable",
					"jj-meta is not on PATH; the change is recorded but no trailer is written"))
			default:
				err := app.JJMeta.Attribute(context.Background(), changeID, jjmeta.Options{
					Session: id.ID,
					Harness: id.Harness,
					Model:   model,
				})
				if err != nil {
					issues = append(issues, warningIssue("jj-meta-failed", err.Error()))
				} else {
					attributed = true
				}
			}
			if app.JSON {
				return app.writeJSON("session record-change", map[string]any{
					"session":    sidecar,
					"sidecar":    path,
					"change_id":  changeID,
					"recorded":   recorded,
					"attributed": attributed,
				}, issues)
			}
			if recorded {
				fmt.Fprintf(app.Out, "recorded %s\n", changeID)
			} else {
				fmt.Fprintf(app.Out, "%s already recorded\n", changeID)
			}
			if attributed {
				fmt.Fprintf(app.Out, "attributed %s\n", changeID)
			}
			printIssues(app, issues)
			return nil
		},
	}
}

func newSessionRecordCommitCmd(app *App, opts *sessionOptions) *cobra.Command {
	return &cobra.Command{
		Use:   "record-commit <commit-id>",
		Short: "Record a jj commit ID in the session sidecar",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			commitID := strings.TrimSpace(args[0])
			if commitID == "" {
				return fmt.Errorf("empty commit ID")
			}
			id, err := app.resolveIdentity(*opts)
			if err != nil {
				return err
			}
			sidecar, path, issues, err := app.openSidecar(id)
			if err != nil {
				return err
			}
			recorded := sidecar.AddCommit(commitID)
			if err := sidecar.Save(path); err != nil {
				return err
			}
			if app.JSON {
				return app.writeJSON("session record-commit", map[string]any{
					"session":   sidecar,
					"sidecar":   path,
					"commit_id": commitID,
					"recorded":  recorded,
				}, issues)
			}
			if recorded {
				fmt.Fprintf(app.Out, "recorded %s\n", commitID)
			} else {
				fmt.Fprintf(app.Out, "%s already recorded\n", commitID)
			}
			printIssues(app, issues)
			return nil
		},
	}
}

func newSessionChangesCmd(app *App, opts *sessionOptions) *cobra.Command {
	return &cobra.Command{
		Use:   "changes",
		Short: "Resolve the recorded jj change IDs",
		RunE: func(cmd *cobra.Command, args []string) error {
			id, err := app.resolveIdentity(*opts)
			if err != nil {
				return err
			}
			return app.sessionChanges(id)
		},
	}
}

func newSessionAtuinCmd(app *App, opts *sessionOptions) *cobra.Command {
	return &cobra.Command{
		Use:   "atuin",
		Short: "Link this session to its Atuin Thread",
		RunE: func(cmd *cobra.Command, args []string) error {
			id, err := app.resolveIdentity(*opts)
			if err != nil {
				return err
			}
			return app.sessionAtuin(id)
		},
	}
}

// resolveIdentity merges the explicit overrides over the detected environment.
func (a *App) resolveIdentity(opts sessionOptions) (sessionid.Identity, error) {
	id, _ := sessionid.Detect(a.Getenv)
	if v := strings.TrimSpace(opts.session); v != "" {
		id.ID = v
		id.Source = "flag"
	}
	if v := strings.TrimSpace(opts.harness); v != "" {
		id.Harness = sessionid.NormalizeHarness(v)
		id.Source = "flag"
	}
	if v := strings.TrimSpace(opts.model); v != "" {
		id.Model = v
		id.Source = "flag"
	}
	if id.ID == "" || id.Harness == "" {
		return id, fmt.Errorf("cannot detect the agent session; pass --session and --harness")
	}
	return id, nil
}

// openSidecar finds or creates the session directory and returns the sidecar to update. It does
// not save; the caller decides when the write is complete.
func (a *App) openSidecar(id sessionid.Identity) (*sessionid.Sidecar, string, []task.Issue, error) {
	dir, err := sessionid.FindOrCreate(a.Root, id, a.Now())
	if err != nil {
		return nil, "", nil, err
	}
	path := filepath.Join(dir, "session.json")
	now := a.Now()
	var issues []task.Issue
	sidecar, err := sessionid.Load(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			issues = append(issues, task.Issue{
				Severity: "warning",
				Code:     "sidecar-corrupt",
				Path:     path,
				Message:  err.Error(),
			})
		}
		sidecar = &sessionid.Sidecar{}
	}
	if sidecar.SchemaVersion == 0 {
		sidecar.SchemaVersion = sessionid.SchemaVersion
	}
	if sidecar.StartedAt == "" {
		sidecar.StartedAt = now.Format(time.RFC3339)
	}
	sidecar.Harness = id.Harness
	sidecar.SessionID = id.ID
	if cwd, err := os.Getwd(); err == nil {
		sidecar.Cwd = cwd
	}
	sidecar.Touch(now)
	return sidecar, path, issues, nil
}

// loadSidecar reads an existing sidecar. It never creates a directory.
func (a *App) loadSidecar(id sessionid.Identity) (*sessionid.Sidecar, string, error) {
	dir, err := sessionid.Find(a.Root, id)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, "", fmt.Errorf("no session sidecar for %s; run kdn-journal session init", id.ID)
		}
		return nil, "", err
	}
	path := filepath.Join(dir, "session.json")
	sidecar, err := sessionid.Load(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, path, fmt.Errorf("%s has no session.json; run kdn-journal session init", dir)
		}
		return nil, path, err
	}
	return sidecar, path, nil
}

func (a *App) sessionChanges(id sessionid.Identity) error {
	sidecar, _, err := a.loadSidecar(id)
	if err != nil {
		return err
	}
	var issues []task.Issue
	available := a.JJ.Available()
	if !available {
		issues = append(issues, warningIssue("jj-unavailable",
			"jj is not on PATH; the recorded change IDs are listed without details"))
	}
	changes := make([]jjrun.Change, 0, len(sidecar.JJ.ChangeIDs))
	for _, changeID := range sidecar.JJ.ChangeIDs {
		if !available {
			changes = append(changes, jjrun.Change{ChangeID: changeID})
			continue
		}
		change, err := a.JJ.Change(context.Background(), changeID)
		if err != nil {
			issues = append(issues, task.Issue{
				Severity: "warning",
				Code:     "change-missing",
				Message:  changeID + ": " + err.Error(),
			})
			changes = append(changes, jjrun.Change{ChangeID: changeID})
			continue
		}
		changes = append(changes, change)
	}
	if a.JSON {
		return a.writeJSON("session changes", map[string]any{"session": sidecar, "changes": changes}, issues)
	}
	fmt.Fprintf(a.Out, "session %s (%s)\n", sidecar.SessionID, sidecar.Harness)
	if len(changes) == 0 {
		fmt.Fprintln(a.Out, "no recorded changes")
	}
	for _, change := range changes {
		description := firstLine(change.Description)
		if description == "" {
			description = "(no description)"
		}
		fmt.Fprintf(a.Out, "%s  %s  %s\n", change.ChangeID, change.CommitID, description)
		if change.Author != "" || change.Timestamp != "" {
			fmt.Fprintf(a.Out, "  %s  %s\n", change.Author, change.Timestamp)
		}
		if len(change.Files) > 0 {
			fmt.Fprintf(a.Out, "  %s\n", strings.Join(change.Files, ", "))
		}
	}
	printIssues(a, issues)
	return nil
}

func (a *App) sessionAtuin(id sessionid.Identity) error {
	sidecar, path, err := a.loadSidecar(id)
	if err != nil {
		return err
	}
	var issues []task.Issue
	if !a.Atuin.Available() {
		issues = append(issues, warningIssue("atuin-unavailable", "atuin is not on PATH; no thread link is possible"))
		return a.finishAtuin(sidecar, issues, "")
	}
	threads, err := a.Atuin.List(context.Background())
	if err != nil {
		issues = append(issues, warningIssue("atuin-unavailable", err.Error()))
		return a.finishAtuin(sidecar, issues, "")
	}
	if len(threads) == 0 {
		issues = append(issues, warningIssue("atuin-empty",
			"Atuin captured no threads; check [threads] capture = true and run atuin threads import"))
		return a.finishAtuin(sidecar, issues, "")
	}
	started, _ := atuin.ParseTime(sidecar.StartedAt)
	match := atuin.Find(threads, sidecar.SessionID, sidecar.Harness, sidecar.Cwd, started, 10*time.Minute)
	switch match.How {
	case atuin.MatchNone:
		issues = append(issues, warningIssue("atuin-no-match", "no Atuin thread matches this session"))
	case atuin.MatchAmbiguous:
		issues = append(issues, warningIssue("atuin-ambiguous", "several Atuin threads match this session; not linking"))
	default:
		sidecar.Atuin = sessionid.Atuin{
			ThreadID:       match.Thread.AtuinID,
			AgentSessionID: match.Thread.SessionID,
			Model:          match.Thread.Model,
			MessageCount:   match.Thread.MessageCount,
			UpdatedAt:      match.Thread.UpdatedAt,
		}
		// The sidecar may have been created after the session started. Atuin knows the real start,
		// so adopt it when it is earlier.
		if threadStart, err := atuin.ParseTime(match.Thread.StartedAt); err == nil {
			if current, err := atuin.ParseTime(sidecar.StartedAt); err != nil || threadStart.Before(current) {
				sidecar.StartedAt = threadStart.Format(time.RFC3339)
			}
		}
		sidecar.Touch(a.Now())
		if err := sidecar.Save(path); err != nil {
			return err
		}
	}
	return a.finishAtuin(sidecar, issues, match.How)
}

func (a *App) finishAtuin(sidecar *sessionid.Sidecar, issues []task.Issue, how string) error {
	if a.JSON {
		return a.writeJSON("session atuin", map[string]any{
			"session": sidecar,
			"match":   how,
		}, issues)
	}
	if sidecar.Atuin.ThreadID == "" {
		fmt.Fprintln(a.Out, "no Atuin thread linked")
		printIssues(a, issues)
		return nil
	}
	fmt.Fprintf(a.Out, "atuin   %s\n", sidecar.Atuin.ThreadID)
	fmt.Fprintf(a.Out, "match   %s\n", how)
	if sidecar.Atuin.MessageCount > 0 {
		fmt.Fprintf(a.Out, "messages %d\n", sidecar.Atuin.MessageCount)
	}
	if sidecar.Atuin.UpdatedAt != "" {
		fmt.Fprintf(a.Out, "updated %s\n", sidecar.Atuin.UpdatedAt)
	}
	printIssues(a, issues)
	return nil
}

// atuinModel returns the model Atuin recorded for the session, when the environment does not
// export one.
func (a *App) atuinModel(ctx context.Context, id sessionid.Identity) string {
	if !a.Atuin.Available() {
		return ""
	}
	threads, err := a.Atuin.List(ctx)
	if err != nil {
		return ""
	}
	if thread, ok := atuin.FindSession(threads, id.ID); ok {
		return thread.Model
	}
	return ""
}

func warningIssue(code, message string) task.Issue {
	return task.Issue{Severity: "warning", Code: code, Message: message}
}

func printIssues(app *App, issues []task.Issue) {
	for _, issue := range issues {
		fmt.Fprintf(app.Err, "kdn-journal: %s: %s\n", issue.Code, issue.Message)
	}
}

func firstLine(text string) string {
	if idx := strings.IndexByte(text, '\n'); idx >= 0 {
		return strings.TrimSpace(text[:idx])
	}
	return strings.TrimSpace(text)
}
