// Package jjrun reads jj changes for the journal. It is a thin, read-only adapter: the journal
// never rewrites a change, and commit trailers belong to kdn-jj-meta.
package jjrun

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// Change is one jj change as the journal displays it.
type Change struct {
	ChangeID    string   `json:"change_id"`
	CommitID    string   `json:"commit_id"`
	Description string   `json:"description"`
	Author      string   `json:"author"`
	Timestamp   string   `json:"timestamp"`
	Files       []string `json:"files,omitempty"`
}

// Runner is the jj surface the journal depends on. Tests replace it.
type Runner interface {
	// Available reports whether the jj binary can be found.
	Available() bool
	// WorkingCopyChange returns the change ID of @.
	WorkingCopyChange(ctx context.Context) (string, error)
	// Change resolves one change ID or commit ID.
	Change(ctx context.Context, rev string) (Change, error)
	// Changes returns every change a revset matches, without the file list.
	Changes(ctx context.Context, revset string) ([]Change, error)
}

// CLI runs the real jj binary.
type CLI struct {
	// Bin is the jj executable. Empty means "jj" from PATH.
	Bin string
	// Dir is the working directory of every command. Empty means the current one.
	Dir string
}

// Available reports whether the jj binary can be found.
func (c *CLI) Available() bool {
	bin := c.Bin
	if bin == "" {
		bin = "jj"
	}
	_, err := exec.LookPath(bin)
	return err == nil
}

// WorkingCopyChange implements Runner.
func (c *CLI) WorkingCopyChange(ctx context.Context) (string, error) {
	out, err := c.run(ctx, "log", "--no-pager", "--no-graph", "-r", "@", "-T", `change_id.short() ++ "\n"`)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// Change implements Runner.
func (c *CLI) Change(ctx context.Context, rev string) (Change, error) {
	rev = strings.TrimSpace(rev)
	if rev == "" {
		return Change{}, fmt.Errorf("empty revision")
	}
	out, err := c.run(ctx, "log", "--no-pager", "--no-graph", "-r", rev, "-T", "json(self)")
	if err != nil {
		return Change{}, err
	}
	var record struct {
		ChangeID    string `json:"change_id"`
		CommitID    string `json:"commit_id"`
		Description string `json:"description"`
		Author      struct {
			Name      string `json:"name"`
			Email     string `json:"email"`
			Timestamp string `json:"timestamp"`
		} `json:"author"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &record); err != nil {
		return Change{}, fmt.Errorf("parse jj log output: %w", err)
	}
	change := Change{
		ChangeID:    record.ChangeID,
		CommitID:    record.CommitID,
		Description: record.Description,
		Author:      strings.TrimSpace(record.Author.Name + " <" + record.Author.Email + ">"),
		Timestamp:   record.Author.Timestamp,
	}
	if files, err := c.files(ctx, rev); err == nil {
		change.Files = files
	}
	return change, nil
}

// Changes implements Runner. It returns every change the revset matches and skips the per-change
// file list, so a large revset stays fast.
func (c *CLI) Changes(ctx context.Context, revset string) ([]Change, error) {
	revset = strings.TrimSpace(revset)
	if revset == "" {
		return nil, fmt.Errorf("empty revset")
	}
	out, err := c.run(ctx, "log", "--no-pager", "--no-graph", "-r", revset, "-T", `json(self) ++ "\n"`)
	if err != nil {
		return nil, err
	}
	var changes []Change
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var record struct {
			ChangeID    string `json:"change_id"`
			CommitID    string `json:"commit_id"`
			Description string `json:"description"`
			Author      struct {
				Name      string `json:"name"`
				Email     string `json:"email"`
				Timestamp string `json:"timestamp"`
			} `json:"author"`
		}
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			return nil, fmt.Errorf("parse jj log output: %w", err)
		}
		changes = append(changes, Change{
			ChangeID:    record.ChangeID,
			CommitID:    record.CommitID,
			Description: record.Description,
			Author:      strings.TrimSpace(record.Author.Name + " <" + record.Author.Email + ">"),
			Timestamp:   record.Author.Timestamp,
		})
	}
	return changes, nil
}

// files reads the changed paths of one change. A failure is not fatal: the change itself is the
// useful part, and a merge or an empty change may have no summary.
func (c *CLI) files(ctx context.Context, rev string) ([]string, error) {
	out, err := c.run(ctx, "diff", "--no-pager", "-r", rev, "--summary")
	if err != nil {
		return nil, err
	}
	var files []string
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		_, path, ok := strings.Cut(line, " ")
		if !ok {
			continue
		}
		files = append(files, strings.TrimSpace(path))
	}
	return files, nil
}

func (c *CLI) run(ctx context.Context, args ...string) (string, error) {
	bin := c.Bin
	if bin == "" {
		bin = "jj"
	}
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Dir = c.Dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		message := strings.TrimSpace(stderr.String())
		if message == "" {
			message = err.Error()
		}
		return "", fmt.Errorf("jj %s: %s", args[0], message)
	}
	return stdout.String(), nil
}

var _ Runner = (*CLI)(nil)
