package bundle

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseFrontmatter(t *testing.T) {
	t.Parallel()

	document := `---
type: Decision
title: One writer per bundle
description: okf-agent-memory writes .agents/knowledge; kdn-okf only reads it.
generated: { by: agent/cli, at: "2026-11-16T14:12:45Z" }
status: stable
id: one-writer-per-bundle
links:
  - rel: relates-to
    to: cache-outside-bundle
---

# One writer per bundle

` + "`create`/`update` maintain `index.md` and `log.md`.\n\n## Related Concepts\n"

	fields, body := ParseFrontmatter(document)
	if fields["type"] != "Decision" {
		t.Fatalf("type = %q", fields["type"])
	}
	if fields["title"] != "One writer per bundle" {
		t.Fatalf("title = %q", fields["title"])
	}
	if fields["id"] != "one-writer-per-bundle" {
		t.Fatalf("id = %q", fields["id"])
	}
	if fields["status"] != "stable" {
		t.Fatalf("status = %q", fields["status"])
	}
	if _, ok := fields["generated"]; ok {
		t.Fatalf("an inline map was parsed as a scalar: %v", fields)
	}
	if _, ok := fields["rel"]; ok {
		t.Fatalf("a nested key was parsed as a scalar: %v", fields)
	}
	if FirstParagraph(body) != "`create`/`update` maintain `index.md` and `log.md`." {
		t.Fatalf("first paragraph = %q", FirstParagraph(body))
	}
}

func TestParseFrontmatterWithoutBlock(t *testing.T) {
	t.Parallel()

	fields, body := ParseFrontmatter("# Title\n\nText.")
	if len(fields) != 0 {
		t.Fatalf("fields = %v, want none", fields)
	}
	if body != "# Title\n\nText." {
		t.Fatalf("body = %q", body)
	}
}

func TestLoadSkipsReservedFiles(t *testing.T) {
	t.Parallel()

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
	write("decisions/no-push.md", "---\ntype: Decision\ntitle: Never push\ndescription: The user reviews every change.\nid: no-push\nstatus: stable\n---\n\n# Never push\n\nThe user reviews every change.\n")
	write("facts/sqlite-cli.md", "---\ntype: Fact\ntitle: SQLite through the CLI\n---\n\n# SQLite through the CLI\n\nThe standard library has no driver.\n")

	concepts, err := Load(root)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(concepts) != 2 {
		t.Fatalf("concepts = %d, want 2: %+v", len(concepts), concepts)
	}
	if concepts[0].RelPath != "decisions/no-push.md" {
		t.Fatalf("first concept = %+v", concepts[0])
	}
	if concepts[0].Kind != "decision" || concepts[0].Statement != "The user reviews every change." {
		t.Fatalf("first concept = %+v", concepts[0])
	}
	if concepts[1].ID != "sqlite-cli" {
		t.Fatalf("the id did not fall back to the file name: %+v", concepts[1])
	}
	if concepts[1].Kind != "fact" {
		t.Fatalf("kind = %q", concepts[1].Kind)
	}
	if concepts[0].Label() != "Never push The user reviews every change." {
		t.Fatalf("label = %q", concepts[0].Label())
	}
}

func TestLoadMissingBundle(t *testing.T) {
	t.Parallel()

	concepts, err := Load(filepath.Join(t.TempDir(), "absent"))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(concepts) != 0 {
		t.Fatalf("concepts = %v, want none", concepts)
	}
}
