// Package pipeline holds the two steps that touch both the store and the ledger: choosing the
// sessions that extraction still owes, and finishing one session.
package pipeline

import (
	"context"
	"sort"
	"time"

	"kdn-knowledge/internal/corpus"
	"kdn-knowledge/internal/extract"
	"kdn-knowledge/internal/llm"
	"kdn-knowledge/internal/state"
	"kdn-knowledge/internal/store"
)

// ExtractOptions tunes one extract run.
type ExtractOptions struct {
	ChunkChars int
	MaxChunks  int
	Now        func() time.Time
}

// Outcome is the result of one session.
type Outcome struct {
	ID        string
	Items     int
	Chunks    int
	Calls     int
	Truncated bool
	Duration  time.Duration
	Err       error
}

// Candidates returns the sessions that still need extraction, newest first.
//
// A session is a candidate while its status is new or failed. --force adds the done sessions.
func Candidates(ledger *state.State, force bool, limit int) []string {
	type row struct {
		id      string
		started string
	}
	rows := make([]row, 0, len(ledger.Sessions))
	for id, entry := range ledger.Sessions {
		switch entry.Status {
		case state.StatusNew, state.StatusFailed:
		case state.StatusDone:
			if !force {
				continue
			}
		default:
			continue
		}
		rows = append(rows, row{id: id, started: entry.Started})
	}
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i].started != rows[j].started {
			return rows[i].started > rows[j].started
		}
		return rows[i].id > rows[j].id
	})
	ids := make([]string, 0, len(rows))
	for _, item := range rows {
		ids = append(ids, item.id)
		if limit > 0 && len(ids) >= limit {
			break
		}
	}
	return ids
}

// LoadCorpus reads one corpus record.
func LoadCorpus(st *store.Store, id string) (corpus.Session, error) {
	var session corpus.Session
	err := store.ReadJSON(st.CorpusPath(id), &session)
	return session, err
}

// ExtractOne runs one session, writes candidates/<id>.json on success, and updates the ledger.
// The ledger is saved on both paths, so a killed run loses at most this session.
func ExtractOne(
	ctx context.Context,
	client *llm.Client,
	st *store.Store,
	ledger *state.State,
	session corpus.Session,
	opts ExtractOptions,
) Outcome {
	now := time.Now
	if opts.Now != nil {
		now = opts.Now
	}
	result, err := extract.ExtractSession(ctx, client, session, extract.Options{
		ChunkChars: opts.ChunkChars,
		MaxChunks:  opts.MaxChunks,
	})
	entry, _ := ledger.Get(session.ID)
	outcome := Outcome{ID: session.ID}
	if err != nil {
		entry.Status = state.StatusFailed
		entry.Attempts++
		entry.Reason = err.Error()
		ledger.Put(session.ID, entry)
		_ = ledger.Save()
		outcome.Err = err
		return outcome
	}
	file := extract.File{
		Session:     session.ID,
		Model:       client.Model,
		ExtractedAt: now().UTC().Format(time.RFC3339),
		Truncated:   result.Truncated,
		Items:       result.Items,
	}
	if writeErr := store.WriteJSON(st.CandidatesPath(session.ID), file); writeErr != nil {
		entry.Status = state.StatusFailed
		entry.Attempts++
		entry.Reason = writeErr.Error()
		ledger.Put(session.ID, entry)
		_ = ledger.Save()
		outcome.Err = writeErr
		return outcome
	}
	entry.Status = state.StatusDone
	entry.Attempts = 0
	entry.Reason = ""
	entry.Seconds = result.Duration.Seconds()
	ledger.Put(session.ID, entry)
	_ = ledger.Save()

	outcome.Items = len(result.Items)
	outcome.Chunks = result.Chunks
	outcome.Calls = result.Calls
	outcome.Truncated = result.Truncated
	outcome.Duration = result.Duration
	return outcome
}
