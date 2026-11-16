package cmd

import (
	"context"
	"fmt"
	"strings"

	"github.com/spf13/cobra"

	"kdn-jj-meta/internal/attribution"
	"kdn-jj-meta/internal/session"
	"kdn-jj-meta/internal/trailer"
)

type attributeOptions struct {
	revset         string
	session        string
	harness        string
	model          string
	profiles       []string
	trailers       []string
	coauthor       bool
	coauthorEmail  string
	generated      bool
	noSession      bool
	allowImmutable bool
	dryRun         bool
	allowEmpty     bool
}

type changeAttribution struct {
	ChangeID string   `json:"change_id"`
	CommitID string   `json:"commit_id"`
	Mutable  bool     `json:"mutable"`
	Added    []string `json:"added"`
	Skipped  []string `json:"skipped"`
	Written  bool     `json:"written"`
	Reason   string   `json:"reason,omitempty"`
}

type attributeData struct {
	Profiles []string            `json:"profiles"`
	Session  session.Session     `json:"session"`
	DryRun   bool                `json:"dry_run"`
	Changes  []changeAttribution `json:"changes"`
}

func newAttributeCmd(app *App) *cobra.Command {
	var opts attributeOptions
	cmd := &cobra.Command{
		Use:   "attribute [<change-id>]",
		Short: "Append the missing attribution trailers to a mutable change",
		Long: "Append the missing attribution trailers to the description of a mutable change.\n\n" +
			"The default target is @. Every target is intersected with mutable(), so the command\n" +
			"refuses immutable history. Existing trailers are never removed or rewritten; a second\n" +
			"run adds nothing.",
		Example: "  kdn-jj-meta attribute @\n" +
			"  kdn-jj-meta attribute main..@ --profile github --coauthor-email bot@example.com\n" +
			"  kdn-jj-meta attribute --revset 'main..@' --dry-run",
		Args: cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			revset := opts.revset
			if len(args) == 1 {
				if revset != "" {
					return fmt.Errorf("pass a change ID or --revset, not both")
				}
				revset = args[0]
			}
			if revset == "" {
				revset = "@"
			}
			return app.attribute(revset, opts)
		},
	}
	flags := cmd.Flags()
	flags.StringVar(&opts.revset, "revset", "", "attribute every change the revset matches")
	flags.StringVar(&opts.session, "session", "", "session ID (default: detect from the environment)")
	flags.StringVar(&opts.harness, "harness", "", "agent harness, for example opencode or pi")
	flags.StringVar(&opts.model, "model", "", "model name and version")
	flags.StringArrayVar(&opts.profiles, "profile", nil, "active trailer profiles: agent, nixpkgs, asf, github, full; repeatable or comma-separated (default: agent,nixpkgs,asf)")
	flags.StringArrayVar(&opts.trailers, "trailer", nil, "extra trailer as key=value; repeatable")
	flags.BoolVar(&opts.coauthor, "coauthor", false, "also add the agent Co-authored-by line (needs an email)")
	flags.StringVar(&opts.coauthorEmail, "coauthor-email", "", "agent email for Co-authored-by (default: KDN_JJ_META_COAUTHOR_EMAIL)")
	flags.BoolVar(&opts.generated, "generated", false, "also add Generated-by for mostly machine-authored work")
	flags.BoolVar(&opts.noSession, "no-session", false, "do not write Session-Id")
	flags.BoolVar(&opts.allowImmutable, "allow-immutable", false, "try an immutable change anyway (jj itself refuses to rewrite it)")
	flags.BoolVar(&opts.dryRun, "dry-run", false, "print the plan and change nothing")
	flags.BoolVar(&opts.allowEmpty, "allow-empty", false, "attribute a change with an empty description")
	return cmd
}

func (a *App) attribute(revset string, opts attributeOptions) error {
	ctx := context.Background()
	changes, err := a.Runner.Changes(ctx, revset)
	if err != nil {
		return err
	}
	if len(changes) == 0 {
		return &ExitError{Code: 1, Err: fmt.Errorf("no change matches %q", revset)}
	}
	for _, change := range changes {
		if change.Immutable && !opts.allowImmutable {
			return &ExitError{Code: 1, Err: fmt.Errorf(
				"change %s is immutable; pass --allow-immutable to try anyway", shortID(change.ChangeID))}
		}
	}
	profileValues := opts.profiles
	if len(profileValues) == 0 {
		if env := a.Getenv("KDN_JJ_META_PROFILE"); strings.TrimSpace(env) != "" {
			profileValues = []string{env}
		}
	}
	profiles, err := attribution.ParseProfiles(profileValues)
	if err != nil {
		return err
	}
	extra, err := parseTrailers(opts.trailers)
	if err != nil {
		return err
	}
	email := opts.coauthorEmail
	if email == "" {
		email = a.Getenv("KDN_JJ_META_COAUTHOR_EMAIL")
	}
	sess := session.Detect(a.Getenv).Apply(opts.harness, opts.session, opts.model)
	plan, err := attribution.Build(attribution.Options{
		Profiles:      profiles,
		Session:       sess,
		NoSession:     opts.noSession,
		Coauthor:      opts.coauthor,
		CoauthorEmail: email,
		Generated:     opts.generated,
		Extra:         extra,
	})
	if err != nil {
		return err
	}
	for _, warning := range plan.Warnings {
		a.warnf("%s", warning)
	}
	data := attributeData{Profiles: attribution.Names(profiles), Session: sess, DryRun: opts.dryRun}
	var issues []Issue
	for _, change := range changes {
		if strings.TrimSpace(change.Description) == "" && !opts.allowEmpty {
			result := changeAttribution{
				ChangeID: change.ChangeID,
				CommitID: change.CommitID,
				Mutable:  !change.Immutable,
				Added:    []string{},
				Skipped:  []string{},
				Reason:   "empty description",
			}
			data.Changes = append(data.Changes, result)
			if !a.JSON {
				fmt.Fprintf(a.Out, "%s: empty description; pass --allow-empty to attribute it\n", shortID(change.ChangeID))
			}
			continue
		}
		doc := trailer.Parse(change.Description)
		updated, added, skipped := doc.Append(plan.Trailers)
		result := changeAttribution{
			ChangeID: change.ChangeID,
			CommitID: change.CommitID,
			Mutable:  !change.Immutable,
			Added:    trailer.Render(added),
			Skipped:  trailer.Render(skipped),
		}
		if len(added) > 0 && !opts.dryRun {
			if err := a.Runner.Describe(ctx, change.ChangeID, updated); err != nil {
				issues = append(issues, Issue{Code: "describe-failed", Message: err.Error(), ChangeID: change.ChangeID, Severity: "error"})
				data.Changes = append(data.Changes, result)
				if a.JSON {
					continue
				}
				return err
			}
			result.Written = true
		}
		data.Changes = append(data.Changes, result)
		if a.JSON {
			continue
		}
		a.printAttribution(result, opts.dryRun)
	}
	if a.JSONL {
		items := make([]any, 0, len(data.Changes))
		for _, change := range data.Changes {
			items = append(items, change)
		}
		if err := a.writeJSONL(items); err != nil {
			return err
		}
		if len(issues) > 0 {
			return &ExitError{Code: 1}
		}
		return nil
	}
	if a.JSON {
		if len(issues) > 0 {
			_ = a.writeJSON("attribute", data, issues)
			return &ExitError{Code: 1}
		}
		return a.writeJSON("attribute", data, nil)
	}
	return nil
}

func (a *App) printAttribution(result changeAttribution, dryRun bool) {
	verb := "attributed"
	if dryRun {
		verb = "would attribute"
	}
	if len(result.Added) == 0 {
		fmt.Fprintf(a.Out, "%s: nothing to add\n", shortID(result.ChangeID))
		for _, line := range result.Skipped {
			fmt.Fprintf(a.Out, "  = %s\n", line)
		}
		return
	}
	fmt.Fprintf(a.Out, "%s %s\n", verb, shortID(result.ChangeID))
	for _, line := range result.Added {
		fmt.Fprintf(a.Out, "  + %s\n", line)
	}
	for _, line := range result.Skipped {
		fmt.Fprintf(a.Out, "  = %s\n", line)
	}
}

func parseTrailers(args []string) ([]trailer.Trailer, error) {
	out := make([]trailer.Trailer, 0, len(args))
	for _, arg := range args {
		t, err := trailer.ParseKeyValue(arg)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, nil
}
