package cmd

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"strings"
	"time"

	"kdn-knowledge/internal/guard"
	"kdn-knowledge/internal/llm"
	"kdn-knowledge/internal/pipeline"
	"kdn-knowledge/internal/state"
)

type extractOptions struct {
	Limit      int
	Force      bool
	DryRun     bool
	ChunkChars int
	MaxChunks  int
}

type extractFailure struct {
	Session string `json:"session"`
	Reason  string `json:"reason"`
}

type extractSummary struct {
	Model     string           `json:"model"`
	Endpoint  string           `json:"endpoint"`
	Decide    string           `json:"decide"`
	Selected  int              `json:"selected"`
	Extracted int              `json:"extracted"`
	Failed    int              `json:"failed"`
	Items     int              `json:"items"`
	Calls     int              `json:"calls"`
	Pending   int              `json:"pending"`
	Seconds   float64          `json:"seconds"`
	Average   float64          `json:"average_seconds,omitempty"`
	Remaining int              `json:"remaining"`
	Estimate  float64          `json:"estimate_seconds,omitempty"`
	Failures  []extractFailure `json:"failures"`
}

// Line is the one-line summary, including the running average and the estimate for the sessions
// that the limit left.
func (s *extractSummary) Line() string {
	line := fmt.Sprintf("extract: %d extracted, %d failed, %d items, %d calls",
		s.Extracted, s.Failed, s.Items, s.Calls)
	if s.Average > 0 {
		line += fmt.Sprintf(", avg %.1f s/session, ~%s for %d remaining",
			s.Average, formatEstimate(s.Estimate), s.Remaining)
	}
	return line + fmt.Sprintf(" (model %s)", s.Model)
}

func (a *App) runExtract(args []string) error {
	fs := flag.NewFlagSet("extract", flag.ContinueOnError)
	fs.SetOutput(a.errOut)
	a.commonFlags(fs)
	a.modelFlags(fs)
	var opts extractOptions
	fs.IntVar(&opts.Limit, "limit", 0, "maximum number of sessions")
	fs.BoolVar(&opts.Force, "force", false, "re-extract sessions that are already done")
	fs.BoolVar(&opts.DryRun, "dry-run", false, "list the sessions that would be extracted and stop")
	fs.IntVar(&opts.ChunkChars, "chunk-chars", 0, "split a transcript at this many characters (default: no split, the frontier window holds a session)")
	fs.IntVar(&opts.MaxChunks, "max-chunks", 0, "cap the calls per session when chunking (default: no cap)")
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

	summary, err := a.doExtract(context.Background(), cfg, opts)
	if err != nil {
		return err
	}
	return a.emit("extract", summary.Line(), summary)
}

// doExtract preflights the model, then extracts every pending session. The ledger is saved after
// every session, so a dropped connection loses at most one session.
func (a *App) doExtract(ctx context.Context, cfg *config, opts extractOptions) (*extractSummary, error) {
	summary := &extractSummary{
		Model:    cfg.Model,
		Endpoint: cfg.Endpoint,
		Failures: []extractFailure{},
	}
	client := llm.New(cfg.Endpoint, cfg.Model, cfg.APIKey, cfg.Timeout)

	if strings.TrimSpace(cfg.Manager) == "" {
		summary.Decide = "skipped"
		a.progressf("decide: skipped (no --manager configured; on brys pass --manager http://127.0.0.1:8181)")
	} else {
		verdict, decideErr := llm.Decide(ctx, cfg.Manager, cfg.Model)
		var cooldown *llm.CooldownError
		switch {
		case errors.As(decideErr, &cooldown):
			summary.Decide = "cooldown"
			a.progressf("/decide %s: %v — unknown, continue", cfg.Model, decideErr)
		case decideErr != nil:
			summary.Decide = "unknown"
			a.progressf("/decide %s: manager unreachable (%v) — unknown, continue", cfg.Model, decideErr)
		case verdict.Admits():
			summary.Decide = verdict.Summary()
			a.progressf("/decide %s: %s", cfg.Model, verdict.Summary())
		default:
			summary.Decide = verdict.Summary()
			trace := strings.Join(verdict.Trace(4), "; ")
			return summary, &ExitError{Code: 1, Err: fmt.Errorf(
				"the placement manager refuses model %q: %s. Trace: %s. "+
					"qfn is the only model that fits beside the resting profile; a grunt model needs a colo profile",
				cfg.Model, verdict.Summary(), trace)}
		}
	}

	candidates := pipeline.Candidates(cfg.Ledger, opts.Force, opts.Limit)
	summary.Selected = len(candidates)
	summary.Pending = len(pipeline.Candidates(cfg.Ledger, opts.Force, 0)) - len(candidates)
	if opts.DryRun {
		for index, id := range candidates {
			entry, _ := cfg.Ledger.Get(id)
			a.progressf("[%d/%d] %s %s", index+1, len(candidates), id, entry.Status)
		}
		return summary, nil
	}
	if len(candidates) == 0 {
		a.progressf("extract: nothing to do, every session is done")
		return summary, nil
	}

	var elapsed time.Duration
	for index, id := range candidates {
		session, err := pipeline.LoadCorpus(cfg.Store, id)
		if err != nil {
			entry, _ := cfg.Ledger.Get(id)
			entry.Status = state.StatusFailed
			entry.Attempts++
			entry.Reason = "corpus file is missing; run harvest: " + err.Error()
			cfg.Ledger.Put(id, entry)
			_ = cfg.Ledger.Save()
			summary.Failed++
			summary.Failures = append(summary.Failures, extractFailure{Session: id, Reason: entry.Reason})
			a.progressf("[%d/%d] %s failed: %s", index+1, len(candidates), id, entry.Reason)
			continue
		}
		outcome := pipeline.ExtractOne(ctx, client, cfg.Store, cfg.Ledger, session, pipeline.ExtractOptions{
			ChunkChars: opts.ChunkChars,
			MaxChunks:  opts.MaxChunks,
			Now:        a.Now,
		})
		elapsed += outcome.Duration
		if outcome.Err != nil {
			summary.Failed++
			summary.Failures = append(summary.Failures, extractFailure{Session: id, Reason: outcome.Err.Error()})
			a.progressf("[%d/%d] %s failed (%s): %v",
				index+1, len(candidates), id, formatSeconds(outcome.Duration), outcome.Err)
			continue
		}
		summary.Extracted++
		summary.Items += outcome.Items
		summary.Calls += outcome.Calls
		a.progressf("[%d/%d] %s %d items (%s)",
			index+1, len(candidates), id, outcome.Items, formatSeconds(outcome.Duration))
	}
	summary.Seconds = elapsed.Seconds()
	if summary.Extracted > 0 {
		summary.Average = summary.Seconds / float64(summary.Extracted)
	}
	// The estimate answers "how much work is left", so it never counts the sessions that --force
	// re-ran on purpose.
	summary.Remaining = len(pipeline.Candidates(cfg.Ledger, false, 0))
	summary.Estimate = summary.Average * float64(summary.Remaining)
	return summary, nil
}
