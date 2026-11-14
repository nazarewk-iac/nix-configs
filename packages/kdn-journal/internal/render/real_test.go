package render_test

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"

	"kdn-journal/internal/journal"
	"kdn-journal/internal/render"
	"kdn-journal/internal/task"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "docs", "tasks")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Skip("repository root not found")
		}
		dir = parent
	}
}

func TestSummaryRealEightBoardSession(t *testing.T) {
	root := repoRoot(t)
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	session, _, err := store.Find("opencode-20261110-ses_e3c837bf2ffeKUFIukMf5s2OB2")
	if err != nil {
		t.Fatal(err)
	}
	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	journalTask, err := tree.Find("agent-journal-summary")
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	opts := render.Options{Width: 100, Tail: 5, Items: 3}
	if err := render.Summary(&buf, opts, session, journalTask); err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimRight(buf.String(), "\n"), "\n")
	if len(lines) > 24 {
		t.Fatalf("summary has %d lines, want at most 24:\n%s", len(lines), buf.String())
	}
	for i, line := range lines {
		if width := utf8.RuneCountInString(line); width > 100 {
			t.Errorf("line %d is %d runes wide, want at most 100: %q", i+1, width, line)
		}
	}
	for _, want := range []string{"SESSION", "board.md", "tracks", "WORKLOG", "TASK", "agent-journal-summary"} {
		if !strings.Contains(buf.String(), want) {
			t.Errorf("summary does not contain %q:\n%s", want, buf.String())
		}
	}
}

func TestOtherRenderersRealData(t *testing.T) {
	root := repoRoot(t)
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	opts := render.Options{Width: 100, Tail: 3}
	var buf bytes.Buffer
	if err := render.Sessions(&buf, opts, store.Sessions, 3); err != nil {
		t.Fatal(err)
	}
	if err := render.Tasks(&buf, opts, tree.Tasks, true, 3); err != nil {
		t.Fatal(err)
	}
	item, err := tree.Find("agent-journal-summary")
	if err != nil {
		t.Fatal(err)
	}
	if err := render.Task(&buf, opts, item); err != nil {
		t.Fatal(err)
	}
	if item.Board != nil {
		if err := render.Board(&buf, opts, item.Board); err != nil {
			t.Fatal(err)
		}
	}
	if item.Worklog != nil {
		if err := render.Worklog(&buf, opts, item.Worklog, 3); err != nil {
			t.Fatal(err)
		}
	}
	if err := render.Doctor(&buf, opts, tree.Validate()); err != nil {
		t.Fatal(err)
	}
	for i, line := range strings.Split(buf.String(), "\n") {
		if utf8.RuneCountInString(line) > 100 {
			t.Errorf("line %d is wider than 100 runes: %q", i+1, line)
		}
	}
}
