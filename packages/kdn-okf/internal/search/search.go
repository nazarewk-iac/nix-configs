// Package search implements the v1 in-memory search behind the kdn-okf CLI.
package search

import (
	"fmt"
	"regexp"
	"strings"

	"kdn-okf/internal/okf"
)

// Query is one search request.
type Query struct {
	Text   string
	Regex  bool
	Exact  bool
	Scope  string // title, heading, body, all
	Type   string
	Tag    string
	Status string
	Limit  int
}

// Hit points at a concept and a heading range, never at a whole body.
type Hit struct {
	ConceptID string `json:"concept_id"`
	Path      string `json:"path"`
	RelPath   string `json:"rel_path"`
	Heading   string `json:"heading,omitempty"`
	Level     int    `json:"level,omitempty"`
	StartLine int    `json:"start_line"`
	EndLine   int    `json:"end_line"`
	Snippet   string `json:"snippet,omitempty"`
}

// Search runs q against every concept in the bundle.
func Search(bundle *okf.Bundle, q Query) ([]Hit, error) {
	match, err := matcher(q)
	if err != nil {
		return nil, err
	}
	limit := q.Limit
	if limit <= 0 {
		limit = 20
	}
	var hits []Hit
	for _, concept := range bundle.Concepts {
		if q.Type != "" && !strings.EqualFold(concept.Type, q.Type) {
			continue
		}
		if q.Status != "" && !strings.EqualFold(concept.Status, q.Status) {
			continue
		}
		if q.Tag != "" && !hasTag(concept.Tags, q.Tag) {
			continue
		}
		hits = append(hits, conceptHits(concept, match, q)...)
		if len(hits) >= limit {
			return hits[:limit], nil
		}
	}
	return hits, nil
}

func conceptHits(concept *okf.Concept, match func(string) bool, q Query) []Hit {
	scope := q.Scope
	if scope == "" {
		scope = "all"
	}
	lines := strings.Split(strings.ReplaceAll(string(concept.Body), "\r\n", "\n"), "\n")
	var hits []Hit
	if scope == "all" || scope == "title" {
		text := strings.Join([]string{concept.Title, concept.Description, strings.Join(concept.Tags, " ")}, " ")
		if match(text) {
			hits = append(hits, Hit{
				ConceptID: concept.ID,
				Path:      concept.Path,
				RelPath:   concept.RelPath,
				Heading:   concept.Title,
				StartLine: 1,
				EndLine:   len(lines),
				Snippet:   snippet(concept.Description),
			})
		}
	}
	if scope == "heading" {
		for _, heading := range okf.FlattenHeadings(concept.Headings) {
			if match(heading.Text) {
				hits = append(hits, hitFor(concept, heading, ""))
			}
		}
		return hits
	}
	if scope != "all" && scope != "body" {
		return hits
	}
	// One hit per heading section: a line belongs to its deepest enclosing heading.
	seen := map[int]bool{}
	for i, line := range lines {
		if !match(line) {
			continue
		}
		heading := deepestHeading(concept.Headings, i+1)
		key := heading.StartLine
		if seen[key] {
			continue
		}
		seen[key] = true
		hits = append(hits, hitFor(concept, heading, snippet(line)))
	}
	return hits
}

func hitFor(concept *okf.Concept, heading okf.Heading, text string) Hit {
	return Hit{
		ConceptID: concept.ID,
		Path:      concept.Path,
		RelPath:   concept.RelPath,
		Heading:   heading.Text,
		Level:     heading.Level,
		StartLine: heading.StartLine,
		EndLine:   heading.EndLine,
		Snippet:   text,
	}
}

// deepestHeading returns the most specific heading that contains line.
func deepestHeading(headings []okf.Heading, line int) okf.Heading {
	found := okf.Heading{StartLine: 1, EndLine: line}
	var walk func([]okf.Heading)
	walk = func(list []okf.Heading) {
		for _, heading := range list {
			if heading.StartLine <= line && line <= heading.EndLine {
				found = heading
				walk(heading.Children)
			}
		}
	}
	walk(headings)
	return found
}

func matcher(q Query) (func(string) bool, error) {
	text := q.Text
	if text == "" {
		return nil, fmt.Errorf("empty search query")
	}
	if q.Regex {
		re, err := regexp.Compile("(?i)" + text)
		if err != nil {
			return nil, fmt.Errorf("invalid regex: %w", err)
		}
		return re.MatchString, nil
	}
	if q.Exact {
		return func(s string) bool { return strings.Contains(s, text) }, nil
	}
	lower := strings.ToLower(text)
	return func(s string) bool { return strings.Contains(strings.ToLower(s), lower) }, nil
}

func hasTag(tags []string, want string) bool {
	for _, tag := range tags {
		if strings.EqualFold(tag, want) {
			return true
		}
	}
	return false
}

func snippet(line string) string {
	line = strings.TrimSpace(strings.ReplaceAll(line, "|", " "))
	if len(line) <= 120 {
		return line
	}
	return line[:119] + "…"
}
