package task_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

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

func TestRealTaskTree(t *testing.T) {
	root := repoRoot(t)
	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(tree.Tasks) < 100 {
		t.Fatalf("loaded %d tasks, want at least 100", len(tree.Tasks))
	}
	found, err := tree.Find("agent-journal-summary")
	if err != nil {
		t.Fatal(err)
	}
	if found.Status != "done" {
		t.Errorf("agent-journal-summary status = %q, want done", found.Status)
	}
	if found.Board == nil {
		t.Error("agent-journal-summary has no parsed board")
	}
	if found.Depth != 0 {
		t.Errorf("agent-journal-summary depth = %d, want 0", found.Depth)
	}

	umbrella, err := tree.Find("generalization")
	if err != nil {
		t.Fatal(err)
	}
	if len(umbrella.Subtasks) == 0 {
		t.Error("generalization has no sub-tasks")
	}
	for _, sub := range umbrella.Subtasks {
		if sub.Depth != umbrella.Depth+1 {
			t.Errorf("%s depth = %d, want %d", sub.RelDir, sub.Depth, umbrella.Depth+1)
		}
		if sub.ParentDir != umbrella.Dir {
			t.Errorf("%s parent = %q, want %q", sub.RelDir, sub.ParentDir, umbrella.Dir)
		}
	}

	for _, selector := range []string{
		"docs/tasks/2026-11/agent-journal-summary",
		filepath.Join(root, "docs/tasks/2026-11/agent-journal-summary"),
		"agent-journal",
	} {
		if _, err := tree.Find(selector); err != nil {
			t.Errorf("Find(%q): %v", selector, err)
		}
	}

	issues := tree.Validate()
	errors, warnings := 0, 0
	for _, issue := range issues {
		if issue.Severity == "error" {
			errors++
			t.Logf("error %s %s: %s", issue.Code, issue.Path, issue.Message)
		} else {
			warnings++
		}
		if issue.Code == "frontmatter-missing" || issue.Code == "type-not-task" {
			t.Errorf("unexpected structural issue: %+v", issue)
		}
	}
	t.Logf("%d tasks, %d errors, %d warnings", len(tree.Tasks), errors, warnings)
}

func TestRealTaskMonthInheritance(t *testing.T) {
	root := repoRoot(t)
	tree, err := task.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, task := range tree.Tasks {
		if !strings.HasPrefix(task.RelDir, "docs/tasks/") {
			t.Errorf("%s is outside docs/tasks", task.RelDir)
		}
		parts := strings.Split(task.RelDir, "/")
		if len(parts) < 4 {
			t.Errorf("%s has no month", task.RelDir)
			continue
		}
		if task.Month != parts[2] {
			t.Errorf("%s month = %q, want %q", task.RelDir, task.Month, parts[2])
		}
	}
}
