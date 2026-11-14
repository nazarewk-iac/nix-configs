package journal_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"kdn-journal/internal/journal"
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

func TestRealJournalStore(t *testing.T) {
	root := repoRoot(t)
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(store.Sessions) == 0 {
		t.Fatal("no sessions loaded")
	}
	newest := store.Newest()
	if newest == nil {
		t.Fatal("Newest returned nil")
	}
	t.Logf("newest session: %s touched %s", newest.Name, newest.LastTouched.Format("2006-01-02T15:04:05Z07:00"))

	eight, all, err := store.Find("opencode-20261110-ses_e3c837bf2ffeKUFIukMf5s2OB2")
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 1 {
		t.Errorf("matches = %d, want 1", len(all))
	}
	if len(eight.Boards) < 7 {
		t.Errorf("eight-board session has %d boards, want at least 7", len(eight.Boards))
	}
	if eight.Worklog == nil || len(eight.Worklog.Entries) < 60 {
		t.Errorf("eight-board session worklog is missing or short")
	}

	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	journalTask, err := tree.Find("agent-journal-summary")
	if err != nil {
		t.Fatal(err)
	}
	related := store.ForTask(journalTask)
	if len(related) == 0 {
		t.Error("no session references agent-journal-summary")
	}
	found := false
	for _, session := range related {
		if strings.Contains(session.Name, "ses_e1f8bbd08ffep6essAsRoa3wna") {
			found = true
		}
	}
	if !found {
		t.Errorf("current session not related to agent-journal-summary: %v", related)
	}

	// A deep podman overlay must not make an old session the newest.
	for _, session := range store.Sessions {
		if strings.Contains(session.Name, "ses_e2933f0deffeERrdlOBc6LRMXs") {
			if session.LastTouched.IsZero() {
				t.Error("LastTouched is zero for a session with a deep overlay")
			}
			if session.LastTouched.Year() < 2020 {
				t.Errorf("LastTouched = %s, want a real timestamp", session.LastTouched)
			}
		}
	}
}
