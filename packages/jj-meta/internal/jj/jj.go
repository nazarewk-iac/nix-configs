// Package jj runs the jj commands jj-meta needs: read a change set and rewrite one description.
//
// The package uses only jj's documented machine-readable surface: the `json(self)` template for
// reading, and `jj describe --stdin` for writing. It never parses the human log format.
package jj

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

// Change is one jj change with the fields jj-meta needs.
type Change struct {
	ChangeID    string `json:"change_id"`
	CommitID    string `json:"commit_id"`
	Description string `json:"description"`
	Immutable   bool   `json:"immutable"`
}

// Runner is the jj surface jj-meta depends on. Tests replace it with a fake.
type Runner interface {
	// Changes returns the changes the revset matches, with immutability resolved.
	Changes(ctx context.Context, revset string) ([]Change, error)
	// Describe replaces the description of one change.
	Describe(ctx context.Context, changeID, description string) error
}

// CLI runs the real jj binary.
type CLI struct {
	// Bin is the jj executable. Empty means "jj" from PATH.
	Bin string
	// Dir is the working directory of every command. Empty means the current one.
	Dir string
}

const logTemplate = `json(self) ++ "\n"`

// Changes implements Runner.
func (c *CLI) Changes(ctx context.Context, revset string) ([]Change, error) {
	revset = strings.TrimSpace(revset)
	if revset == "" {
		return nil, errors.New("empty revset")
	}
	out, err := c.run(ctx, "", "log", "--no-pager", "--no-graph", "-r", revset, "-T", logTemplate)
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
		}
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			return nil, fmt.Errorf("parse jj log output: %w", err)
		}
		changes = append(changes, Change{
			ChangeID:    record.ChangeID,
			CommitID:    record.CommitID,
			Description: record.Description,
		})
	}
	if len(changes) == 0 {
		return nil, nil
	}
	immutable, err := c.immutable(ctx, revset)
	if err != nil {
		return nil, err
	}
	for i := range changes {
		changes[i].Immutable = immutable[changes[i].ChangeID]
	}
	return changes, nil
}

// immutable returns the change IDs of the revset that are not mutable.
func (c *CLI) immutable(ctx context.Context, revset string) (map[string]bool, error) {
	out, err := c.run(ctx, "", "log", "--no-pager", "--no-graph",
		"-r", "("+revset+") & ~mutable()", "-T", `change_id ++ "\n"`)
	if err != nil {
		return nil, err
	}
	found := make(map[string]bool)
	for _, line := range strings.Split(out, "\n") {
		if id := strings.TrimSpace(line); id != "" {
			found[id] = true
		}
	}
	return found, nil
}

// Describe implements Runner.
func (c *CLI) Describe(ctx context.Context, changeID, description string) error {
	if strings.TrimSpace(description) == "" {
		return errors.New("refusing to write an empty description")
	}
	_, err := c.run(ctx, description, "describe", "--no-pager", "-r", changeID, "--stdin")
	return err
}

// run executes one jj command and returns its stdout.
func (c *CLI) run(ctx context.Context, stdin string, args ...string) (string, error) {
	bin := c.Bin
	if bin == "" {
		bin = "jj"
	}
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Dir = c.Dir
	if stdin != "" {
		cmd.Stdin = strings.NewReader(stdin)
	}
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

// Compile-time check that the CLI satisfies the interface.
var _ Runner = (*CLI)(nil)
