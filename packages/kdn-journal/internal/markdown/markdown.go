// Package markdown is a small, fence-aware line scanner. It is the single place that decides
// whether a line is a heading, a bullet, a table row or prose, so the board and worklog parsers
// never disagree about a fenced code block.
package markdown

import (
	"regexp"
	"strings"
)

// Kind is the syntactic class of one line.
type Kind int

const (
	KindBlank Kind = iota
	KindHeading
	KindBullet
	KindTable
	KindFence
	KindProse
)

// Line is one scanned line.
type Line struct {
	Kind     Kind
	Level    int    // heading level (1-6)
	Text     string // heading text, bullet text, or prose
	Raw      string // the original line without the line terminator
	Indent   int    // leading spaces
	Marker   string // "-", "*", "+", "1.", "1)"
	Checkbox int    // -1 none, 0 open, 1 done
	Cells    []string
	Number   int // 1-based line number
}

var (
	headingRE = regexp.MustCompile(`^(#{1,6})[ \t]+(.*)$`)
	bulletRE  = regexp.MustCompile(`^([ \t]*)([-*+]|[0-9]+[.)])[ \t]+(.*)$`)
	fenceRE   = regexp.MustCompile("^[ \t]*(`{3,}|~{3,})(.*)$")
)

// Scan returns every line of data with its syntactic class. Fenced code blocks are recognised
// once, here; a heading-like line inside a fence stays KindFence.
func Scan(data []byte) []Line {
	rawLines := strings.Split(string(data), "\n")
	// A trailing newline produces one empty final element; drop it so line counts match editors.
	if len(rawLines) > 0 && rawLines[len(rawLines)-1] == "" {
		rawLines = rawLines[:len(rawLines)-1]
	}
	lines := make([]Line, 0, len(rawLines))
	var fenceChar byte
	var fenceLen int
	for i, raw := range rawLines {
		raw = strings.TrimSuffix(raw, "\r")
		number := i + 1
		trimmedLeft := strings.TrimLeft(raw, " \t")
		if fenceChar != 0 {
			lines = append(lines, Line{Kind: KindFence, Text: raw, Raw: raw, Number: number})
			if isFenceClose(trimmedLeft, fenceChar, fenceLen) {
				fenceChar = 0
				fenceLen = 0
			}
			continue
		}
		if m := fenceRE.FindStringSubmatch(raw); m != nil {
			fenceChar = m[1][0]
			fenceLen = len(m[1])
			lines = append(lines, Line{Kind: KindFence, Text: raw, Raw: raw, Number: number})
			continue
		}
		if strings.TrimSpace(raw) == "" {
			lines = append(lines, Line{Kind: KindBlank, Text: raw, Raw: raw, Number: number})
			continue
		}
		if m := headingRE.FindStringSubmatch(trimmedLeft); m != nil {
			text := strings.TrimSpace(m[2])
			text = strings.TrimRight(text, "#")
			text = strings.TrimSpace(text)
			lines = append(lines, Line{
				Kind:   KindHeading,
				Level:  len(m[1]),
				Text:   text,
				Indent: len(raw) - len(trimmedLeft),
				Raw:    raw, Number: number,
			})
			continue
		}
		if m := bulletRE.FindStringSubmatch(raw); m != nil {
			indent := len(strings.ReplaceAll(m[1], "\t", "    "))
			text := m[3]
			checkbox := -1
			switch {
			case strings.HasPrefix(text, "[ ] "):
				checkbox = 0
				text = strings.TrimPrefix(text, "[ ] ")
			case strings.HasPrefix(text, "[x] "), strings.HasPrefix(text, "[X] "):
				checkbox = 1
				text = text[4:]
			case text == "[ ]":
				checkbox = 0
				text = ""
			case text == "[x]", text == "[X]":
				checkbox = 1
				text = ""
			}
			lines = append(lines, Line{
				Kind:     KindBullet,
				Text:     text,
				Raw:      raw,
				Indent:   indent,
				Marker:   m[2],
				Checkbox: checkbox,
				Number:   number,
			})
			continue
		}
		if strings.Contains(raw, "|") {
			lines = append(lines, Line{Kind: KindTable, Text: raw, Cells: splitRow(raw), Raw: raw, Number: number})
			continue
		}
		lines = append(lines, Line{Kind: KindProse, Text: raw, Indent: len(raw) - len(trimmedLeft), Raw: raw, Number: number})
	}
	return lines
}

// Headings returns the heading lines in file order.
func Headings(lines []Line) []Line {
	out := make([]Line, 0)
	for _, line := range lines {
		if line.Kind == KindHeading {
			out = append(out, line)
		}
	}
	return out
}

// Tables returns groups of consecutive table lines, excluding the separator row. A group is a
// table only when it contains a separator row with a header before it; a prose line that happens to
// contain a pipe before the header is returned with the table as prose by the caller.
func Tables(lines []Line) [][]Line {
	var out [][]Line
	for i := 0; i < len(lines); {
		if lines[i].Kind != KindTable {
			i++
			continue
		}
		start := i
		for i < len(lines) && lines[i].Kind == KindTable {
			i++
		}
		group := lines[start:i]
		sep := -1
		for j, line := range group {
			if isSeparator(line.Cells) {
				sep = j
				break
			}
		}
		if sep < 1 {
			continue
		}
		table := make([]Line, 0, len(group)-1)
		table = append(table, group[sep-1])
		table = append(table, group[sep+1:]...)
		out = append(out, table)
	}
	return out
}

func isFenceClose(line string, char byte, length int) bool {
	if len(line) < length {
		return false
	}
	for i := 0; i < length; i++ {
		if line[i] != char {
			return false
		}
	}
	return true
}

func isSeparator(cells []string) bool {
	if len(cells) == 0 {
		return false
	}
	for _, cell := range cells {
		cell = strings.TrimSpace(cell)
		cell = strings.Trim(cell, ":")
		if len(cell) < 1 || strings.Trim(cell, "-") != "" {
			return false
		}
	}
	return true
}

func splitRow(line string) []string {
	line = strings.TrimSpace(line)
	line = strings.TrimPrefix(line, "|")
	line = strings.TrimSuffix(line, "|")
	parts := strings.Split(line, "|")
	cells := make([]string, len(parts))
	for i, part := range parts {
		cells[i] = strings.TrimSpace(part)
	}
	return cells
}
