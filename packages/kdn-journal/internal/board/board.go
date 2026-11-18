// Package board parses the free-form Markdown boards used by agent journals.
//
// The parser is heading-driven and tolerant. A board with no recognised section still parses and
// reports its items; a board with no frontmatter is normal. The real boards in this repository use
// date-headed `item|state` tables, `## Status` checkboxes and `## Done` sections, so all three are
// first-class.
package board

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"kdn-journal/internal/frontmatter"
	"kdn-journal/internal/markdown"
)

// Kind is the role of a section.
type Kind string

const (
	KindNow     Kind = "now"
	KindNext    Kind = "next"
	KindBlocked Kind = "blocked"
	KindDone    Kind = "done"
	KindNotes   Kind = "notes"
	KindOther   Kind = "other"
)

// Item is one row or bullet on a board.
type Item struct {
	Text     string   `json:"text"`
	State    string   `json:"state,omitempty"`
	Extra    []string `json:"extra,omitempty"`
	Done     bool     `json:"done"`
	Blocked  bool     `json:"blocked"`
	Dropped  bool     `json:"dropped"`
	Checkbox bool     `json:"checkbox,omitempty"`
	Depth    int      `json:"depth,omitempty"`
	Section  string   `json:"section,omitempty"`
	Line     int      `json:"-"`
}

// Section is one heading and its content. A subsection inherits its parent's kind when its own
// heading is neutral.
type Section struct {
	Title     string   `json:"title"`
	Level     int      `json:"level"`
	Kind      Kind     `json:"kind"`
	Parent    *Section `json:"-"`
	Items     []Item   `json:"items,omitempty"`
	Prose     []string `json:"-"`
	inherited bool
}

// Counts summarises every item on a board.
type Counts struct {
	Open    int `json:"open"`
	Done    int `json:"done"`
	Blocked int `json:"blocked"`
	Dropped int `json:"dropped"`
}

// Board is one parsed board file.
type Board struct {
	Path           string    `json:"path"`
	Title          string    `json:"title"`
	Description    string    `json:"description,omitempty"`
	Status         string    `json:"status"`
	Updated        time.Time `json:"updated"`
	HasUpdated     bool      `json:"-"`
	Tags           []string  `json:"tags,omitempty"`
	Sections       []Section `json:"sections"`
	HasFrontmatter bool      `json:"has_frontmatter"`
	ModTime        time.Time `json:"-"`
}

// MarshalJSON omits a missing updated time instead of emitting the zero time.
func (b Board) MarshalJSON() ([]byte, error) {
	type alias Board
	data, err := json.Marshal(alias(b))
	if err != nil {
		return nil, err
	}
	var fields map[string]any
	if err := json.Unmarshal(data, &fields); err != nil {
		return nil, err
	}
	if b.Updated.IsZero() {
		delete(fields, "updated")
	}
	return json.Marshal(fields)
}

var (
	dateHeadingRE   = regexp.MustCompile(`\d{4}-\d{2}-\d{2}`)
	statePhraseRE   = regexp.MustCompile(`(?i)(?:^|\s)(?:—|–|-|:)\s*\*{0,2}(done|complete|completed|closed|shipped|committed|verified|pass|passed|blocked|blocker|waiting|on hold|gated|dropped|cancelled|abandoned|n/a|wontfix)\*{0,2}\b`)
	parentheticalRE = regexp.MustCompile(`(?i)\((done|blocked|dropped)\)`)
	// A `done` cell can carry a qualifier that names the current state. `DONE (parked,
	// in-progress)` records that the close-out action happened, but the task is still parked;
	// the qualifier wins over the leading `done`.
	openQualifierRE = regexp.MustCompile(`(?:^|[^a-z])(?:in-progress|in progress|parked|wip|ongoing|still open)(?:[^a-z]|$)`)
)

// ParseFile reads and parses one board file.
func ParseFile(path string) (*Board, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	return Parse(data, path, info.ModTime())
}

// Parse parses board data. modTime is the fallback for Updated.
func Parse(data []byte, path string, modTime time.Time) (*Board, error) {
	doc := frontmatter.Parse(data)
	lines := markdown.Scan(doc.Body)
	b := &Board{
		Path:           path,
		Description:    doc.String("description"),
		Tags:           doc.Strings("tags"),
		HasFrontmatter: doc.HasFrontmatter,
		ModTime:        modTime,
	}

	root := &Section{Level: 0, Kind: KindOther}
	sections := []*Section{root}
	current := root
	stack := []*Section{root}
	itemIndex := -1
	var itemIndent int

	for i := 0; i < len(lines); i++ {
		line := lines[i]
		switch line.Kind {
		case markdown.KindHeading:
			itemIndex = -1
			if line.Level == 1 {
				current = root
				continue
			}
			sec := &Section{Title: line.Text, Level: line.Level, Kind: classifyHeading(line.Text)}
			for len(stack) > 0 && stack[len(stack)-1].Level >= sec.Level {
				stack = stack[:len(stack)-1]
			}
			if len(stack) > 0 {
				sec.Parent = stack[len(stack)-1]
				if sec.Kind == KindOther {
					sec.Kind = sec.Parent.Kind
					sec.inherited = true
				}
			}
			stack = append(stack, sec)
			sections = append(sections, sec)
			current = sec
		case markdown.KindBullet:
			item := Item{
				Text:     strings.TrimSpace(line.Text),
				Depth:    line.Indent / 2,
				Line:     line.Number,
				Section:  current.Title,
				Checkbox: line.Checkbox >= 0,
			}
			if line.Checkbox == 1 {
				item.Done = true
			}
			if item.State == "" {
				if phrase, ok := statePhrase(item.Text); ok {
					item.State = phrase
					applyState(&item, phrase)
				}
			}
			if current.Kind == KindDone && !item.Blocked && !item.Dropped {
				item.Done = true
			}
			if current.Kind == KindBlocked && !item.Done && !item.Dropped {
				item.Blocked = true
			}
			current.Items = append(current.Items, item)
			itemIndex = len(current.Items) - 1
			itemIndent = line.Indent
		case markdown.KindBlank:
			// A blank line does not close a bullet; it may separate it from a continuation.
		case markdown.KindProse:
			if itemIndex >= 0 && line.Indent > itemIndent {
				text := strings.TrimSpace(line.Text)
				if text != "" {
					current.Items[itemIndex].Text = strings.TrimSpace(current.Items[itemIndex].Text + " " + text)
				}
				continue
			}
			itemIndex = -1
			current.Prose = append(current.Prose, line.Text)
		case markdown.KindTable:
			itemIndex = -1
			group := []markdown.Line{line}
			for i+1 < len(lines) && lines[i+1].Kind == markdown.KindTable {
				i++
				group = append(group, lines[i])
			}
			items, prose := parseTable(group)
			for _, item := range items {
				item.Section = current.Title
				if current.Kind == KindDone && !item.Blocked && !item.Dropped {
					item.Done = true
				}
				if current.Kind == KindBlocked && !item.Done && !item.Dropped {
					item.Blocked = true
				}
				current.Items = append(current.Items, item)
			}
			current.Prose = append(current.Prose, prose...)
		case markdown.KindFence:
			itemIndex = -1
			current.Prose = append(current.Prose, line.Text)
		}
	}

	// A notes/other section that carries an item+state table with at least one non-done row is a
	// current-state section in practice. This is the structural backstop for headings such as
	// "Containers review cycle (2026-11-14)" and "Goal (current phase, 2026-11-14)".
	for _, sec := range sections {
		if sec.Kind != KindNotes && sec.Kind != KindOther {
			continue
		}
		hasState, hasOpen := false, false
		for _, item := range sec.Items {
			if item.State != "" {
				hasState = true
			}
			if !item.Done && !item.Blocked && !item.Dropped {
				hasOpen = true
			}
		}
		if hasState && hasOpen {
			sec.Kind = KindNow
		}
	}
	// Propagate a changed parent kind to children that inherited it.
	for _, sec := range sections {
		if sec.inherited && sec.Parent != nil && sec.Kind != sec.Parent.Kind {
			sec.Kind = sec.Parent.Kind
		}
	}

	// Drop an empty root section. Keep a non-empty root so a board with no headings still shows
	// its items and prose.
	filtered := make([]Section, 0, len(sections))
	for i, sec := range sections {
		if i == 0 && len(sec.Items) == 0 && len(sec.Prose) == 0 {
			continue
		}
		filtered = append(filtered, *sec)
	}
	b.Sections = filtered
	b.Title = boardTitle(doc, lines, path)
	b.Status = inferStatus(doc.String("status"), b.Counts())
	if t, ok := doc.Time("updated"); ok {
		b.Updated = t
		b.HasUpdated = true
	} else if t, ok := doc.Time("timestamp"); ok {
		b.Updated = t
		b.HasUpdated = true
	} else {
		b.Updated = modTime
	}
	return b, nil
}

// Items returns every item of one kind, in file order. For now-kind sections, date-headed and
// status sections come before the overview tables (Lanes, Tracks, Deliverables), so the summary
// shows current work rather than the track index.
func (b *Board) Items(kind Kind) []Item {
	var primary, overview []Item
	for _, sec := range b.Sections {
		if sec.Kind != kind {
			continue
		}
		target := &primary
		if kind == KindNow && isOverviewHeading(sec.Title) {
			target = &overview
		}
		*target = append(*target, sec.Items...)
	}
	return append(primary, overview...)
}

func isOverviewHeading(title string) bool {
	norm := normalize(title)
	return containsAny(norm, "lanes", "tracks", "deliverables")
}

// Counts summarises every state-bearing item. A plain bullet in a notes or other section is
// prose, not a task item; a checkbox, a state phrase or a table row is an item.
func (b *Board) Counts() Counts {
	var c Counts
	for _, sec := range b.Sections {
		for _, item := range sec.Items {
			if item.Depth > 0 {
				continue
			}
			if (sec.Kind == KindNotes || sec.Kind == KindOther) &&
				!item.Checkbox && item.State == "" && !item.Done && !item.Blocked && !item.Dropped {
				continue
			}
			switch {
			case item.Done:
				c.Done++
			case item.Blocked:
				c.Blocked++
			case item.Dropped:
				c.Dropped++
			default:
				c.Open++
			}
		}
	}
	return c
}

func parseTable(group []markdown.Line) ([]Item, []string) {
	sep := -1
	for i, line := range group {
		if isSeparatorCells(line.Cells) {
			sep = i
			break
		}
	}
	if sep < 1 {
		return nil, tableProse(group)
	}
	header := group[sep-1].Cells
	prose := tableProse(group[:sep-1])
	itemCol, stateCol := -1, -1
	for i, cell := range header {
		norm := normalize(cell)
		if itemCol < 0 && containsAny(norm, "item", "task", "what", "name", "track", "lane", "step", "check", "deliverable") {
			itemCol = i
		}
		if stateCol < 0 && containsAny(norm, "state", "status", "done") {
			stateCol = i
		}
	}
	if itemCol < 0 || stateCol < 0 {
		return nil, append(prose, tableProse(group[sep-1:])...)
	}
	var items []Item
	for _, row := range group[sep+1:] {
		if isSeparatorCells(row.Cells) {
			continue
		}
		if len(row.Cells) <= itemCol || len(row.Cells) <= stateCol {
			continue
		}
		item := Item{
			Text:  strings.TrimSpace(row.Cells[itemCol]),
			State: strings.TrimSpace(row.Cells[stateCol]),
			Line:  row.Number,
		}
		for i, cell := range row.Cells {
			if i != itemCol && i != stateCol && strings.TrimSpace(cell) != "" {
				item.Extra = append(item.Extra, strings.TrimSpace(cell))
			}
		}
		if item.Text == "" {
			continue
		}
		applyState(&item, item.State)
		items = append(items, item)
	}
	return items, prose
}

func tableProse(group []markdown.Line) []string {
	out := make([]string, 0, len(group))
	for _, line := range group {
		out = append(out, line.Text)
	}
	return out
}

func isSeparatorCells(cells []string) bool {
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

func statePhrase(text string) (string, bool) {
	if m := statePhraseRE.FindStringSubmatch(text); m != nil {
		return m[1], true
	}
	if m := parentheticalRE.FindStringSubmatch(text); m != nil {
		return m[1], true
	}
	return "", false
}

func applyState(item *Item, state string) {
	norm := strings.ToLower(strings.TrimSpace(state))
	norm = strings.TrimRight(norm, " .,:;—–-")
	if norm == "" {
		return
	}
	// A qualifier that names an open state wins over a leading `done`: `DONE (parked,
	// in-progress)` records the close-out action, but the task is still parked.
	if openQualifierRE.MatchString(norm) {
		return
	}
	// A state cell that starts with a known word followed by a separator is that state; this
	// covers `DONE — 5 reports`, `done, with evidence` and `done (prettier-formatted)`.
	for _, prefix := range []string{"done", "complete", "completed", "closed", "shipped", "committed", "verified", "pass", "passed"} {
		if norm == prefix || strings.HasPrefix(norm, prefix+" ") || strings.HasPrefix(norm, prefix+"(") ||
			strings.HasPrefix(norm, prefix+",") || strings.HasPrefix(norm, prefix+":") ||
			strings.HasPrefix(norm, prefix+"—") || strings.HasPrefix(norm, prefix+"–") {
			item.Done = true
			return
		}
	}
	for _, prefix := range []string{"blocked", "blocker", "waiting", "hold", "on hold", "gated"} {
		if norm == prefix || strings.HasPrefix(norm, prefix+" ") || strings.HasPrefix(norm, prefix+"(") ||
			strings.HasPrefix(norm, prefix+",") || strings.HasPrefix(norm, prefix+":") {
			item.Blocked = true
			return
		}
	}
	for _, prefix := range []string{"dropped", "cancelled", "abandoned", "n/a", "wontfix", "not applicable"} {
		if norm == prefix || strings.HasPrefix(norm, prefix+" ") || strings.HasPrefix(norm, prefix+"(") ||
			strings.HasPrefix(norm, prefix+",") || strings.HasPrefix(norm, prefix+":") {
			item.Dropped = true
			return
		}
	}
	if norm == "x" || norm == "✓" || norm == "✔" {
		item.Done = true
	}
}

func inferStatus(frontmatterStatus string, counts Counts) string {
	switch strings.ToLower(strings.TrimSpace(frontmatterStatus)) {
	case "active", "in-progress", "in progress", "open":
		return "active"
	case "blocked":
		return "blocked"
	case "done":
		return "done"
	}
	switch {
	case counts.Blocked > 0:
		return "blocked"
	case counts.Open > 0:
		return "active"
	case counts.Done > 0 && counts.Open == 0 && counts.Blocked == 0 && counts.Dropped == 0:
		return "done"
	default:
		return "unknown"
	}
}

func classifyHeading(text string) Kind {
	norm := normalize(text)
	switch {
	case containsAny(norm, "not blocker", "not blockers"):
		return KindNext
	case containsAny(norm, "blocked", "blocker", "blockers", "waiting", "on hold", "gated"):
		return KindBlocked
	case containsAny(norm, "done", "completed", "finished", "shipped", "resolved"):
		return KindDone
	case containsAny(norm, "now", "current", "in progress", "doing", "active", "status", "state", "run state", "check state", "open items", "sub items", "items", "deliverables", "tracks", "lanes"):
		return KindNow
	case containsAny(norm, "notes") && containsAny(norm, "next"):
		return KindNotes
	case containsAny(norm, "next", "todo", "to do", "remaining", "follow up", "follow ups", "followup", "followups", "not started", "queued", "owner actions"):
		return KindNext
	case containsAny(norm, "notes", "where we are", "context", "plan", "review", "risks", "caveats", "evidence", "hypotheses", "reference", "order", "commits", "verified state", "why", "root cause", "fix", "result", "contract", "verification", "controls", "blast radius", "harness", "host", "goal"):
		return KindNotes
	case dateHeadingRE.MatchString(text):
		return KindNow
	default:
		return KindOther
	}
}

func normalize(text string) string {
	text = strings.ToLower(text)
	var b strings.Builder
	space := true
	for _, r := range text {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' {
			b.WriteRune(r)
			space = false
		} else if !space {
			b.WriteByte(' ')
			space = true
		}
	}
	return strings.TrimSpace(b.String())
}

func containsAny(norm string, needles ...string) bool {
	for _, needle := range needles {
		if needle == "" {
			continue
		}
		if strings.Contains(" "+norm+" ", " "+needle+" ") {
			return true
		}
		// Multi-word phrases are already space-separated by normalize.
		if strings.Contains(norm, needle) && strings.Contains(needle, " ") {
			return true
		}
	}
	return false
}

func boardTitle(doc *frontmatter.Document, lines []markdown.Line, path string) string {
	if title := strings.TrimSpace(doc.String("title")); title != "" {
		return title
	}
	h1 := ""
	for _, line := range markdown.Headings(lines) {
		if line.Level != 1 {
			continue
		}
		h1 = strings.TrimSpace(line.Text)
		h1 = strings.TrimPrefix(h1, "Board — ")
		h1 = strings.TrimPrefix(h1, "Board – ")
		h1 = strings.TrimPrefix(h1, "Board - ")
		h1 = strings.TrimPrefix(h1, "Board: ")
		h1 = strings.TrimSpace(h1)
		break
	}
	if h1 != "" && h1 != "Board" {
		return h1
	}
	base := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	if strings.HasPrefix(base, ".") {
		base = strings.TrimPrefix(base, ".")
	}
	if base == "" {
		base = "board"
	}
	if h1 == "Board" {
		base = filepath.Base(filepath.Dir(path))
	}
	return base
}
