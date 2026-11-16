package attribution

import (
	"strings"
	"testing"

	"kdn-jj-meta/internal/session"
	"kdn-jj-meta/internal/trailer"
)

func build(t *testing.T, opts Options) Plan {
	t.Helper()
	plan, err := Build(opts)
	if err != nil {
		t.Fatalf("Build() error = %v", err)
	}
	return plan
}

func keys(plan Plan) []string {
	out := make([]string, 0, len(plan.Trailers))
	for _, t := range plan.Trailers {
		out = append(out, t.Key+"="+t.Value)
	}
	return out
}

func joined(plan Plan) string { return strings.Join(keys(plan), "\n") }

var agent = session.Session{Harness: "opencode", ID: "ses_1", Model: "model"}

func TestDefaultProfiles(t *testing.T) {
	plan := build(t, Options{Session: agent})
	want := "Assisted-by=opencode:model\nGenerated-by=opencode:model\nSession-Id=ses_1\nHarness=opencode\nModel=model"
	if got := joined(plan); got != want {
		t.Fatalf("Build() =\n%s\nwant\n%s", got, want)
	}
	if len(plan.Warnings) != 0 {
		t.Fatalf("unexpected warnings: %v", plan.Warnings)
	}
}

func TestAgentProfileOnly(t *testing.T) {
	plan := build(t, Options{Profiles: []Profile{Agent}, Session: agent})
	want := "Session-Id=ses_1\nHarness=opencode\nModel=model"
	if got := joined(plan); got != want {
		t.Fatalf("Build() =\n%s\nwant\n%s", got, want)
	}
}

func TestNixpkgsProfileOnly(t *testing.T) {
	plan := build(t, Options{Profiles: []Profile{Nixpkgs}, Session: agent})
	if got := joined(plan); got != "Assisted-by=opencode:model" {
		t.Fatalf("Build() = %s", got)
	}
}

func TestNoSession(t *testing.T) {
	plan := build(t, Options{Session: agent, NoSession: true})
	if strings.Contains(joined(plan), "Session-Id") {
		t.Fatalf("NoSession wrote a Session-Id: %s", joined(plan))
	}
}

func TestGitHubProfileNeedsEmail(t *testing.T) {
	if _, err := Build(Options{Profiles: []Profile{GitHub}, Session: agent}); err == nil {
		t.Fatal("Build() accepted the github profile without an email")
	}
	plan := build(t, Options{Profiles: []Profile{GitHub}, Session: agent, CoauthorEmail: "bot@example.com"})
	if got := joined(plan); got != "Co-authored-by=opencode <bot@example.com>" {
		t.Fatalf("Build() = %s", got)
	}
}

func TestCoauthorAddsToTheActiveSet(t *testing.T) {
	plan := build(t, Options{Session: agent, Coauthor: true, CoauthorEmail: "bot@example.com"})
	got := joined(plan)
	if !strings.Contains(got, "Co-authored-by=opencode <bot@example.com>") {
		t.Fatalf("Build() = %s", got)
	}
	if !strings.Contains(got, "Assisted-by=opencode:model") || !strings.Contains(got, "Generated-by=opencode:model") {
		t.Fatalf("--coauthor dropped the default profiles: %s", got)
	}
	for _, line := range plan.Trailers {
		if strings.EqualFold(line.Key, "Co-authored-by") && strings.Contains(line.Value, "kdn.im") {
			t.Fatalf("the human author leaked into Co-authored-by: %s", line)
		}
	}
}

func TestASFProfileUsesGeneratedBy(t *testing.T) {
	plan := build(t, Options{Profiles: []Profile{ASF}, Session: agent})
	got := joined(plan)
	if !strings.Contains(got, "Generated-by=opencode:model") {
		t.Fatalf("Build() = %s", got)
	}
	if strings.Contains(got, "Assisted-by") || strings.Contains(got, "Session-Id") {
		t.Fatalf("asf profile wrote another profile's field: %s", got)
	}
}

func TestFullProfile(t *testing.T) {
	plan := build(t, Options{Profiles: []Profile{Full}, Session: agent, CoauthorEmail: "bot@example.com"})
	got := joined(plan)
	for _, want := range []string{"Assisted-by=", "Generated-by=", "Co-authored-by=", "Session-Id=", "Harness=", "Model="} {
		if !strings.Contains(got, want) {
			t.Fatalf("full profile misses %s:\n%s", want, got)
		}
	}
}

func TestGeneratedFlag(t *testing.T) {
	plan := build(t, Options{Profiles: []Profile{Nixpkgs}, Session: agent, Generated: true})
	got := joined(plan)
	if !strings.Contains(got, "Generated-by=opencode:model") || !strings.Contains(got, "Assisted-by=opencode:model") {
		t.Fatalf("Build() = %s", got)
	}
}

func TestModelUnknown(t *testing.T) {
	plan := build(t, Options{Session: session.Session{Harness: "opencode", ID: "ses_1"}})
	got := joined(plan)
	if !strings.Contains(got, "Assisted-by=opencode") || strings.Contains(got, "Model=") {
		t.Fatalf("Build() = %s", got)
	}
	if len(plan.Warnings) == 0 {
		t.Fatal("a missing model must warn")
	}
}

func TestHarnessUnknown(t *testing.T) {
	plan := build(t, Options{Session: session.Session{ID: "ses_1"}})
	got := joined(plan)
	if strings.Contains(got, "Assisted-by") || strings.Contains(got, "Generated-by") {
		t.Fatalf("Build() wrote a disclosure without a harness: %s", got)
	}
	if !strings.Contains(got, "Session-Id=ses_1") {
		t.Fatalf("Build() dropped the session key: %s", got)
	}
	if len(plan.Warnings) == 0 {
		t.Fatal("a missing harness must warn")
	}
}

func TestNothingToAttribute(t *testing.T) {
	if _, err := Build(Options{Session: session.Session{}}); err == nil {
		t.Fatal("Build() accepted an empty plan")
	}
}

func TestExtraTrailers(t *testing.T) {
	plan := build(t, Options{Session: agent, Extra: []trailer.Trailer{{Key: "Reviewed-by", Value: "Human"}}})
	if !strings.Contains(joined(plan), "Reviewed-by=Human") {
		t.Fatalf("Build() = %s", joined(plan))
	}
}

func TestParseProfiles(t *testing.T) {
	got, err := ParseProfiles(nil)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(Names(got), ",") != "agent,nixpkgs,asf" {
		t.Fatalf("default = %v", Names(got))
	}
	got, err = ParseProfiles([]string{"github, nixpkgs", "github"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(Names(got), ",") != "nixpkgs,github" {
		t.Fatalf("comma list = %v", Names(got))
	}
	got, err = ParseProfiles([]string{"full"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(Names(got), ",") != "agent,nixpkgs,asf,github" {
		t.Fatalf("full = %v", Names(got))
	}
	if _, err := ParseProfiles([]string{"nope"}); err == nil {
		t.Fatal("ParseProfiles accepted an unknown name")
	}
	if _, err := ParseProfiles([]string{"portable"}); err == nil {
		t.Fatal("ParseProfiles accepted the removed portable profile")
	}
}
