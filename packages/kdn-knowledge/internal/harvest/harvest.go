// Package harvest reads the session stores and writes one normalised corpus record per session.
// It never deletes a record: a session that left its store is marked orphaned.
package harvest

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"kdn-knowledge/internal/corpus"
	"kdn-knowledge/internal/pi"
	"kdn-knowledge/internal/state"
	"kdn-knowledge/internal/store"
)

// Source names.
const (
	SourceAll      = "all"
	SourceOpencode = "opencode"
	SourcePi       = "pi"
)

// Options selects the sessions of one harvest run.
type Options struct {
	DB          string
	Project     string
	Since       time.Time
	Limit       int
	IncludeLive bool
	ToolChars   int
	Source      string
	PiRoot      string
}

// Event is one progress line.
type Event struct {
	Index    int
	Total    int
	Source   string
	ID       string
	Messages int
	Elapsed  time.Duration
	Written  bool
}

// Summary is the result of one harvest run.
type Summary struct {
	DB        string         `json:"db"`
	Project   string         `json:"project"`
	Source    string         `json:"source"`
	Selected  int            `json:"selected"`
	Written   int            `json:"written"`
	Unchanged int            `json:"unchanged"`
	New       int            `json:"new"`
	Orphaned  int            `json:"orphaned"`
	Messages  int            `json:"messages"`
	BySource  map[string]int `json:"by_source"`
	Malformed int            `json:"malformed_lines"`
	Warnings  []string       `json:"warnings"`
	Seconds   float64        `json:"seconds"`
}

type loadResult struct {
	session   corpus.Session
	malformed int
	skipped   bool
}

type candidate struct {
	source string
	row    corpus.Row
	load   func(context.Context) (loadResult, error)
}

// Run executes one harvest.
func Run(ctx context.Context, st *store.Store, ledger *state.State, opts Options, progress func(Event)) (*Summary, error) {
	started := time.Now()
	if opts.Source == "" {
		opts.Source = SourceAll
	}
	switch opts.Source {
	case SourceAll, SourceOpencode, SourcePi:
	default:
		return nil, fmt.Errorf("unknown source %q; use all, opencode or pi", opts.Source)
	}
	if progress == nil {
		progress = func(Event) {}
	}

	candidates, present, warnings, err := collect(ctx, opts)
	if err != nil {
		return nil, err
	}
	sort.SliceStable(candidates, func(i, j int) bool {
		if !candidates[i].row.Created.Equal(candidates[j].row.Created) {
			return candidates[i].row.Created.After(candidates[j].row.Created)
		}
		return candidates[i].row.ID > candidates[j].row.ID
	})
	if opts.Limit > 0 && len(candidates) > opts.Limit {
		candidates = candidates[:opts.Limit]
	}

	summary := &Summary{
		DB:       opts.DB,
		Project:  opts.Project,
		Source:   opts.Source,
		Selected: len(candidates),
		BySource: map[string]int{},
		Warnings: warnings,
	}
	for index, item := range candidates {
		sessionStarted := time.Now()
		loaded, err := item.load(ctx)
		if err != nil {
			return nil, fmt.Errorf("session %s (%s): %w", item.row.ID, item.source, err)
		}
		summary.Malformed += loaded.malformed
		if loaded.skipped {
			continue
		}
		session := loaded.session
		previous, known := ledger.Get(session.ID)
		unchanged := known && previous.Hash == session.Hash &&
			previous.Status != state.StatusOrphaned && fileExists(st.CorpusPath(session.ID))

		if !unchanged {
			if err := store.WriteJSON(st.CorpusPath(session.ID), session); err != nil {
				return nil, err
			}
			summary.Written++
		} else {
			summary.Unchanged++
		}

		entry := previous
		entry.Hash = session.Hash
		entry.Source = item.source
		entry.Started = session.Started.Format(time.RFC3339)
		switch {
		case !known:
			entry.Status = state.StatusNew
			entry.Attempts = 0
			entry.Reason = ""
		case previous.Hash != session.Hash:
			entry.Status = state.StatusNew
			entry.Attempts = 0
			entry.Reason = ""
		case previous.Status == state.StatusOrphaned:
			entry.Status = state.StatusNew
			entry.Attempts = 0
			entry.Reason = ""
		}
		ledger.Put(session.ID, entry)
		if entry.Status == state.StatusNew {
			summary.New++
		}
		if err := ledger.Save(); err != nil {
			return nil, err
		}
		summary.Messages += len(session.Messages)
		summary.BySource[item.source]++
		progress(Event{
			Index:    index + 1,
			Total:    len(candidates),
			Source:   item.source,
			ID:       session.ID,
			Messages: len(session.Messages),
			Elapsed:  time.Since(sessionStarted),
			Written:  !unchanged,
		})
	}

	summary.Orphaned = markOrphans(ledger, present)
	if summary.Orphaned > 0 {
		if err := ledger.Save(); err != nil {
			return nil, err
		}
	}
	summary.Seconds = time.Since(started).Seconds()
	return summary, nil
}

// collect reads the selection metadata of every enabled source, and the full id set that the
// orphan pass needs.
func collect(ctx context.Context, opts Options) ([]candidate, map[string]map[string]struct{}, []string, error) {
	candidates := make([]candidate, 0, 512)
	present := map[string]map[string]struct{}{}
	warnings := make([]string, 0, 4)

	if enabled(opts.Source, SourceOpencode) {
		if _, err := os.Stat(opts.DB); err != nil {
			if opts.Source == SourceOpencode {
				return nil, nil, nil, fmt.Errorf("session database %s: %w", opts.DB, err)
			}
			warnings = append(warnings, "opencode source skipped: "+err.Error())
		} else {
			rows, err := corpus.Sessions(ctx, opts.DB, corpus.Query{
				Project:     opts.Project,
				Since:       opts.Since,
				Limit:       0,
				IncludeLive: opts.IncludeLive,
			})
			if err != nil {
				return nil, nil, nil, err
			}
			ids, err := corpus.AllIDs(ctx, opts.DB)
			if err != nil {
				return nil, nil, nil, err
			}
			present[SourceOpencode] = ids
			for _, row := range rows {
				row := row
				candidates = append(candidates, candidate{
					source: SourceOpencode,
					row:    row,
					load: func(ctx context.Context) (loadResult, error) {
						raw, err := corpus.Messages(ctx, opts.DB, row.ID)
						if err != nil {
							return loadResult{}, err
						}
						return loadResult{session: corpus.Build(row, raw, opts.ToolChars)}, nil
					},
				})
			}
		}
	}

	if enabled(opts.Source, SourcePi) {
		paths, err := pi.Walk(opts.PiRoot)
		if err != nil {
			if opts.Source == SourcePi {
				return nil, nil, nil, fmt.Errorf("Pi session root %s: %w", opts.PiRoot, err)
			}
			warnings = append(warnings, "pi source skipped: "+err.Error())
		} else {
			ids := make(map[string]struct{}, len(paths))
			for _, path := range paths {
				meta, err := pi.Index(path)
				if err != nil {
					warnings = append(warnings, "pi: "+err.Error())
					continue
				}
				ids[meta.ID] = struct{}{}
				if !projectMatch(meta.Cwd, opts.Project) {
					continue
				}
				if !opts.Since.IsZero() && meta.Started.Before(opts.Since) {
					continue
				}
				path := path
				row := corpus.Row{
					ID:        meta.ID,
					Title:     meta.Title,
					Directory: meta.Cwd,
					Created:   meta.Started,
					Updated:   meta.Updated,
				}
				candidates = append(candidates, candidate{
					source: SourcePi,
					row:    row,
					load: func(context.Context) (loadResult, error) {
						session, malformed, err := pi.Load(path, opts.ToolChars)
						if err != nil {
							return loadResult{malformed: malformed}, err
						}
						if session.ID == "" {
							return loadResult{malformed: malformed, skipped: true}, nil
						}
						return loadResult{session: session, malformed: malformed}, nil
					},
				})
			}
			present[SourcePi] = ids
		}
	}
	return candidates, present, warnings, nil
}

// markOrphans flags the sessions that their store no longer lists. A source that this run did
// not read is left alone.
func markOrphans(ledger *state.State, present map[string]map[string]struct{}) int {
	orphaned := 0
	for id, entry := range ledger.Sessions {
		source := entry.Source
		if source == "" {
			source = SourceOpencode
		}
		ids, enabled := present[source]
		if !enabled {
			continue
		}
		if _, ok := ids[id]; ok {
			continue
		}
		if entry.Status == state.StatusOrphaned {
			continue
		}
		entry.Status = state.StatusOrphaned
		entry.Reason = "the session is no longer in the " + source + " store"
		ledger.Put(id, entry)
		orphaned++
	}
	return orphaned
}

func enabled(selected, source string) bool {
	return selected == SourceAll || selected == source
}

func projectMatch(directory, project string) bool {
	if strings.TrimSpace(project) == "" {
		return true
	}
	directory = strings.TrimRight(directory, "/")
	project = strings.TrimRight(project, "/")
	return directory == project || strings.HasPrefix(directory, project+"/")
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
