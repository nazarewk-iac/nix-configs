package okf

import (
	"fmt"
	"regexp"
	"strings"
)

// Heading is one Markdown heading with its 1-based inclusive source range.
type Heading struct {
	Level     int       `json:"level"`
	Text      string    `json:"text"`
	StartLine int       `json:"start_line"`
	EndLine   int       `json:"end_line"`
	Children  []Heading `json:"children,omitempty"`
}

// Link is one link found in a concept body.
type Link struct {
	Source   string `json:"source"`
	Target   string `json:"target"`
	Resolved string `json:"resolved,omitempty"`
	Kind     string `json:"kind"`
	Missing  bool   `json:"missing,omitempty"`
	Line     int    `json:"line"`
}

// LinkKind values. The JSON vocabulary is kebab-case and stable.
const (
	LinkBundleAbsolute = "bundle-absolute"
	LinkRelative       = "relative"
	LinkExternal       = "external"
	LinkFragment       = "fragment"
)

// CodeBlock is one fenced code block.
type CodeBlock struct {
	Language  string `json:"language,omitempty"`
	StartLine int    `json:"start_line"`
	EndLine   int    `json:"end_line"`
}

// Table is one Markdown table.
type Table struct {
	StartLine int `json:"start_line"`
	EndLine   int `json:"end_line"`
}

// Scan is the Markdown structure of one body.
type Scan struct {
	Headings []Heading   `json:"headings"`
	Links    []Link      `json:"links"`
	Code     []CodeBlock `json:"code_blocks"`
	Tables   []Table     `json:"tables"`
}

var (
	headingRE    = regexp.MustCompile(`^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$`)
	inlineLinkRE = regexp.MustCompile(`!?\[([^\]]*)\]\(([^)]+)\)`)
	refDefRE     = regexp.MustCompile(`^\[([^\]]+)\]:[ \t]*(\S+)`)
	refUseRE     = regexp.MustCompile(`\[([^\]]*)\]\[([^\]]*)\]`)
	inlineCodeRE = regexp.MustCompile("`[^`]*`")
	tableSepRE   = regexp.MustCompile(`^\|?[ \t:-]+\|`)
)

type rawHeading struct {
	level int
	text  string
	line  int
}

// ScanMarkdown reads headings, links, fenced code and tables from a body. Headings and links
// inside a fenced block or an inline code span are ignored.
func ScanMarkdown(body []byte) Scan {
	text := strings.ReplaceAll(string(body), "\r\n", "\n")
	lines := strings.Split(text, "\n")
	var scan Scan
	var headings []rawHeading
	refs := map[string]string{}
	fence := ""
	fenceStart := 0
	fenceLang := ""
	inTable := false
	tableStart := 0

	for i, line := range lines {
		number := i + 1
		trimmed := strings.TrimSpace(line)
		if fence != "" {
			if strings.HasPrefix(trimmed, fence) {
				scan.Code = append(scan.Code, CodeBlock{Language: fenceLang, StartLine: fenceStart, EndLine: number})
				fence = ""
			}
			continue
		}
		if strings.HasPrefix(trimmed, "```") || strings.HasPrefix(trimmed, "~~~") {
			fence = trimmed[:3]
			fenceStart = number
			fenceLang = strings.TrimSpace(trimmed[3:])
			continue
		}
		if strings.HasPrefix(trimmed, "|") {
			if !inTable {
				inTable = true
				tableStart = number
			}
		} else if inTable {
			scan.Tables = append(scan.Tables, Table{StartLine: tableStart, EndLine: number - 1})
			inTable = false
		}

		if match := refDefRE.FindStringSubmatch(line); match != nil {
			refs[strings.ToLower(match[1])] = strings.TrimSpace(match[2])
		}
		if match := headingRE.FindStringSubmatch(line); match != nil {
			headings = append(headings, rawHeading{level: len(match[1]), text: strings.TrimSpace(match[2]), line: number})
			continue
		}
		cleaned := inlineCodeRE.ReplaceAllStringFunc(line, func(s string) string { return strings.Repeat(" ", len(s)) })
		for _, match := range inlineLinkRE.FindAllStringSubmatch(cleaned, -1) {
			if strings.HasPrefix(match[0], "!") {
				continue
			}
			scan.Links = append(scan.Links, Link{Target: strings.TrimSpace(match[2]), Line: number})
		}
		for _, match := range refUseRE.FindAllStringSubmatch(cleaned, -1) {
			key := strings.TrimSpace(match[2])
			if key == "" {
				key = strings.TrimSpace(match[1])
			}
			if target, ok := refs[strings.ToLower(key)]; ok {
				scan.Links = append(scan.Links, Link{Target: target, Line: number})
			}
		}
	}
	if inTable {
		scan.Tables = append(scan.Tables, Table{StartLine: tableStart, EndLine: len(lines)})
	}
	if fence != "" {
		scan.Code = append(scan.Code, CodeBlock{Language: fenceLang, StartLine: fenceStart, EndLine: len(lines)})
	}
	scan.Headings = nestHeadings(headings, len(lines))
	return scan
}

func nestHeadings(raw []rawHeading, total int) []Heading {
	flat := make([]Heading, len(raw))
	for i, h := range raw {
		flat[i] = Heading{Level: h.level, Text: h.text, StartLine: h.line}
	}
	for i := range flat {
		end := total
		for j := i + 1; j < len(flat); j++ {
			if flat[j].Level <= flat[i].Level {
				end = flat[j].StartLine - 1
				break
			}
		}
		flat[i].EndLine = end
	}
	type node struct {
		heading  Heading
		children []int
	}
	nodes := make([]node, len(flat))
	for i := range flat {
		nodes[i].heading = flat[i]
	}
	var stack []int
	var roots []int
	for i := range nodes {
		for len(stack) > 0 && nodes[stack[len(stack)-1]].heading.Level >= nodes[i].heading.Level {
			stack = stack[:len(stack)-1]
		}
		if len(stack) == 0 {
			roots = append(roots, i)
		} else {
			parent := stack[len(stack)-1]
			nodes[parent].children = append(nodes[parent].children, i)
		}
		stack = append(stack, i)
	}
	var build func(int) Heading
	build = func(i int) Heading {
		h := nodes[i].heading
		for _, child := range nodes[i].children {
			h.Children = append(h.Children, build(child))
		}
		return h
	}
	out := make([]Heading, 0, len(roots))
	for _, root := range roots {
		out = append(out, build(root))
	}
	return out
}

// FlattenHeadings returns the heading tree in document order.
func FlattenHeadings(headings []Heading) []Heading {
	var out []Heading
	for _, h := range headings {
		out = append(out, h)
		out = append(out, FlattenHeadings(h.Children)...)
	}
	return out
}

// Section returns the Markdown of one heading range. maxLines > 0 truncates the slice.
func Section(concept *Concept, heading string, maxLines int) (SectionResult, bool) {
	flat := FlattenHeadings(concept.Headings)
	match := findHeading(flat, heading)
	if match == nil {
		return SectionResult{}, false
	}
	lines := strings.Split(strings.ReplaceAll(string(concept.Body), "\r\n", "\n"), "\n")
	start := match.StartLine - 1
	end := match.EndLine
	if start < 0 {
		start = 0
	}
	if end > len(lines) {
		end = len(lines)
	}
	slice := lines[start:end]
	truncated := false
	if maxLines > 0 && len(slice) > maxLines {
		slice = slice[:maxLines]
		truncated = true
	}
	return SectionResult{
		ConceptID: concept.ID,
		Heading:   match.Text,
		StartLine: match.StartLine,
		EndLine:   match.EndLine,
		Markdown:  strings.Join(slice, "\n"),
		Truncated: truncated,
	}, true
}

// SectionResult is the payload of `section`.
type SectionResult struct {
	ConceptID string `json:"concept_id"`
	Heading   string `json:"heading"`
	StartLine int    `json:"start_line"`
	EndLine   int    `json:"end_line"`
	Markdown  string `json:"markdown"`
	Truncated bool   `json:"truncated,omitempty"`
}

// findHeading matches an exact heading first, then a unique case-insensitive prefix.
func findHeading(headings []Heading, query string) *Heading {
	query = strings.TrimSpace(strings.TrimPrefix(query, "#"))
	for i := range headings {
		if strings.EqualFold(strings.TrimSpace(headings[i].Text), query) {
			return &headings[i]
		}
	}
	var matches []*Heading
	for i := range headings {
		if strings.HasPrefix(strings.ToLower(strings.TrimSpace(headings[i].Text)), strings.ToLower(query)) {
			matches = append(matches, &headings[i])
		}
	}
	if len(matches) == 1 {
		return matches[0]
	}
	return nil
}

// Outline is the progressive-discovery payload.
type Outline struct {
	Kind      string      `json:"kind"`
	ConceptID string      `json:"concept_id,omitempty"`
	Title     string      `json:"title,omitempty"`
	Headings  []Heading   `json:"headings"`
	Links     []Link      `json:"links,omitempty"`
	Code      []CodeBlock `json:"code_blocks,omitempty"`
	Tables    []Table     `json:"tables,omitempty"`
}

// OutlineOf returns the outline of one concept, capped at depth (0 = unlimited).
func OutlineOf(concept *Concept, depth int) Outline {
	headings := concept.Headings
	if depth > 0 {
		headings = capDepth(headings, 1, depth)
	}
	return Outline{
		Kind:      "concept",
		ConceptID: concept.ID,
		Title:     concept.Title,
		Headings:  headings,
		Links:     concept.Links,
		Code:      concept.ScanCode,
		Tables:    concept.ScanTables,
	}
}

func capDepth(headings []Heading, level, max int) []Heading {
	if level > max {
		return nil
	}
	out := make([]Heading, 0, len(headings))
	for _, h := range headings {
		h.Children = capDepth(h.Children, level+1, max)
		out = append(out, h)
	}
	return out
}

// Context is the budgeted summary payload.
type Context struct {
	ConceptID   string    `json:"concept_id"`
	Title       string    `json:"title"`
	Type        string    `json:"type"`
	Description string    `json:"description,omitempty"`
	Tags        []string  `json:"tags,omitempty"`
	Status      string    `json:"status"`
	Trust       string    `json:"trust"`
	Stale       bool      `json:"stale"`
	Headings    []Heading `json:"headings"`
	Preview     string    `json:"preview"`
	Budget      int       `json:"budget"`
	Truncated   bool      `json:"truncated,omitempty"`
}

// ContextOf builds a line-budgeted summary: header, heading tree and the first paragraph of each
// section, stopping at budget lines.
func ContextOf(concept *Concept, budget int) Context {
	var b strings.Builder
	if concept.Description != "" {
		b.WriteString(concept.Description)
		b.WriteString("\n\n")
	}
	lines := strings.Split(strings.ReplaceAll(string(concept.Body), "\r\n", "\n"), "\n")
	for _, heading := range FlattenHeadings(concept.Headings) {
		fmt.Fprintf(&b, "%s %s\n", strings.Repeat("#", heading.Level), heading.Text)
		body := firstParagraph(lines, heading.StartLine, heading.EndLine)
		if body != "" {
			b.WriteString(body)
			b.WriteString("\n")
		}
	}
	preview := strings.TrimRight(b.String(), "\n")
	truncated := false
	if budget > 0 {
		previewLines := strings.Split(preview, "\n")
		if len(previewLines) > budget {
			preview = strings.Join(previewLines[:budget], "\n")
			truncated = true
		}
	}
	return Context{
		ConceptID:   concept.ID,
		Title:       concept.Title,
		Type:        concept.Type,
		Description: concept.Description,
		Tags:        concept.Tags,
		Status:      concept.Status,
		Trust:       concept.Trust.String(),
		Stale:       concept.Stale,
		Headings:    concept.Headings,
		Preview:     preview,
		Budget:      budget,
		Truncated:   truncated,
	}
}

func firstParagraph(lines []string, startLine, endLine int) string {
	start := startLine // skip the heading line itself
	if start < 0 {
		start = 0
	}
	if endLine > len(lines) {
		endLine = len(lines)
	}
	var out []string
	seen := false
	for i := start; i < endLine; i++ {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			if seen {
				break
			}
			continue
		}
		if strings.HasPrefix(line, "#") || strings.HasPrefix(line, "```") || strings.HasPrefix(line, "|") {
			if seen {
				break
			}
			continue
		}
		seen = true
		out = append(out, line)
	}
	return strings.Join(out, " ")
}

// CapDepth caps a heading tree at depth (1 = top-level headings only).
func CapDepth(headings []Heading, depth int) []Heading {
	if depth <= 0 {
		return headings
	}
	return capDepth(headings, 1, depth)
}
