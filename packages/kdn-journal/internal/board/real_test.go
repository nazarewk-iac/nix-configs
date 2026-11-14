package board_test

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"kdn-journal/internal/board"
	"kdn-journal/internal/worklog"
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

func walkFiles(t *testing.T, root string, match func(string) bool, fn func(string)) {
	t.Helper()
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		if match(path) {
			fn(path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

func TestRealBoardsParse(t *testing.T) {
	root := repoRoot(t)
	seen := 0
	walkFiles(t, filepath.Join(root, "docs", "tasks"), func(path string) bool {
		return strings.HasSuffix(path, ".board.md")
	}, func(path string) {
		b, err := board.ParseFile(path)
		if err != nil {
			t.Errorf("%s: %v", path, err)
			return
		}
		seen++
		t.Logf("%-80s status=%-8s open=%d done=%d blocked=%d dropped=%d title=%q",
			strings.TrimPrefix(path, root+"/"), b.Status, b.Counts().Open, b.Counts().Done,
			b.Counts().Blocked, b.Counts().Dropped, b.Title)
	})
	walkFiles(t, filepath.Join(root, ".cache", "agents"), func(path string) bool {
		base := filepath.Base(path)
		return strings.HasPrefix(base, "board") && strings.HasSuffix(base, ".md")
	}, func(path string) {
		b, err := board.ParseFile(path)
		if err != nil {
			t.Errorf("%s: %v", path, err)
			return
		}
		seen++
		t.Logf("%-80s status=%-8s open=%d done=%d blocked=%d dropped=%d title=%q",
			strings.TrimPrefix(path, root+"/"), b.Status, b.Counts().Open, b.Counts().Done,
			b.Counts().Blocked, b.Counts().Dropped, b.Title)
	})
	if seen == 0 {
		t.Fatal("no boards found")
	}
}

func TestRealBoardExpectations(t *testing.T) {
	root := repoRoot(t)
	cases := []struct {
		path    string
		status  string
		atLeast map[string]int
	}{
		{
			path:    ".cache/agents/opencode-20261110-ses_e3c837bf2ffeKUFIukMf5s2OB2/board.md",
			status:  "active",
			atLeast: map[string]int{"open": 1},
		},
		{
			path:    ".cache/agents/opencode-20261110-ses_e3c837bf2ffeKUFIukMf5s2OB2/board-ssh-ca.md",
			status:  "active",
			atLeast: map[string]int{"done": 4, "open": 1},
		},
		{
			path:    "docs/tasks/2026-11/secret-service-backend/.board.md",
			status:  "active",
			atLeast: map[string]int{"open": 8},
		},
	}
	for _, tc := range cases {
		b, err := board.ParseFile(filepath.Join(root, tc.path))
		if err != nil {
			t.Fatalf("%s: %v", tc.path, err)
		}
		if b.Status != tc.status {
			t.Errorf("%s: status = %q, want %q", tc.path, b.Status, tc.status)
		}
		c := b.Counts()
		got := map[string]int{"open": c.Open, "done": c.Done, "blocked": c.Blocked, "dropped": c.Dropped}
		for key, want := range tc.atLeast {
			if got[key] < want {
				t.Errorf("%s: %s = %d, want >= %d", tc.path, key, got[key], want)
			}
		}
	}
}

func TestRealWorklogsParse(t *testing.T) {
	root := repoRoot(t)
	seen := 0
	match := func(path string) bool {
		base := filepath.Base(path)
		return strings.HasSuffix(base, ".worklog.md") ||
			strings.HasPrefix(base, "worklog") && strings.HasSuffix(base, ".md")
	}
	walkFiles(t, filepath.Join(root, "docs", "tasks"), match, func(path string) {
		w, err := worklog.ParseFile(path)
		if err != nil {
			t.Errorf("%s: %v", path, err)
			return
		}
		seen++
		t.Logf("%-80s entries=%d", strings.TrimPrefix(path, root+"/"), len(w.Entries))
	})
	walkFiles(t, filepath.Join(root, ".cache", "agents"), match, func(path string) {
		w, err := worklog.ParseFile(path)
		if err != nil {
			t.Errorf("%s: %v", path, err)
			return
		}
		seen++
		t.Logf("%-80s entries=%d", strings.TrimPrefix(path, root+"/"), len(w.Entries))
	})
	if seen == 0 {
		t.Fatal("no worklogs found")
	}
}
