// Package trailer parses and augments the trailer block of a jj commit description.
//
// The parser never rewrites existing text. It locates the trailing trailer paragraph, records
// every `Key: value` line, and renders the description back unchanged apart from the lines the
// caller asks to append.
package trailer

import (
	"regexp"
	"strings"
)

// Trailer is one `Key: value` line.
type Trailer struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// String renders the trailer in the canonical `Key: value` form.
func (t Trailer) String() string { return t.Key + ": " + t.Value }

// singleValued holds the keys that describe one fact about one change. A second, different value
// is never appended: the first one wins and the caller reports it as skipped.
var singleValued = map[string]bool{
	"session-id": true,
	"harness":    true,
	"model":      true,
}

// SingleValued reports whether key accepts one value only. The comparison ignores case.
func SingleValued(key string) bool {
	return singleValued[strings.ToLower(strings.TrimSpace(key))]
}

// trailerLine matches one trailer. The value must be non-empty, and the key must not start with a
// digit-only local part such as a bare timestamp, so a prose paragraph is not misread.
var trailerLine = regexp.MustCompile(`^([A-Za-z][A-Za-z0-9-]*):[ \t]+(\S.*)$`)

// Document is a parsed commit description.
type Document struct {
	// Raw is the description the caller passed to Parse.
	Raw string
	// Lines holds the description split into lines, without terminators and without CRLF.
	Lines []string
	// TrailerStart is the index of the first line of the trailer paragraph, or -1 when the
	// description has no trailer paragraph.
	TrailerStart int
	// TrailerEnd is the index just past the last line of the trailer paragraph, or -1 when the
	// description has no trailer paragraph. Trailing blank lines sit after it.
	TrailerEnd int
	// Trailers holds the parsed trailer lines in their original order.
	Trailers []Trailer
	// CRLF records whether the description used CRLF line endings.
	CRLF bool
	// TrailingEOL records whether the description ended with a newline.
	TrailingEOL bool
}

// Parse splits a description into a body and a trailer block.
//
// A trailer block is the last paragraph when every line of it is a `Key: value` trailer or a
// folded continuation of one. A paragraph that holds prose, a fenced code block or a list is not
// a trailer block, so the tool appends a new block instead of touching it.
func Parse(description string) Document {
	d := Document{Raw: description, TrailerStart: -1, TrailerEnd: -1}
	text := description
	if strings.Contains(text, "\r\n") {
		d.CRLF = true
		text = strings.ReplaceAll(text, "\r\n", "\n")
	}
	d.TrailingEOL = strings.HasSuffix(text, "\n")
	text = strings.TrimSuffix(text, "\n")
	if text == "" {
		return d
	}
	d.Lines = strings.Split(text, "\n")
	// Trailing blank lines are not part of the last paragraph; keep them out of the block so a
	// description that ends with one still gets its trailers detected.
	end := len(d.Lines)
	for end > 0 && strings.TrimSpace(d.Lines[end-1]) == "" {
		end--
	}
	if end == 0 {
		d.Lines = nil
		return d
	}
	start := 0
	for i := end - 1; i >= 0; i-- {
		if strings.TrimSpace(d.Lines[i]) == "" {
			start = i + 1
			break
		}
	}
	block := d.Lines[start:end]
	if len(block) == 0 {
		return d
	}
	trailers := make([]Trailer, 0, len(block))
	for _, line := range block {
		if match := trailerLine.FindStringSubmatch(line); match != nil {
			trailers = append(trailers, Trailer{Key: match[1], Value: match[2]})
			continue
		}
		// A folded value continues the previous trailer. Git allows it; keep it attached so a
		// duplicate is still detected, and never rewrite the folded lines.
		if (strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t")) && len(trailers) > 0 {
			last := &trailers[len(trailers)-1]
			last.Value += " " + strings.TrimSpace(line)
			continue
		}
		return d
	}
	d.TrailerStart = start
	d.TrailerEnd = end
	d.Trailers = trailers
	return d
}

// Body returns the description without the trailer paragraph.
func (d Document) Body() string {
	end := len(d.Lines)
	if d.TrailerStart >= 0 {
		end = d.TrailerStart
	}
	return strings.TrimRight(strings.Join(d.Lines[:end], "\n"), "\n")
}

// Values returns every value recorded for key. The key comparison ignores case.
func (d Document) Values(key string) []string {
	var out []string
	for _, t := range d.Trailers {
		if strings.EqualFold(t.Key, key) {
			out = append(out, t.Value)
		}
	}
	return out
}

// Has reports whether key appears at least once.
func (d Document) Has(key string) bool { return len(d.Values(key)) > 0 }

func (d Document) hasExact(t Trailer) bool {
	for _, existing := range d.Trailers {
		if strings.EqualFold(existing.Key, t.Key) && existing.Value == t.Value {
			return true
		}
	}
	return false
}

// Append returns the description with every missing trailer of extra added, plus the trailers it
// added and the ones it skipped because an equivalent line already exists.
//
// The body, the existing trailer text and the trailing-newline state are preserved. The result is
// byte-identical to the input when nothing is missing.
func (d Document) Append(extra []Trailer) (string, []Trailer, []Trailer) {
	var added, skipped []Trailer
	for _, t := range extra {
		key := strings.TrimSpace(t.Key)
		value := strings.TrimSpace(t.Value)
		if key == "" || value == "" {
			continue
		}
		t = Trailer{Key: key, Value: value}
		if SingleValued(key) {
			if d.Has(key) {
				skipped = append(skipped, t)
				continue
			}
		} else if d.hasExact(t) {
			skipped = append(skipped, t)
			continue
		}
		duplicate := false
		for _, a := range added {
			if strings.EqualFold(a.Key, t.Key) && a.Value == t.Value {
				duplicate = true
				break
			}
		}
		if duplicate {
			skipped = append(skipped, t)
			continue
		}
		added = append(added, t)
	}
	if len(added) == 0 {
		return d.Raw, nil, skipped
	}
	lines := append([]string(nil), d.Lines...)
	rendered := make([]string, 0, len(added))
	for _, t := range added {
		rendered = append(rendered, t.String())
	}
	switch {
	case d.TrailerStart >= 0:
		// Insert right after the last trailer line, so trailing blank lines stay at the end.
		out := make([]string, 0, len(lines)+len(rendered))
		out = append(out, lines[:d.TrailerEnd]...)
		out = append(out, rendered...)
		out = append(out, lines[d.TrailerEnd:]...)
		lines = out
	case len(lines) == 0:
		lines = rendered
	default:
		if strings.TrimSpace(lines[len(lines)-1]) != "" {
			lines = append(lines, "")
		}
		lines = append(lines, rendered...)
	}
	out := strings.Join(lines, "\n")
	if d.TrailingEOL {
		out += "\n"
	}
	if d.CRLF {
		out = strings.ReplaceAll(out, "\n", "\r\n")
	}
	return out, added, skipped
}

// Render formats trailers as lines.
func Render(trailers []Trailer) []string {
	out := make([]string, 0, len(trailers))
	for _, t := range trailers {
		out = append(out, t.String())
	}
	return out
}

// ParseKeyValue splits a `key=value` argument.
func ParseKeyValue(arg string) (Trailer, error) {
	key, value, ok := strings.Cut(arg, "=")
	if !ok {
		return Trailer{}, &InvalidError{Arg: arg}
	}
	key = strings.TrimSpace(key)
	value = strings.TrimSpace(value)
	if key == "" || value == "" {
		return Trailer{}, &InvalidError{Arg: arg}
	}
	return Trailer{Key: key, Value: value}, nil
}

// InvalidError reports a malformed `key=value` trailer argument.
type InvalidError struct{ Arg string }

func (e *InvalidError) Error() string {
	return "expected key=value, got " + e.Arg
}
