// Package state keeps the per-session ledger that makes a run resumable.
//
// The file is rewritten after every session through an atomic rename, so a dropped connection or
// a kill loses at most the session in flight.
package state

import (
	"fmt"
	"os"
	"sort"
	"time"

	"kdn-knowledge/internal/store"
)

// Status is the lifecycle state of one session in the pipeline.
type Status string

// The four states of a session.
const (
	StatusNew      Status = "new"
	StatusDone     Status = "done"
	StatusFailed   Status = "failed"
	StatusOrphaned Status = "orphaned"
)

// Entry is what the pipeline remembers about one session.
type Entry struct {
	Hash   string `json:"hash"`
	Status Status `json:"status"`
	// Source is the store that produced the session: opencode or pi. An older entry carries no
	// source and is treated as opencode.
	Source   string  `json:"source,omitempty"`
	Attempts int     `json:"attempts"`
	Seconds  float64 `json:"seconds,omitempty"`
	Reason   string  `json:"reason,omitempty"`
	Started  string  `json:"started,omitempty"`
	Updated  string  `json:"updated,omitempty"`
}

// State is the whole ledger. The map is encoded with sorted keys by encoding/json.
type State struct {
	Version  int              `json:"version"`
	Sessions map[string]Entry `json:"sessions"`

	path string
	now  func() time.Time
}

// Load reads the ledger, or returns an empty one when the file does not exist.
func Load(path string) (*State, error) {
	state := &State{Version: 1, Sessions: map[string]Entry{}, path: path, now: time.Now}
	if _, err := os.Stat(path); err != nil {
		if os.IsNotExist(err) {
			return state, nil
		}
		return nil, err
	}
	if err := store.ReadJSON(path, state); err != nil {
		return nil, fmt.Errorf("state file is corrupt: %w", err)
	}
	if state.Sessions == nil {
		state.Sessions = map[string]Entry{}
	}
	if state.Version == 0 {
		state.Version = 1
	}
	state.path = path
	state.now = time.Now
	return state, nil
}

// SetNow overrides the clock, for tests.
func (s *State) SetNow(now func() time.Time) {
	if now != nil {
		s.now = now
	}
}

// Path is the file the ledger is saved to.
func (s *State) Path() string { return s.path }

// Get returns the entry of one session.
func (s *State) Get(id string) (Entry, bool) {
	entry, ok := s.Sessions[id]
	return entry, ok
}

// Put stores one entry and stamps it with the current time.
func (s *State) Put(id string, entry Entry) {
	entry.Updated = s.now().UTC().Format(time.RFC3339)
	s.Sessions[id] = entry
}

// Save writes the ledger atomically.
func (s *State) Save() error {
	if s.path == "" {
		return fmt.Errorf("state has no path")
	}
	return store.WriteJSON(s.path, s)
}

// Counts returns the number of sessions per status, with every known status present.
func (s *State) Counts() map[Status]int {
	counts := map[Status]int{
		StatusNew:      0,
		StatusDone:     0,
		StatusFailed:   0,
		StatusOrphaned: 0,
	}
	for _, entry := range s.Sessions {
		counts[entry.Status]++
	}
	return counts
}

// Statuses is the stable order that Counts is printed in.
var Statuses = []Status{StatusNew, StatusDone, StatusFailed, StatusOrphaned}

// AverageSeconds returns the mean extraction time of the finished sessions, and how many
// sessions that mean covers.
func (s *State) AverageSeconds() (float64, int) {
	total := 0.0
	count := 0
	for _, entry := range s.Sessions {
		if entry.Status != StatusDone || entry.Seconds <= 0 {
			continue
		}
		total += entry.Seconds
		count++
	}
	if count == 0 {
		return 0, 0
	}
	return total / float64(count), count
}

// Failed returns the failed sessions sorted by id, with their reasons.
func (s *State) Failed() []FailedSession {
	failed := make([]FailedSession, 0)
	for id, entry := range s.Sessions {
		if entry.Status != StatusFailed {
			continue
		}
		failed = append(failed, FailedSession{ID: id, Reason: entry.Reason, Attempts: entry.Attempts})
	}
	sort.Slice(failed, func(i, j int) bool { return failed[i].ID < failed[j].ID })
	return failed
}

// FailedSession is one row of the failure report.
type FailedSession struct {
	ID       string `json:"id"`
	Reason   string `json:"reason"`
	Attempts int    `json:"attempts"`
}

// New returns an empty ledger bound to path. It is the constructor the tests use.
func New(path string) *State {
	return &State{Version: 1, Sessions: map[string]Entry{}, path: path, now: time.Now}
}
