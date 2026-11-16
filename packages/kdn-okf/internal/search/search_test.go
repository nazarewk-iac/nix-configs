package search

import (
	"testing"

	"kdn-okf/internal/okf"
)

func fixture() *okf.Bundle {
	body := []byte("# Alpha\n\nintro line\n\n## Details\n\nthe needle is here\n")
	return &okf.Bundle{Concepts: []*okf.Concept{
		{
			ID:     "alpha",
			Title:  "Alpha",
			Type:   "Note",
			Status: "stable",
			Tags:   []string{"one"},
			Body:   body,
			Headings: []okf.Heading{
				{Level: 1, Text: "Alpha", StartLine: 1, EndLine: 7, Children: []okf.Heading{
					{Level: 2, Text: "Details", StartLine: 5, EndLine: 7},
				}},
			},
		},
		{
			ID:     "beta",
			Title:  "Beta",
			Type:   "Note",
			Status: "draft",
			Body:   []byte("# Beta\n\nnothing here\n"),
			Headings: []okf.Heading{
				{Level: 1, Text: "Beta", StartLine: 1, EndLine: 3},
			},
		},
	}}
}

func TestSearchScopes(t *testing.T) {
	bundle := fixture()
	hits, err := Search(bundle, Query{Text: "needle", Limit: 5})
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 1 || hits[0].ConceptID != "alpha" || hits[0].Heading != "Details" {
		t.Fatalf("hits = %#v", hits)
	}
	if hits[0].StartLine != 5 || hits[0].EndLine != 7 {
		t.Errorf("hit range = %d-%d", hits[0].StartLine, hits[0].EndLine)
	}
	titleHits, err := Search(bundle, Query{Text: "alpha", Scope: "title"})
	if err != nil {
		t.Fatal(err)
	}
	if len(titleHits) != 1 || titleHits[0].ConceptID != "alpha" {
		t.Fatalf("title hits = %#v", titleHits)
	}
}

func TestSearchFiltersAndRegex(t *testing.T) {
	bundle := fixture()
	hits, err := Search(bundle, Query{Text: "needle", Status: "draft"})
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 0 {
		t.Errorf("status filter leaked hits: %#v", hits)
	}
	hits, err = Search(bundle, Query{Text: "needl.", Regex: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 1 {
		t.Errorf("regex hits = %d", len(hits))
	}
	if _, err := Search(bundle, Query{Text: "[", Regex: true}); err == nil {
		t.Error("invalid regex accepted")
	}
}
