package proposal

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"kdn-knowledge/internal/dream"
	"kdn-knowledge/internal/extract"
	"kdn-knowledge/internal/store"
)

var fixedNow = time.Date(2026, 11, 22, 0, 5, 0, 0, time.UTC)

func testPlan(t *testing.T) *dream.Plan {
	t.Helper()
	return buildPlan(t, 60)
}

func buildPlan(t *testing.T, maxConcepts int) *dream.Plan {
	t.Helper()
	items := []extract.Item{
		{Session: "ses_1", Kind: "decision", Statement: "Never push; the user reviews every change.", Tags: []string{"jj"}, Confidence: "high", Evidence: []string{"2026-11-21T10:00:00Z"}},
		{Session: "ses_2", Kind: "runbook", Statement: "Rebuild the host with nixos-rebuild switch.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T11:00:00Z"}},
		{Session: "ses_3", Kind: "runbook", Statement: "Rebuild the host with nixos-rebuild switch.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T12:00:00Z"}},
		{Session: "ses_4", Kind: "runbook", Statement: "Rebuild the host with nixos-rebuild switch.", Tags: []string{"nix"}, Confidence: "medium", Evidence: []string{"2026-11-21T13:00:00Z"}},
	}
	commands := map[string][]string{
		"ses_2": {"nix build .#host"},
		"ses_3": {"nix build .#host", "nixos-rebuild switch --flake .#host"},
		"ses_4": {"git status", "systemctl status"},
	}
	plan, err := dream.Build(t.Context(), dream.Input{Items: items, Commands: commands, Failures: []dream.Failure{
		{ID: "ses_bad", Reason: "the model endpoint answered 500", Attempts: 2},
	}}, dream.Options{Now: func() time.Time { return fixedNow }, Model: "qfn", MinSessions: 3, MaxConcepts: maxConcepts})
	if err != nil {
		t.Fatalf("dream.Build: %v", err)
	}
	return plan
}

func TestWriteProposal(t *testing.T) {
	t.Parallel()

	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	plan := testPlan(t)
	written, err := Write(st, plan, fixedNow)
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if !strings.HasSuffix(written.Dir, "20261122T000500Z") {
		t.Fatalf("proposal dir = %s", written.Dir)
	}
	if len(plan.Actions) != 2 {
		t.Fatalf("actions = %d, want 2", len(plan.Actions))
	}
	if len(written.Concepts) != 2 || len(written.Skills) != 1 {
		t.Fatalf("written = %+v", written)
	}

	concept, err := os.ReadFile(filepath.Join(written.Dir, written.Concepts[0]))
	if err != nil {
		t.Fatalf("read concept: %v", err)
	}
	text := string(concept)
	for _, want := range []string{
		"type: ", "title: ", "description: ", "generated: { by: agent/kdn-knowledge, at: \"2026-11-22T00:05:00Z\" }",
		"status: draft", "id: ", "links: []", "## Evidence", "ses_",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("concept draft does not contain %q:\n%s", want, text)
		}
	}

	skill, err := os.ReadFile(filepath.Join(written.Dir, written.Skills[0]))
	if err != nil {
		t.Fatalf("read skill: %v", err)
	}
	skillText := string(skill)
	for _, want := range []string{
		"type: Skill", "status: draft", "id: ", "## When to use", "## Steps", "## Evidence",
		"nix build .#host", "nixos-rebuild switch --flake .#host",
	} {
		if !strings.Contains(skillText, want) {
			t.Fatalf("skill draft does not contain %q:\n%s", want, skillText)
		}
	}

	var planFile dream.Plan
	if err := store.ReadJSON(written.PlanPath, &planFile); err != nil {
		t.Fatalf("read plan.json: %v", err)
	}
	if planFile.Model != "qfn" || len(planFile.Actions) != 2 {
		t.Fatalf("plan.json = %+v", planFile)
	}
	if len(planFile.Skills) != 1 {
		t.Fatalf("plan.json skills = %d", len(planFile.Skills))
	}

	report, err := os.ReadFile(written.ReportPath)
	if err != nil {
		t.Fatalf("read report: %v", err)
	}
	reportText := string(report)
	for _, want := range []string{
		"## What the run read",
		"- sessions with candidates: 4",
		"- items extracted: 4",
		"## Actions",
		"## Top ten clusters by evidence count",
		"## Failed sessions",
		"`ses_bad` — the model endpoint answered 500 (2 attempts)",
		"## What to review first",
	} {
		if !strings.Contains(reportText, want) {
			t.Fatalf("report does not contain %q:\n%s", want, reportText)
		}
	}
	if strings.Contains(reportText, "Nothing: the proposal is empty") {
		t.Fatalf("a non-empty proposal has no review order:\n%s", reportText)
	}
}

func TestRenderConceptIsValidFrontmatter(t *testing.T) {
	t.Parallel()

	action := dream.Action{
		Action:    "new",
		Kind:      "pitfall",
		ID:        "avoid-global-nix-fmt",
		Title:     "Avoid global nix fmt",
		Statement: "Run nix fmt only on the files the session touched.",
		Tags:      []string{"nix", "fmt"},
		Evidence: []dream.Evidence{
			{Session: "ses_a", Date: "2026-11-21T10:00:00Z"},
		},
		Confidence: "high",
	}
	body := string(RenderConcept(action, fixedNow))
	if !strings.HasPrefix(body, "---\n") {
		t.Fatalf("concept does not start with frontmatter: %s", body)
	}
	if !strings.Contains(body, "type: Pitfall") {
		t.Fatalf("type is not capitalised: %s", body)
	}
	if !strings.Contains(body, "tags: [nix, fmt]") {
		t.Fatalf("tags are missing: %s", body)
	}
	if strings.Count(body, "---") != 2 {
		t.Fatalf("frontmatter is not closed exactly once: %s", body)
	}
}

func TestWriteIsIdempotentPerTimestamp(t *testing.T) {
	t.Parallel()

	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	plan := testPlan(t)
	first, err := Write(st, plan, fixedNow)
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	second, err := Write(st, plan, fixedNow)
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if first.Dir == second.Dir {
		t.Fatalf("two writes in the same second reused %s", first.Dir)
	}
	if !strings.HasSuffix(second.Dir, "-2") {
		t.Fatalf("second dir = %s, want a -2 suffix", second.Dir)
	}
}

func TestReportListsTheOverCapClusters(t *testing.T) {
	t.Parallel()

	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	// Four clusters, one proposed: the runbook cluster of three sessions ranks first.
	plan := buildPlan(t, 1)
	if plan.Proposed != 1 || len(plan.NotProposed) != 1 {
		t.Fatalf("proposed %d, over cap %d, want 1 and 1", plan.Proposed, len(plan.NotProposed))
	}
	written, err := Write(st, plan, fixedNow)
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	report, err := os.ReadFile(written.ReportPath)
	if err != nil {
		t.Fatalf("read report: %v", err)
	}
	text := string(report)
	if !strings.Contains(text, "## Not proposed (over the cap)") {
		t.Fatalf("the report has no over-cap section:\n%s", text)
	}
	if !strings.Contains(text, plan.NotProposed[0].Statement) {
		t.Fatalf("the over-cap statement is missing from the report:\n%s", text)
	}
	if !strings.Contains(text, "- proposed: 1 of 2 clusters (over the cap: 1)") {
		t.Fatalf("the report does not state the cap:\n%s", text)
	}
}
