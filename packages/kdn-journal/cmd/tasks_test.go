package cmd

import (
	"testing"
	"time"

	"kdn-journal/internal/task"
)

func TestOrderTasksKeepsChildrenWithParent(t *testing.T) {
	now := time.Now()
	parent := &task.Task{Dir: "/p", RelDir: "p", Slug: "parent", LastActivity: now.Add(-time.Hour)}
	child := &task.Task{Dir: "/p/c", RelDir: "p/c", Slug: "child", ParentDir: "/p", Depth: 1, LastActivity: now}
	other := &task.Task{Dir: "/o", RelDir: "o", Slug: "other", LastActivity: now.Add(-2 * time.Hour)}
	got := orderTasks([]*task.Task{child, other, parent}, true)
	if len(got) != 3 {
		t.Fatalf("orderTasks returned %d tasks", len(got))
	}
	if got[0] != parent || got[1] != child || got[2] != other {
		t.Errorf("order = %v, want parent, child, other", []string{got[0].Slug, got[1].Slug, got[2].Slug})
	}
}

func TestOrderTasksFlatByActivity(t *testing.T) {
	now := time.Now()
	older := &task.Task{Dir: "/a", RelDir: "a", LastActivity: now.Add(-time.Hour)}
	newer := &task.Task{Dir: "/b", RelDir: "b", LastActivity: now}
	got := orderTasks([]*task.Task{older, newer}, false)
	if got[0] != newer || got[1] != older {
		t.Errorf("flat order is not newest first")
	}
}
