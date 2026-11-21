package harvest

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"kdn-knowledge/internal/corpus"
	"kdn-knowledge/internal/state"
	"kdn-knowledge/internal/store"
	"kdn-knowledge/internal/testsupport"
)

func fixture(t *testing.T) (string, *store.Store, *state.State) {
	t.Helper()
	db := testsupport.NewDB(t,
		testsupport.Session{
			ID: "ses_one", Title: "One", Directory: "/repo", CreatedMS: 1700000000000, UpdatedMS: 1700000001000,
			Messages: []testsupport.Message{
				testsupport.User("first session"),
				testsupport.Assistant(testsupport.Text("The build is pinned.")),
			},
		},
		testsupport.Session{
			ID: "ses_two", Title: "Two", Directory: "/repo", CreatedMS: 1700000002000, UpdatedMS: 1700000003000,
			Messages: []testsupport.Message{
				testsupport.User("second session"),
			},
		},
	)
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	ledger, err := state.Load(st.StatePath())
	if err != nil {
		t.Fatalf("state.Load: %v", err)
	}
	return db, st, ledger
}

func run(t *testing.T, db string, st *store.Store, ledger *state.State) *Summary {
	t.Helper()
	summary, err := Run(context.Background(), st, ledger, Options{DB: db, Project: "/repo"}, nil)
	if err != nil {
		t.Fatalf("harvest.Run: %v", err)
	}
	return summary
}

func TestHarvestIsResumableByHash(t *testing.T) {
	db, st, ledger := fixture(t)

	first := run(t, db, st, ledger)
	if first.Selected != 2 || first.Written != 2 || first.New != 2 {
		t.Fatalf("first run = %+v, want 2 selected, 2 written, 2 new", first)
	}
	for _, id := range []string{"ses_one", "ses_two"} {
		entry, ok := ledger.Get(id)
		if !ok || entry.Status != state.StatusNew || entry.Hash == "" || entry.Started == "" {
			t.Fatalf("entry of %s = %+v, want a new session with a hash and a start", id, entry)
		}
	}

	second := run(t, db, st, ledger)
	if second.Written != 0 || second.Unchanged != 2 || second.New != 2 {
		t.Fatalf("second run = %+v, want 0 written, 2 unchanged, 2 new", second)
	}

	// A finished session keeps its status when nothing changed.
	entry, _ := ledger.Get("ses_one")
	entry.Status = state.StatusDone
	ledger.Put("ses_one", entry)
	entry, _ = ledger.Get("ses_two")
	entry.Status = state.StatusDone
	ledger.Put("ses_two", entry)
	if err := ledger.Save(); err != nil {
		t.Fatalf("Save: %v", err)
	}
	third := run(t, db, st, ledger)
	if third.Written != 0 || third.Unchanged != 2 {
		t.Fatalf("third run = %+v, want nothing written", third)
	}
	if entry, _ := ledger.Get("ses_one"); entry.Status != state.StatusDone {
		t.Fatalf("status = %q, want done", entry.Status)
	}

	// A changed session becomes new again, and its attempt count resets.
	entry, _ = ledger.Get("ses_one")
	entry.Attempts = 3
	entry.Status = state.StatusFailed
	ledger.Put("ses_one", entry)
	if err := ledger.Save(); err != nil {
		t.Fatalf("Save: %v", err)
	}
	testsupport.Exec(t, db,
		"UPDATE session_message SET data = replace(data, 'The build is pinned.', 'The build is pinned to a rev.')"+
			" WHERE session_id = 'ses_one'")
	changed := run(t, db, st, ledger)
	if changed.Selected != 2 || changed.Written != 1 || changed.Unchanged != 1 || changed.New != 1 {
		t.Fatalf("changed run = %+v, want 1 written, 1 unchanged, 1 new", changed)
	}
	entry, _ = ledger.Get("ses_one")
	if entry.Status != state.StatusNew || entry.Attempts != 0 {
		t.Fatalf("changed entry = %+v, want new with zero attempts", entry)
	}
	if entry, _ := ledger.Get("ses_two"); entry.Status != state.StatusDone {
		t.Fatalf("untouched entry = %+v, want done", entry)
	}

	// A session that leaves the database keeps its corpus and is marked orphaned.
	testsupport.Exec(t, db, "DELETE FROM session_v2 WHERE id = 'ses_two'")
	orphaned := run(t, db, st, ledger)
	if orphaned.Orphaned != 1 || orphaned.Selected != 1 {
		t.Fatalf("orphan run = %+v, want 1 orphaned and 1 selected", orphaned)
	}
	if entry, _ := ledger.Get("ses_two"); entry.Status != state.StatusOrphaned {
		t.Fatalf("orphan entry = %+v, want orphaned", entry)
	}
	if _, err := st.ListJSON(st.CorpusDir()); err != nil {
		t.Fatalf("ListJSON: %v", err)
	}
	if !fileExists(st.CorpusPath("ses_two")) {
		t.Fatal("harvest deleted the corpus file of an orphaned session")
	}

	// A session that returns is new again.
	testsupport.Exec(t, db,
		"INSERT INTO session_v2 (id, title, directory, time_created, time_updated, time_idle)"+
			" VALUES ('ses_two', 'Two', '/repo', 1700000002000, 1700000003000, 1700000003000)")
	returned := run(t, db, st, ledger)
	if returned.New != 2 {
		t.Fatalf("returned run = %+v, want 2 new (ses_one was already new)", returned)
	}
	if entry, _ := ledger.Get("ses_two"); entry.Status != state.StatusNew {
		t.Fatalf("returned entry = %+v, want new", entry)
	}
}

func TestHarvestSkipsLiveSessions(t *testing.T) {
	db := testsupport.NewDB(t,
		testsupport.Session{
			ID: "ses_live", Title: "Live", Directory: "/repo", CreatedMS: 1700000000000, UpdatedMS: 1700000001000,
			Live:     true,
			Messages: []testsupport.Message{testsupport.User("still running")},
		},
	)
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	ledger, err := state.Load(st.StatePath())
	if err != nil {
		t.Fatalf("state.Load: %v", err)
	}
	summary := run(t, db, st, ledger)
	if summary.Selected != 0 {
		t.Fatalf("selected = %d, want 0 for a live session", summary.Selected)
	}
	if entry, ok := ledger.Get("ses_live"); ok {
		t.Fatalf("live session entered the ledger: %+v", entry)
	}

	summary, err = Run(context.Background(), st, ledger, Options{DB: db, Project: "/repo", IncludeLive: true}, nil)
	if err != nil {
		t.Fatalf("harvest.Run: %v", err)
	}
	if summary.Selected != 1 || summary.New != 1 {
		t.Fatalf("include-live run = %+v, want the session", summary)
	}
}

func TestHarvestWritesTheToolPart(t *testing.T) {
	db := testsupport.NewDB(t,
		testsupport.Session{
			ID: "ses_tool", Title: "Tool", Directory: "/repo", CreatedMS: 1700000000000, UpdatedMS: 1700000001000,
			Messages: []testsupport.Message{
				testsupport.User("run the build"),
				testsupport.Assistant(
					testsupport.Reasoning("internal plan"),
					testsupport.Text("I ran the build."),
					testsupport.Tool("shell", map[string]any{"command": "nix build .#x"}, "ok"),
				),
			},
		},
	)
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	ledger, err := state.Load(st.StatePath())
	if err != nil {
		t.Fatalf("state.Load: %v", err)
	}
	if summary := run(t, db, st, ledger); summary.Messages != 3 {
		t.Fatalf("messages = %d, want 3: user, assistant text and tool", summary.Messages)
	}
	session, err := readCorpus(st, "ses_tool")
	if err != nil {
		t.Fatalf("readCorpus: %v", err)
	}
	if len(session.Messages) != 3 {
		t.Fatalf("corpus has %d messages, want 3", len(session.Messages))
	}
	if session.Messages[2].Command != "nix build .#x" {
		t.Fatalf("tool command = %q", session.Messages[2].Command)
	}
	if strings.Contains(session.Messages[0].Text, "internal plan") {
		t.Fatal("the reasoning part reached the corpus")
	}
}

func readCorpus(st *store.Store, id string) (corpus.Session, error) {
	var session corpus.Session
	err := store.ReadJSON(st.CorpusPath(id), &session)
	return session, err
}

func piFixture(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	repo := filepath.Join(root, "repo")
	other := filepath.Join(root, "other")
	for _, dir := range []string{repo, other} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("mkdir: %v", err)
		}
	}
	write := func(path string, lines ...string) {
		if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
	write(filepath.Join(repo, "a.jsonl"),
		`{"type":"session","version":3,"id":"pi-repo-1","timestamp":"2026-11-01T10:00:00.000Z","cwd":"/repo"}`,
		`{"type":"message","timestamp":"2026-11-01T10:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"Use rg instead of grep."}]}}`,
		`{"type":"message","timestamp":"2026-11-01T10:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"I used rg."}]}}`,
	)
	write(filepath.Join(other, "b.jsonl"),
		`{"type":"session","version":3,"id":"pi-other-1","timestamp":"2026-11-02T10:00:00.000Z","cwd":"/other"}`,
		`{"type":"message","timestamp":"2026-11-02T10:00:01.000Z","message":{"role":"user","content":"Another project."}}`,
	)
	return root, repo
}

func TestHarvestPiSource(t *testing.T) {
	root, _ := piFixture(t)
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	ledger, err := state.Load(st.StatePath())
	if err != nil {
		t.Fatalf("state.Load: %v", err)
	}
	run := func() *Summary {
		t.Helper()
		summary, err := Run(context.Background(), st, ledger, Options{
			Source:  SourcePi,
			PiRoot:  root,
			Project: "/repo",
		}, nil)
		if err != nil {
			t.Fatalf("harvest.Run: %v", err)
		}
		return summary
	}

	first := run()
	if first.Selected != 1 || first.Written != 1 || first.New != 1 || first.BySource[SourcePi] != 1 {
		t.Fatalf("first pi run = %+v, want one pi session", first)
	}
	entry, ok := ledger.Get("pi-repo-1")
	if !ok || entry.Status != state.StatusNew || entry.Source != SourcePi {
		t.Fatalf("pi entry = %+v", entry)
	}
	session, err := readCorpus(st, "pi-repo-1")
	if err != nil {
		t.Fatalf("readCorpus: %v", err)
	}
	if session.Source != SourcePi || len(session.Messages) != 2 {
		t.Fatalf("pi corpus = %+v", session)
	}

	second := run()
	if second.Unchanged != 1 || second.Written != 0 {
		t.Fatalf("second pi run = %+v, want one unchanged session", second)
	}

	// A removed session is orphaned; a source that the run does not read is left alone.
	if err := os.Remove(filepath.Join(root, "repo", "a.jsonl")); err != nil {
		t.Fatalf("remove: %v", err)
	}
	third := run()
	if third.Orphaned != 1 {
		t.Fatalf("third pi run = %+v, want one orphaned session", third)
	}
	if entry, _ := ledger.Get("pi-repo-1"); entry.Status != state.StatusOrphaned {
		t.Fatalf("pi entry = %+v, want orphaned", entry)
	}
}
