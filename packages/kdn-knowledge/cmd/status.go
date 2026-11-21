package cmd

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"kdn-knowledge/internal/guard"
	"kdn-knowledge/internal/llm"
	"kdn-knowledge/internal/state"
	"kdn-knowledge/internal/store"
)

// DefaultFrontierModel is the resting engine. `status` asks the placement manager about this
// model, because it is the one that answers without a profile switch.
const DefaultFrontierModel = "qfn"

type sessionCounts struct {
	New      int `json:"new"`
	Done     int `json:"done"`
	Failed   int `json:"failed"`
	Orphaned int `json:"orphaned"`
}

type statusSummary struct {
	DataDir         string         `json:"data_dir"`
	DB              string         `json:"db"`
	Endpoint        string         `json:"endpoint"`
	EndpointAllowed bool           `json:"endpoint_allowed"`
	EndpointIssue   string         `json:"endpoint_issue,omitempty"`
	KeyFile         string         `json:"key_file"`
	KeyPresent      bool           `json:"key_present"`
	KeyError        string         `json:"key_error,omitempty"`
	ExtractModel    string         `json:"extract_model"`
	MergeModel      string         `json:"merge_model"`
	FrontierModel   string         `json:"frontier_model"`
	Manager         string         `json:"manager"`
	Corpus          int            `json:"corpus"`
	Candidates      int            `json:"candidates"`
	CandidateItems  int            `json:"candidate_items"`
	Sessions        sessionCounts  `json:"sessions"`
	Sources         map[string]int `json:"sources"`
	AverageSeconds  float64        `json:"average_seconds,omitempty"`
	AverageFrom     int            `json:"average_from,omitempty"`
	EstimateSeconds float64        `json:"estimate_seconds,omitempty"`
	LastRun         string         `json:"last_run"`
	LastProposal    string         `json:"last_proposal"`
	Decide          string         `json:"decide"`
	DecideWhy       []string       `json:"decide_why"`
	Warning         string         `json:"warning,omitempty"`
}

func (a *App) runStatus(args []string) error {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	fs.SetOutput(a.errOut)
	a.commonFlags(fs)
	a.modelFlags(fs)
	if err := a.parse(fs, args); err != nil {
		return err
	}
	cfg, err := a.prepare()
	if err != nil {
		return err
	}
	summary := &statusSummary{
		DataDir:       cfg.DataDir,
		DB:            cfg.DB,
		Endpoint:      cfg.Endpoint,
		KeyFile:       cfg.KeyFile,
		KeyPresent:    cfg.APIKey != "",
		ExtractModel:  cfg.Model,
		MergeModel:    cfg.MergeModel,
		FrontierModel: DefaultFrontierModel,
		Manager:       cfg.Manager,
		DecideWhy:     []string{},
	}
	if cfg.KeyError != nil {
		summary.KeyError = cfg.KeyError.Error()
	}
	if _, err := guard.Check(cfg.Endpoint, a.AllowHosts); err != nil {
		summary.EndpointIssue = err.Error()
	} else {
		summary.EndpointAllowed = true
	}
	if cfg.Model != DefaultFrontierModel {
		summary.Warning = fmt.Sprintf(
			"model %q is not the resting frontier: it needs a colo profile (omni-fast or omni-max) "+
				"and a 58-74 s engine switch that stops every other session", cfg.Model)
	}

	if ids, err := cfg.Store.ListJSON(cfg.Store.CorpusDir()); err == nil {
		summary.Corpus = len(ids)
	}
	if ids, err := cfg.Store.ListJSON(cfg.Store.CandidatesDir()); err == nil {
		summary.Candidates = len(ids)
	}
	summary.CandidateItems = countCandidateItems(cfg.Store.CandidatesDir())
	counts := cfg.Ledger.Counts()
	summary.Sessions = sessionCounts{
		New:      counts[state.StatusNew],
		Done:     counts[state.StatusDone],
		Failed:   counts[state.StatusFailed],
		Orphaned: counts[state.StatusOrphaned],
	}
	summary.Sources = map[string]int{}
	for _, entry := range cfg.Ledger.Sessions {
		source := entry.Source
		if source == "" {
			source = "opencode"
		}
		summary.Sources[source]++
	}
	if average, sample := cfg.Ledger.AverageSeconds(); sample > 0 {
		summary.AverageSeconds = average
		summary.AverageFrom = sample
		summary.EstimateSeconds = average * float64(summary.Corpus)
	}
	summary.LastRun = newestFile(cfg.Store.RunsDir())
	summary.LastProposal = newestDir(cfg.Store.ProposalsDir())

	if strings.TrimSpace(cfg.Manager) == "" {
		summary.Decide = "skipped"
		summary.DecideWhy = []string{"no --manager configured; on brys pass --manager http://127.0.0.1:8181"}
	} else {
		verdict, err := llm.Decide(context.Background(), cfg.Manager, DefaultFrontierModel)
		var cooldown *llm.CooldownError
		switch {
		case errors.As(err, &cooldown):
			summary.Decide = "cooldown"
			summary.DecideWhy = []string{err.Error() + " — not a capacity refusal"}
		case err != nil:
			summary.Decide = "unreachable"
			summary.DecideWhy = []string{err.Error() + " — unknown, continue"}
		case verdict.Admits():
			summary.Decide = verdict.Summary()
		default:
			summary.Decide = verdict.Summary()
			summary.DecideWhy = verdict.Trace(4)
		}
	}

	if a.JSON {
		return a.emit("status", "", summary)
	}
	out := a.out
	fmt.Fprintf(out, "data dir:       %s\n", summary.DataDir)
	fmt.Fprintf(out, "database:       %s\n", summary.DB)
	if summary.EndpointAllowed {
		fmt.Fprintf(out, "endpoint:       %s\n", summary.Endpoint)
	} else {
		fmt.Fprintf(out, "endpoint:       %s (REFUSED: %s)\n", summary.Endpoint, summary.EndpointIssue)
	}
	if summary.KeyPresent {
		fmt.Fprintf(out, "api key:        %s (ok)\n", summary.KeyFile)
	} else {
		fmt.Fprintf(out, "api key:        %s (missing: %s)\n", summary.KeyFile, summary.KeyError)
	}
	fmt.Fprintf(out, "extract model:  %s\n", summary.ExtractModel)
	fmt.Fprintf(out, "merge model:    %s\n", summary.MergeModel)
	fmt.Fprintf(out, "corpus:         %d sessions\n", summary.Corpus)
	fmt.Fprintf(out, "candidates:     %d sessions, %d items\n", summary.Candidates, summary.CandidateItems)
	fmt.Fprintf(out, "sessions:       new %d, done %d, failed %d, orphaned %d\n",
		summary.Sessions.New, summary.Sessions.Done, summary.Sessions.Failed, summary.Sessions.Orphaned)
	if len(summary.Sources) > 0 {
		fmt.Fprintf(out, "sources:        %s\n", formatSources(summary.Sources))
	}
	if summary.AverageFrom > 0 {
		fmt.Fprintf(out, "estimate:       ~%s for %d sessions (%.1f s each, from %d finished)\n",
			formatEstimate(summary.EstimateSeconds), summary.Corpus, summary.AverageSeconds, summary.AverageFrom)
	}
	fmt.Fprintf(out, "last run:       %s\n", orNone(summary.LastRun))
	fmt.Fprintf(out, "last proposal:  %s\n", orNone(summary.LastProposal))
	switch summary.Decide {
	case "skipped":
		fmt.Fprintf(out, "/decide: skipped (no --manager; on brys pass --manager http://127.0.0.1:8181)\n")
	case "unreachable":
		fmt.Fprintf(out, "/decide %s: unreachable (%s) — unknown, continue\n", DefaultFrontierModel, cfg.Manager)
	default:
		fmt.Fprintf(out, "/decide %s: %s\n", DefaultFrontierModel, summary.Decide)
		for _, line := range summary.DecideWhy {
			fmt.Fprintf(out, "  - %s\n", line)
		}
	}
	if summary.Warning != "" {
		fmt.Fprintf(out, "warning:        %s\n", summary.Warning)
	}
	return nil
}

func formatEstimate(seconds float64) string {
	switch {
	case seconds <= 0:
		return "unknown"
	case seconds < 90:
		return fmt.Sprintf("%.0f s", seconds)
	case seconds < 5400:
		return fmt.Sprintf("%.0f min", seconds/60)
	default:
		return fmt.Sprintf("%.1f h", seconds/3600)
	}
}

// formatSources prints the session count per store, sorted by name.
func formatSources(sources map[string]int) string {
	names := make([]string, 0, len(sources))
	for name := range sources {
		names = append(names, name)
	}
	sort.Strings(names)
	parts := make([]string, 0, len(names))
	for _, name := range names {
		parts = append(parts, fmt.Sprintf("%s %d", name, sources[name]))
	}
	return strings.Join(parts, ", ")
}

func countCandidateItems(dir string) int {
	ids, err := store.ListJSON(dir)
	if err != nil {
		return 0
	}
	total := 0
	for _, id := range ids {
		var file struct {
			Items []struct {
				Statement string `json:"statement"`
			} `json:"items"`
		}
		if err := store.ReadJSON(filepath.Join(dir, id+".json"), &file); err != nil {
			continue
		}
		total += len(file.Items)
	}
	return total
}

func newestFile(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() {
			names = append(names, entry.Name())
		}
	}
	if len(names) == 0 {
		return ""
	}
	sort.Strings(names)
	return names[len(names)-1]
}

func newestDir(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			names = append(names, entry.Name())
		}
	}
	if len(names) == 0 {
		return ""
	}
	sort.Strings(names)
	return names[len(names)-1]
}

func orNone(value string) string {
	if value == "" {
		return "none"
	}
	return value
}
