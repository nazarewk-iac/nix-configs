package cmd

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func jsonRepo(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	taskDir := filepath.Join(root, "docs", "tasks", "2026-11", "example")
	if err := os.MkdirAll(taskDir, 0o755); err != nil {
		t.Fatal(err)
	}
	definition := "---\ntype: Task\ndescription: A test task\nstatus: open\nauthored_by: agent\ntimestamp: 2026-11-15T10:00:00+01:00\n---\n\n# Example\n"
	if err := os.WriteFile(filepath.Join(taskDir, "definition.md"), []byte(definition), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(taskDir, ".board.md"), []byte("# Board — example\n\n## Status\n\n- [ ] open item\n- [x] done item\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(taskDir, ".worklog.md"), []byte("## 2026-11-15T10:00:00+01:00 — run\nbody\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	sessionDir := filepath.Join(root, ".cache", "agents", "opencode-20261115-ses_json")
	if err := os.MkdirAll(sessionDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sessionDir, "board.md"), []byte("# Board — session\n\n## Status\n\n- [ ] session item\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sessionDir, "worklog.md"), []byte("## 2026-11-15T10:00:00+01:00 — run\nbody\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func runJSON(t *testing.T, root string, args ...string) map[string]any {
	t.Helper()
	var out bytes.Buffer
	app := &App{
		Root:  root,
		JSON:  true,
		Width: 100,
		Out:   &out,
		Err:   &out,
		Now:   func() time.Time { return time.Date(2026, 11, 15, 12, 0, 0, 0, time.UTC) },
	}
	cmd := NewRootWithApp(app)
	cmd.SetArgs(args)
	if err := cmd.Execute(); err != nil {
		t.Fatalf("%v: %v\n%s", args, err, out.String())
	}
	var envelope map[string]any
	if err := json.Unmarshal(out.Bytes(), &envelope); err != nil {
		t.Fatalf("%v: invalid JSON: %v\n%s", args, err, out.String())
	}
	if envelope["schema_version"] != float64(1) {
		t.Errorf("%v: schema_version = %v", args, envelope["schema_version"])
	}
	if _, ok := envelope["issues"].([]any); !ok {
		t.Errorf("%v: issues is %T, want an array", args, envelope["issues"])
	}
	return envelope
}

func TestJSONEnvelopes(t *testing.T) {
	root := jsonRepo(t)
	commands := [][]string{
		{"summary", "--task", "example"},
		{"tasks"},
		{"sessions"},
		{"task", "example"},
		{"board", "docs/tasks/2026-11/example"},
		{"worklog", "docs/tasks/2026-11/example"},
		{"doctor", "--parse-only"},
	}
	for _, args := range commands {
		envelope := runJSON(t, root, args...)
		if envelope["command"] == "" {
			t.Errorf("%v: empty command", args)
		}
		if envelope["data"] == nil {
			t.Errorf("%v: nil data", args)
		}
	}
}

func TestJSONSummaryPayload(t *testing.T) {
	root := jsonRepo(t)
	envelope := runJSON(t, root, "summary", "--task", "example")
	data, ok := envelope["data"].(map[string]any)
	if !ok {
		t.Fatalf("data is %T", envelope["data"])
	}
	session, ok := data["session"].(map[string]any)
	if !ok {
		t.Fatalf("session is %T", data["session"])
	}
	if session["id"] != "ses_json" {
		t.Errorf("session id = %v", session["id"])
	}
	if _, ok := data["task"].(map[string]any); !ok {
		t.Errorf("task is %T", data["task"])
	}
}

func TestTasksUnknownStatus(t *testing.T) {
	root := jsonRepo(t)
	var out bytes.Buffer
	app := &App{Root: root, Width: 100, Out: &out, Err: &out, Now: time.Now}
	cmd := NewRootWithApp(app)
	cmd.SetArgs([]string{"tasks", "--status", "bogus"})
	if err := cmd.Execute(); err == nil {
		t.Fatal("tasks --status bogus succeeded")
	}
}
