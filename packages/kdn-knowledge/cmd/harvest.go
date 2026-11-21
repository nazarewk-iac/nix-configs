package cmd

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"kdn-knowledge/internal/harvest"
)

func defaultPiRoot() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".pi", "agent", "sessions")
}

func (a *App) runHarvest(args []string) error {
	fs := flag.NewFlagSet("harvest", flag.ContinueOnError)
	fs.SetOutput(a.errOut)
	a.commonFlags(fs)
	var db, project, sinceRaw, source, piRoot string
	var limit int
	var includeLive bool
	fs.StringVar(&db, "db", "", "OpenCode session database (default: ~/.local/share/opencode/opencode.db)")
	fs.StringVar(&source, "source", harvest.SourceAll, "session store: all, opencode or pi")
	fs.StringVar(&piRoot, "pi-root", "", "Pi session root (default: ~/.pi/agent/sessions)")
	fs.StringVar(&project, "project", "", "only sessions of this project directory (default: current directory)")
	fs.StringVar(&sinceRaw, "since", "", "only sessions started on or after this date (YYYY-MM-DD or RFC 3339)")
	fs.IntVar(&limit, "limit", 0, "maximum number of sessions, newest first")
	fs.BoolVar(&includeLive, "include-live", false, "include OpenCode sessions that are still running")
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

	summary, err := harvest.Run(context.Background(), cfg.Store, cfg.Ledger, harvest.Options{
		DB:          db,
		Project:     project,
		Since:       since,
		Limit:       limit,
		IncludeLive: includeLive,
		Source:      source,
		PiRoot:      piRoot,
	}, func(event harvest.Event) {
		state := "written"
		if !event.Written {
			state = "unchanged"
		}
		a.progressf("[%d/%d] %s %s %d messages (%s, %s)",
			event.Index, event.Total, event.Source, event.ID, event.Messages, state,
			formatSeconds(event.Elapsed))
	})
	if err != nil {
		return err
	}
	for _, warning := range summary.Warnings {
		a.progressf("warning: %s", warning)
	}
	if summary.Malformed > 0 {
		a.progressf("pi: %d malformed lines skipped", summary.Malformed)
	}
	return a.emit("harvest", fmt.Sprintf(
		"harvest: %d selected, %d written, %d unchanged, %d new, %d orphaned (%s)",
		summary.Selected, summary.Written, summary.Unchanged, summary.New, summary.Orphaned,
		formatSeconds(time.Duration(summary.Seconds*float64(time.Second)))), summary)
}

func formatSeconds(duration time.Duration) string {
	return fmt.Sprintf("%.1f s", duration.Seconds())
}
