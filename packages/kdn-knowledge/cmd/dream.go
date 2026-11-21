package cmd

import (
	"context"
	"flag"
	"fmt"
	"time"

	"kdn-knowledge/internal/bundle"
	"kdn-knowledge/internal/corpus"
	"kdn-knowledge/internal/dream"
	"kdn-knowledge/internal/extract"
	"kdn-knowledge/internal/guard"
	"kdn-knowledge/internal/llm"
	"kdn-knowledge/internal/pipeline"
	"kdn-knowledge/internal/proposal"
)

type dreamOptions struct {
	Threshold   float64
	MinSessions int
}

type dreamSummary struct {
	Dir      string  `json:"dir"`
	Model    string  `json:"model"`
	Sessions int     `json:"sessions"`
	Items    int     `json:"items"`
	Clusters int     `json:"clusters"`
	Merged   int     `json:"merged"`
	Dropped  int     `json:"dropped"`
	New      int     `json:"new"`
	Update   int     `json:"update"`
	Conflict int     `json:"conflict"`
	Skills   int     `json:"skills"`
	Failures int     `json:"failures"`
	Report   string  `json:"report"`
	Plan     string  `json:"plan"`
	Seconds  float64 `json:"seconds"`
}

func (a *App) runDream(args []string) error {
	fs := flag.NewFlagSet("dream", flag.ContinueOnError)
	fs.SetOutput(a.errOut)
	a.commonFlags(fs)
	a.modelFlags(fs)
	var opts dreamOptions
	fs.Float64Var(&opts.Threshold, "threshold", dream.DefaultThreshold, "similarity at which two items join a cluster")
	fs.IntVar(&opts.MinSessions, "min-sessions", dream.DefaultMinSessions, "distinct sessions that a runbook needs to become a skill")
	if err := a.parse(fs, args); err != nil {
		return err
	}
	cfg, err := a.prepare()
	if err != nil {
		return err
	}
	if err := a.requireKey(cfg); err != nil {
		return err
	}
	if _, err := guard.Check(cfg.Endpoint, a.AllowHosts); err != nil {
		return &ExitError{Code: 1, Err: err}
	}
	if err := a.startLog(cfg.Store); err != nil {
		return err
	}
	defer a.stopLog()

	summary, err := a.doDream(context.Background(), cfg, opts)
	if err != nil {
		return err
	}
	line := fmt.Sprintf("dream: %d clusters, %d new, %d update, %d conflict, %d skills -> %s",
		summary.Clusters, summary.New, summary.Update, summary.Conflict, summary.Skills, summary.Dir)
	return a.emit("dream", line, summary)
}

// doDream clusters the candidates, merges the repeats, and writes one proposal directory.
func (a *App) doDream(ctx context.Context, cfg *config, opts dreamOptions) (*dreamSummary, error) {
	started := time.Now()
	files, err := extract.LoadFiles(cfg.Store.CandidatesDir())
	if err != nil {
		return nil, err
	}
	input := dream.Input{
		Items:    []extract.Item{},
		Commands: map[string][]string{},
	}
	truncated := make([]string, 0, 4)
	for _, file := range files {
		input.Items = append(input.Items, file.Items...)
		if file.Truncated {
			truncated = append(truncated, file.Session)
		}
		if session, err := pipeline.LoadCorpus(cfg.Store, file.Session); err == nil {
			input.Commands[file.Session] = commandsOf(session)
		}
	}
	concepts, err := bundle.Load(cfg.Bundle)
	if err != nil {
		return nil, err
	}
	input.Concepts = concepts
	for _, failure := range cfg.Ledger.Failed() {
		input.Failures = append(input.Failures, dream.Failure{
			ID:       failure.ID,
			Reason:   failure.Reason,
			Attempts: failure.Attempts,
		})
	}

	judge := &llm.Judge{Client: llm.New(cfg.Endpoint, cfg.MergeModel, cfg.APIKey, cfg.Timeout)}
	plan, err := dream.Build(ctx, input, dream.Options{
		Threshold:   opts.Threshold,
		MinSessions: opts.MinSessions,
		Merger:      judge,
		Now:         a.Now,
		Model:       cfg.MergeModel,
	})
	if err != nil {
		return nil, err
	}
	plan.Truncated = truncated
	written, err := proposal.Write(cfg.Store, plan, a.Now())
	if err != nil {
		return nil, err
	}

	summary := &dreamSummary{
		Dir:      written.Dir,
		Model:    cfg.MergeModel,
		Sessions: len(plan.Sessions),
		Items:    plan.Items,
		Clusters: plan.Clusters,
		Merged:   plan.Merged,
		Dropped:  plan.Dropped,
		Failures: len(plan.Failures),
		Report:   written.ReportPath,
		Plan:     written.PlanPath,
		Seconds:  time.Since(started).Seconds(),
	}
	for _, action := range plan.Actions {
		switch action.Action {
		case "new":
			summary.New++
		case "update":
			summary.Update++
		case "conflict":
			summary.Conflict++
		}
	}
	summary.Skills = len(plan.Skills)
	a.progressf("dream: %d candidate sessions, %d items, %d clusters (%d merged, %d dropped)",
		summary.Sessions, summary.Items, summary.Clusters, summary.Merged, summary.Dropped)
	a.progressf("dream: proposal written to %s", written.Dir)
	return summary, nil
}

// commandsOf returns the shell commands of one session, in transcript order.
func commandsOf(session corpus.Session) []string {
	commands := make([]string, 0, 16)
	for _, message := range session.Messages {
		if message.Role != "tool" || message.Command == "" {
			continue
		}
		commands = append(commands, message.Command)
	}
	return commands
}
