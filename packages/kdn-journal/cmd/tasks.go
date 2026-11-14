package cmd

import (
	"fmt"
	"sort"
	"strings"

	"github.com/spf13/cobra"

	"kdn-journal/internal/render"
	"kdn-journal/internal/task"
)

func newTasksCmd(app *App) *cobra.Command {
	var (
		status string
		month  string
		tree   bool
		limit  int
		all    bool
	)
	cmd := &cobra.Command{
		Use:   "tasks",
		Short: "List repository tasks",
		RunE: func(cmd *cobra.Command, args []string) error {
			treeData, err := app.loadTree()
			if err != nil {
				return err
			}
			tasks := append([]*task.Task(nil), treeData.Tasks...)
			filtered := tasks[:0]
			for _, item := range tasks {
				if status != "" && status != "all" && item.Status != status {
					continue
				}
				if month != "" && item.Month != month {
					continue
				}
				filtered = append(filtered, item)
			}
			tasks = filtered
			if status != "" && status != "all" {
				known := map[string]bool{}
				for _, item := range treeData.Tasks {
					known[item.Status] = true
				}
				if !known[status] {
					values := make([]string, 0, len(known))
					for value := range known {
						values = append(values, value)
					}
					sort.Strings(values)
					return fmt.Errorf("status %q not found; known: %s", status, strings.Join(values, ", "))
				}
			}
			tasks = orderTasks(tasks, tree)
			if app.JSON {
				return app.writeJSON("tasks", map[string]any{"tasks": tasks}, nil)
			}
			return render.Tasks(app.Out, app.renderOptions(all, 0), tasks, tree, limit)
		},
	}
	cmd.Flags().StringVar(&status, "status", "all", "filter by status (open, in-progress, done, not-scheduled, or any value)")
	cmd.Flags().StringVar(&month, "month", "", "filter by month (YYYY-MM)")
	cmd.Flags().BoolVar(&tree, "tree", false, "indent sub-tasks under their parent")
	cmd.Flags().IntVar(&limit, "limit", 20, "maximum tasks to print")
	cmd.Flags().BoolVar(&all, "all", false, "print every task")
	return cmd
}

func newTaskCmd(app *App) *cobra.Command {
	var printPath bool
	cmd := &cobra.Command{
		Use:   "task <dir|slug>",
		Short: "Show one repository task",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			treeData, err := app.loadTree()
			if err != nil {
				return err
			}
			item, err := treeData.Find(args[0])
			if err != nil {
				return err
			}
			if printPath {
				_, err := fmt.Fprintln(app.Out, item.DefinitionPath)
				return err
			}
			if app.JSON {
				return app.writeJSON("task", map[string]any{"task": item}, item.Issues)
			}
			return render.Task(app.Out, app.renderOptions(false, 5), item)
		},
	}
	cmd.Flags().BoolVar(&printPath, "print-path", false, "print the resolved definition.md and exit")
	cmd.AddCommand(newSetStatusCmd(app))
	return cmd
}

func newSetStatusCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "set-status <dir|slug> <open|in-progress|done|not-scheduled|blocked>",
		Short: "Update the status field of a task definition",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			return setTaskStatus(app, args[0], args[1])
		},
	}
}

func knownStatus(value string) bool {
	switch strings.ToLower(value) {
	case "open", "in-progress", "done", "not-scheduled", "blocked", "active":
		return true
	default:
		return false
	}
}

// orderTasks sorts a flat list by activity. In tree mode it keeps each parent and its children
// adjacent, so the indentation never attaches a child to an unrelated task.
func orderTasks(tasks []*task.Task, tree bool) []*task.Task {
	if !tree {
		sortGroup(tasks)
		return tasks
	}
	present := map[string]bool{}
	for _, item := range tasks {
		present[item.Dir] = true
	}
	groups := map[string][]*task.Task{}
	for _, item := range tasks {
		parent := item.ParentDir
		if parent == "" || !present[parent] {
			parent = ""
		}
		groups[parent] = append(groups[parent], item)
	}
	for _, group := range groups {
		sortGroup(group)
	}
	out := make([]*task.Task, 0, len(tasks))
	var add func(string)
	add = func(parent string) {
		for _, item := range groups[parent] {
			out = append(out, item)
			add(item.Dir)
		}
	}
	add("")
	return out
}

func sortGroup(tasks []*task.Task) {
	sort.SliceStable(tasks, func(i, j int) bool {
		if tasks[i].LastActivity.Equal(tasks[j].LastActivity) {
			return tasks[i].RelDir < tasks[j].RelDir
		}
		return tasks[i].LastActivity.After(tasks[j].LastActivity)
	})
}
