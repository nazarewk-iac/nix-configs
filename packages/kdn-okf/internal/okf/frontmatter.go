// Package okf holds the Open Knowledge Format v0.2 model: concepts, frontmatter, trust and the
// Markdown structure the browser reads.
package okf

import (
	"bytes"
	"fmt"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Document is one Markdown file split into frontmatter values and body.
type Document struct {
	Raw              []byte
	Body             []byte
	Values           map[string]any
	HasFrontmatter   bool
	FrontmatterError string
}

// Parse splits data at the frontmatter delimiters and decodes the YAML block. A parse error is
// recorded and a line-based fallback keeps the flat keys readable; it is never a hard failure.
func Parse(data []byte) *Document {
	doc := &Document{Raw: data, Body: data, Values: map[string]any{}}
	start, end, ok := frontmatterBlock(data)
	if !ok {
		return doc
	}
	doc.HasFrontmatter = true
	doc.Body = data[afterLine(data, end):]
	block := data[start:end]
	if err := yaml.Unmarshal(block, &doc.Values); err != nil {
		doc.FrontmatterError = err.Error()
		doc.Values = fallbackValues(block)
	}
	if doc.Values == nil {
		doc.Values = map[string]any{}
	}
	return doc
}

// String returns a scalar value as text.
func (d *Document) String(key string) string {
	value, ok := d.Values[key]
	if !ok || value == nil {
		return ""
	}
	switch typed := value.(type) {
	case string:
		return typed
	case time.Time:
		return typed.Format(time.RFC3339)
	default:
		return fmt.Sprint(value)
	}
}

// Strings returns a list value. A comma-separated scalar is accepted too.
func (d *Document) Strings(key string) []string {
	value, ok := d.Values[key]
	if !ok || value == nil {
		return nil
	}
	switch typed := value.(type) {
	case []string:
		return append([]string(nil), typed...)
	case []any:
		out := make([]string, 0, len(typed))
		for _, item := range typed {
			out = append(out, fmt.Sprint(item))
		}
		return out
	case string:
		parts := strings.Split(typed, ",")
		out := make([]string, 0, len(parts))
		for _, part := range parts {
			if part = strings.TrimSpace(part); part != "" {
				out = append(out, part)
			}
		}
		return out
	}
	return nil
}

// Map returns a mapping value.
func (d *Document) Map(key string) map[string]any {
	value, ok := d.Values[key]
	if !ok || value == nil {
		return nil
	}
	switch typed := value.(type) {
	case map[string]any:
		return typed
	case map[any]any:
		out := make(map[string]any, len(typed))
		for k, v := range typed {
			out[fmt.Sprint(k)] = v
		}
		return out
	}
	return nil
}

// Slice returns a list of mappings. A single mapping becomes a one-element list.
func (d *Document) Slice(key string) []map[string]any {
	value, ok := d.Values[key]
	if !ok || value == nil {
		return nil
	}
	switch typed := value.(type) {
	case []any:
		out := make([]map[string]any, 0, len(typed))
		for _, item := range typed {
			switch entry := item.(type) {
			case map[string]any:
				out = append(out, entry)
			case map[any]any:
				m := make(map[string]any, len(entry))
				for k, v := range entry {
					m[fmt.Sprint(k)] = v
				}
				out = append(out, m)
			}
		}
		return out
	case map[string]any:
		return []map[string]any{typed}
	case map[any]any:
		m := make(map[string]any, len(typed))
		for k, v := range typed {
			m[fmt.Sprint(k)] = v
		}
		return []map[string]any{m}
	}
	return nil
}

// Time returns a timestamp value and whether it was present and parseable.
func (d *Document) Time(key string) (time.Time, bool) {
	value, ok := d.Values[key]
	if !ok || value == nil {
		return time.Time{}, false
	}
	switch typed := value.(type) {
	case time.Time:
		return typed, true
	case string:
		return ParseTime(typed)
	default:
		return ParseTime(fmt.Sprint(value))
	}
}

// ParseTime accepts the timestamp shapes OKF bundles use.
func ParseTime(value string) (time.Time, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}, false
	}
	for _, layout := range []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02 15:04:05 -0700",
		"2006-01-02 15:04:05",
		"2006-01-02",
	} {
		if t, err := time.Parse(layout, value); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

func frontmatterBlock(data []byte) (start, end int, ok bool) {
	if !bytes.HasPrefix(data, []byte("---")) {
		return 0, 0, false
	}
	firstEnd := bytes.IndexByte(data, '\n')
	if firstEnd < 0 {
		return 0, 0, false
	}
	if strings.TrimSpace(string(data[:firstEnd])) != "---" {
		return 0, 0, false
	}
	pos := firstEnd + 1
	for pos <= len(data) {
		next := bytes.IndexByte(data[pos:], '\n')
		var line []byte
		lineEnd := len(data)
		if next >= 0 {
			line = data[pos : pos+next]
			lineEnd = pos + next + 1
		} else {
			line = data[pos:]
		}
		trimmed := strings.TrimSpace(string(line))
		if trimmed == "---" || trimmed == "..." {
			return firstEnd + 1, pos, true
		}
		if next < 0 {
			break
		}
		pos = lineEnd
	}
	return 0, 0, false
}

func afterLine(data []byte, pos int) int {
	if pos >= len(data) {
		return len(data)
	}
	if idx := bytes.IndexByte(data[pos:], '\n'); idx >= 0 {
		return pos + idx + 1
	}
	return len(data)
}

// fallbackValues reads top-level `key: value` lines when YAML parsing fails.
func fallbackValues(block []byte) map[string]any {
	values := map[string]any{}
	var currentKey string
	var list []string
	flush := func() {
		if currentKey != "" && len(list) > 0 {
			items := make([]any, len(list))
			for i, item := range list {
				items[i] = item
			}
			values[currentKey] = items
		}
		currentKey = ""
		list = nil
	}
	for _, raw := range strings.Split(string(block), "\n") {
		line := strings.TrimRight(raw, "\r")
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		if line[0] == ' ' || line[0] == '\t' {
			trimmed := strings.TrimSpace(line)
			if currentKey != "" && strings.HasPrefix(trimmed, "- ") {
				list = append(list, cleanScalar(strings.TrimPrefix(trimmed, "- ")))
			}
			continue
		}
		idx := strings.IndexByte(line, ':')
		if idx < 0 {
			continue
		}
		key := strings.TrimSpace(line[:idx])
		if key == "" {
			continue
		}
		flush()
		value := strings.TrimSpace(line[idx+1:])
		if value == "" {
			currentKey = key
			continue
		}
		values[key] = cleanScalar(value)
	}
	flush()
	return values
}

func cleanScalar(value string) string {
	value = strings.TrimSpace(value)
	if len(value) >= 2 {
		if (value[0] == '"' && value[len(value)-1] == '"') || (value[0] == '\'' && value[len(value)-1] == '\'') {
			return value[1 : len(value)-1]
		}
	}
	if idx := strings.Index(value, " #"); idx >= 0 {
		value = strings.TrimSpace(value[:idx])
	}
	return value
}
