// Package render formats task and journal models for the terminal. Every line is truncated to
// the requested width, and summary output is capped so one screen stays one screen.
package render

import (
	"fmt"
	"io"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"kdn-journal/internal/board"
	"kdn-journal/internal/journal"
	"kdn-journal/internal/task"
	"kdn-journal/internal/worklog"
)

// Options controls the text renderer.
type Options struct {
	Width    int
	Full     bool
	Color    bool
	Items    int
	Tail     int
	Now      time.Time
	RunCount int
	// ShowAtuin adds the Atuin Thread link (UUID and message count) to a summary line.
	ShowAtuin bool
}

// Defaults fills the renderer defaults.
func Defaults(o Options) Options {
	if o.Width <= 0 {
		o.Width = 100
	}
	if o.Items <= 0 {
		o.Items = 3
	}
	if o.Tail <= 0 {
		o.Tail = 5
	}
	if o.Now.IsZero() {
		o.Now = time.Now()
	}
	return o
}

var datePrefixRE = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}(?:T[^\s]+)?\s*(?:—|–|-|:)?\s*`)

const (
	ansiReset  = "\x1b[0m"
	ansiBold   = "\x1b[1m"
	ansiRed    = "\x1b[31m"
	ansiGreen  = "\x1b[32m"
	ansiYellow = "\x1b[33m"
)

func paint(s, code string, enabled bool) string {
	if !enabled || code == "" {
		return s
	}
	return code + s + ansiReset
}

func statusPaint(status string, enabled bool) string {
	code := ansiYellow
	switch status {
	case "done", "active", "in-progress":
		code = ansiGreen
	case "blocked":
		code = ansiRed
	}
	return paint("["+status+"]", code, enabled)
}

// Summary writes the one-screen session and optional task summary.
func Summary(w io.Writer, o Options, s *journal.Session, t *task.Task) error {
	o = Defaults(o)
	if s == nil {
		return fmt.Errorf("no session selected")
	}
	lines := []string{}
	header := paint("SESSION", ansiBold, o.Color) + "  " + s.Name
	if !s.DateParsed.IsZero() {
		header += "  (" + s.DateParsed.Format("2006-01-02") + ", touched " + relTime(o.Now, s.LastTouched) + ")"
	}
	if o.RunCount > 1 {
		header += fmt.Sprintf("  (1 of %d runs)", o.RunCount)
	}
	lines = append(lines, header)
	if o.ShowAtuin {
		lines = append(lines, atuinLine(s))
	}
	if len(s.Boards) == 0 {
		lines = append(lines, "  no boards")
	} else {
		main := s.Boards[0]
		lines = append(lines, "  "+filepath.Base(main.Path)+"  "+main.Title+"  "+statusPaint(main.Status, o.Color))
		lines = appendSection(lines, "now", main.Items(board.KindNow), o)
		lines = appendSection(lines, "next", main.Items(board.KindNext), o)
		lines = appendSection(lines, "blocked", main.Items(board.KindBlocked), o)
		if len(s.Boards) > 1 {
			lines = append(lines, fmt.Sprintf("  tracks   %d", len(s.Boards)-1))
			for _, b := range s.Boards[1:] {
				lines = append(lines, "    "+truncate(trackLine(b, o), o.Width-4))
			}
		}
	}
	if s.Worklog != nil {
		lines = append(lines, fmt.Sprintf("WORKLOG  %s, last %d:", plural(len(s.Worklog.Entries), "entry", "entries"), min(o.Tail, len(s.Worklog.Entries))))
		for _, entry := range s.Worklog.Tail(o.Tail) {
			lines = append(lines, "  "+truncate(worklogLine(entry), o.Width-2))
		}
	}
	if t != nil {
		lines = append(lines, "TASK     "+t.RelDir+"  "+statusPaint(t.Status, o.Color))
		if t.Board == nil {
			lines = append(lines, "  board    none")
		} else {
			c := t.Board.Counts()
			lines = append(lines, fmt.Sprintf("  board    %d open, %d done, %d blocked", c.Open, c.Done, c.Blocked))
			lines = appendSection(lines, "now", t.Board.Items(board.KindNow), o)
			lines = appendSection(lines, "next", t.Board.Items(board.KindNext), o)
			lines = appendSection(lines, "blocked", t.Board.Items(board.KindBlocked), o)
		}
	}
	return writeCapped(w, lines, o.Width, 24, o.Full)
}

// Sessions writes the session list.
func Sessions(w io.Writer, o Options, sessions []*journal.Session, limit int) error {
	o = Defaults(o)
	lines := []string{fmt.Sprintf("SESSIONS  %d", len(sessions))}
	shown := 0
	for _, s := range sessions {
		if !o.Full && limit > 0 && shown >= limit {
			break
		}
		shown++
		lines = append(lines, "  "+truncate(sessionLine(s, o), o.Width-2))
	}
	if !o.Full && limit > 0 && len(sessions) > limit {
		lines = append(lines, fmt.Sprintf("  … +%d more", len(sessions)-limit))
	}
	return writeLines(w, lines, o.Width)
}

// Tasks writes the task list.
func Tasks(w io.Writer, o Options, tasks []*task.Task, tree bool, limit int) error {
	o = Defaults(o)
	open, inProgress, done, other := 0, 0, 0, 0
	for _, t := range tasks {
		switch t.Status {
		case "open":
			open++
		case "in-progress", "active":
			inProgress++
		case "done":
			done++
		default:
			other++
		}
	}
	lines := []string{fmt.Sprintf("TASKS  %d  (%d open, %d in-progress, %d done, %d other)", len(tasks), open, inProgress, done, other)}
	shown := 0
	for _, t := range tasks {
		if !o.Full && limit > 0 && shown >= limit {
			break
		}
		shown++
		indent := ""
		if tree {
			indent = strings.Repeat("  ", t.Depth)
		}
		lines = append(lines, "  "+indent+truncate(taskLine(t, o), o.Width-2-utf8.RuneCountInString(indent)))
		lines = append(lines, "    "+indent+truncate(taskDetailLine(t, o), o.Width-4-utf8.RuneCountInString(indent)))
	}
	if !o.Full && limit > 0 && len(tasks) > limit {
		lines = append(lines, fmt.Sprintf("  … +%d more", len(tasks)-limit))
	}
	return writeLines(w, lines, o.Width)
}

// Task writes one task detail block.
func Task(w io.Writer, o Options, t *task.Task) error {
	o = Defaults(o)
	lines := []string{paint("TASK", ansiBold, o.Color) + "  " + t.Slug + "  " + statusPaint(t.Status, o.Color)}
	lines = append(lines, "  path     "+t.RelDir)
	if t.Description != "" {
		lines = append(lines, "  about    "+truncate(t.Description, o.Width-11))
	}
	if !t.Timestamp.IsZero() {
		lines = append(lines, "  started  "+t.Timestamp.Format("2006-01-02 15:04"))
	}
	if !t.LastActivity.IsZero() {
		lines = append(lines, "  active   "+relTime(o.Now, t.LastActivity))
	}
	files := make([]string, 0, len(t.Files))
	for _, f := range t.Files {
		files = append(files, f.Name)
	}
	if len(files) > 0 {
		lines = append(lines, "  files    "+truncate(strings.Join(files, ", "), o.Width-11))
	}
	if t.Board == nil {
		lines = append(lines, "  board    none")
	} else {
		c := t.Board.Counts()
		lines = append(lines, fmt.Sprintf("  board    %s  %d open, %d done, %d blocked", t.Board.Status, c.Open, c.Done, c.Blocked))
		for _, sec := range t.Board.Sections {
			if len(sec.Items) == 0 {
				continue
			}
			lines = append(lines, "  "+strings.ToLower(sec.Title))
			for _, item := range sec.Items {
				lines = append(lines, "    "+truncate(itemLine(item), o.Width-4))
			}
		}
	}
	if t.Worklog != nil {
		lines = append(lines, fmt.Sprintf("  worklog  %s", plural(len(t.Worklog.Entries), "entry", "entries")))
		for _, entry := range t.Worklog.Tail(o.Tail) {
			lines = append(lines, "    "+truncate(worklogLine(entry), o.Width-4))
		}
	}
	if len(t.Subtasks) > 0 {
		lines = append(lines, fmt.Sprintf("  subtasks %d", len(t.Subtasks)))
		for _, sub := range t.Subtasks {
			lines = append(lines, "    "+sub.Status+"  "+sub.Slug)
		}
	}
	return writeLines(w, lines, o.Width)
}

// Board writes one board detail block.
func Board(w io.Writer, o Options, b *board.Board) error {
	o = Defaults(o)
	c := b.Counts()
	lines := []string{paint("BOARD", ansiBold, o.Color) + "  " + b.Title + "  " + statusPaint(b.Status, o.Color)}
	lines = append(lines, fmt.Sprintf("  %d open, %d done, %d blocked, %d dropped", c.Open, c.Done, c.Blocked, c.Dropped))
	if !b.Updated.IsZero() {
		lines = append(lines, "  updated  "+b.Updated.Format("2006-01-02 15:04"))
	}
	for _, sec := range b.Sections {
		if len(sec.Items) == 0 && len(sec.Prose) == 0 {
			continue
		}
		lines = append(lines, "  "+sec.Title)
		for _, item := range sec.Items {
			lines = append(lines, "    "+truncate(itemLine(item), o.Width-4))
		}
	}
	return writeLines(w, lines, o.Width)
}

// Worklog writes one worklog detail block.
func Worklog(w io.Writer, o Options, wl *worklog.Worklog, tail int) error {
	o = Defaults(o)
	lines := []string{fmt.Sprintf("WORKLOG  %s", plural(len(wl.Entries), "entry", "entries"))}
	for _, entry := range wl.Tail(tail) {
		lines = append(lines, "  "+truncate(worklogLine(entry), o.Width-2))
		if entry.Body != "" && o.Full {
			for _, line := range strings.Split(entry.Body, "\n") {
				lines = append(lines, "    "+truncate(line, o.Width-4))
			}
		}
	}
	return writeLines(w, lines, o.Width)
}

// Doctor writes the issue list.
func Doctor(w io.Writer, o Options, issues []task.Issue) error {
	o = Defaults(o)
	errors, warnings := 0, 0
	for _, issue := range issues {
		if issue.Severity == "error" {
			errors++
		} else {
			warnings++
		}
	}
	lines := []string{fmt.Sprintf("DOCTOR  %d errors, %d warnings", errors, warnings)}
	if len(issues) == 0 {
		lines = append(lines, "  clean")
	}
	for _, issue := range issues {
		label := strings.ToUpper(issue.Severity)
		code := ansiYellow
		if issue.Severity == "error" {
			code = ansiRed
		}
		lines = append(lines, "  "+paint(label, code, o.Color)+"  "+issue.Code+"  "+issue.Path+"  "+issue.Message)
	}
	return writeLines(w, lines, o.Width)
}

func appendSection(lines []string, label string, items []board.Item, o Options) []string {
	if len(items) == 0 {
		return lines
	}
	parts := make([]string, 0, o.Items+1)
	for i, item := range items {
		if i >= o.Items {
			break
		}
		parts = append(parts, itemLine(item))
	}
	if len(items) > o.Items {
		parts = append(parts, fmt.Sprintf("(+%d more)", len(items)-o.Items))
	}
	return append(lines, "    "+fmt.Sprintf("%-8s", label)+" "+strings.Join(parts, "  "))
}

func itemLine(item board.Item) string {
	prefix := ""
	switch {
	case item.Done:
		prefix = "[x] "
	case item.Blocked:
		prefix = "[!] "
	case item.Dropped:
		prefix = "[~] "
	case item.Checkbox:
		prefix = "[ ] "
	}
	text := oneLine(item.Text)
	if item.State != "" && !item.Checkbox && !item.Done && !item.Blocked && !item.Dropped {
		return text + " — " + oneLine(item.State)
	}
	return prefix + text
}

func trackLine(b *board.Board, o Options) string {
	c := b.Counts()
	line := filepath.Base(b.Path) + "  " + b.Title + "  " + statusPaint(b.Status, o.Color)
	if c.Open+c.Done+c.Blocked+c.Dropped > 0 {
		line += fmt.Sprintf("  %d open, %d done", c.Open, c.Done)
		if c.Blocked > 0 {
			line += fmt.Sprintf(", %d blocked", c.Blocked)
		}
	}
	if next, ok := firstItem(b, board.KindNext); ok {
		line += "  next: " + oneLine(next.Text)
	}
	return line
}

func firstItem(b *board.Board, kind board.Kind) (board.Item, bool) {
	for _, item := range b.Items(kind) {
		if !item.Done && !item.Dropped {
			return item, true
		}
	}
	return board.Item{}, false
}

func sessionLine(s *journal.Session, o Options) string {
	date := s.Date
	if !s.DateParsed.IsZero() {
		date = s.DateParsed.Format("2006-01-02")
	}
	boards := len(s.Boards)
	entries := 0
	if s.Worklog != nil {
		entries = len(s.Worklog.Entries)
	}
	refs := len(s.TaskRefs)
	line := fmt.Sprintf("%s  %-8s  %-48s  %-10s  %s  %s  %s",
		date, s.Harness, truncateMiddle(s.ID, 48), relTime(o.Now, s.LastTouched),
		plural(boards, "board", "boards"), plural(entries, "log entry", "log entries"), plural(refs, "task", "tasks"))
	if o.ShowAtuin {
		if s.Sidecar != nil && s.Sidecar.Atuin.ThreadID != "" {
			line += "  atuin:" + s.Sidecar.Atuin.ThreadID
		} else {
			line += "  atuin:not-linked"
		}
	}
	return line
}

// atuinLine renders the sidecar's Atuin Thread link. It stays local: no Atuin CLI call, so the
// summary keeps working when Atuin is missing or capture is off.
func atuinLine(s *journal.Session) string {
	if s.Sidecar == nil || s.Sidecar.Atuin.ThreadID == "" {
		return "ATUIN    not linked"
	}
	a := s.Sidecar.Atuin
	line := "ATUIN    " + a.ThreadID
	if a.MessageCount > 0 {
		line += "  " + plural(a.MessageCount, "message", "messages")
	}
	if a.Model != "" {
		line += "  " + a.Model
	}
	return line
}

func taskLine(t *task.Task, o Options) string {
	parts := []string{statusPaint(t.Status, o.Color)}
	if t.Depth == 0 {
		parts = append(parts, t.Month)
	}
	parts = append(parts, t.Slug, oneLine(t.Description))
	return strings.Join(parts, "  ")
}

func taskDetailLine(t *task.Task, o Options) string {
	return fmt.Sprintf("%s  last %s  %d open, %d blocked", t.RelDir, relTime(o.Now, t.LastActivity), t.OpenItems, t.BlockedItems)
}

func worklogLine(entry worklog.Entry) string {
	ts := "—"
	if entry.HasTimestamp {
		if entry.Precise {
			ts = entry.Timestamp.Format("2006-01-02T15:04:05Z07:00")
		} else {
			ts = entry.Timestamp.Format("2006-01-02")
		}
	}
	heading := datePrefixRE.ReplaceAllString(entry.Heading, "")
	heading = strings.TrimLeft(heading, " —–-:")
	return ts + "  " + oneLine(heading)
}

func relTime(now, t time.Time) string {
	if t.IsZero() {
		return "unknown"
	}
	diff := now.Sub(t)
	if diff < 0 {
		return "just now"
	}
	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		return fmt.Sprintf("%dm ago", int(diff.Minutes()))
	case diff < 24*time.Hour:
		return fmt.Sprintf("%dh ago", int(diff.Hours()))
	case diff < 30*24*time.Hour:
		return fmt.Sprintf("%dd ago", int(diff.Hours()/24))
	default:
		return t.Format("2006-01-02")
	}
}

func oneLine(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

func truncate(s string, width int) string {
	s = strings.ReplaceAll(s, "\n", " ")
	if width <= 0 {
		return s
	}
	if visibleLen(s) <= width {
		return s
	}
	if width == 1 {
		return "…"
	}
	var out strings.Builder
	count := 0
	hadANSI := false
	for i := 0; i < len(s); {
		if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '[' {
			j := i + 2
			for j < len(s) && s[j] != 'm' {
				j++
			}
			if j < len(s) {
				out.WriteString(s[i : j+1])
				hadANSI = true
				i = j + 1
				continue
			}
		}
		r, size := utf8.DecodeRuneInString(s[i:])
		if count >= width-1 {
			break
		}
		out.WriteRune(r)
		count++
		i += size
	}
	out.WriteString("…")
	if hadANSI {
		out.WriteString(ansiReset)
	}
	return out.String()
}

func visibleLen(s string) int {
	count := 0
	for i := 0; i < len(s); {
		if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '[' {
			j := i + 2
			for j < len(s) && s[j] != 'm' {
				j++
			}
			if j < len(s) {
				i = j + 1
				continue
			}
		}
		_, size := utf8.DecodeRuneInString(s[i:])
		count++
		i += size
	}
	return count
}

func truncateMiddle(s string, width int) string {
	if width <= 0 || utf8.RuneCountInString(s) <= width {
		return s
	}
	runes := []rune(s)
	if width < 5 {
		return string(runes[:width])
	}
	left := (width - 1) / 2
	right := width - 1 - left
	return string(runes[:left]) + "…" + string(runes[len(runes)-right:])
}

func writeCapped(w io.Writer, lines []string, width, max int, full bool) error {
	if !full && len(lines) > max {
		remaining := len(lines) - max + 1
		lines = append(lines[:max-1], fmt.Sprintf("… +%d more", remaining))
	}
	return writeLines(w, lines, width)
}

func writeLines(w io.Writer, lines []string, width int) error {
	for _, line := range lines {
		if _, err := fmt.Fprintln(w, truncate(line, width)); err != nil {
			return err
		}
	}
	return nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func plural(n int, singular, pluralForm string) string {
	if n == 1 {
		return fmt.Sprintf("%d %s", n, singular)
	}
	return fmt.Sprintf("%d %s", n, pluralForm)
}
