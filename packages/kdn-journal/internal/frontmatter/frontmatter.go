// Package frontmatter parses the YAML frontmatter block of an OKF Markdown file.
//
// The parser is deliberately tolerant. Several task definitions in this repository carry an
// unquoted `: ` inside `description`, which is invalid YAML. A parse error must not hide the
// task, so Parse falls back to a line-based reader and records the problem in
// Document.FrontmatterError.
package frontmatter

import (
	"bytes"
	"fmt"
	"os"
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

// Parse splits data at the frontmatter delimiters and decodes the YAML block.
func Parse(data []byte) *Document {
	doc := &Document{
		Raw:    data,
		Body:   data,
		Values: map[string]any{},
	}
	start, end, ok := frontmatterBlock(data)
	if !ok {
		return doc
	}
	doc.HasFrontmatter = true
	doc.Body = data[afterLine(data, end):]
	yamlBlock := data[start:end]
	if err := yaml.Unmarshal(yamlBlock, &doc.Values); err != nil {
		doc.FrontmatterError = err.Error()
		doc.Values = fallbackValues(yamlBlock)
	}
	if doc.Values == nil {
		doc.Values = map[string]any{}
	}
	return doc
}

// ParseFile reads path and parses it.
func ParseFile(path string) (*Document, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return Parse(data), nil
}

// String returns a scalar value as text.
func (d *Document) String(key string) string {
	v, ok := d.Values[key]
	if !ok || v == nil {
		return ""
	}
	switch value := v.(type) {
	case string:
		return value
	case time.Time:
		return value.Format(time.RFC3339)
	default:
		return fmt.Sprint(value)
	}
}

// Strings returns a list value. A comma-separated scalar is also accepted; this is intended for
// the `tags` key only.
func (d *Document) Strings(key string) []string {
	v, ok := d.Values[key]
	if !ok || v == nil {
		return nil
	}
	switch value := v.(type) {
	case []string:
		return append([]string(nil), value...)
	case []any:
		out := make([]string, 0, len(value))
		for _, item := range value {
			out = append(out, fmt.Sprint(item))
		}
		return out
	case string:
		if strings.TrimSpace(value) == "" {
			return nil
		}
		parts := strings.Split(value, ",")
		out := make([]string, 0, len(parts))
		for _, part := range parts {
			if part = strings.TrimSpace(part); part != "" {
				out = append(out, part)
			}
		}
		return out
	default:
		return nil
	}
}

// Time returns a timestamp value and whether it was present and parseable.
func (d *Document) Time(key string) (time.Time, bool) {
	v, ok := d.Values[key]
	if !ok || v == nil {
		return time.Time{}, false
	}
	switch value := v.(type) {
	case time.Time:
		return value, true
	case string:
		return ParseTime(value)
	default:
		return ParseTime(fmt.Sprint(value))
	}
}

// ParseTime accepts the timestamp shapes used in this repository.
func ParseTime(value string) (time.Time, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}, false
	}
	layouts := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02 15:04:05 -0700",
		"2006-01-02 15:04:05",
		"2006-01-02",
	}
	for _, layout := range layouts {
		if t, err := time.Parse(layout, value); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// SetScalar rewrites one top-level key inside the frontmatter block and preserves every other
// byte. It is used by `task set-status`.
func SetScalar(data []byte, key, value string) ([]byte, error) {
	start, end, ok := frontmatterBlock(data)
	if !ok {
		return nil, fmt.Errorf("file has no frontmatter")
	}
	yamlBlock := data[start:end]
	lineEnd := "\n"
	if bytes.Contains(yamlBlock, []byte("\r\n")) {
		lineEnd = "\r\n"
	}
	encoded := yamlScalar(value)

	lines := splitLines(yamlBlock)
	var out bytes.Buffer
	replaced := false
	for _, line := range lines {
		content := strings.TrimRight(line, "\r\n")
		eol := line[len(content):]
		if !replaced && isTopLevelKey(content, key) {
			out.WriteString(key + ": " + encoded + eol)
			replaced = true
			continue
		}
		out.WriteString(line)
	}
	if !replaced {
		// Insert before the closing delimiter. The block ends with the newline before `---`,
		// so append a new line when the block is non-empty.
		if out.Len() > 0 && !bytes.HasSuffix(out.Bytes(), []byte("\n")) {
			out.WriteString(lineEnd)
		}
		out.WriteString(key + ": " + encoded + lineEnd)
	}

	result := make([]byte, 0, len(data)+len(encoded))
	result = append(result, data[:start]...)
	result = append(result, out.Bytes()...)
	result = append(result, data[end:]...)
	return result, nil
}

// frontmatterBlock returns the byte range of the YAML block, excluding both delimiter lines.
func frontmatterBlock(data []byte) (start, end int, ok bool) {
	if !bytes.HasPrefix(data, []byte("---")) {
		return 0, 0, false
	}
	firstEnd := bytes.IndexByte(data, '\n')
	if firstEnd < 0 {
		return 0, 0, false
	}
	first := strings.TrimSpace(string(data[:firstEnd]))
	if first != "---" {
		return 0, 0, false
	}
	pos := firstEnd + 1
	for pos <= len(data) {
		next := bytes.IndexByte(data[pos:], '\n')
		var line []byte
		var lineEnd int
		if next < 0 {
			line = data[pos:]
			lineEnd = len(data)
		} else {
			line = data[pos : pos+next]
			lineEnd = pos + next + 1
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

func splitLines(data []byte) []string {
	var lines []string
	for len(data) > 0 {
		idx := bytes.IndexByte(data, '\n')
		if idx < 0 {
			lines = append(lines, string(data))
			break
		}
		lines = append(lines, string(data[:idx+1]))
		data = data[idx+1:]
	}
	return lines
}

// afterLine returns the byte offset just after the line that starts at pos.
func afterLine(data []byte, pos int) int {
	if pos >= len(data) {
		return len(data)
	}
	idx := bytes.IndexByte(data[pos:], '\n')
	if idx < 0 {
		return len(data)
	}
	return pos + idx + 1
}

func isTopLevelKey(line, key string) bool {
	if line == "" || line[0] == ' ' || line[0] == '\t' || line[0] == '#' {
		return false
	}
	idx := strings.IndexByte(line, ':')
	if idx < 0 {
		return false
	}
	return strings.TrimSpace(line[:idx]) == key
}

func yamlScalar(value string) string {
	if value == "" {
		return `""`
	}
	safe := true
	for _, r := range value {
		if !(r == '-' || r == '_' || r == '.' || r == '/' || r == '@' || r == '+' ||
			r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9') {
			safe = false
			break
		}
	}
	if safe {
		return value
	}
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

// fallbackValues reads top-level `key: value` lines when YAML parsing fails. It is intentionally
// small: it does not try to be a YAML parser, only to recover the flat keys this repository uses.
func fallbackValues(block []byte) map[string]any {
	values := map[string]any{}
	var currentKey string
	var list []string
	flushList := func() {
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
		flushList()
		value := strings.TrimSpace(line[idx+1:])
		if value == "" {
			currentKey = key
			continue
		}
		values[key] = cleanScalar(value)
	}
	flushList()
	return values
}

func cleanScalar(value string) string {
	value = strings.TrimSpace(value)
	if len(value) >= 2 {
		if (value[0] == '"' && value[len(value)-1] == '"') ||
			(value[0] == '\'' && value[len(value)-1] == '\'') {
			return value[1 : len(value)-1]
		}
	}
	if idx := strings.Index(value, " #"); idx >= 0 {
		value = strings.TrimSpace(value[:idx])
	}
	return value
}
