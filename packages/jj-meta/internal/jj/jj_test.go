package jj

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestCLIAgainstRealRepo exercises the documented jj surface: `json(self)` for reading and
// `describe --stdin` for writing. It skips when jj is not on PATH, so the suite still passes in a
// sandbox without jj.
func TestCLIAgainstRealRepo(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping the jj integration test in short mode")
	}
	if _, err := exec.LookPath("jj"); err != nil {
		t.Skip("jj is not on PATH")
	}
	dir := t.TempDir()
	config := filepath.Join(dir, "jj.toml")
	if err := os.WriteFile(config, []byte("user.name = \"Test\"\nuser.email = \"test@example.com\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("JJ_CONFIG", config)
	t.Setenv("JJ_USER", "Test")
	t.Setenv("JJ_EMAIL", "test@example.com")

	cli := &CLI{Dir: dir}
	if _, err := cli.run(context.Background(), "", "git", "init"); err != nil {
		t.Fatalf("jj git init: %v", err)
	}

	changes, err := cli.Changes(context.Background(), "@")
	if err != nil {
		t.Fatalf("Changes() error = %v", err)
	}
	if len(changes) != 1 {
		t.Fatalf("Changes() returned %d changes, want 1", len(changes))
	}
	change := changes[0]
	if change.ChangeID == "" || change.CommitID == "" {
		t.Fatalf("Changes() = %#v", change)
	}
	if change.Immutable {
		t.Fatalf("the working copy must be mutable: %#v", change)
	}

	description := "subject\n\nAssisted-by: opencode:model\nSession-Id: ses_1\n"
	if err := cli.Describe(context.Background(), change.ChangeID, description); err != nil {
		t.Fatalf("Describe() error = %v", err)
	}
	changes, err = cli.Changes(context.Background(), change.ChangeID)
	if err != nil {
		t.Fatalf("Changes() error = %v", err)
	}
	if len(changes) != 1 {
		t.Fatalf("Changes() returned %d changes", len(changes))
	}
	if changes[0].Description != description {
		t.Fatalf("Description = %q, want %q", changes[0].Description, description)
	}

	if err := cli.Describe(context.Background(), change.ChangeID, ""); err == nil {
		t.Fatal("Describe() accepted an empty description")
	}
	if _, err := cli.Changes(context.Background(), ""); err == nil {
		t.Fatal("Changes() accepted an empty revset")
	}
	if _, err := cli.Changes(context.Background(), "no-such-change"); err == nil {
		t.Fatal("Changes() accepted an unknown revision")
	}
}

func TestImmutableChanges(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping the jj integration test in short mode")
	}
	if _, err := exec.LookPath("jj"); err != nil {
		t.Skip("jj is not on PATH")
	}
	dir := t.TempDir()
	config := filepath.Join(dir, "jj.toml")
	if err := os.WriteFile(config, []byte("user.name = \"Test\"\nuser.email = \"test@example.com\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("JJ_CONFIG", config)
	cli := &CLI{Dir: dir}
	if _, err := cli.run(context.Background(), "", "git", "init"); err != nil {
		t.Fatalf("jj git init: %v", err)
	}
	// The root commit is always immutable, so it is the stable fixture for the revset.
	changes, err := cli.Changes(context.Background(), "@-")
	if err != nil {
		t.Fatalf("Changes() error = %v", err)
	}
	if len(changes) != 1 {
		t.Fatalf("Changes() returned %d changes", len(changes))
	}
	if !changes[0].Immutable {
		t.Fatalf("the root change must be immutable: %#v", changes[0])
	}
	if got := strings.TrimSpace(changes[0].Description); got != "" {
		t.Fatalf("root description = %q", got)
	}
}
