// Package jjmeta calls the separate jj-meta binary.
//
// kdn-journal never edits a commit description. It records the session mapping in its sidecar and
// asks jj-meta to write the trailers, so the attribution policy lives in one place.
package jjmeta

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// Options selects the attribution a caller wants.
type Options struct {
	Session string
	Harness string
	Model   string
	Profile string
}

// Attributor is the jj-meta surface the journal depends on. Tests replace it.
type Attributor interface {
	// Available reports whether the binary can be found.
	Available() bool
	// Attribute appends the missing trailers to one change.
	Attribute(ctx context.Context, changeID string, opts Options) error
}

// CLI runs the real jj-meta binary.
type CLI struct {
	// Bin is the executable. Empty means "jj-meta" from PATH.
	Bin string
}

// New returns a CLI that uses bin, or PATH when bin is empty.
func New(bin string) *CLI { return &CLI{Bin: bin} }

func (c *CLI) bin() string {
	if c.Bin != "" {
		return c.Bin
	}
	return "jj-meta"
}

// Available implements Attributor.
func (c *CLI) Available() bool {
	_, err := exec.LookPath(c.bin())
	return err == nil
}

// Attribute implements Attributor.
func (c *CLI) Attribute(ctx context.Context, changeID string, opts Options) error {
	args := []string{"attribute", changeID}
	if opts.Session != "" {
		args = append(args, "--session", opts.Session)
	}
	if opts.Harness != "" {
		args = append(args, "--harness", opts.Harness)
	}
	if opts.Model != "" {
		args = append(args, "--model", opts.Model)
	}
	if opts.Profile != "" {
		args = append(args, "--profile", opts.Profile)
	}
	cmd := exec.CommandContext(ctx, c.bin(), args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		message := strings.TrimSpace(stderr.String())
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("jj-meta attribute: %s", message)
	}
	return nil
}

var _ Attributor = (*CLI)(nil)
