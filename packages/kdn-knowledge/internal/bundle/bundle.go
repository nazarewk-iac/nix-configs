// Package bundle reads the existing memory bundle. The pipeline never writes here; it compares
// its merged items with these concepts and leaves the writing to `apply`.
package bundle

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"kdn-knowledge/internal/okfkind"
)

// Concept is one concept of the bundle, with the fields that a comparison needs.
type Concept struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Type        string `json:"type"`
	Kind        string `json:"kind"`
	Status      string `json:"status"`
	RelPath     string `json:"rel_path"`
	Statement   string `json:"statement"`
}

// Label is the text that similarity compares against: title and description.
func (c Concept) Label() string {
	return strings.TrimSpace(c.Title + " " + c.Description)
}

// Load reads every concept under root. A missing root is not an error: it means the bundle is
// empty, and every proposed item is new.
func Load(root string) ([]Concept, error) {
	info, err := os.Stat(root)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	if !info.IsDir() {
		return nil, nil
	}
	concepts := make([]Concept, 0, 64)
	err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			name := entry.Name()
			if path != root && (strings.HasPrefix(name, ".") || name == "proposals") {
				return fs.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(strings.ToLower(entry.Name()), ".md") {
			return nil
		}
		switch entry.Name() {
		case "index.md", "log.md", "README.md":
			return nil
		}
		body, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		fields, rest := ParseFrontmatter(string(body))
		concept := Concept{
			ID:          fields["id"],
			Title:       fields["title"],
			Description: fields["description"],
			Type:        fields["type"],
			Status:      fields["status"],
			Statement:   FirstParagraph(rest),
		}
		if concept.ID == "" {
			concept.ID = strings.TrimSuffix(entry.Name(), filepath.Ext(entry.Name()))
		}
		if concept.Type == "" {
			return nil
		}
		concept.Kind = okfkind.Kind(concept.Type)
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		concept.RelPath = filepath.ToSlash(rel)
		concepts = append(concepts, concept)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(concepts, func(i, j int) bool { return concepts[i].RelPath < concepts[j].RelPath })
	return concepts, nil
}

// ParseFrontmatter returns the top-level scalar fields and the body.
//
// The parser covers the subset that the bundle uses: one `key: value` per line, quoted or bare,
// with nested keys and list items ignored. A full YAML parser would be a third-party dependency.
func ParseFrontmatter(document string) (map[string]string, string) {
	fields := map[string]string{}
	if !strings.HasPrefix(document, "---\n") && document != "---" {
		return fields, document
	}
	lines := strings.Split(document, "\n")
	end := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == "---" {
			end = i
			break
		}
	}
	if end < 0 {
		return fields, document
	}
	for _, line := range lines[1:end] {
		if line == "" || strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
			continue
		}
		if strings.HasPrefix(strings.TrimSpace(line), "- ") {
			continue
		}
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		key = strings.ToLower(strings.TrimSpace(key))
		value = strings.TrimSpace(value)
		if strings.HasPrefix(value, "{") {
			continue
		}
		value = strings.Trim(value, `"'`)
		if key == "" || value == "" {
			continue
		}
		fields[key] = value
	}
	body := strings.Join(lines[end+1:], "\n")
	return fields, body
}

// FirstParagraph returns the first non-heading, non-empty paragraph of a Markdown body.
func FirstParagraph(body string) string {
	var paragraph []string
	for _, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			if len(paragraph) > 0 {
				break
			}
			continue
		}
		if strings.HasPrefix(trimmed, "#") {
			if len(paragraph) > 0 {
				break
			}
			continue
		}
		paragraph = append(paragraph, trimmed)
	}
	return strings.Join(paragraph, " ")
}
