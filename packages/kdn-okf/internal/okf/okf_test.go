package okf

import (
	"testing"
	"time"
)

func TestParseConcept(t *testing.T) {
	data := []byte(`---
type: Note
title: Alpha
description: First concept
tags: [one, two]
status: draft
verified:
  - by: human:alice
    at: 2026-11-01
stale_after: 2026-11-01
generated:
  by: agent
  at: 2026-11-01
---
# Alpha

## Section

[beta](beta.md) and ![image](ignored.png)
`)
	now := time.Date(2026, 11, 16, 0, 0, 0, 0, time.UTC)
	concept := ParseConcept("/bundle", "/bundle/alpha.md", data, now, now)
	if concept.ID != "alpha" || concept.Type != "Note" || concept.Title != "Alpha" {
		t.Fatalf("concept = %#v", concept)
	}
	if concept.Status != "draft" || concept.Trust != TrustHuman || !concept.Stale {
		t.Fatalf("status/trust/stale = %s/%s/%v", concept.Status, concept.Trust, concept.Stale)
	}
	if len(concept.Tags) != 2 || concept.Tags[0] != "one" {
		t.Fatalf("tags = %#v", concept.Tags)
	}
	if len(concept.Links) != 1 || concept.Links[0].Target != "beta.md" {
		t.Fatalf("links = %#v", concept.Links)
	}
	if len(concept.Headings) != 1 || concept.Headings[0].Text != "Alpha" || len(concept.Headings[0].Children) != 1 || concept.Headings[0].Children[0].Text != "Section" {
		t.Fatalf("headings = %#v", concept.Headings)
	}
}

func TestStatusDefaultsAndValidation(t *testing.T) {
	now := time.Now()
	stable := ParseConcept("/b", "/b/a.md", []byte("---\ntype: Note\n---\n"), now, now)
	if stable.Status != "stable" {
		t.Errorf("default status = %q", stable.Status)
	}
	invalid := ParseConcept("/b", "/b/a.md", []byte("---\ntype: Note\nstatus: ancient\n---\n"), now, now)
	if invalid.Status != "stable" {
		t.Errorf("invalid status = %q", invalid.Status)
	}
	found := false
	for _, issue := range invalid.Issues {
		if issue.Code == "status-invalid" {
			found = true
		}
	}
	if !found {
		t.Errorf("status-invalid issue missing: %#v", invalid.Issues)
	}
}

func TestLegacyTimestampAndTrust(t *testing.T) {
	now := time.Now()
	concept := ParseConcept("/b", "/b/a.md", []byte("---\ntype: Note\ntimestamp: 2026-11-01\n---\n"), now, now)
	if concept.Generated == nil || concept.Generated.At == "" {
		t.Fatalf("legacy timestamp not adopted: %#v", concept.Generated)
	}
	if concept.Trust != TrustUnverified {
		t.Errorf("trust = %s", concept.Trust)
	}
	machine := ParseConcept("/b", "/b/a.md", []byte("---\ntype: Note\nverified: [{by: tool}]\n---\n"), now, now)
	if machine.Trust != TrustMachine {
		t.Errorf("machine trust = %s", machine.Trust)
	}
}

func TestAttestedComputationShape(t *testing.T) {
	now := time.Now()
	data := []byte("---\ntype: Attested Computation\nruntime: python\nexecutor: {resource: /x}\nattester: {resource: /y}\n---\n")
	concept := ParseConcept("/b", "/b/a.md", data, now, now)
	for _, issue := range concept.Issues {
		if issue.Code == "computation-shape" {
			t.Fatalf("complete computation reported an issue: %#v", issue)
		}
	}
	partial := ParseConcept("/b", "/b/a.md", []byte("---\ntype: Attested Computation\n---\n"), now, now)
	found := false
	for _, issue := range partial.Issues {
		if issue.Code == "computation-shape" {
			found = true
		}
	}
	if !found {
		t.Fatalf("partial computation has no computation-shape issue: %#v", partial.Issues)
	}
}

func TestScanFenceAndImages(t *testing.T) {
	scan := ScanMarkdown([]byte("# Heading\n\n```go\n# not a heading\n[not](a-link)\n```\n\n[real](target.md)\n![image](x.png)\n"))
	if len(scan.Headings) != 1 || scan.Headings[0].Text != "Heading" {
		t.Fatalf("headings = %#v", scan.Headings)
	}
	if len(scan.Links) != 1 || scan.Links[0].Target != "target.md" {
		t.Fatalf("links = %#v", scan.Links)
	}
	if len(scan.Code) != 1 || scan.Code[0].Language != "go" {
		t.Fatalf("code = %#v", scan.Code)
	}
}

func TestSectionAndContext(t *testing.T) {
	now := time.Now()
	body := "---\ntype: Note\n---\n# Title\n\nintro\n\n## One\n\nfirst\n\n## Two\n\nsecond\n"
	concept := ParseConcept("/b", "/b/a.md", []byte(body), now, now)
	section, ok := Section(concept, "One", 0)
	if !ok || section.Heading != "One" {
		t.Fatalf("section = %#v, %v", section, ok)
	}
	if section.StartLine != 5 || section.EndLine != 8 {
		t.Fatalf("section range = %d-%d", section.StartLine, section.EndLine)
	}
	if _, ok := Section(concept, "Missing", 0); ok {
		t.Error("Section matched a missing heading")
	}
	ctx := ContextOf(concept, 3)
	if !ctx.Truncated || len(FlattenHeadings(ctx.Headings)) != 3 {
		t.Fatalf("context = %#v", ctx)
	}
}
