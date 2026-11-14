package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func testRepo(t *testing.T, status string) (string, string) {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, "docs", "tasks", "2026-11", "example")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "definition.md")
	body := "---\ntype: Task\ndescription: Suite: a test task\nstatus: " + status + "\nauthored_by: agent\ntimestamp: 2026-11-15T10:00:00+01:00\n---\n\n# Example\n\nBody stays.\n"
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return root, path
}

func testApp(root string) (*App, *bytes.Buffer) {
	var buf bytes.Buffer
	return &App{
		Root:  root,
		Width: 100,
		Out:   &buf,
		Err:   &buf,
		Now:   func() time.Time { return time.Date(2026, 11, 15, 12, 0, 0, 0, time.UTC) },
	}, &buf
}

func TestSetTaskStatusInProgress(t *testing.T) {
	root, path := testRepo(t, "open")
	app, _ := testApp(root)
	if err := setTaskStatus(app, "example", "in-progress"); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "status: in-progress") {
		t.Errorf("status was not updated:\n%s", data)
	}
	if !strings.Contains(string(data), "description: Suite: a test task") {
		t.Errorf("description changed:\n%s", data)
	}
	if !strings.Contains(string(data), "Body stays.") {
		t.Errorf("body changed:\n%s", data)
	}
}

func TestSetTaskStatusDoneRequiresDoneFile(t *testing.T) {
	root, _ := testRepo(t, "in-progress")
	app, _ := testApp(root)
	if err := setTaskStatus(app, "example", "done"); err == nil {
		t.Fatal("setTaskStatus(done) succeeded without done.md")
	}
}

func TestSetTaskStatusDoneWritesSolution(t *testing.T) {
	root, path := testRepo(t, "in-progress")
	dir := filepath.Dir(path)
	if err := os.WriteFile(filepath.Join(dir, "done.md"), []byte("# done\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	app, _ := testApp(root)
	if err := setTaskStatus(app, "example", "done"); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "status: done") {
		t.Errorf("status was not updated:\n%s", data)
	}
	if !strings.Contains(string(data), "solution: done.md") {
		t.Errorf("solution was not inserted:\n%s", data)
	}
}

func TestSetTaskStatusDoneRefusesStatusFile(t *testing.T) {
	root, path := testRepo(t, "in-progress")
	dir := filepath.Dir(path)
	if err := os.WriteFile(filepath.Join(dir, "done.md"), []byte("# done\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "status.md"), []byte("# status\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	app, _ := testApp(root)
	if err := setTaskStatus(app, "example", "done"); err == nil {
		t.Fatal("setTaskStatus(done) succeeded with status.md present")
	}
}
