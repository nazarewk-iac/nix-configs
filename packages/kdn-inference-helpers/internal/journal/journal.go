// Package journal is the append-only record of everything the runtime does, plus the aggregation
// behind `GET /stats`.
//
// One JSON object per line, and the file is the only durable state the runtime keeps besides the
// selected profile. Records are `map[string]any` on purpose: the Python implementation wrote a
// different field set per event, and a struct with optional fields would either drop those fields
// or need a hand-written marshaller for every variant. The compatibility rule is that an unknown
// event name or a record without a duration is aggregated, never rejected.
package journal

import (
	"bufio"
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// Event names the runtime writes. Keeping them in one place makes a typo a compile error.
const (
	EventSwitch        = "switch"
	EventEngineLoad    = "engine_load"
	EventEngineStop    = "engine_stop"
	EventCacheDrop     = "cache_drop"
	EventDrain         = "drain"
	EventDrainTimeout  = "drain_timeout"
	EventRequest       = "request"
	EventCompanionUp   = "companion_up"
	EventCompanionDown = "companion_down"
)

// Journal appends to one file and reads it back. It is safe for concurrent use.
type Journal struct {
	path string
	mu   sync.Mutex
}

// New returns a journal at path. The directory is created on the first append.
func New(path string) *Journal { return &Journal{path: path} }

// Path is the file this journal writes, for logging.
func (j *Journal) Path() string { return j.path }

// Append writes one record, stamping `ts` and leaving the event name to the caller. A write failure
// is returned but never fatal to the caller: a switch must not fail because the journal is full.
func (j *Journal) Append(record map[string]any) error {
	if _, ok := record["ts"]; !ok {
		record["ts"] = float64(time.Now().UnixNano()) / 1e9
	}
	line, err := json.Marshal(record)
	if err != nil {
		return err
	}
	j.mu.Lock()
	defer j.mu.Unlock()
	if err := os.MkdirAll(filepath.Dir(j.path), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(j.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	w := bufio.NewWriter(f)
	if _, err := w.Write(append(line, '\n')); err != nil {
		return err
	}
	return w.Flush()
}

// Events returns the newest limit records, oldest first. A limit of zero returns everything.
func (j *Journal) Events(limit int) []map[string]any {
	j.mu.Lock()
	defer j.mu.Unlock()
	f, err := os.Open(j.path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []map[string]any
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}
		var rec map[string]any
		if err := json.Unmarshal(line, &rec); err != nil {
			continue // a torn line from an older version is skipped, not fatal
		}
		out = append(out, rec)
	}
	if limit > 0 && len(out) > limit {
		out = out[len(out)-limit:]
	}
	return out
}

// LastSwitch is the newest switch record, which `/status` reports so an agent can notice a switch
// it did not intend.
func (j *Journal) LastSwitch() (map[string]any, bool) {
	events := j.Events(0)
	for i := len(events) - 1; i >= 0; i-- {
		if events[i]["event"] == EventSwitch {
			return events[i], true
		}
	}
	return nil, false
}

// Bucket is the aggregate of one event name or one profile transition.
type Bucket struct {
	N      int     `json:"n"`
	Median float64 `json:"median"`
	P90    float64 `json:"p90"`
	Max    float64 `json:"max"`
}

// Stats is the JSON shape `GET /stats` returns.
type Stats struct {
	Events       int               `json:"events"`
	FirstTS      float64           `json:"first_ts"`
	ByEvent      map[string]Bucket `json:"by_event"`
	ByTransition map[string]Bucket `json:"by_transition"`
}

// Compute aggregates the journal. Only records that carry a numeric `seconds` contribute to a
// bucket; a companion unload records `loaded_for` instead, so it will not appear as a duration.
func (j *Journal) Stats() Stats {
	events := j.Events(0)
	byEvent := map[string][]float64{}
	byTransition := map[string][]float64{}
	stats := Stats{Events: len(events), ByEvent: map[string]Bucket{}, ByTransition: map[string]Bucket{}}
	if len(events) > 0 {
		stats.FirstTS, _ = events[0]["ts"].(float64)
	}
	for _, rec := range events {
		secs, ok := number(rec["seconds"])
		if !ok {
			continue
		}
		name, _ := rec["event"].(string)
		byEvent[name] = append(byEvent[name], secs)
		if name == EventSwitch {
			from, _ := rec["from"].(string)
			to, _ := rec["to"].(string)
			byTransition[from+"->"+to] = append(byTransition[from+"->"+to], secs)
		}
	}
	for name, values := range byEvent {
		stats.ByEvent[name] = summarise(values)
	}
	for name, values := range byTransition {
		stats.ByTransition[name] = summarise(values)
	}
	return stats
}

func summarise(values []float64) Bucket {
	sort.Float64s(values)
	return Bucket{
		N:      len(values),
		Median: percentile(values, 50),
		P90:    percentile(values, 90),
		Max:    values[len(values)-1],
	}
}

// percentile uses round-half-to-even, because Python's round() is banker's rounding: the aggregate
// must not drift by one index against the Python implementation (n=6 gives index 2, not 3).
func percentile(sorted []float64, pct float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	idx := int(math.RoundToEven((pct / 100) * float64(len(sorted)-1)))
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}
	return sorted[idx]
}

// number accepts the float64 a JSON decode produces and the int a caller may set directly.
func number(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	default:
		return 0, false
	}
}
