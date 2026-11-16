package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"kdn-journal/internal/frontmatter"
)

func setTaskStatus(app *App, selector, status string) error {
	status = strings.ToLower(strings.TrimSpace(status))
	if !knownStatus(status) {
		return fmt.Errorf("unknown status %q; use open, in-progress, done, not-scheduled or blocked", status)
	}
	tree, err := app.loadTree()
	if err != nil {
		return err
	}
	item, err := tree.Find(selector)
	if err != nil {
		return err
	}
	if item.Status == status {
		fmt.Fprintf(app.Out, "%s: already %s\n", item.RelDir, status)
		return nil
	}
	if status == "done" {
		if _, err := os.Stat(filepath.Join(item.Dir, "done.md")); err != nil {
			return fmt.Errorf("refusing done: %s has no done.md; write the solution first", item.RelDir)
		}
		if _, err := os.Stat(filepath.Join(item.Dir, "status.md")); err == nil {
			return fmt.Errorf("refusing done: %s still has status.md; fold it into done.md and delete it", item.RelDir)
		}
		if item.Solution != "" {
			if _, err := os.Stat(filepath.Join(item.Dir, item.Solution)); err != nil {
				return fmt.Errorf("refusing done: solution %q does not exist", item.Solution)
			}
		}
	}
	info, err := os.Lstat(item.DefinitionPath)
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("refusing to rewrite %s: it is a symlink", item.DefinitionPath)
	}
	data, err := os.ReadFile(item.DefinitionPath)
	if err != nil {
		return err
	}
	data, err = frontmatter.SetScalar(data, "status", status)
	if err != nil {
		return err
	}
	if status == "done" && strings.TrimSpace(item.Solution) == "" {
		data, err = frontmatter.SetScalar(data, "solution", "done.md")
		if err != nil {
			return err
		}
	}
	if err := atomicWrite(item.DefinitionPath, data, info.Mode()); err != nil {
		return err
	}
	if app.JSONL {
		return app.writeJSONL([]any{map[string]any{"task": item.RelDir, "status": status}})
	}
	if app.JSON {
		return app.writeJSON("task set-status", map[string]any{"task": item.RelDir, "status": status}, nil)
	}
	fmt.Fprintf(app.Out, "%s: %s -> %s\n", item.RelDir, item.Status, status)
	return nil
}

func atomicWrite(path string, data []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".kdn-journal-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(mode); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}
