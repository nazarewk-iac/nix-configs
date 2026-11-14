package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/glamour"

	"kdn-journal/internal/board"
	"kdn-journal/internal/journal"
	"kdn-journal/internal/task"
	"kdn-journal/internal/worklog"
)

const (
	previewItems    = 4
	previewHeadings = 5
	fullHeadings    = 20
)

// detailMarkdown builds the Markdown that glamour renders into the viewport.
func (m Model) detailMarkdown(full bool) string {
	if m.tab == TabSessions {
		if s := m.selectedSession(); s != nil {
			return sessionMarkdown(s, full)
		}
		return "# Nothing selected\n\nUse `j`/`k` to move and `/` to filter.\n"
	}
	if t := m.selectedTask(); t != nil {
		return taskMarkdown(t, full)
	}
	return "# Nothing selected\n\nUse `j`/`k` to move and `/` to filter.\n"
}

func taskMarkdown(t *task.Task, full bool) string {
	var b strings.Builder
	title := t.Title
	if title == "" {
		title = t.Slug
	}
	fmt.Fprintf(&b, "# %s\n\n", title)
	fmt.Fprintf(&b, "**%s** · `%s`\n\n", t.Status, t.RelDir)
	if t.Description != "" {
		fmt.Fprintf(&b, "%s\n\n", t.Description)
	}
	if !t.Timestamp.IsZero() {
		fmt.Fprintf(&b, "Started: %s\n\n", t.Timestamp.Format("2006-01-02 15:04"))
	}
	if !t.LastActivity.IsZero() {
		fmt.Fprintf(&b, "Active: %s\n\n", t.LastActivity.Format("2006-01-02 15:04"))
	}

	b.WriteString("## Board\n\n")
	if t.Board == nil {
		b.WriteString("_No board yet._\n\n")
	} else {
		boardMarkdown(&b, t.Board, full)
	}

	if t.Worklog != nil {
		b.WriteString("## Worklog\n\n")
		worklogMarkdown(&b, t.Worklog, full)
	}

	if len(t.Subtasks) > 0 {
		b.WriteString("## Subtasks\n\n")
		for _, sub := range t.Subtasks {
			fmt.Fprintf(&b, "- [%s] `%s` — %s\n", sub.Status, sub.Slug, sub.Title)
		}
		b.WriteString("\n")
	}

	if len(t.Issues) > 0 {
		b.WriteString("## Doctor\n\n")
		for _, issue := range t.Issues {
			fmt.Fprintf(&b, "- **%s** `%s` — %s\n", issue.Severity, issue.Code, issue.Message)
		}
		b.WriteString("\n")
	}

	if len(t.Files) > 0 {
		b.WriteString("## Files\n\n")
		for _, f := range t.Files {
			fmt.Fprintf(&b, "- `%s`\n", f.Name)
		}
	}
	return b.String()
}

func sessionMarkdown(s *journal.Session, full bool) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n", s.Name)
	date := s.Date
	if !s.DateParsed.IsZero() {
		date = s.DateParsed.Format("2006-01-02")
	}
	fmt.Fprintf(&b, "**%s** · %s · `%s`\n\n", orDefault(s.Harness, "?"), date, s.RelDir)
	if !s.LastTouched.IsZero() {
		fmt.Fprintf(&b, "Last touched: %s\n\n", s.LastTouched.Format("2006-01-02 15:04"))
	}

	if len(s.Boards) == 0 {
		b.WriteString("## Boards\n\n_No boards._\n\n")
	} else {
		b.WriteString("## Main board\n\n")
		boardMarkdown(&b, s.Boards[0], full)
		if len(s.Boards) > 1 {
			b.WriteString("## Tracks\n\n")
			for _, track := range s.Boards[1:] {
				c := track.Counts()
				fmt.Fprintf(&b, "- **%s** — %s [%s] — %d open, %d done",
					baseName(track.Path), track.Title, track.Status, c.Open, c.Done)
				if c.Blocked > 0 {
					fmt.Fprintf(&b, ", %d blocked", c.Blocked)
				}
				b.WriteString("\n")
			}
			b.WriteString("\n")
		}
	}

	if s.Worklog != nil {
		b.WriteString("## Worklog\n\n")
		worklogMarkdown(&b, s.Worklog, full)
	}

	if len(s.TaskRefs) > 0 {
		b.WriteString("## Task references\n\n")
		for _, ref := range s.TaskRefs {
			fmt.Fprintf(&b, "- `%s`\n", ref)
		}
		b.WriteString("\n")
	}

	if len(s.Issues) > 0 {
		b.WriteString("## Doctor\n\n")
		for _, issue := range s.Issues {
			fmt.Fprintf(&b, "- **%s** `%s` — %s\n", issue.Severity, issue.Code, issue.Message)
		}
	}
	return b.String()
}

func boardMarkdown(b *strings.Builder, data *board.Board, full bool) {
	c := data.Counts()
	fmt.Fprintf(b, "_%s · %d open, %d done, %d blocked, %d dropped_\n\n",
		data.Status, c.Open, c.Done, c.Blocked, c.Dropped)
	for _, section := range data.Sections {
		if len(section.Items) == 0 && len(section.Prose) == 0 {
			continue
		}
		title := section.Title
		if title == "" {
			title = "Items"
		}
		fmt.Fprintf(b, "### %s\n\n", title)
		limit := len(section.Items)
		if !full && limit > previewItems {
			limit = previewItems
		}
		for i := 0; i < limit; i++ {
			b.WriteString(itemMarkdown(section.Items[i]))
			b.WriteString("\n")
		}
		if limit < len(section.Items) {
			fmt.Fprintf(b, "- … +%d more\n", len(section.Items)-limit)
		}
		b.WriteString("\n")
	}
}

func itemMarkdown(item board.Item) string {
	indent := strings.Repeat("  ", item.Depth)
	text := strings.TrimSpace(item.Text)
	switch {
	case item.Done:
		return indent + "- [x] " + text
	case item.Blocked:
		return indent + "- " + text + " — **blocked**"
	case item.Dropped:
		return indent + "- ~~" + text + "~~"
	case item.Checkbox:
		return indent + "- [ ] " + text
	case item.State != "":
		return indent + "- " + text + " — " + item.State
	default:
		return indent + "- " + text
	}
}

func worklogMarkdown(b *strings.Builder, w *worklog.Worklog, full bool) {
	limit := previewHeadings
	if full {
		limit = fullHeadings
	}
	for _, entry := range w.Tail(limit) {
		fmt.Fprintf(b, "### %s\n\n", entry.Heading)
		if full && entry.Body != "" {
			b.WriteString(entry.Body)
			b.WriteString("\n\n")
		}
	}
	if len(w.Entries) > limit {
		fmt.Fprintf(b, "_… +%d more entries_\n\n", len(w.Entries)-limit)
	}
}

func renderMarkdown(markdown string, width int) string {
	if width < 20 {
		width = 20
	}
	renderer, err := glamour.NewTermRenderer(
		glamour.WithStandardStyle("dark"),
		glamour.WithWordWrap(width-2),
	)
	if err != nil {
		return markdown
	}
	out, err := renderer.Render(markdown)
	if err != nil {
		return markdown
	}
	return strings.Trim(out, "\n")
}

func baseName(path string) string {
	if idx := strings.LastIndexByte(path, '/'); idx >= 0 {
		return path[idx+1:]
	}
	return path
}

func orDefault(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
