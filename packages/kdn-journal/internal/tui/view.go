package tui

import (
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"

	"kdn-journal/internal/board"
	"kdn-journal/internal/journal"
	"kdn-journal/internal/task"
	"kdn-journal/internal/worklog"
)

// previewItems and previewHeadings cap the right pane before `enter` opens the full-pane detail.
const (
	previewItems    = 4
	previewHeadings = 5
)

var (
	styleTitle   = lipgloss.NewStyle().Bold(true)
	styleTabOn   = lipgloss.NewStyle().Bold(true).Reverse(true)
	styleTabOff  = lipgloss.NewStyle().Faint(true)
	styleDim     = lipgloss.NewStyle().Faint(true)
	styleStatus  = lipgloss.NewStyle().Faint(true).Italic(true)
	styleCursor  = lipgloss.NewStyle().Reverse(true)
	styleSection = lipgloss.NewStyle().Bold(true)
)

// View renders the whole screen.
func (m Model) View() string {
	if m.width <= 0 || m.height <= 0 {
		return ""
	}
	lines := make([]string, 0, m.height)
	lines = append(lines, m.headerLine())
	lines = append(lines, m.bodyLines()...)
	if m.status != "" {
		lines = append(lines, styleStatus.Render(trunc(m.status, m.width)))
	}
	lines = append(lines, m.footerLine())
	if len(lines) > m.height {
		lines = lines[:m.height]
	}
	for len(lines) < m.height {
		lines = append(lines, "")
	}
	return strings.Join(lines, "\n")
}

// headerLine is the repository root plus the tab bar.
func (m Model) headerLine() string {
	tabs := m.tabBar()
	tabWidth := lipgloss.Width(tabs)
	left := styleTitle.Render("kdn-journal")
	if root := m.root; root != "" && tabWidth+len("kdn-journal  ")+4 < m.width {
		left += "  " + styleDim.Render(trunc(root, m.width-tabWidth-len("kdn-journal  ")-1))
	}
	gap := m.width - lipgloss.Width(left) - tabWidth
	if gap < 1 {
		return fit(trunc("kdn-journal  Tasks | Sessions", m.width), m.width)
	}
	return fit(left+strings.Repeat(" ", gap)+tabs, m.width)
}

func (m Model) tabBar() string {
	tasks, sessions := "Tasks", "Sessions"
	if m.tab == TabTasks {
		tasks = styleTabOn.Render(" Tasks ")
		sessions = styleTabOff.Render(sessions)
	} else {
		tasks = styleTabOff.Render(tasks)
		sessions = styleTabOn.Render(" Sessions ")
	}
	return tasks + styleDim.Render(" │ ") + sessions
}

// footerLine is the key help, or the filter prompt while filtering.
func (m Model) footerLine() string {
	if m.filterMode {
		hint := "  enter apply  esc cancel  ⌫ erase"
		plain := "/" + m.filter + "▏" + hint
		return styleDim.Render(trunc(plain, m.width))
	}
	var keys string
	if m.fullDetail {
		keys = "esc back  j/k scroll  g/G ends  e edit  r refresh  q quit"
	} else {
		keys = "j/k move  enter detail  tab switch  / filter  e edit  r refresh  q quit"
	}
	if m.filter != "" {
		keys = fmt.Sprintf("filter %q  ", m.filter) + keys
	}
	return styleDim.Render(trunc(keys, m.width))
}

// bodyHeight is the number of rows between the header and the footer.
func (m Model) bodyHeight() int {
	height := m.height - 2
	if m.status != "" {
		height--
	}
	if height < 1 {
		height = 1
	}
	return height
}

// leftWidth is the width of the list pane.
func (m Model) leftWidth() int {
	width := m.width / 3
	if width < 20 {
		width = 20
	}
	if width > 44 {
		width = 44
	}
	if width > m.width-8 {
		width = m.width - 8
	}
	if width < 1 {
		width = 1
	}
	return width
}

// paneWidth is the width available to the detail view.
func (m Model) paneWidth() int {
	if m.fullDetail {
		return m.width
	}
	width := m.width - m.leftWidth() - 1
	if width < 1 {
		width = 1
	}
	return width
}

func (m Model) bodyLines() []string {
	height := m.bodyHeight()
	if m.fullDetail {
		return windowLines(m.detailForPane(m.paneWidth()), m.detailScroll, height)
	}
	leftWidth := m.leftWidth()
	rightWidth := m.paneWidth()
	left := windowLines(m.listLines(leftWidth), m.listOffset, height)
	right := windowLines(m.detailForPane(rightWidth), m.detailScroll, height)
	rows := make([]string, height)
	for i := 0; i < height; i++ {
		cell := strings.Repeat(" ", leftWidth)
		if i < len(left) && left[i] != "" {
			cell = fit(left[i], leftWidth)
		}
		detail := ""
		if i < len(right) {
			detail = right[i]
		}
		rows[i] = fit(cell+"│"+detail, m.width)
	}
	return rows
}

// listLines renders one row per visible entry.
func (m Model) listLines(width int) []string {
	rows := make([]string, 0, m.listLen())
	contentWidth := width - 2
	if contentWidth < 1 {
		contentWidth = 1
	}
	if m.tab == TabSessions {
		for i, session := range m.sessions {
			rows = append(rows, m.listRow(i, width, sessionRow(session, contentWidth)))
		}
	} else {
		for i, t := range m.tasks {
			rows = append(rows, m.listRow(i, width, taskRow(t)))
		}
	}
	if len(rows) == 0 {
		rows = append(rows, styleDim.Render(trunc("  no entries", width)))
	}
	return rows
}

func (m Model) listRow(index, width int, text string) string {
	marker := "  "
	if index == m.cursor {
		marker = "▸ "
	}
	line := fit(trunc(marker+text, width), width)
	if index == m.cursor {
		return styleCursor.Render(line)
	}
	return line
}

func taskRow(t *task.Task) string {
	row := fmt.Sprintf("[%s] %s %s", statusOr(t.Status), monthOr(t.Month), t.Slug)
	if t.Description != "" {
		row += "  " + t.Description
	}
	return row
}

func sessionRow(s *journal.Session, width int) string {
	date := "--------"
	if len(s.Date) == 8 {
		date = s.Date[0:4] + "-" + s.Date[4:6] + "-" + s.Date[6:8]
	} else if s.Date != "" {
		date = s.Date
	}
	harness := s.Harness
	if harness == "" {
		harness = "?"
	}
	left := fmt.Sprintf("%s %s %s", date, harness, s.ID)
	count := fmt.Sprintf("%d boards", len(s.Boards))
	leftWidth := width - lipgloss.Width(count) - 1
	if leftWidth < 8 {
		return trunc(left+"  "+count, width)
	}
	trimmed := trunc(left, leftWidth)
	return trimmed + strings.Repeat(" ", leftWidth-lipgloss.Width(trimmed)+1) + count
}

func entryCount(n int) string {
	if n == 1 {
		return "1 entry"
	}
	return fmt.Sprintf("%d entries", n)
}

func (m Model) detailForPane(width int) []string {
	if width < 8 {
		width = 8
	}
	if m.tab == TabSessions {
		return m.sessionDetail(m.selectedSession(), width)
	}
	return m.taskDetail(m.selectedTask(), width)
}

func (m Model) itemCap() int {
	if m.fullDetail {
		return 0
	}
	return previewItems
}

func (m Model) headingCap() int {
	if m.fullDetail {
		return 0
	}
	return previewHeadings
}

func (m Model) taskDetail(t *task.Task, width int) []string {
	b := &detailBuilder{width: width}
	if t == nil {
		b.add("")
		b.add("  no task selected")
		return b.lines
	}
	b.add(t.RelDir)
	if t.Title != "" {
		b.wrapped(t.Title, 0)
	}
	if t.Description != "" && t.Description != t.Title {
		b.wrapped(t.Description, 0)
	}
	b.gap()
	b.add(fmt.Sprintf("%s · %s · last activity %s",
		statusOr(t.Status), monthOr(t.Month), relTime(t.LastActivity)))
	b.add(fmt.Sprintf("items  open %d · done %d · blocked %d · dropped %d",
		t.OpenItems, t.DoneItems, t.BlockedItems, t.DroppedItems))
	if t.Board != nil {
		b.gap()
		b.section("board", fmt.Sprintf("%s [%s]", t.Board.Title, t.Board.Status))
		b.boardSections(t.Board, m.itemCap())
	}
	if t.Worklog != nil && len(t.Worklog.Entries) > 0 {
		b.gap()
		b.section("worklog", entryCount(len(t.Worklog.Entries)))
		b.worklogHeadings(t.Worklog, m.headingCap())
	}
	if len(t.Subtasks) > 0 {
		b.gap()
		b.section("subtasks", fmt.Sprintf("%d", len(t.Subtasks)))
		cap := m.itemCap()
		for i, sub := range t.Subtasks {
			if cap > 0 && i >= cap {
				b.add(fmt.Sprintf("  … +%d more", len(t.Subtasks)-cap))
				break
			}
			b.add(fmt.Sprintf("  - %s  %s", sub.Slug, statusOr(sub.Status)))
		}
	}
	if len(t.Files) > 0 {
		b.gap()
		names := make([]string, 0, len(t.Files))
		for _, file := range t.Files {
			names = append(names, file.Name)
		}
		b.section("files", fmt.Sprintf("%d", len(names)))
		b.wrapped(strings.Join(names, "  "), 2)
	}
	return b.lines
}

func (m Model) sessionDetail(s *journal.Session, width int) []string {
	b := &detailBuilder{width: width}
	if s == nil {
		b.add("")
		b.add("  no session selected")
		return b.lines
	}
	b.add(s.RelDir)
	b.add(fmt.Sprintf("touched %s · %d boards", relTime(s.LastTouched), len(s.Boards)))
	if s.Worklog != nil {
		b.add(entryCount(len(s.Worklog.Entries)) + " in worklog.md")
	}
	if len(s.TaskRefs) > 0 {
		b.wrapped("tasks: "+strings.Join(s.TaskRefs, ", "), 0)
	}
	if len(s.Boards) == 0 {
		b.gap()
		b.add("  no boards")
	} else {
		main := s.Boards[0]
		b.gap()
		b.section("main board", fmt.Sprintf("%s [%s]", main.Title, main.Status))
		b.boardSections(main, m.itemCap())
		if tracks := s.Boards[1:]; len(tracks) > 0 {
			b.gap()
			b.section("tracks", fmt.Sprintf("%d", len(tracks)))
			cap := m.itemCap()
			for i, track := range tracks {
				if cap > 0 && i >= cap {
					b.add(fmt.Sprintf("  … +%d more", len(tracks)-cap))
					break
				}
				counts := track.Counts()
				b.add(fmt.Sprintf("  %s [%s]  open %d · blocked %d · done %d",
					filepath.Base(track.Path), track.Status, counts.Open, counts.Blocked, counts.Done))
			}
		}
	}
	if s.Worklog != nil && len(s.Worklog.Entries) > 0 {
		b.gap()
		b.section("worklog", entryCount(len(s.Worklog.Entries)))
		b.worklogHeadings(s.Worklog, m.headingCap())
	}
	for _, track := range s.TrackWorklogs {
		if track == nil || len(track.Entries) == 0 {
			continue
		}
		b.gap()
		b.section("worklog "+filepath.Base(track.Path), entryCount(len(track.Entries)))
		b.worklogHeadings(track, m.headingCap())
	}
	return b.lines
}

// detailBuilder accumulates width-limited lines for one pane.
type detailBuilder struct {
	width int
	lines []string
}

func (b *detailBuilder) add(text string) {
	for _, line := range strings.Split(text, "\n") {
		b.lines = append(b.lines, trunc(line, b.width))
	}
}

func (b *detailBuilder) gap() { b.lines = append(b.lines, "") }

func (b *detailBuilder) wrapped(text string, indent int) {
	if strings.TrimSpace(text) == "" {
		return
	}
	for _, line := range wrapIndent(text, indent, b.width) {
		b.lines = append(b.lines, trunc(line, b.width))
	}
}

func (b *detailBuilder) section(label, rest string) {
	line := strings.ToUpper(label)
	if rest != "" {
		line += "  " + rest
	}
	b.lines = append(b.lines, styleSection.Render(trunc(line, b.width)))
}

func (b *detailBuilder) boardSections(src *board.Board, limit int) {
	for _, kind := range []board.Kind{board.KindNow, board.KindNext, board.KindBlocked} {
		items := src.Items(kind)
		if len(items) == 0 {
			continue
		}
		b.add("  " + strings.ToUpper(string(kind)))
		for i, item := range items {
			if limit > 0 && i >= limit {
				b.add(fmt.Sprintf("    … +%d more", len(items)-limit))
				break
			}
			b.wrapped(itemMark(item)+strings.TrimSpace(item.Text), 4)
		}
	}
}

func (b *detailBuilder) worklogHeadings(src *worklog.Worklog, limit int) {
	entries := src.Entries
	start := 0
	if limit > 0 && len(entries) > limit {
		start = len(entries) - limit
	}
	for _, entry := range entries[start:] {
		stamp := "—"
		if entry.HasTimestamp {
			stamp = entry.Timestamp.Format("2006-01-02 15:04")
		}
		b.add("  " + stamp + "  " + entry.Heading)
	}
}

func itemMark(item board.Item) string {
	switch {
	case item.Done:
		return "✓ "
	case item.Blocked:
		return "✗ "
	case item.Dropped:
		return "– "
	default:
		return "· "
	}
}

func statusOr(status string) string {
	if status = strings.TrimSpace(status); status == "" {
		return "no-status"
	}
	return status
}

func monthOr(month string) string {
	if month = strings.TrimSpace(month); month == "" {
		return "-------"
	}
	return month
}

func relTime(at time.Time) string {
	if at.IsZero() {
		return "unknown"
	}
	diff := time.Since(at)
	if diff < 0 {
		diff = -diff
	}
	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		return fmt.Sprintf("%dm ago", int(diff.Minutes()))
	case diff < 24*time.Hour:
		return fmt.Sprintf("%dh ago", int(diff.Hours()))
	default:
		return fmt.Sprintf("%dd ago", int(diff.Hours()/24))
	}
}

// windowLines returns exactly height lines starting at offset, clamped to the content.
func windowLines(lines []string, offset, height int) []string {
	out := make([]string, 0, height)
	if height <= 0 {
		return out
	}
	limit := len(lines) - height
	if limit < 0 {
		limit = 0
	}
	if offset > limit {
		offset = limit
	}
	if offset < 0 {
		offset = 0
	}
	for i := 0; i < height; i++ {
		if index := offset + i; index < len(lines) {
			out = append(out, lines[index])
		} else {
			out = append(out, "")
		}
	}
	return out
}

// wrapIndent word-wraps text to the width, prefixing every line with indent spaces.
func wrapIndent(text string, indent, width int) []string {
	available := width - indent
	if available < 10 {
		available = 10
	}
	words := strings.Fields(text)
	if len(words) == 0 {
		return nil
	}
	var chunks []string
	current := ""
	for _, word := range words {
		switch {
		case current == "":
			current = word
		case lipgloss.Width(current)+1+lipgloss.Width(word) <= available:
			current += " " + word
		default:
			chunks = append(chunks, current)
			current = word
		}
	}
	chunks = append(chunks, current)
	pad := strings.Repeat(" ", indent)
	out := make([]string, len(chunks))
	for i, chunk := range chunks {
		out[i] = pad + chunk
	}
	return out
}

// fit pads a rendered line to width with trailing spaces.
func fit(line string, width int) string {
	if pad := width - lipgloss.Width(line); pad > 0 {
		return line + strings.Repeat(" ", pad)
	}
	return line
}

// trunc shortens a plain (unstyled) string to width, appending a tail ellipsis.
func trunc(text string, width int) string {
	if width <= 0 {
		return ""
	}
	if lipgloss.Width(text) <= width {
		return text
	}
	runes := []rune(text)
	for len(runes) > 0 {
		runes = runes[:len(runes)-1]
		if lipgloss.Width(string(runes)) <= width-1 {
			return string(runes) + "…"
		}
	}
	return ""
}

func lowerTrim(text string) string { return strings.ToLower(strings.TrimSpace(text)) }

func trimSpace(text string) string { return strings.TrimSpace(text) }

func containsFold(haystack, needle string) bool {
	return strings.Contains(strings.ToLower(haystack), strings.ToLower(needle))
}

func taskHaystack(t *task.Task) string {
	return strings.Join([]string{t.Status, t.Month, t.Slug, t.Title, t.Description, t.RelDir}, " ")
}

func sessionHaystack(s *journal.Session) string {
	parts := []string{s.Date, s.Harness, s.ID, s.Name, s.RelDir}
	for _, b := range s.Boards {
		parts = append(parts, b.Title)
	}
	parts = append(parts, s.TaskRefs...)
	return strings.Join(parts, " ")
}
