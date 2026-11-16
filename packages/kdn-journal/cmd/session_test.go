package cmd

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"kdn-journal/internal/atuin"
	"kdn-journal/internal/jjmeta"
	"kdn-journal/internal/jjrun"
	"kdn-journal/internal/sessionid"
)

type fakeJJ struct {
	available   bool
	workingCopy string
	changes     map[string]jjrun.Change
	all         []jjrun.Change
}

func (f *fakeJJ) Available() bool { return f.available }
func (f *fakeJJ) WorkingCopyChange(context.Context) (string, error) {
	return f.workingCopy, nil
}

func (f *fakeJJ) Change(_ context.Context, rev string) (jjrun.Change, error) {
	if change, ok := f.changes[rev]; ok {
		return change, nil
	}
	return jjrun.Change{}, errors.New("no such change")
}

func (f *fakeJJ) Changes(context.Context, string) ([]jjrun.Change, error) {
	if f.all != nil {
		return f.all, nil
	}
	out := make([]jjrun.Change, 0, len(f.changes))
	for _, change := range f.changes {
		out = append(out, change)
	}
	return out, nil
}

type fakeAtuin struct {
	available bool
	threads   []atuin.Thread
	err       error
}

func (f *fakeAtuin) Available() bool { return f.available }
func (f *fakeAtuin) List(context.Context) ([]atuin.Thread, error) {
	return f.threads, f.err
}

func (f *fakeAtuin) Show(_ context.Context, id string) (atuin.Thread, error) {
	for _, thread := range f.threads {
		if thread.AtuinID == id {
			return thread, nil
		}
	}
	return atuin.Thread{}, errors.New("thread not found")
}

func (f *fakeAtuin) Search(context.Context, string, string, int) ([]atuin.Thread, error) {
	return f.threads, f.err
}

type fakeJJMeta struct {
	available bool
	changeIDs []string
	calls     []jjmeta.Options
	result    jjmeta.Result
	err       error
}

func (f *fakeJJMeta) Available() bool { return f.available }
func (f *fakeJJMeta) Attribute(_ context.Context, changeID string, opts jjmeta.Options) (jjmeta.Result, error) {
	f.changeIDs = append(f.changeIDs, changeID)
	f.calls = append(f.calls, opts)
	if f.err != nil {
		return jjmeta.Result{}, f.err
	}
	if f.result.Added != nil || f.result.Written {
		return f.result, nil
	}
	return jjmeta.Result{Added: []string{"Assisted-by: test"}, Written: true}, nil
}

func sessionTestApp(t *testing.T, env map[string]string) (*App, *fakeJJ, *fakeAtuin, *fakeJJMeta) {
	t.Helper()
	var out bytes.Buffer
	jj := &fakeJJ{available: true, workingCopy: "wc0000000000", changes: map[string]jjrun.Change{}}
	at := &fakeAtuin{available: true}
	meta := &fakeJJMeta{available: true}
	app := &App{
		Root:   t.TempDir(),
		Width:  100,
		Out:    &out,
		Err:    &out,
		Now:    func() time.Time { return time.Date(2026, 11, 16, 10, 0, 0, 0, time.UTC) },
		Getenv: func(key string) string { return env[key] },
		JJ:     jj,
		Atuin:  at,
		JJMeta: meta,
	}
	return app, jj, at, meta
}

func runSession(t *testing.T, app *App, args ...string) (string, error) {
	t.Helper()
	root := NewRootWithApp(app)
	root.SetArgs(args)
	err := root.Execute()
	out, _ := app.Out.(*bytes.Buffer)
	return out.String(), err
}

func loadTestSidecar(t *testing.T, app *App, sessionID string) *sessionid.Sidecar {
	t.Helper()
	entries, err := os.ReadDir(filepath.Join(app.Root, ".cache", "agents"))
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), "-"+sessionID) {
			continue
		}
		sidecar, err := sessionid.Load(filepath.Join(app.Root, ".cache", "agents", entry.Name(), "session.json"))
		if err != nil {
			t.Fatal(err)
		}
		return sidecar
	}
	t.Fatalf("no session directory for %s", sessionID)
	return nil
}

func TestSessionInitWritesSidecar(t *testing.T) {
	app, _, _, _ := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	out, err := runSession(t, app, "session", "init")
	if err != nil {
		t.Fatalf("session init: %v\n%s", err, out)
	}
	if !strings.Contains(out, "session ses_1 (opencode)") {
		t.Fatalf("output = %q", out)
	}
	sidecar := loadTestSidecar(t, app, "ses_1")
	if sidecar.SchemaVersion != sessionid.SchemaVersion {
		t.Fatalf("schema_version = %d", sidecar.SchemaVersion)
	}
	if sidecar.Harness != "opencode" || sidecar.SessionID != "ses_1" {
		t.Fatalf("sidecar = %#v", sidecar)
	}
	if sidecar.JJ.WorkingCopyChange != "wc0000000000" {
		t.Fatalf("working copy = %q", sidecar.JJ.WorkingCopyChange)
	}
	if sidecar.StartedAt == "" || sidecar.UpdatedAt == "" {
		t.Fatalf("timestamps = %#v", sidecar)
	}
}

func TestSessionInitReusesExistingDirectory(t *testing.T) {
	app, _, _, _ := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	existing := filepath.Join(app.Root, ".cache", "agents", "opencode-20261110-ses_1")
	if err := os.MkdirAll(existing, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := runSession(t, app, "session", "init"); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(filepath.Join(app.Root, ".cache", "agents"))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "opencode-20261110-ses_1" {
		t.Fatalf("session directories = %#v", entries)
	}
	if _, err := os.Stat(filepath.Join(existing, "session.json")); err != nil {
		t.Fatalf("sidecar missing in the reused directory: %v", err)
	}
}

func TestSessionInitWithoutIdentity(t *testing.T) {
	app, _, _, _ := sessionTestApp(t, nil)
	if _, err := runSession(t, app, "session", "init"); err == nil {
		t.Fatal("session init succeeded without a session identity")
	}
}

func TestSessionRecordChangeCallsJJMeta(t *testing.T) {
	app, _, _, meta := sessionTestApp(t, map[string]string{
		"OPENCODE_SESSION_ID": "ses_1",
		"OPENCODE_MODEL":      "model",
	})
	out, err := runSession(t, app, "session", "record-change", "aaaa")
	if err != nil {
		t.Fatalf("record-change: %v\n%s", err, out)
	}
	if len(meta.changeIDs) != 1 || meta.changeIDs[0] != "aaaa" {
		t.Fatalf("kdn-jj-meta calls = %#v", meta.changeIDs)
	}
	want := jjmeta.Options{Session: "ses_1", Harness: "opencode", Model: "model"}
	if meta.calls[0] != want {
		t.Fatalf("kdn-jj-meta options = %#v, want %#v", meta.calls[0], want)
	}
	sidecar := loadTestSidecar(t, app, "ses_1")
	if len(sidecar.JJ.ChangeIDs) != 1 || sidecar.JJ.ChangeIDs[0] != "aaaa" {
		t.Fatalf("sidecar = %#v", sidecar.JJ)
	}
	if !strings.Contains(out, "attributed aaaa") {
		t.Fatalf("output = %q", out)
	}
}

func TestSessionRecordChangeUsesAtuinModel(t *testing.T) {
	app, _, at, meta := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	at.threads = []atuin.Thread{{AtuinID: "t1", Harness: "opencode", SessionID: "ses_1", Model: "atuin-model"}}
	if _, err := runSession(t, app, "session", "record-change", "aaaa"); err != nil {
		t.Fatal(err)
	}
	if meta.calls[0].Model != "atuin-model" {
		t.Fatalf("model = %q, want the Atuin model", meta.calls[0].Model)
	}
}

func TestSessionRecordChangeWithoutJJMeta(t *testing.T) {
	app, _, _, meta := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	meta.available = false
	out, err := runSession(t, app, "session", "record-change", "aaaa")
	if err != nil {
		t.Fatalf("record-change: %v\n%s", err, out)
	}
	if !strings.Contains(out, "kdn-jj-meta-unavailable") {
		t.Fatalf("output = %q", out)
	}
	sidecar := loadTestSidecar(t, app, "ses_1")
	if len(sidecar.JJ.ChangeIDs) != 1 {
		t.Fatalf("sidecar = %#v", sidecar.JJ)
	}
}

func TestSessionRecordChangeIsIdempotent(t *testing.T) {
	app, _, _, meta := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	if _, err := runSession(t, app, "session", "record-change", "aaaa"); err != nil {
		t.Fatal(err)
	}
	out, err := runSession(t, app, "session", "record-change", "aaaa")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "already recorded") {
		t.Fatalf("output = %q", out)
	}
	if len(meta.changeIDs) != 2 {
		t.Fatalf("kdn-jj-meta calls = %#v", meta.changeIDs)
	}
	sidecar := loadTestSidecar(t, app, "ses_1")
	if len(sidecar.JJ.ChangeIDs) != 1 {
		t.Fatalf("sidecar = %#v", sidecar.JJ)
	}
}

func TestSessionRecordCommit(t *testing.T) {
	app, _, _, _ := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	if _, err := runSession(t, app, "session", "record-commit", "1111"); err != nil {
		t.Fatal(err)
	}
	sidecar := loadTestSidecar(t, app, "ses_1")
	if len(sidecar.JJ.Commits) != 1 || sidecar.JJ.Commits[0] != "1111" {
		t.Fatalf("sidecar = %#v", sidecar.JJ)
	}
}

func TestSessionChanges(t *testing.T) {
	app, jj, _, _ := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	if _, err := runSession(t, app, "session", "record-change", "aaaa"); err != nil {
		t.Fatal(err)
	}
	if _, err := runSession(t, app, "session", "record-change", "missing"); err != nil {
		t.Fatal(err)
	}
	jj.changes["aaaa"] = jjrun.Change{
		ChangeID:    "aaaa",
		CommitID:    "1111",
		Description: "feat: something\n\nbody",
		Author:      "Test <test@example.com>",
		Timestamp:   "2026-11-16T09:00:00+01:00",
		Files:       []string{"a.go", "b.go"},
	}
	out, err := runSession(t, app, "session", "changes")
	if err != nil {
		t.Fatalf("session changes: %v\n%s", err, out)
	}
	for _, want := range []string{"session ses_1 (opencode)", "aaaa  1111  feat: something", "a.go, b.go", "change-missing"} {
		if !strings.Contains(out, want) {
			t.Fatalf("output misses %q:\n%s", want, out)
		}
	}
}

func TestSessionAtuinLinksThread(t *testing.T) {
	app, _, at, _ := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	if _, err := runSession(t, app, "session", "init"); err != nil {
		t.Fatal(err)
	}
	at.threads = []atuin.Thread{{
		AtuinID:      "t1",
		Harness:      "opencode",
		SessionID:    "ses_1",
		Model:        "model",
		MessageCount: 42,
		UpdatedAt:    "2026-11-16T09:30:00Z",
	}}
	out, err := runSession(t, app, "session", "atuin")
	if err != nil {
		t.Fatalf("session atuin: %v\n%s", err, out)
	}
	if !strings.Contains(out, "atuin   t1") || !strings.Contains(out, "messages 42") {
		t.Fatalf("output = %q", out)
	}
	sidecar := loadTestSidecar(t, app, "ses_1")
	if sidecar.Atuin.ThreadID != "t1" || sidecar.Atuin.MessageCount != 42 {
		t.Fatalf("sidecar = %#v", sidecar.Atuin)
	}
}

func TestSessionAtuinAmbiguous(t *testing.T) {
	app, _, at, _ := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	if _, err := runSession(t, app, "session", "init"); err != nil {
		t.Fatal(err)
	}
	at.threads = []atuin.Thread{
		{AtuinID: "t1", Harness: "opencode", SessionID: "other-1", Cwd: app.Root, StartedAt: "2026-11-16T10:00:00Z"},
		{AtuinID: "t2", Harness: "opencode", SessionID: "other-2", Cwd: app.Root, StartedAt: "2026-11-16T10:01:00Z"},
	}
	out, err := runSession(t, app, "session", "atuin")
	if err != nil {
		t.Fatalf("session atuin: %v\n%s", err, out)
	}
	if !strings.Contains(out, "atuin-ambiguous") {
		t.Fatalf("output = %q", out)
	}
	sidecar := loadTestSidecar(t, app, "ses_1")
	if sidecar.Atuin.ThreadID != "" {
		t.Fatalf("an ambiguous match was linked: %#v", sidecar.Atuin)
	}
}

func TestSessionAtuinWithoutAtuin(t *testing.T) {
	app, _, at, _ := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	at.available = false
	if _, err := runSession(t, app, "session", "init"); err != nil {
		t.Fatal(err)
	}
	out, err := runSession(t, app, "session", "atuin")
	if err != nil {
		t.Fatalf("session atuin: %v\n%s", err, out)
	}
	if !strings.Contains(out, "atuin-unavailable") {
		t.Fatalf("output = %q", out)
	}
}

func TestSessionChangesJSON(t *testing.T) {
	app, jj, _, _ := sessionTestApp(t, map[string]string{"OPENCODE_SESSION_ID": "ses_1"})
	if _, err := runSession(t, app, "session", "record-change", "aaaa"); err != nil {
		t.Fatal(err)
	}
	jj.changes["aaaa"] = jjrun.Change{ChangeID: "aaaa", CommitID: "1111", Description: "subject"}
	out, err := runSession(t, app, "--json", "session", "changes")
	if err != nil {
		t.Fatalf("session changes --json: %v\n%s", err, out)
	}
	if !strings.Contains(out, `"command": "session changes"`) || !strings.Contains(out, `"change_id": "aaaa"`) {
		t.Fatalf("output = %q", out)
	}
}

func TestSessionBackfillTimeWindow(t *testing.T) {
	app, jj, at, meta := sessionTestApp(t, nil)
	jj.all = []jjrun.Change{{
		ChangeID:    "aaaa",
		CommitID:    "1111",
		Description: "subject",
		Timestamp:   "2026-11-16T10:00:00Z",
	}}
	at.threads = []atuin.Thread{{
		AtuinID:   "t1",
		Harness:   "opencode",
		SessionID: "ses_thread",
		Model:     "m",
		Cwd:       app.Root,
		StartedAt: "2026-11-16T09:00:00Z",
		UpdatedAt: "2026-11-16T11:00:00Z",
	}}
	out, err := runSession(t, app, "session", "backfill")
	if err != nil {
		t.Fatalf("session backfill: %v\n%s", err, out)
	}
	if len(meta.changeIDs) != 1 || meta.changeIDs[0] != "aaaa" {
		t.Fatalf("kdn-jj-meta calls = %#v", meta.changeIDs)
	}
	want := jjmeta.Options{Session: "ses_thread", Harness: "opencode", Model: "m"}
	if meta.calls[0] != want {
		t.Fatalf("options = %#v, want %#v", meta.calls[0], want)
	}
	if !strings.Contains(out, "attributed 1") {
		t.Fatalf("output = %q", out)
	}
}

func TestSessionBackfillDryRun(t *testing.T) {
	app, jj, at, meta := sessionTestApp(t, nil)
	jj.all = []jjrun.Change{{ChangeID: "aaaa", Description: "subject", Timestamp: "2026-11-16T10:00:00Z"}}
	at.threads = []atuin.Thread{{
		AtuinID: "t1", Harness: "opencode", SessionID: "ses_thread", Cwd: app.Root,
		StartedAt: "2026-11-16T09:00:00Z", UpdatedAt: "2026-11-16T11:00:00Z",
	}}
	out, err := runSession(t, app, "session", "backfill", "--dry-run")
	if err != nil {
		t.Fatalf("session backfill --dry-run: %v\n%s", err, out)
	}
	if len(meta.changeIDs) != 0 {
		t.Fatalf("dry run called kdn-jj-meta: %#v", meta.changeIDs)
	}
	if !strings.Contains(out, "matched 1") {
		t.Fatalf("output = %q", out)
	}
}

func TestSessionBackfillSidecarWins(t *testing.T) {
	app, jj, at, meta := sessionTestApp(t, nil)
	dir := filepath.Join(app.Root, ".cache", "agents", "pi-20261116-ses_side")
	sidecar := &sessionid.Sidecar{SchemaVersion: 1, Harness: "pi", SessionID: "ses_side"}
	sidecar.AddChange("aaaa")
	if err := sidecar.Save(filepath.Join(dir, "session.json")); err != nil {
		t.Fatal(err)
	}
	jj.all = []jjrun.Change{{ChangeID: "aaaa", Description: "subject", Timestamp: "2026-11-16T10:00:00Z"}}
	at.threads = []atuin.Thread{{
		AtuinID: "t1", Harness: "opencode", SessionID: "ses_thread", Cwd: app.Root,
		StartedAt: "2026-11-16T09:00:00Z", UpdatedAt: "2026-11-16T11:00:00Z",
	}}
	if _, err := runSession(t, app, "session", "backfill"); err != nil {
		t.Fatal(err)
	}
	if meta.calls[0].Session != "ses_side" || meta.calls[0].Harness != "pi" {
		t.Fatalf("sidecar did not win: %#v", meta.calls[0])
	}
}

func TestSessionBackfillSkips(t *testing.T) {
	app, jj, _, meta := sessionTestApp(t, nil)
	jj.all = []jjrun.Change{
		{ChangeID: "empty", Description: "", Timestamp: "2026-11-16T10:00:00Z"},
		{ChangeID: "old", Description: "subject", Timestamp: "2020-01-01T00:00:00Z"},
	}
	out, err := runSession(t, app, "session", "backfill")
	if err != nil {
		t.Fatalf("session backfill: %v\n%s", err, out)
	}
	if len(meta.changeIDs) != 0 {
		t.Fatalf("kdn-jj-meta calls = %#v", meta.changeIDs)
	}
	if !strings.Contains(out, "skipped 2") || !strings.Contains(out, "empty description") {
		t.Fatalf("output = %q", out)
	}
}

func TestSessionBackfillSessionFilter(t *testing.T) {
	app, jj, at, meta := sessionTestApp(t, nil)
	jj.all = []jjrun.Change{{ChangeID: "aaaa", Description: "subject", Timestamp: "2026-11-16T10:00:00Z"}}
	at.threads = []atuin.Thread{{
		AtuinID: "t1", Harness: "opencode", SessionID: "ses_thread", Cwd: app.Root,
		StartedAt: "2026-11-16T09:00:00Z", UpdatedAt: "2026-11-16T11:00:00Z",
	}}
	out, err := runSession(t, app, "session", "backfill", "--session", "ses_other")
	if err != nil {
		t.Fatal(err)
	}
	if len(meta.changeIDs) != 0 || !strings.Contains(out, "skipped 1") {
		t.Fatalf("output = %q, calls = %#v", out, meta.changeIDs)
	}
}
