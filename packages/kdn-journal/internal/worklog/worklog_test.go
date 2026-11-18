package worklog_test

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"kdn-journal/internal/worklog"
)

var worklogModTime = time.Date(2020, 1, 2, 3, 4, 5, 0, time.UTC)

func parseWorklog(t *testing.T, data, path string) *worklog.Worklog {
	t.Helper()
	return worklog.Parse([]byte(data), path, worklogModTime)
}

func entryHeadings(entries []worklog.Entry) []string {
	out := make([]string, len(entries))
	for i, entry := range entries {
		out[i] = entry.Heading
	}
	return out
}

func TestDatedHeadings(t *testing.T) {
	data := `# Worklog

## 2026-11-12T04:56:00Z — first entry

body one

### Detail

more detail

## 2026-11-13 — second entry

body two
`
	w := parseWorklog(t, data, "session/worklog.md")

	if w.Path != "session/worklog.md" {
		t.Errorf("Path = %q, want %q", w.Path, "session/worklog.md")
	}
	if !w.ModTime.Equal(worklogModTime) {
		t.Errorf("ModTime = %s, want %s", w.ModTime, worklogModTime)
	}
	if len(w.Entries) != 2 {
		t.Fatalf("entries = %v, want 2", entryHeadings(w.Entries))
	}

	first := w.Entries[0]
	if first.Heading != "2026-11-12T04:56:00Z — first entry" {
		t.Errorf("first Heading = %q", first.Heading)
	}
	if !first.HasTimestamp {
		t.Fatal("first HasTimestamp = false, want true")
	}
	if want := time.Date(2026, 11, 12, 4, 56, 0, 0, time.UTC); !first.Timestamp.Equal(want) {
		t.Errorf("first Timestamp = %s, want %s", first.Timestamp, want)
	}
	if first.Line != 3 {
		t.Errorf("first Line = %d, want 3", first.Line)
	}
	if body := strings.TrimSpace(first.Body); body != "body one\n\n### Detail\n\nmore detail" {
		t.Errorf("first Body = %q, want it to include the level-3 subsection", body)
	}

	second := w.Entries[1]
	if !second.HasTimestamp {
		t.Fatal("second HasTimestamp = false, want true")
	}
	if want := time.Date(2026, 11, 13, 0, 0, 0, 0, time.UTC); !second.Timestamp.Equal(want) {
		t.Errorf("second Timestamp = %s, want %s", second.Timestamp, want)
	}
	if body := strings.TrimSpace(second.Body); body != "body two" {
		t.Errorf("second Body = %q, want %q", body, "body two")
	}
}

func TestDateAnywhereInHeading(t *testing.T) {
	w := parseWorklog(t, "## Verbatim reports — 2026-10-15\n\ntext\n", "session/worklog.md")
	if len(w.Entries) != 1 {
		t.Fatalf("entries = %v, want 1", entryHeadings(w.Entries))
	}
	entry := w.Entries[0]
	if !entry.HasTimestamp {
		t.Fatal("HasTimestamp = false, want true")
	}
	if want := time.Date(2026, 10, 15, 0, 0, 0, 0, time.UTC); !entry.Timestamp.Equal(want) {
		t.Errorf("Timestamp = %s, want %s", entry.Timestamp, want)
	}
}

func TestTimestampWithoutSeconds(t *testing.T) {
	// A bare ISO 8601 heading, as the 2026-11-14 session journal uses. RFC3339 needs
	// seconds, so this form used to parse as an undated entry and render as "—".
	w := parseWorklog(t, "## 2026-11-14T05:09+01:00\n\ntext\n", "session/worklog.md")
	if len(w.Entries) != 1 {
		t.Fatalf("entries = %v, want 1", entryHeadings(w.Entries))
	}
	entry := w.Entries[0]
	if !entry.HasTimestamp {
		t.Fatal("HasTimestamp = false, want true")
	}
	if !entry.Precise {
		t.Error("Precise = false, want true")
	}
	want := time.Date(2026, 11, 14, 5, 9, 0, 0, time.FixedZone("", 3600))
	if !entry.Timestamp.Equal(want) {
		t.Errorf("Timestamp = %s, want %s", entry.Timestamp, want)
	}
}

func TestUndatedHeading(t *testing.T) {
	w := parseWorklog(t, "## Plan review\n\ntext\n", "session/worklog.md")
	if len(w.Entries) != 1 {
		t.Fatalf("entries = %v, want 1", entryHeadings(w.Entries))
	}
	if w.Entries[0].HasTimestamp {
		t.Error("HasTimestamp = true, want false")
	}
	if !w.Entries[0].Timestamp.IsZero() {
		t.Errorf("Timestamp = %s, want the zero time", w.Entries[0].Timestamp)
	}
}

func TestLevelOneFallback(t *testing.T) {
	data := `# 2026-01-01 first

body one

# 2026-01-02 second

body two
`
	w := parseWorklog(t, data, "session/worklog.md")
	if want := []string{"2026-01-01 first", "2026-01-02 second"}; !reflect.DeepEqual(entryHeadings(w.Entries), want) {
		t.Fatalf("entries = %v, want %v", entryHeadings(w.Entries), want)
	}
}

func TestNoHeadings(t *testing.T) {
	w := parseWorklog(t, "just prose\n\nno headings here\n", "session/worklog.md")
	if len(w.Entries) != 0 {
		t.Errorf("entries = %v, want none", entryHeadings(w.Entries))
	}
}

func TestFencedCodeHidesHeadings(t *testing.T) {
	data := `## 2026-01-01 entry

~~~text
## 2026-01-02 not an entry
- bullet
~~~

## 2026-01-03 second
`
	w := parseWorklog(t, data, "session/worklog.md")
	if want := []string{"2026-01-01 entry", "2026-01-03 second"}; !reflect.DeepEqual(entryHeadings(w.Entries), want) {
		t.Fatalf("entries = %v, want %v", entryHeadings(w.Entries), want)
	}
	if !strings.Contains(w.Entries[0].Body, "## 2026-01-02 not an entry") {
		t.Errorf("first Body = %q, want the fenced line kept as body", w.Entries[0].Body)
	}
}

func TestBacktickFenceHidesHeadings(t *testing.T) {
	data := "## 2026-01-01 entry\n\n" + "```text\n## 2026-01-02 not an entry\n```\n"
	w := parseWorklog(t, data, "session/worklog.md")
	if len(w.Entries) != 1 {
		t.Fatalf("entries = %v, want 1", entryHeadings(w.Entries))
	}
	if !strings.Contains(w.Entries[0].Body, "## 2026-01-02 not an entry") {
		t.Errorf("Body = %q, want the fenced line kept as body", w.Entries[0].Body)
	}
}

func TestTailOrder(t *testing.T) {
	data := `## 2026-01-01 first

one

## 2026-01-02 second

two

## 2026-01-03 third

three
`
	w := parseWorklog(t, data, "session/worklog.md")

	tail := w.Tail(2)
	if want := []string{"2026-01-02 second", "2026-01-03 third"}; !reflect.DeepEqual(entryHeadings(tail), want) {
		t.Errorf("Tail(2) = %v, want %v", entryHeadings(tail), want)
	}
	if got := len(w.Tail(1)); got != 1 {
		t.Errorf("Tail(1) returned %d entries, want 1", got)
	}
	if got := len(w.Tail(0)); got != 3 {
		t.Errorf("Tail(0) returned %d entries, want all 3", got)
	}
	if got := len(w.Tail(99)); got != 3 {
		t.Errorf("Tail(99) returned %d entries, want all 3", got)
	}
}

func TestTailReturnsACopy(t *testing.T) {
	w := parseWorklog(t, "## 2026-01-01 only\n\nbody\n", "session/worklog.md")
	tail := w.Tail(1)
	tail[0].Heading = "mutated"
	if w.Entries[0].Heading != "2026-01-01 only" {
		t.Error("Tail returned a slice that aliases Entries")
	}
}

func TestNonChronologicalFile(t *testing.T) {
	data := `## 2026-11-15 first in file

newer

## 2026-11-10 earlier

older
`
	w := parseWorklog(t, data, "session/worklog.md")
	// File order is kept; Tail does not sort by timestamp.
	tail := w.Tail(1)
	if len(tail) != 1 || tail[0].Heading != "2026-11-10 earlier" {
		t.Fatalf("Tail(1) = %v, want the last heading in file order", entryHeadings(tail))
	}
	if want := time.Date(2026, 11, 10, 0, 0, 0, 0, time.UTC); !tail[0].Timestamp.Equal(want) {
		t.Errorf("Timestamp = %s, want %s", tail[0].Timestamp, want)
	}
	if want := []string{"2026-11-15 first in file", "2026-11-10 earlier"}; !reflect.DeepEqual(entryHeadings(w.Entries), want) {
		t.Errorf("entries = %v, want %v", entryHeadings(w.Entries), want)
	}
}

func TestFrontmatterStripped(t *testing.T) {
	data := `---
type: Worklog
description: A worklog
---

## 2026-01-01 entry

body
`
	w := parseWorklog(t, data, "session/worklog.md")
	if len(w.Entries) != 1 {
		t.Fatalf("entries = %v, want 1", entryHeadings(w.Entries))
	}
	if w.Entries[0].Heading != "2026-01-01 entry" {
		t.Errorf("Heading = %q", w.Entries[0].Heading)
	}
}

func TestParseFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "worklog.md")
	data := `# Worklog

## 2026-02-03 verifies the file path

body
`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}

	w, err := worklog.ParseFile(path)
	if err != nil {
		t.Fatalf("ParseFile: %v", err)
	}
	if w.Path != path {
		t.Errorf("Path = %q, want %q", w.Path, path)
	}
	if len(w.Entries) != 1 || !w.Entries[0].HasTimestamp {
		t.Fatalf("entries = %+v, want one dated entry", w.Entries)
	}
	if want := time.Date(2026, 2, 3, 0, 0, 0, 0, time.UTC); !w.Entries[0].Timestamp.Equal(want) {
		t.Errorf("Timestamp = %s, want %s", w.Entries[0].Timestamp, want)
	}

	if _, err := worklog.ParseFile(filepath.Join(dir, "absent.md")); err == nil {
		t.Fatal("ParseFile error = nil for a missing file, want an error")
	}
}
