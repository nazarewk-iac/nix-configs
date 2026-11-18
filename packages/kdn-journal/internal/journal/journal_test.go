package journal_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"kdn-journal/internal/journal"
)

func writeFile(t *testing.T, path, content string, mtime time.Time) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, mtime, mtime); err != nil {
		t.Fatal(err)
	}
}

func session(t *testing.T, root, name, board string, mtime time.Time) string {
	t.Helper()
	dir := filepath.Join(root, ".cache", "agents", name)
	writeFile(t, filepath.Join(dir, "board.md"), board, mtime)
	writeFile(t, filepath.Join(dir, "worklog.md"), "## 2026-11-15T10:00:00+01:00 — run\nbody\n", mtime)
	return dir
}

func TestSessionNameAndOrder(t *testing.T) {
	root := t.TempDir()
	older := time.Date(2026, 11, 14, 10, 0, 0, 0, time.Local)
	newer := time.Date(2026, 11, 15, 10, 0, 0, 0, time.Local)
	session(t, root, "opencode-20261114-ses_aaa", "# Board — old\n", older)
	session(t, root, "pi-20261115-01a193a9", "# Board — new\n", newer)
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(store.Sessions) != 2 {
		t.Fatalf("sessions = %d, want 2", len(store.Sessions))
	}
	if store.Sessions[0].Harness != "pi" || store.Sessions[0].Date != "20261115" || store.Sessions[0].ID != "01a193a9" {
		t.Errorf("newest session parsed as %+v", store.Sessions[0])
	}
	if store.Newest() != store.Sessions[0] {
		t.Error("Newest is not the first session")
	}
}

func TestDuplicateIDSelectsNewest(t *testing.T) {
	root := t.TempDir()
	older := time.Date(2026, 11, 15, 10, 0, 0, 0, time.Local)
	newer := time.Date(2026, 11, 16, 10, 0, 0, 0, time.Local)
	session(t, root, "opencode-20261115-ses_abc", "# Board — first\n", older)
	session(t, root, "opencode-20261116-ses_abc", "# Board — second\n", newer)
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	selected, matches, err := store.Find("ses_abc")
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 2 {
		t.Fatalf("matches = %d, want 2", len(matches))
	}
	if selected.Name != "opencode-20261116-ses_abc" {
		t.Errorf("selected %q, want the newest run", selected.Name)
	}
	dated, _, err := store.Find("ses_abc@20261115")
	if err != nil {
		t.Fatal(err)
	}
	if dated.Name != "opencode-20261115-ses_abc" {
		t.Errorf("id@date selected %q", dated.Name)
	}
}

func TestBroadPrefixIsAmbiguous(t *testing.T) {
	root := t.TempDir()
	now := time.Date(2026, 11, 15, 10, 0, 0, 0, time.Local)
	session(t, root, "opencode-20261115-ses_aaa", "# Board — a\n", now)
	session(t, root, "opencode-20261115-ses_bbb", "# Board — b\n", now)
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := store.Find("ses_"); err == nil {
		t.Fatal("Find(ses_) succeeded across two distinct ids")
	}
}

func TestTaskRefsNormalize(t *testing.T) {
	root := t.TempDir()
	taskDir := filepath.Join(root, "docs", "tasks", "2026-11", "foo")
	writeFile(t, filepath.Join(taskDir, "definition.md"), "---\ntype: Task\n---\n", time.Now())
	board := `# Board
- see docs/tasks/2026-11/foo/research.md:12-14
- see docs/tasks/2026-11/foo/{definition,research}.md
- see docs/tasks/README.md
- see docs/tasks/**
`
	session(t, root, "opencode-20261115-ses_refs", board, time.Now())
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	refs := store.Sessions[0].TaskRefs
	if len(refs) != 1 || refs[0] != "docs/tasks/2026-11/foo" {
		t.Errorf("TaskRefs = %v, want [docs/tasks/2026-11/foo]", refs)
	}
}

func TestLastTouchedIgnoresDeepFiles(t *testing.T) {
	root := t.TempDir()
	boardTime := time.Date(2026, 11, 15, 10, 0, 0, 0, time.Local)
	deepTime := time.Date(2026, 11, 20, 10, 0, 0, 0, time.Local)
	dir := session(t, root, "opencode-20261115-ses_deep", "# Board\n", boardTime)
	writeFile(t, filepath.Join(dir, "poc", "storage", "deep.md"), "future\n", deepTime)
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	got := store.Sessions[0].LastTouched
	if got.After(boardTime.Add(time.Second)) {
		t.Errorf("LastTouched = %s, want the top-level board time %s", got, boardTime)
	}
}

func TestIndexOrdersBoards(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, ".cache", "agents", "opencode-20261115-ses_index")
	writeFile(t, filepath.Join(dir, "index.md"), "* [B](board-b.md)\n* [A](board-a.md)\n", time.Now())
	writeFile(t, filepath.Join(dir, "board.md"), "# Board — main\n", time.Now())
	writeFile(t, filepath.Join(dir, "board-a.md"), "# Board — a\n", time.Now())
	writeFile(t, filepath.Join(dir, "board-b.md"), "# Board — b\n", time.Now())
	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	names := make([]string, len(store.Sessions[0].Boards))
	for i, b := range store.Sessions[0].Boards {
		names[i] = filepath.Base(b.Path)
	}
	got := strings.Join(names, ",")
	if got != "board-b.md,board-a.md,board.md" {
		t.Errorf("board order = %s", got)
	}
}

func TestSidecarSharedAcrossDuplicateID(t *testing.T) {
	root := t.TempDir()
	older := time.Date(2026, 11, 15, 10, 0, 0, 0, time.Local)
	newer := time.Date(2026, 11, 16, 10, 0, 0, 0, time.Local)
	oldDir := session(t, root, "opencode-20261115-ses_dup", "# Board — old\n", older)
	session(t, root, "opencode-20261116-ses_dup", "# Board — new\n", newer)
	writeFile(t, filepath.Join(oldDir, "session.json"),
		`{"schema_version":1,"harness":"opencode","session_id":"ses_dup","atuin":{"thread_id":"01a1e074","message_count":7}}`,
		older)

	store, err := journal.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(store.Sessions) != 2 {
		t.Fatalf("sessions = %d, want 2", len(store.Sessions))
	}
	for _, s := range store.Sessions {
		if s.Sidecar == nil {
			t.Fatalf("%s has no sidecar", s.Name)
		}
		if s.Sidecar.Atuin.ThreadID != "01a1e074" || s.Sidecar.Atuin.MessageCount != 7 {
			t.Errorf("%s atuin = %+v", s.Name, s.Sidecar.Atuin)
		}
	}
}
