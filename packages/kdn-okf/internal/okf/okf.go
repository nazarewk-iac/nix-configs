package okf

import (
	"fmt"
	"path/filepath"
	"strings"
	"time"
)

// Issue is one diagnostic with a stable code.
type Issue struct {
	Severity string `json:"severity"`
	Code     string `json:"code"`
	Path     string `json:"path,omitempty"`
	Concept  string `json:"concept,omitempty"`
	Line     int    `json:"line,omitempty"`
	Target   string `json:"target,omitempty"`
	Message  string `json:"message"`
}

// Severity values.
const (
	SeverityError   = "error"
	SeverityWarning = "warning"
	SeverityInfo    = "info"
)

// TrustTier is derived from `verified`.
type TrustTier int

const (
	TrustUnverified TrustTier = iota
	TrustMachine
	TrustHuman
)

func (t TrustTier) String() string {
	switch t {
	case TrustMachine:
		return "machine-confirmed"
	case TrustHuman:
		return "human-reviewed"
	}
	return "unverified"
}

// MarshalText keeps the JSON vocabulary kebab-case.
func (t TrustTier) MarshalText() ([]byte, error) { return []byte(t.String()), nil }

// UnmarshalText restores a trust tier from its kebab-case name, so the cache round-trips.
func (t *TrustTier) UnmarshalText(data []byte) error {
	switch string(data) {
	case "machine-confirmed":
		*t = TrustMachine
	case "human-reviewed":
		*t = TrustHuman
	default:
		*t = TrustUnverified
	}
	return nil
}

// Event is one `generated` or `verified` entry.
type Event struct {
	By string `json:"by,omitempty"`
	At string `json:"at,omitempty"`
}

// Source is one provenance entry.
type Source struct {
	ID           string `json:"id,omitempty"`
	Resource     string `json:"resource,omitempty"`
	Title        string `json:"title,omitempty"`
	Author       string `json:"author,omitempty"`
	UsageCount   int    `json:"usage_count,omitempty"`
	LastModified string `json:"last_modified,omitempty"`
}

// Parameter is one Attested Computation parameter.
type Parameter struct {
	Name        string `json:"name,omitempty"`
	Type        string `json:"type,omitempty"`
	Description string `json:"description,omitempty"`
}

// ResourceRef names an executor or attester.
type ResourceRef struct {
	Resource string `json:"resource,omitempty"`
	Title    string `json:"title,omitempty"`
}

// Concept is one OKF document.
type Concept struct {
	ID          string       `json:"id"`
	Path        string       `json:"path"`
	RelPath     string       `json:"rel_path"`
	Bundle      string       `json:"bundle,omitempty"`
	Type        string       `json:"type"`
	Title       string       `json:"title"`
	Description string       `json:"description,omitempty"`
	Resource    string       `json:"resource,omitempty"`
	Tags        []string     `json:"tags"`
	Status      string       `json:"status"`
	Generated   *Event       `json:"generated,omitempty"`
	Verified    []Event      `json:"verified"`
	Trust       TrustTier    `json:"trust"`
	StaleAfter  string       `json:"stale_after,omitempty"`
	Stale       bool         `json:"stale"`
	Sources     []Source     `json:"sources"`
	Runtime     string       `json:"runtime,omitempty"`
	Parameters  []Parameter  `json:"parameters,omitempty"`
	Computation string       `json:"computation,omitempty"`
	Executor    *ResourceRef `json:"executor,omitempty"`
	Attester    *ResourceRef `json:"attester,omitempty"`
	Headings    []Heading    `json:"headings"`
	Links       []Link       `json:"links"`
	Backlinks   []Link       `json:"backlinks"`
	ModTime     time.Time    `json:"-"`
	Size        int64        `json:"size"`
	Issues      []Issue      `json:"issues"`

	Body       []byte      `json:"-"`
	ScanCode   []CodeBlock `json:"-"`
	ScanTables []Table     `json:"-"`
}

// Reserved is `index.md` or `log.md`.
type Reserved struct {
	Path    string `json:"path"`
	RelPath string `json:"rel_path"`
	Kind    string `json:"kind"`
	Body    []byte `json:"-"`
}

// Bundle is one indexed directory tree.
type Bundle struct {
	Root     string      `json:"root"`
	Name     string      `json:"name"`
	Concepts []*Concept  `json:"concepts"`
	Reserved []*Reserved `json:"reserved"`
	Issues   []Issue     `json:"issues"`
}

// Find returns the concept with the given ID.
func (b *Bundle) Find(id string) *Concept {
	for _, concept := range b.Concepts {
		if concept.ID == id {
			return concept
		}
	}
	return nil
}

// ParseConcept builds one concept from a file. It never fails: a malformed file becomes a concept
// with issues, so a bundle stays browsable.
func ParseConcept(root, path string, data []byte, modTime time.Time, now time.Time) *Concept {
	rel, err := filepath.Rel(root, path)
	if err != nil {
		rel = path
	}
	rel = filepath.ToSlash(rel)
	id := strings.TrimSuffix(rel, ".md")
	concept := &Concept{
		ID:       id,
		Path:     path,
		RelPath:  rel,
		Bundle:   root,
		ModTime:  modTime,
		Size:     int64(len(data)),
		Tags:     []string{},
		Verified: []Event{},
		Sources:  []Source{},
		Links:    []Link{},
		Headings: []Heading{},
		Issues:   []Issue{},
	}
	doc := Parse(data)
	concept.Body = doc.Body
	if !doc.HasFrontmatter {
		concept.Issues = append(concept.Issues, Issue{
			Severity: SeverityError,
			Code:     "frontmatter-missing",
			Path:     path,
			Concept:  id,
			Message:  "file has no YAML frontmatter block",
		})
	}
	if doc.FrontmatterError != "" {
		concept.Issues = append(concept.Issues, Issue{
			Severity: SeverityWarning,
			Code:     "frontmatter-invalid",
			Path:     path,
			Concept:  id,
			Message:  doc.FrontmatterError,
		})
	}
	concept.Type = doc.String("type")
	if concept.Type == "" {
		concept.Issues = append(concept.Issues, Issue{
			Severity: SeverityError,
			Code:     "type-missing",
			Path:     path,
			Concept:  id,
			Message:  "frontmatter has no non-empty type",
		})
	} else if _, ok := doc.Values["type"].(string); !ok {
		concept.Issues = append(concept.Issues, Issue{
			Severity: SeverityError,
			Code:     "type-not-string",
			Path:     path,
			Concept:  id,
			Message:  "type is not a string",
		})
	}

	scan := ScanMarkdown(doc.Body)
	concept.Headings = scan.Headings
	concept.Links = scan.Links
	concept.ScanCode = scan.Code
	concept.ScanTables = scan.Tables
	for i := range concept.Links {
		concept.Links[i].Source = id
	}

	concept.Title = doc.String("title")
	if concept.Title == "" {
		concept.Title = firstHeading(scan.Headings)
	}
	if concept.Title == "" {
		concept.Title = strings.TrimSuffix(filepath.Base(rel), ".md")
	}
	concept.Description = doc.String("description")
	concept.Resource = doc.String("resource")
	concept.Tags = nonNil(doc.Strings("tags"))

	concept.Status = strings.ToLower(doc.String("status"))
	if concept.Status == "" {
		concept.Status = "stable"
	}
	switch concept.Status {
	case "draft", "stable", "deprecated":
	default:
		concept.Issues = append(concept.Issues, Issue{
			Severity: SeverityWarning,
			Code:     "status-invalid",
			Path:     path,
			Concept:  id,
			Message:  fmt.Sprintf("unknown status %q; expected draft, stable or deprecated", concept.Status),
		})
		concept.Status = "stable"
	}

	concept.Generated = parseEvent(doc.Map("generated"), path, id, "generated-shape", &concept.Issues)
	if concept.Generated == nil {
		if at, ok := doc.Time("timestamp"); ok {
			concept.Generated = &Event{At: at.Format(time.RFC3339)}
		}
	}
	for _, entry := range doc.Slice("verified") {
		concept.Verified = append(concept.Verified, eventFromMap(entry))
	}
	if raw, ok := doc.Values["verified"]; ok {
		switch typed := raw.(type) {
		case string:
			concept.Verified = append(concept.Verified, Event{By: typed})
		case []any:
			for _, item := range typed {
				if s, ok := item.(string); ok {
					concept.Verified = append(concept.Verified, Event{By: s})
				}
			}
		case nil:
		default:
			if len(concept.Verified) == 0 {
				concept.Issues = append(concept.Issues, Issue{
					Severity: SeverityWarning,
					Code:     "verified-shape",
					Path:     path,
					Concept:  id,
					Message:  "verified is neither a list nor a mapping",
				})
			}
		}
	}
	concept.Trust = deriveTrust(concept.Verified)

	if raw := doc.String("stale_after"); raw != "" {
		concept.StaleAfter = raw
		if at, ok := ParseTime(raw); ok {
			concept.Stale = !now.Before(at)
		} else {
			concept.Issues = append(concept.Issues, Issue{
				Severity: SeverityWarning,
				Code:     "stale-after-invalid",
				Path:     path,
				Concept:  id,
				Message:  fmt.Sprintf("stale_after %q is not a timestamp", raw),
			})
		}
	}

	for _, entry := range doc.Slice("sources") {
		source := Source{
			ID:         scalar(entry["id"]),
			Resource:   scalar(entry["resource"]),
			Title:      scalar(entry["title"]),
			Author:     scalar(entry["author"]),
			UsageCount: integer(entry["usage_count"]),
		}
		if at, ok := ParseTime(scalar(entry["last_modified"])); ok {
			source.LastModified = at.Format(time.RFC3339)
		}
		concept.Sources = append(concept.Sources, source)
	}

	if strings.EqualFold(concept.Type, "Attested Computation") {
		concept.Runtime = doc.String("runtime")
		concept.Computation = doc.String("computation")
		for _, entry := range doc.Slice("parameters") {
			concept.Parameters = append(concept.Parameters, Parameter{
				Name:        scalar(entry["name"]),
				Type:        scalar(entry["type"]),
				Description: scalar(entry["description"]),
			})
		}
		concept.Executor = parseResourceRef(doc.Map("executor"))
		concept.Attester = parseResourceRef(doc.Map("attester"))
		missing := []string{}
		if concept.Runtime == "" {
			missing = append(missing, "runtime")
		}
		if concept.Executor == nil {
			missing = append(missing, "executor")
		}
		if concept.Attester == nil {
			missing = append(missing, "attester")
		}
		if len(missing) > 0 {
			concept.Issues = append(concept.Issues, Issue{
				Severity: SeverityWarning,
				Code:     "computation-shape",
				Path:     path,
				Concept:  id,
				Message:  "Attested Computation misses " + strings.Join(missing, ", "),
			})
		}
	}
	return concept
}

func parseEvent(entry map[string]any, path, id, code string, issues *[]Issue) *Event {
	if entry == nil {
		return nil
	}
	event := &Event{By: scalar(entry["by"])}
	if at, ok := ParseTime(scalar(entry["at"])); ok {
		event.At = at.Format(time.RFC3339)
	} else if scalar(entry["at"]) != "" {
		*issues = append(*issues, Issue{
			Severity: SeverityWarning,
			Code:     code,
			Path:     path,
			Concept:  id,
			Message:  "at is not a timestamp",
		})
	}
	return event
}

func eventFromMap(entry map[string]any) Event {
	event := Event{By: scalar(entry["by"])}
	if at, ok := ParseTime(scalar(entry["at"])); ok {
		event.At = at.Format(time.RFC3339)
	}
	return event
}

func deriveTrust(verified []Event) TrustTier {
	if len(verified) == 0 {
		return TrustUnverified
	}
	for _, event := range verified {
		if strings.HasPrefix(strings.ToLower(strings.TrimSpace(event.By)), "human:") {
			return TrustHuman
		}
	}
	return TrustMachine
}

func parseResourceRef(entry map[string]any) *ResourceRef {
	if entry == nil {
		return nil
	}
	ref := &ResourceRef{Resource: scalar(entry["resource"]), Title: scalar(entry["title"])}
	if ref.Resource == "" && ref.Title == "" {
		return nil
	}
	return ref
}

func firstHeading(headings []Heading) string {
	for _, heading := range headings {
		if heading.Level == 1 {
			return heading.Text
		}
	}
	return ""
}

func scalar(value any) string {
	if value == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(value))
}

func integer(value any) int {
	switch typed := value.(type) {
	case int:
		return typed
	case int64:
		return int(typed)
	case float64:
		return int(typed)
	case string:
		var out int
		_, _ = fmt.Sscanf(typed, "%d", &out)
		return out
	}
	return 0
}

func nonNil(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}
