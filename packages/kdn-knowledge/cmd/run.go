package cmd

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"kdn-knowledge/internal/guard"
	"kdn-knowledge/internal/harvest"
)

type runSummary struct {
	Harvest *harvest.Summary `json:"harvest"`
	Extract *extractSummary  `json:"extract"`
	Dream   *dreamSummary    `json:"dream"`
	Seconds float64          `json:"seconds"`
}

func (a *App) runAll(args []string) error {
	fs := flag.NewFlagSet("run", flag.ContinueOnError)
	fs.SetOutput(a.errOut)
	a.commonFlags(fs)
	a.modelFlags(fs)
	var db, project, sinceRaw, source, piRoot string
	var harvestLimit, extractLimit, chunkChars, maxChunks int
	var includeLive, force bool
	var opts dreamOptions
	fs.StringVar(&db, "db", "", "OpenCode session database (default: ~/.local/share/opencode/opencode.db)")
	fs.StringVar(&source, "source", harvest.SourceAll, "session store: all, opencode or pi")
	fs.StringVar(&piRoot, "pi-root", "", "Pi session root (default: ~/.pi/agent/sessions)")
	fs.StringVar(&project, "project", "", "only sessions of this project directory (default: current directory)")
	fs.StringVar(&sinceRaw, "since", "", "only sessions started on or after this date")
	fs.IntVar(&harvestLimit, "limit", 0, "maximum number of sessions to harvest")
	fs.IntVar(&extractLimit, "extract-limit", 0, "maximum number of sessions to extract")
	fs.BoolVar(&includeLive, "include-live", false, "include sessions that are still running")
	fs.BoolVar(&force, "force", false, "re-extract sessions that are already done")
	fs.IntVar(&chunkChars, "chunk-chars", 0, "split a transcript at this many characters")
	fs.IntVar(&maxChunks, "max-chunks", 0, "cap the calls per session when chunking")
	fs.Float64Var(&opts.Threshold, "threshold", 0.35, "similarity at which two items join a cluster")
	fs.IntVar(&opts.MinSessions, "min-sessions", 3, "distinct sessions that a runbook needs to become a skill")
	fs.IntVar(&opts.MaxConcepts, "max-concepts", 60, "cap the proposal; the rest goes to the report (0 means no cap)")
	if err := a.parse(fs, args); err != nil {
		return err
	}
	since, err := parseSince(sinceRaw)
	if err != nil {
		return &ExitError{Code: 2, Err: err}
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
	if db == "" {
		db = cfg.DB
	}
	if piRoot == "" {
		piRoot = defaultPiRoot()
	}
	if project == "" {
		if cwd, err := os.Getwd(); err == nil {
			project = cwd
		}
	}
	if err := a.startLog(cfg.Store); err != nil {
		return err
	}
	defer a.stopLog()
	started := time.Now()

	harvested, err := harvest.Run(context.Background(), cfg.Store, cfg.Ledger, harvest.Options{
		DB:          db,
		Project:     project,
		Since:       since,
		Limit:       harvestLimit,
		IncludeLive: includeLive,
		Source:      source,
		PiRoot:      piRoot,
	}, func(event harvest.Event) {
		a.progressf("[harvest %d/%d] %s %s %d messages (%s)",
			event.Index, event.Total, event.Source, event.ID, event.Messages, formatSeconds(event.Elapsed))
	})
	if err != nil {
		return err
	}

	extracted, err := a.doExtract(context.Background(), cfg, extractOptions{
		Limit:      extractLimit,
		Force:      force,
		ChunkChars: chunkChars,
		MaxChunks:  maxChunks,
	})
	if err != nil {
		return err
	}

	dreamed, err := a.doDream(context.Background(), cfg, opts)
	if err != nil {
		return err
	}

	summary := &runSummary{
		Harvest: harvested,
		Extract: extracted,
		Dream:   dreamed,
		Seconds: time.Since(started).Seconds(),
	}
	line := fmt.Sprintf(
		"run: %d harvested, %d extracted (%d items), %d clusters, %d actions, %d skills -> %s",
		harvested.Selected, extracted.Extracted, extracted.Items, dreamed.Clusters,
		dreamed.New+dreamed.Update+dreamed.Conflict, dreamed.Skills, dreamed.Dir)
	return a.emit("run", line, summary)
}
