package task_test

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"kdn-journal/internal/task"
)

func writeTask(t *testing.T, root, rel, status, authoredBy, timestamp string) string {
	t.Helper()
	dir := filepath.Join(root, "docs", "tasks", rel)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	definition := "---\ntype: Task\ndescription: Test task\nstatus: " + status + "\n"
	if authoredBy != "" {
		definition += "authored_by: " + authoredBy + "\n"
	}
	if timestamp != "" {
		definition += "timestamp: " + timestamp + "\n"
	}
	definition += "---\n\n# Test\n"
	if err := os.WriteFile(filepath.Join(dir, "definition.md"), []byte(definition), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestLoadNestedTasksAndFind(t *testing.T) {
	root := t.TempDir()
	parent := writeTask(t, root, "2026-11/parent", "in-progress", "agent", "2026-11-15T10:00:00+01:00")
	child := writeTask(t, root, "2026-11/parent/001-child", "open", "agent", "2026-11-15T10:00:00+01:00")
	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(tree.Tasks) != 2 {
		t.Fatalf("tasks = %d, want 2", len(tree.Tasks))
	}
	parentTask, err := tree.Find("parent")
	if err != nil {
		t.Fatal(err)
	}
	if parentTask.Dir != parent || parentTask.Depth != 0 || parentTask.Month != "2026-11" {
		t.Errorf("parent = %+v", parentTask)
	}
	childTask, err := tree.Find("001-child")
	if err != nil {
		t.Fatal(err)
	}
	if childTask.Dir != child || childTask.Depth != 1 || childTask.ParentDir != parent {
		t.Errorf("child = %+v", childTask)
	}
	if len(parentTask.Subtasks) != 1 || parentTask.Subtasks[0] != childTask {
		t.Errorf("parent subtasks = %v", parentTask.Subtasks)
	}
	if _, err := tree.Find("docs/tasks/2026-11/parent/001-child"); err != nil {
		t.Errorf("path selector: %v", err)
	}
}

func TestFindAmbiguousPrefix(t *testing.T) {
	root := t.TempDir()
	writeTask(t, root, "2026-11/alpha", "open", "agent", "2026-11-15T10:00:00+01:00")
	writeTask(t, root, "2026-11/alpine", "open", "agent", "2026-11-15T10:00:00+01:00")
	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tree.Find("al"); err == nil {
		t.Fatal("Find(al) succeeded across two tasks")
	}
}

func TestValidateCodes(t *testing.T) {
	root := t.TempDir()
	writeTask(t, root, "2026-11/no-author", "open", "", "2026-11-15T10:00:00+01:00")
	writeTask(t, root, "2026-11/done-no-file", "done", "agent", "2026-11-15T10:00:00+01:00")
	writeTask(t, root, "2026-11/month-mismatch", "open", "agent", "2026-10-15T10:00:00+01:00")
	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	issues := tree.Validate()
	codes := map[string]bool{}
	for _, issue := range issues {
		codes[issue.Code] = true
	}
	for _, code := range []string{"authored-by-missing", "done-without-solution", "done-without-done-file", "month-mismatch"} {
		if !codes[code] {
			t.Errorf("missing issue code %s; got %v", code, codes)
		}
	}
}

func TestLastActivityFromBoard(t *testing.T) {
	root := t.TempDir()
	dir := writeTask(t, root, "2026-11/activity", "open", "agent", "2026-11-01T10:00:00+01:00")
	board := "---\ntype: Board\nupdated: 2026-11-10T12:00:00+01:00\n---\n\n## Status\n\n- [ ] item\n"
	if err := os.WriteFile(filepath.Join(dir, ".board.md"), []byte(board), 0o644); err != nil {
		t.Fatal(err)
	}
	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	got := tree.Tasks[0].LastActivity
	want := time.Date(2026, 11, 10, 12, 0, 0, 0, time.FixedZone("CET", 3600))
	if !got.Equal(want) {
		t.Errorf("LastActivity = %s, want %s", got, want)
	}
}
