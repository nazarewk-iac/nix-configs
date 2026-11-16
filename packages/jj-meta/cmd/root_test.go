package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"jj-meta/internal/jj"
)

type describedCall struct {
	changeID    string
	description string
}

type fakeRunner struct {
	changes   []jj.Change
	described []describedCall
	err       error
}

func (f *fakeRunner) Changes(ctx context.Context, revset string) ([]jj.Change, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.changes, nil
}

func (f *fakeRunner) Describe(ctx context.Context, changeID, description string) error {
	f.described = append(f.described, describedCall{changeID: changeID, description: description})
	for i := range f.changes {
		if f.changes[i].ChangeID == changeID {
			f.changes[i].Description = description
		}
	}
	return nil
}

func newTestApp(runner jj.Runner, env map[string]string) *App {
	return &App{
		Out:     &bytes.Buffer{},
		Err:     &bytes.Buffer{},
		Version: "test",
		Now:     func() time.Time { return time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC) },
		Getenv:  func(key string) string { return env[key] },
		Runner:  runner,
	}
}

func execute(t *testing.T, app *App, args ...string) (string, string, error) {
	t.Helper()
	root := NewRootWithApp(app)
	root.SetArgs(args)
	err := root.Execute()
	out, _ := app.Out.(*bytes.Buffer)
	errOut, _ := app.Err.(*bytes.Buffer)
	return out.String(), errOut.String(), err
}

func opencodeEnv() map[string]string {
	return map[string]string{"OPENCODE_SESSION_ID": "ses_1", "OPENCODE_MODEL": "model"}
}

func TestAttributeAddsTrailers(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111", Description: "subject\n"}}}
	app := newTestApp(runner, opencodeEnv())
	out, _, err := execute(t, app, "attribute", "@")
	if err != nil {
		t.Fatalf("attribute: %v", err)
	}
	if !strings.Contains(out, "attributed aaaa") {
		t.Fatalf("output = %q", out)
	}
	if len(runner.described) != 1 {
		t.Fatalf("Describe called %d times", len(runner.described))
	}
	want := "subject\n\nAssisted-by: opencode:model\nSession-Id: ses_1\nHarness: opencode\nModel: model\n"
	if got := runner.described[0].description; got != want {
		t.Fatalf("description = %q, want %q", got, want)
	}
}

func TestAttributeIsIdempotent(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111", Description: "subject\n"}}}
	app := newTestApp(runner, opencodeEnv())
	if _, _, err := execute(t, app, "attribute", "@"); err != nil {
		t.Fatalf("first attribute: %v", err)
	}
	first := runner.described[0].description
	out, _, err := execute(t, app, "attribute", "@")
	if err != nil {
		t.Fatalf("second attribute: %v", err)
	}
	if len(runner.described) != 1 {
		t.Fatalf("the second run rewrote the change: %#v", runner.described)
	}
	if !strings.Contains(out, "nothing to add") {
		t.Fatalf("output = %q", out)
	}
	if runner.changes[0].Description != first {
		t.Fatalf("description changed on the second run")
	}
}

func TestAttributeRefusesImmutable(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111", Immutable: true}}}
	app := newTestApp(runner, opencodeEnv())
	_, _, err := execute(t, app, "attribute", "@-")
	if err == nil {
		t.Fatal("attribute accepted an immutable change")
	}
	exit, ok := AsExitError(err)
	if !ok || exit.Code != 1 {
		t.Fatalf("error = %#v", err)
	}
	if len(runner.described) != 0 {
		t.Fatal("attribute described an immutable change")
	}
}

func TestAttributeDryRun(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111"}}}
	app := newTestApp(runner, opencodeEnv())
	out, _, err := execute(t, app, "attribute", "@", "--dry-run")
	if err != nil {
		t.Fatalf("attribute: %v", err)
	}
	if len(runner.described) != 0 {
		t.Fatal("dry run described the change")
	}
	if !strings.Contains(out, "would attribute aaaa") {
		t.Fatalf("output = %q", out)
	}
}

func TestAttributeNoMatchingChange(t *testing.T) {
	app := newTestApp(&fakeRunner{}, opencodeEnv())
	_, _, err := execute(t, app, "attribute", "none")
	exit, ok := AsExitError(err)
	if !ok || exit.Code != 1 {
		t.Fatalf("error = %#v", err)
	}
}

func TestAttributeGitHubNeedsEmail(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111"}}}
	app := newTestApp(runner, opencodeEnv())
	if _, _, err := execute(t, app, "attribute", "@", "--profile", "github"); err == nil {
		t.Fatal("github profile accepted a missing email")
	}
}

func TestAttributeCoauthorEmailFromEnv(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111"}}}
	env := opencodeEnv()
	env["JJ_META_COAUTHOR_EMAIL"] = "bot@example.com"
	app := newTestApp(runner, env)
	if _, _, err := execute(t, app, "attribute", "@", "--profile", "github"); err != nil {
		t.Fatalf("attribute: %v", err)
	}
	got := runner.described[0].description
	if !strings.Contains(got, "Co-authored-by: opencode <bot@example.com>") {
		t.Fatalf("description = %q", got)
	}
}

func TestAttributeNoSession(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111"}}}
	app := newTestApp(runner, opencodeEnv())
	if _, _, err := execute(t, app, "attribute", "@", "--no-session"); err != nil {
		t.Fatalf("attribute: %v", err)
	}
	if strings.Contains(runner.described[0].description, "Session-Id") {
		t.Fatalf("description = %q", runner.described[0].description)
	}
}

func TestAttributeCustomTrailerAndProfileFromEnv(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111"}}}
	env := opencodeEnv()
	env["JJ_META_PROFILE"] = "asf"
	app := newTestApp(runner, env)
	if _, _, err := execute(t, app, "attribute", "@", "--trailer", "Reviewed-by=Human"); err != nil {
		t.Fatalf("attribute: %v", err)
	}
	got := runner.described[0].description
	if !strings.Contains(got, "Generated-by: opencode:model") {
		t.Fatalf("description = %q", got)
	}
	if !strings.Contains(got, "Reviewed-by: Human") {
		t.Fatalf("description = %q", got)
	}
}

func TestAttributeJSON(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", CommitID: "1111", Description: "subject\n"}}}
	app := newTestApp(runner, opencodeEnv())
	out, _, err := execute(t, app, "--json", "attribute", "@")
	if err != nil {
		t.Fatalf("attribute: %v", err)
	}
	var env struct {
		SchemaVersion int    `json:"schema_version"`
		Command       string `json:"command"`
		Data          struct {
			Profile string `json:"profile"`
			Session struct {
				Harness string `json:"harness"`
				ID      string `json:"session_id"`
			} `json:"session"`
			Changes []struct {
				ChangeID string   `json:"change_id"`
				Added    []string `json:"added"`
				Written  bool     `json:"written"`
			} `json:"changes"`
		} `json:"data"`
	}
	if err := json.Unmarshal([]byte(out), &env); err != nil {
		t.Fatalf("invalid JSON: %v\n%s", err, out)
	}
	if env.SchemaVersion != 1 || env.Command != "attribute" {
		t.Fatalf("envelope = %#v", env)
	}
	if env.Data.Profile != "portable" || env.Data.Session.Harness != "opencode" || env.Data.Session.ID != "ses_1" {
		t.Fatalf("data = %#v", env.Data)
	}
	if len(env.Data.Changes) != 1 || len(env.Data.Changes[0].Added) != 4 || !env.Data.Changes[0].Written {
		t.Fatalf("changes = %#v", env.Data.Changes)
	}
}

func TestShow(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{
		ChangeID:    "aaaa",
		CommitID:    "1111",
		Description: "subject\n\nbody\n\nAssisted-by: opencode:model\n",
	}}}
	app := newTestApp(runner, nil)
	out, _, err := execute(t, app, "show", "@")
	if err != nil {
		t.Fatalf("show: %v", err)
	}
	for _, want := range []string{"aaaa", "mutable", "subject", "body", "Assisted-by: opencode:model"} {
		if !strings.Contains(out, want) {
			t.Fatalf("output misses %q:\n%s", want, out)
		}
	}
}

func TestShowRejectsManyChanges(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa"}, {ChangeID: "bbbb"}}}
	app := newTestApp(runner, nil)
	if _, _, err := execute(t, app, "show", "main..@"); err == nil {
		t.Fatal("show accepted a revset that matches two changes")
	}
}

func TestListMissing(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{
		{ChangeID: "aaaa", Description: "Assisted-by: opencode:model\n"},
		{ChangeID: "bbbb", Description: "subject\n"},
	}}
	app := newTestApp(runner, nil)
	out, _, err := execute(t, app, "list", "--revset", "main..@", "--missing")
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if strings.Contains(out, "aaaa") || !strings.Contains(out, "bbbb") {
		t.Fatalf("output = %q", out)
	}
}

func TestCheck(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{
		{ChangeID: "aaaa", Description: "Assisted-by: opencode:model\n"},
		{ChangeID: "bbbb", Description: "subject\n"},
	}}
	app := newTestApp(runner, nil)
	out, _, err := execute(t, app, "check", "--revset", "main..@")
	if err == nil {
		t.Fatal("check passed with a missing Assisted-by")
	}
	exit, ok := AsExitError(err)
	if !ok || exit.Code != 1 {
		t.Fatalf("error = %#v", err)
	}
	if !strings.Contains(out, "bbbb  missing Assisted-by") || !strings.Contains(out, "aaaa  ok") {
		t.Fatalf("output = %q", out)
	}
}

func TestCheckRequireCoauthor(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "aaaa", Description: "Assisted-by: opencode:model\n"}}}
	app := newTestApp(runner, nil)
	if _, _, err := execute(t, app, "check", "@"); err != nil {
		t.Fatalf("check without the coauthor requirement: %v", err)
	}
	if _, _, err := execute(t, app, "check", "@", "--require", "coauthor"); err == nil {
		t.Fatal("check passed without Co-authored-by while requiring it")
	}
}

func TestCheckJSON(t *testing.T) {
	runner := &fakeRunner{changes: []jj.Change{{ChangeID: "bbbb", Description: "subject\n"}}}
	app := newTestApp(runner, nil)
	out, _, err := execute(t, app, "--json", "check", "@")
	if err == nil {
		t.Fatal("check passed with a missing Assisted-by")
	}
	var env struct {
		Data struct {
			ErrorCount int `json:"error_count"`
			Changes    []struct {
				Errors []string `json:"errors"`
			} `json:"changes"`
		} `json:"data"`
		Issues []Issue `json:"issues"`
	}
	if jsonErr := json.Unmarshal([]byte(out), &env); jsonErr != nil {
		t.Fatalf("invalid JSON: %v\n%s", jsonErr, out)
	}
	if env.Data.ErrorCount != 1 || len(env.Issues) != 1 || env.Issues[0].Severity != "error" {
		t.Fatalf("envelope = %#v", env)
	}
}

func TestVersion(t *testing.T) {
	app := newTestApp(&fakeRunner{}, nil)
	out, _, err := execute(t, app, "version")
	if err != nil {
		t.Fatalf("version: %v", err)
	}
	if strings.TrimSpace(out) != "jj-meta test" {
		t.Fatalf("output = %q", out)
	}
}
