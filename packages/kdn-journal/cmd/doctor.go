package cmd

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/spf13/cobra"

	"kdn-journal/internal/board"
	"kdn-journal/internal/frontmatter"
	"kdn-journal/internal/render"
	"kdn-journal/internal/task"
	"kdn-journal/internal/worklog"
)

func newDoctorCmd(app *App) *cobra.Command {
	var (
		parseOnly bool
		ignore    []string
	)
	cmd := &cobra.Command{
		Use:   "doctor",
		Short: "Validate the task tree and journals",
		RunE: func(cmd *cobra.Command, args []string) error {
			issues, err := app.collectIssues(parseOnly)
			if err != nil {
				return err
			}
			ignored := map[string]bool{}
			for _, code := range ignore {
				ignored[code] = true
			}
			filtered := issues[:0]
			for _, issue := range issues {
				if !ignored[issue.Code] {
					filtered = append(filtered, issue)
				}
			}
			issues = filtered
			errors, warnings := 0, 0
			for _, issue := range issues {
				if issue.Severity == "error" {
					errors++
				} else {
					warnings++
				}
			}
			if app.JSON {
				if err := app.writeJSON("doctor", map[string]any{"errors": errors, "warnings": warnings}, issues); err != nil {
					return err
				}
			} else {
				if err := render.Doctor(app.Out, app.renderOptions(false, 0), issues); err != nil {
					return err
				}
			}
			if errors > 0 {
				return &ExitError{Code: 1}
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&parseOnly, "parse-only", false, "only check that every task, board and worklog parses")
	cmd.Flags().StringArrayVar(&ignore, "ignore", nil, "ignore an issue code (repeatable)")
	return cmd
}

func (a *App) collectIssues(parseOnly bool) ([]task.Issue, error) {
	treeData, err := a.loadTree()
	if err != nil {
		return nil, err
	}
	if parseOnly {
		return parseOnlyIssues(a.Root), nil
	}
	issues := treeData.Validate()
	store, err := a.loadStore()
	if err != nil {
		return nil, err
	}
	for _, session := range store.Sessions {
		issues = append(issues, session.Issues...)
	}
	sort.SliceStable(issues, func(i, j int) bool {
		if issues[i].Path == issues[j].Path {
			return issues[i].Code < issues[j].Code
		}
		return issues[i].Path < issues[j].Path
	})
	return issues, nil
}

func parseOnlyIssues(root string) []task.Issue {
	var issues []task.Issue
	add := func(path string, err error) {
		issues = append(issues, task.Issue{
			Severity: "error",
			Code:     "parse-error",
			Path:     path,
			Message:  err.Error(),
		})
	}
	walk := func(base string, match func(string) bool, parse func(string) error) {
		_ = filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if d.IsDir() || !match(path) {
				return nil
			}
			if err := parse(path); err != nil {
				add(path, err)
			}
			return nil
		})
	}
	tasksRoot := filepath.Join(root, "docs", "tasks")
	walk(tasksRoot, func(path string) bool {
		base := filepath.Base(path)
		return base == "definition.md" || base == ".board.md" || base == "board.md" ||
			base == ".worklog.md" || base == "worklog.md"
	}, func(path string) error {
		if strings.HasSuffix(path, "definition.md") {
			_, err := frontmatter.ParseFile(path)
			return err
		}
		if strings.Contains(filepath.Base(path), "board") {
			_, err := board.ParseFile(path)
			return err
		}
		_, err := worklog.ParseFile(path)
		return err
	})
	agentsRoot := filepath.Join(root, ".cache", "agents")
	entries, err := os.ReadDir(agentsRoot)
	if err == nil {
		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}
			sessionDir := filepath.Join(agentsRoot, entry.Name())
			files, err := os.ReadDir(sessionDir)
			if err != nil {
				continue
			}
			for _, file := range files {
				if file.IsDir() {
					continue
				}
				name := file.Name()
				if !(strings.HasPrefix(name, "board") || strings.HasPrefix(name, "worklog")) || !strings.HasSuffix(name, ".md") {
					continue
				}
				path := filepath.Join(sessionDir, name)
				if strings.HasPrefix(name, "board") {
					if _, err := board.ParseFile(path); err != nil {
						add(path, err)
					}
				} else {
					if _, err := worklog.ParseFile(path); err != nil {
						add(path, err)
					}
				}
			}
		}
	}
	return issues
}
