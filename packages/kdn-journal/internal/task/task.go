// Package task discovers and validates the repository task tree under docs/tasks.
package task

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"kdn-journal/internal/board"
	"kdn-journal/internal/frontmatter"
	"kdn-journal/internal/markdown"
	"kdn-journal/internal/worklog"
)

// File is one file in a task directory.
type File struct {
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	Kind    string    `json:"kind"`
	ModTime time.Time `json:"-"`
}

// Issue is one doctor finding.
type Issue struct {
	Severity string `json:"severity"`
	Code     string `json:"code"`
	Path     string `json:"path"`
	Message  string `json:"message"`
}

// Task is one task directory.
type Task struct {
	Dir            string                `json:"dir"`
	RelDir         string                `json:"rel_dir"`
	Month          string                `json:"month"`
	Slug           string                `json:"slug"`
	Depth          int                   `json:"depth"`
	ParentDir      string                `json:"parent_dir,omitempty"`
	DefinitionPath string                `json:"definition_path"`
	Title          string                `json:"title"`
	Description    string                `json:"description"`
	Status         string                `json:"status"`
	Solution       string                `json:"solution,omitempty"`
	AuthoredBy     string                `json:"authored_by,omitempty"`
	Timestamp      time.Time             `json:"timestamp,omitempty"`
	Files          []File                `json:"files"`
	HasBoard       bool                  `json:"has_board"`
	HasWorklog     bool                  `json:"has_worklog"`
	Board          *board.Board          `json:"board,omitempty"`
	Worklog        *worklog.Worklog      `json:"worklog,omitempty"`
	Subtasks       []*Task               `json:"subtasks,omitempty"`
	LastActivity   time.Time             `json:"last_activity"`
	OpenItems      int                   `json:"open_items"`
	DoneItems      int                   `json:"done_items"`
	BlockedItems   int                   `json:"blocked_items"`
	DroppedItems   int                   `json:"dropped_items"`
	Issues         []Issue               `json:"issues,omitempty"`
	Doc            *frontmatter.Document `json:"-"`
}

// Tree is the loaded task tree.
type Tree struct {
	Root  string  `json:"root"`
	Tasks []*Task `json:"tasks"`
}

// MarshalJSON omits a missing timestamp or activity time instead of emitting the zero time.
func (t Task) MarshalJSON() ([]byte, error) {
	type alias Task
	data, err := json.Marshal(alias(t))
	if err != nil {
		return nil, err
	}
	var fields map[string]any
	if err := json.Unmarshal(data, &fields); err != nil {
		return nil, err
	}
	if t.Timestamp.IsZero() {
		delete(fields, "timestamp")
	}
	if t.LastActivity.IsZero() {
		delete(fields, "last_activity")
	}
	return json.Marshal(fields)
}

// Load walks root/docs/tasks and returns every task directory.
func Load(root string) (*Tree, error) {
	tree := &Tree{Root: root}
	tasksRoot := filepath.Join(root, "docs", "tasks")
	if _, err := os.Stat(tasksRoot); err != nil {
		if os.IsNotExist(err) {
			return tree, nil
		}
		return nil, err
	}
	if err := walkTasks(tasksRoot, root, nil, tree); err != nil {
		return nil, err
	}
	return tree, nil
}

func walkTasks(dir, root string, parent *Task, tree *Tree) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil // skip an unreadable directory; doctor reports the tree it can read
	}
	definition := filepath.Join(dir, "definition.md")
	childParent := parent
	if _, err := os.Stat(definition); err == nil {
		task, err := loadTask(dir, root, parent)
		if err != nil {
			return err
		}
		tree.Tasks = append(tree.Tasks, task)
		if parent != nil {
			parent.Subtasks = append(parent.Subtasks, task)
		}
		childParent = task
	}
	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		child := filepath.Join(dir, entry.Name())
		if err := walkTasks(child, root, childParent, tree); err != nil {
			return err
		}
	}
	return nil
}

func loadTask(dir, root string, parent *Task) (*Task, error) {
	rel, err := filepath.Rel(root, dir)
	if err != nil {
		return nil, err
	}
	rel = filepath.ToSlash(rel)
	parts := strings.Split(rel, "/")
	month := ""
	if len(parts) > 2 {
		month = parts[2]
	}
	definitionPath := filepath.Join(dir, "definition.md")
	task := &Task{
		Dir:            dir,
		RelDir:         rel,
		Month:          month,
		Slug:           filepath.Base(dir),
		DefinitionPath: definitionPath,
	}
	if parent != nil {
		task.ParentDir = parent.Dir
		task.Depth = parent.Depth + 1
	}
	doc, err := frontmatter.ParseFile(definitionPath)
	if err != nil {
		task.Title = task.Slug
		task.Issues = append(task.Issues, Issue{
			Severity: "error",
			Code:     "definition-unreadable",
			Path:     definitionPath,
			Message:  err.Error(),
		})
	} else {
		task.Doc = doc
		task.Title = doc.String("title")
		task.Description = doc.String("description")
		task.Status = strings.TrimSpace(doc.String("status"))
		task.Solution = strings.TrimSpace(doc.String("solution"))
		task.AuthoredBy = strings.TrimSpace(doc.String("authored_by"))
		if task.Title == "" {
			task.Title = firstH1(doc.Body, task.Slug)
		}
		if ts, ok := doc.Time("timestamp"); ok {
			task.Timestamp = ts
		}
	}
	task.Files = listFiles(dir)
	task.HasBoard, task.HasWorklog = false, false
	if path := findFile(dir, ".board.md", "board.md"); path != "" {
		if b, err := board.ParseFile(path); err == nil {
			task.Board = b
			task.HasBoard = true
		}
	}
	if path := findFile(dir, ".worklog.md", "worklog.md"); path != "" {
		if w, err := worklog.ParseFile(path); err == nil {
			task.Worklog = w
			task.HasWorklog = true
		}
	}
	if task.Board != nil {
		c := task.Board.Counts()
		task.OpenItems, task.DoneItems = c.Open, c.Done
		task.BlockedItems, task.DroppedItems = c.Blocked, c.Dropped
		if task.Board.HasUpdated {
			task.LastActivity = task.Board.Updated
		}
	}
	if task.LastActivity.IsZero() {
		task.LastActivity = task.Timestamp
	}
	if task.LastActivity.IsZero() {
		for _, file := range task.Files {
			if file.ModTime.After(task.LastActivity) {
				task.LastActivity = file.ModTime
			}
		}
	}
	task.Issues = append(task.Issues, task.Validate()...)
	return task, nil
}

func firstH1(body []byte, fallback string) string {
	for _, line := range markdown.Headings(markdown.Scan(body)) {
		if line.Level == 1 {
			title := strings.TrimSpace(line.Text)
			if title != "" {
				return title
			}
		}
	}
	return fallback
}

func listFiles(dir string) []File {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	files := make([]File, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		name := entry.Name()
		files = append(files, File{
			Name:    name,
			Path:    filepath.Join(dir, name),
			Kind:    fileKind(name),
			ModTime: info.ModTime(),
		})
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Name < files[j].Name })
	return files
}

func fileKind(name string) string {
	switch name {
	case "definition.md":
		return "definition"
	case "research.md":
		return "research"
	case "design.md":
		return "design"
	case "status.md":
		return "status"
	case "done.md":
		return "done"
	case ".board.md", "board.md":
		return "board"
	case ".worklog.md", "worklog.md":
		return "worklog"
	}
	if strings.HasSuffix(name, ".research.md") {
		return "research"
	}
	if strings.HasSuffix(name, ".design.md") {
		return "design"
	}
	return "other"
}

func findFile(dir string, names ...string) string {
	for _, name := range names {
		path := filepath.Join(dir, name)
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path
		}
	}
	return ""
}

// Find resolves a path, a repo-relative path, a slug or a unique slug prefix.
func (t *Tree) Find(selector string) (*Task, error) {
	selector = strings.TrimSpace(selector)
	if selector == "" {
		return nil, fmt.Errorf("empty task selector")
	}
	clean := filepath.Clean(selector)
	abs := clean
	if !filepath.IsAbs(abs) {
		abs = filepath.Join(t.Root, clean)
	}
	var exact []*Task
	var rel []*Task
	var slug []*Task
	var prefix []*Task
	for _, task := range t.Tasks {
		if task.Dir == abs || task.Dir == clean {
			exact = append(exact, task)
		}
		if task.RelDir == filepath.ToSlash(clean) || task.RelDir == filepath.ToSlash(selector) {
			rel = append(rel, task)
		}
		if task.Slug == selector {
			slug = append(slug, task)
		}
		if strings.HasPrefix(task.Slug, selector) {
			prefix = append(prefix, task)
		}
	}
	for _, candidates := range [][]*Task{exact, rel, slug, prefix} {
		if len(candidates) == 1 {
			return candidates[0], nil
		}
		if len(candidates) > 1 {
			return nil, ambiguous(selector, candidates)
		}
	}
	return nil, fmt.Errorf("task %q not found", selector)
}

func ambiguous(selector string, candidates []*Task) error {
	names := make([]string, len(candidates))
	for i, task := range candidates {
		names[i] = task.RelDir
	}
	return fmt.Errorf("task %q is ambiguous: %s", selector, strings.Join(names, ", "))
}

// Active returns open and in-progress tasks.
// Validate returns every task issue plus tree-level duplicate-slug warnings.
func (t *Tree) Validate() []Issue {
	var issues []Issue
	bySlug := map[string][]*Task{}
	for _, task := range t.Tasks {
		issues = append(issues, task.Issues...)
		bySlug[task.Slug] = append(bySlug[task.Slug], task)
	}
	for slug, tasks := range bySlug {
		if len(tasks) < 2 {
			continue
		}
		paths := make([]string, len(tasks))
		for i, task := range tasks {
			paths[i] = task.RelDir
		}
		sort.Strings(paths)
		issues = append(issues, Issue{
			Severity: "warning",
			Code:     "duplicate-slug",
			Path:     strings.Join(paths, ", "),
			Message:  fmt.Sprintf("slug %q is used by %d tasks", slug, len(tasks)),
		})
	}
	sort.Slice(issues, func(i, j int) bool {
		if issues[i].Path == issues[j].Path {
			return issues[i].Code < issues[j].Code
		}
		return issues[i].Path < issues[j].Path
	})
	return issues
}

// Validate checks one task against the task convention.
func (t *Task) Validate() []Issue {
	var issues []Issue
	add := func(severity, code, message string) {
		issues = append(issues, Issue{Severity: severity, Code: code, Path: t.DefinitionPath, Message: message})
	}
	if t.Doc == nil || !t.Doc.HasFrontmatter {
		add("error", "frontmatter-missing", "definition.md has no frontmatter")
	} else if t.Doc.FrontmatterError != "" {
		add("warning", "frontmatter-invalid", "frontmatter is not valid YAML; used the line fallback: "+t.Doc.FrontmatterError)
	}
	if t.Doc != nil && t.Doc.HasFrontmatter && strings.TrimSpace(t.Doc.String("type")) != "Task" {
		add("error", "type-not-task", fmt.Sprintf("type is %q, want Task", t.Doc.String("type")))
	}
	if t.Status == "" {
		add("error", "status-missing", "status is missing")
	} else if !knownStatus(t.Status) {
		add("warning", "status-unknown", fmt.Sprintf("status %q is not a known value", t.Status))
	}
	if t.AuthoredBy == "" {
		add("error", "authored-by-missing", "authored_by is missing")
	}
	if t.Timestamp.IsZero() {
		add("warning", "timestamp-missing", "timestamp is missing")
	} else if t.Month != "" && t.Timestamp.Format("2006-01") != t.Month {
		add("warning", "month-mismatch", fmt.Sprintf("directory month %s differs from timestamp month %s", t.Month, t.Timestamp.Format("2006-01")))
	}
	done := t.Status == "done"
	if done {
		if t.Solution == "" {
			add("error", "done-without-solution", "status is done but solution is missing")
		} else if _, err := os.Stat(filepath.Join(t.Dir, t.Solution)); err != nil {
			add("error", "solution-missing", fmt.Sprintf("solution %q does not exist", t.Solution))
		}
		if _, err := os.Stat(filepath.Join(t.Dir, "done.md")); err != nil {
			add("error", "done-without-done-file", "status is done but done.md is missing")
		}
		if _, err := os.Stat(filepath.Join(t.Dir, "status.md")); err == nil {
			add("error", "done-with-status-file", "status is done but status.md still exists")
		}
	} else {
		if _, err := os.Stat(filepath.Join(t.Dir, "done.md")); err == nil {
			add("warning", "done-file-while-open", "done.md exists while the task is not done")
		}
		if _, err := os.Stat(filepath.Join(t.Dir, "status.md")); err == nil && t.Status != "in-progress" {
			add("warning", "status-file-while-open", "status.md exists while the task is not in-progress")
		}
	}
	return issues
}

func knownStatus(status string) bool {
	switch status {
	case "open", "in-progress", "done", "not-scheduled", "blocked", "active":
		return true
	default:
		return false
	}
}
