// Package worklog parses the append-only worklog files. An entry starts at a level-2 heading, or
// at a level-1 heading when the file has no level-2 heading. The heading may carry a date anywhere
// in its text; the real worklogs use both `## 2026-11-12T04:56:00Z — …` and
// `## Verbatim reports — 2026-10-15`.
package worklog

import (
	"encoding/json"
	"os"
	"regexp"
	"strings"
	"time"

	"kdn-journal/internal/frontmatter"
	"kdn-journal/internal/markdown"
)

// Entry is one dated section of a worklog.
type Entry struct {
	Heading      string    `json:"heading"`
	Timestamp    time.Time `json:"timestamp,omitempty"`
	HasTimestamp bool      `json:"has_timestamp"`
	Precise      bool      `json:"precise"`
	Body         string    `json:"body,omitempty"`
	Line         int       `json:"-"`
}

// Worklog is one parsed worklog file.
type Worklog struct {
	Path    string    `json:"path"`
	Entries []Entry   `json:"entries"`
	ModTime time.Time `json:"-"`
}

// MarshalJSON omits a missing timestamp instead of emitting the zero time.
func (e Entry) MarshalJSON() ([]byte, error) {
	type alias Entry
	data, err := json.Marshal(alias(e))
	if err != nil {
		return nil, err
	}
	var fields map[string]any
	if err := json.Unmarshal(data, &fields); err != nil {
		return nil, err
	}
	if e.Timestamp.IsZero() {
		delete(fields, "timestamp")
	}
	return json.Marshal(fields)
}

var dateRE = regexp.MustCompile(`\d{4}-\d{2}-\d{2}(?:T[0-9:+\-Z.]+)?`)

// ParseFile reads and parses one worklog file.
func ParseFile(path string) (*Worklog, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	return Parse(data, path, info.ModTime()), nil
}

// Parse parses worklog data.
func Parse(data []byte, path string, modTime time.Time) *Worklog {
	doc := frontmatter.Parse(data)
	lines := markdown.Scan(doc.Body)
	level := entryLevel(lines)
	w := &Worklog{Path: path, ModTime: modTime}
	if level == 0 {
		return w
	}
	for i := 0; i < len(lines); i++ {
		line := lines[i]
		if line.Kind != markdown.KindHeading || line.Level != level {
			continue
		}
		entry := Entry{Heading: line.Text, Line: line.Number}
		if match := dateRE.FindString(line.Text); match != "" {
			if ts, ok := frontmatter.ParseTime(match); ok {
				entry.Timestamp = ts
				entry.HasTimestamp = true
				entry.Precise = strings.Contains(match, "T")
			}
		}
		var body strings.Builder
		for j := i + 1; j < len(lines); j++ {
			next := lines[j]
			if next.Kind == markdown.KindHeading && next.Level <= level {
				break
			}
			body.WriteString(next.Raw)
			body.WriteByte('\n')
		}
		entry.Body = strings.TrimRight(body.String(), "\n")
		w.Entries = append(w.Entries, entry)
	}
	return w
}

// Tail returns the last n entries in file order.
func (w *Worklog) Tail(n int) []Entry {
	if n <= 0 || n >= len(w.Entries) {
		return append([]Entry(nil), w.Entries...)
	}
	return append([]Entry(nil), w.Entries[len(w.Entries)-n:]...)
}

func entryLevel(lines []markdown.Line) int {
	hasTwo := false
	hasOne := false
	for _, line := range lines {
		if line.Kind != markdown.KindHeading {
			continue
		}
		if line.Level == 2 {
			hasTwo = true
		}
		if line.Level == 1 {
			hasOne = true
		}
	}
	if hasTwo {
		return 2
	}
	if hasOne {
		return 1
	}
	return 0
}
