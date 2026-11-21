package apply

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"kdn-knowledge/internal/dream"
	"kdn-knowledge/internal/store"
)

// makeBundle creates a bundle with a stable existing concept and returns its root.
func makeBundle(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	write := func(name, content string) {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("mkdir: %v", err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
	write("index.md", "# Knowledge\n")
	write("log.md", "# Log\n")
	write("decisions/index.md", "# Decisions\n")
	write("decisions/no-push.md", "---\ntype: Decision\ntitle: Never push\ndescription: The user reviews every change.\ngenerated: { by: agent/cli, at: \"2026-11-01T00:00:00Z\" }\nstatus: stable\n---\n\n# Never push\n\nThe user reviews every change.\n")
	write("decisions/old-draft.md", "---\ntype: Decision\ntitle: Old draft\ndescription: An older draft decision.\ngenerated: { by: agent/cli, at: \"2026-11-01T00:00:00Z\" }\nstatus: draft\n---\n\n# Old draft\n\nAn older draft decision.\n")
	return root
}

func makeProposal(t *testing.T, plan *dream.Plan) string {
	t.Helper()
	dir := t.TempDir()
	write := func(name, content string) {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("mkdir: %v", err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
	for _, action := range plan.Actions {
		write(action.Concept, "---\ntype: "+typeOf(action.Kind)+"\ntitle: "+action.Title+
			"\ndescription: "+action.Statement+"\nstatus: draft\nid: "+action.ID+
			"\ntags: ["+strings.Join(action.Tags, ", ")+"]\nlinks: []\n---\n\n# "+action.Title+
			"\n\n"+action.Statement+"\n\n## Evidence\n\n- `ses_x` on 2026-11-21\n")
	}
	if err := store.WriteJSON(filepath.Join(dir, "plan.json"), plan); err != nil {
		t.Fatalf("write plan: %v", err)
	}
	return dir
}

func typeOf(kind string) string {
	switch kind {
	case "decision":
		return "Decision"
	case "runbook":
		return "Runbook"
	default:
		return "Fact"
	}
}

func testPlan() *dream.Plan {
	return &dream.Plan{
		Actions: []dream.Action{
			{
				Action: "new", Kind: "fact", ID: "sqlite-cli", Title: "SQLite through the CLI",
				Statement: "The Go standard library has no SQLite driver.", Tags: []string{"sqlite"},
				Concept: "concepts/sqlite-cli.md", Target: "facts/sqlite-cli.md",
				Evidence: []dream.Evidence{{Session: "ses_x", Date: "2026-11-21"}},
			},
			{
				Action: "update", Kind: "decision", ID: "old-draft", Title: "Old draft",
				Statement: "An older draft decision, now refined.", Tags: []string{"jj"},
				Concept: "concepts/old-draft.md", Target: "decisions/old-draft.md", Existing: "old-draft",
			},
			{
				Action: "conflict", Kind: "decision", ID: "push-always", Title: "Push always",
				Statement: "Push every change.", Concept: "concepts/push-always.md", Existing: "no-push",
			},
		},
		Skills: []dream.SkillDraft{{ID: "rebuild", Title: "Rebuild the host"}},
	}
}

// TestRunFilesFallback checks the path used when the bundle writer is absent.
func TestRunFilesFallback(t *testing.T) {
	t.Setenv("PATH", t.TempDir())

	root := makeBundle(t)
	plan := testPlan()
	proposalDir := makeProposal(t, plan)
	result, err := Run(root, proposalDir, plan)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if result.Writer != "files" {
		t.Fatalf("writer = %q, want files", result.Writer)
	}
	if !strings.Contains(result.Warning, "log.md") || !strings.Contains(result.Warning, "index.md") {
		t.Fatalf("warning = %q, want it to name the missing bookkeeping", result.Warning)
	}
	if len(result.Written) != 2 {
		t.Fatalf("written = %v, want the new and the update", result.Written)
	}
	body, err := os.ReadFile(filepath.Join(root, "facts/sqlite-cli.md"))
	if err != nil {
		t.Fatalf("read new concept: %v", err)
	}
	if !strings.Contains(string(body), "status: draft") {
		t.Fatalf("new concept = %s", body)
	}
	var skipped []string
	for _, skip := range result.Skipped {
		skipped = append(skipped, skip.ID)
	}
	if strings.Join(skipped, ",") != "push-always,rebuild" {
		t.Fatalf("skipped = %v, want the conflict and the skill", skipped)
	}
	if !strings.Contains(result.Validation, "no validator") {
		t.Fatalf("validation = %q, want the no-validator note", result.Validation)
	}
}

func TestRunRefusesStable(t *testing.T) {
	t.Setenv("PATH", t.TempDir())

	root := makeBundle(t)
	plan := testPlan()
	plan.Actions[1].ID = "no-push"
	plan.Actions[1].Target = "decisions/no-push.md"
	plan.Actions[1].Existing = "no-push"
	plan.Actions[1].Concept = "concepts/no-push.md"
	proposalDir := makeProposal(t, plan)
	result, err := Run(root, proposalDir, plan)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	for _, skip := range result.Skipped {
		if skip.ID == "no-push" {
			if !strings.Contains(skip.Reason, "stable") {
				t.Fatalf("skip reason = %q", skip.Reason)
			}
			return
		}
	}
	t.Fatalf("a stable concept was not skipped: %+v", result)
}

func TestRunWithOkfMemory(t *testing.T) {
	if _, err := exec.LookPath("okf-memory"); err != nil {
		t.Skip("okf-memory is not on PATH")
	}
	root := makeBundle(t)
	// okf-memory needs the manifest to exist when okflint validates afterwards.
	manifest := filepath.Join(root, "okf-base.yaml")
	if err := os.WriteFile(manifest, []byte(`okf_version: "0.2"
base:
  name: "test"
  roots:
    - path: "."
  reserved_files:
    index: "index.md"
    log: "log.md"
  link_resolution:
    scope: base
    external_refs: []
profile:
  types:
    Decision:
      required: [type, title, description, status, generated]
      status_values: [draft, stable, deprecated]
    Fact:
      required: [type, title, description, status, generated]
      status_values: [draft, stable, deprecated]
`), 0o644); err != nil {
		t.Fatalf("write manifest: %v", err)
	}
	plan := testPlan()
	proposalDir := makeProposal(t, plan)
	result, err := Run(root, proposalDir, plan)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if result.Writer != "okf-memory" {
		t.Fatalf("writer = %q", result.Writer)
	}
	if result.Warning != "" {
		t.Fatalf("warning = %q, want none", result.Warning)
	}
	logBody, err := os.ReadFile(filepath.Join(root, "log.md"))
	if err != nil {
		t.Fatalf("read log: %v", err)
	}
	if !strings.Contains(string(logBody), "Creation") {
		t.Fatalf("the bundle writer did not update log.md: %s", logBody)
	}
	if !strings.Contains(result.Validation, "OKF-conformant") {
		t.Fatalf("validation = %q", result.Validation)
	}
}
