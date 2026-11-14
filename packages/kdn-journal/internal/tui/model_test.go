package tui

import (
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"kdn-journal/internal/board"
	"kdn-journal/internal/journal"
	"kdn-journal/internal/task"
	"kdn-journal/internal/worklog"
)

var ansiRE = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

func stripANSI(s string) string { return ansiRE.ReplaceAllString(s, "") }

func keyMsg(s string) tea.KeyMsg {
	switch s {
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	case "tab":
		return tea.KeyMsg{Type: tea.KeyTab}
	case "shift+tab":
		return tea.KeyMsg{Type: tea.KeyShiftTab}
	case "down":
		return tea.KeyMsg{Type: tea.KeyDown}
	case "up":
		return tea.KeyMsg{Type: tea.KeyUp}
	case "pgdown":
		return tea.KeyMsg{Type: tea.KeyPgDown}
	case "pgup":
		return tea.KeyMsg{Type: tea.KeyPgUp}
	case "ctrl+c":
		return tea.KeyMsg{Type: tea.KeyCtrlC}
	}
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
}

func send(m Model, s string) Model {
	updated, _ := m.Update(keyMsg(s))
	return updated.(Model)
}

func fixture() Deps {
	now := time.Date(2026, 11, 15, 12, 0, 0, 0, time.UTC)
	alphaBoard := &board.Board{
		Path:    "/repo/docs/tasks/2026-11/alpha/.board.md",
		Title:   "Alpha board",
		Status:  "active",
		Updated: now,
		Sections: []board.Section{
			{Title: "Status", Kind: board.KindNow, Items: []board.Item{
				{Text: "open item", Checkbox: true},
				{Text: "done item", Done: true, Checkbox: true},
			}},
			{Title: "Next", Kind: board.KindNext, Items: []board.Item{{Text: "next item"}}},
			{Title: "Blocked", Kind: board.KindBlocked, Items: []board.Item{{Text: "waiting item", Blocked: true}}},
		},
	}
	alphaWorklog := &worklog.Worklog{
		Path: "/repo/docs/tasks/2026-11/alpha/.worklog.md",
		Entries: []worklog.Entry{
			{Heading: "2026-11-15T10:00:00Z — run", HasTimestamp: true, Precise: true, Timestamp: now, Body: "body text"},
		},
	}
	tasks := []*task.Task{
		{
			Dir:            "/repo/docs/tasks/2026-11/alpha",
			RelDir:         "docs/tasks/2026-11/alpha",
			Month:          "2026-11",
			Slug:           "alpha",
			Title:          "Alpha task",
			Description:    "First task",
			Status:         "in-progress",
			DefinitionPath: "/repo/docs/tasks/2026-11/alpha/definition.md",
			LastActivity:   now,
			OpenItems:      2,
			Board:          alphaBoard,
			Worklog:        alphaWorklog,
		},
		{
			Dir:            "/repo/docs/tasks/2026-11/beta",
			RelDir:         "docs/tasks/2026-11/beta",
			Month:          "2026-11",
			Slug:           "beta",
			Title:          "Beta task",
			Description:    "Second task",
			Status:         "open",
			DefinitionPath: "/repo/docs/tasks/2026-11/beta/definition.md",
			LastActivity:   now.Add(-time.Hour),
		},
	}
	sessionBoard := &board.Board{
		Path:    "/repo/.cache/agents/opencode-20261115-ses_alpha/board.md",
		Title:   "Session board",
		Status:  "active",
		Updated: now,
		Sections: []board.Section{
			{Title: "Status", Kind: board.KindNow, Items: []board.Item{{Text: "session item", Checkbox: true}}},
		},
	}
	sessions := []*journal.Session{
		{
			Dir:         "/repo/.cache/agents/opencode-20261115-ses_alpha",
			RelDir:      ".cache/agents/opencode-20261115-ses_alpha",
			Name:        "opencode-20261115-ses_alpha",
			Harness:     "opencode",
			Date:        "20261115",
			DateParsed:  now,
			ID:          "ses_alpha",
			LastTouched: now,
			Boards:      []*board.Board{sessionBoard},
			Worklog: &worklog.Worklog{
				Path:    "/repo/.cache/agents/opencode-20261115-ses_alpha/worklog.md",
				Entries: []worklog.Entry{{Heading: "2026-11-15T10:00:00Z — run", HasTimestamp: true}},
			},
			TaskRefs: []string{"docs/tasks/2026-11/alpha"},
		},
	}
	return Deps{
		Root:   "/repo",
		Tree:   &task.Tree{Root: "/repo", Tasks: tasks},
		Store:  &journal.Store{Root: "/repo", Sessions: sessions},
		Width:  100,
		Height: 30,
		Editor: "true",
		Reload: func() (*task.Tree, *journal.Store, error) {
			return &task.Tree{Root: "/repo", Tasks: tasks}, &journal.Store{Root: "/repo", Sessions: sessions}, nil
		},
	}
}

func TestNewModelDefaults(t *testing.T) {
	m := NewModel(Deps{})
	if m.width != defaultWidth || m.height != defaultHeight {
		t.Errorf("size = %dx%d, want %dx%d", m.width, m.height, defaultWidth, defaultHeight)
	}
	if len(m.tasks.Items()) != 0 || len(m.sessions.Items()) != 0 {
		t.Errorf("empty model has items")
	}
	if got := m.View(); got == "" {
		t.Error("empty model View is empty")
	}
}

func TestTabSwitch(t *testing.T) {
	m := NewModel(fixture())
	if m.tab != TabTasks {
		t.Fatalf("initial tab = %v", m.tab)
	}
	m = send(m, "tab")
	if m.tab != TabSessions {
		t.Errorf("tab after tab = %v", m.tab)
	}
	m = send(m, "shift+tab")
	if m.tab != TabTasks {
		t.Errorf("tab after shift+tab = %v", m.tab)
	}
	m = send(m, "2")
	if m.tab != TabSessions {
		t.Errorf("tab after 2 = %v", m.tab)
	}
	m = send(m, "1")
	if m.tab != TabTasks {
		t.Errorf("tab after 1 = %v", m.tab)
	}
}

func TestListMovement(t *testing.T) {
	m := NewModel(fixture())
	if got := m.tasks.Index(); got != 0 {
		t.Fatalf("initial index = %d", got)
	}
	m = send(m, "j")
	if got := m.tasks.Index(); got != 1 {
		t.Errorf("index after j = %d", got)
	}
	m = send(m, "k")
	if got := m.tasks.Index(); got != 0 {
		t.Errorf("index after k = %d", got)
	}
	m = send(m, "G")
	if got := m.tasks.Index(); got != len(m.tasks.Items())-1 {
		t.Errorf("index after G = %d, want last", got)
	}
	m = send(m, "g")
	if got := m.tasks.Index(); got != 0 {
		t.Errorf("index after g = %d", got)
	}
}

func TestFilterModeCapturesKeys(t *testing.T) {
	m := NewModel(fixture())
	m = send(m, "/")
	if got := m.tasks.FilterState(); got != list.Filtering {
		t.Fatalf("filter state = %v, want Filtering", got)
	}
	m = send(m, "q")
	m = send(m, "j")
	m = send(m, "tab")
	if m.tab != TabTasks {
		t.Errorf("tab switched tabs while filtering")
	}
	if got := m.tasks.FilterState(); got != list.Filtering {
		t.Errorf("filter state after q/j = %v, want Filtering", got)
	}
	if got := m.tasks.FilterValue(); !strings.Contains(got, "q") || !strings.Contains(got, "j") {
		t.Errorf("filter value = %q, want q and j", got)
	}
	m = send(m, "esc")
	if got := m.tasks.FilterState(); got == list.Filtering {
		t.Errorf("filter still open after esc")
	}
}

func TestEnterOpensDetailAndEscReturns(t *testing.T) {
	m := NewModel(fixture())
	m = send(m, "enter")
	if !m.fullDetail {
		t.Fatal("enter did not open detail")
	}
	if !strings.Contains(stripANSI(m.detail.View()), "Alpha task") {
		t.Errorf("detail view does not contain the task title:\n%s", stripANSI(m.detail.View()))
	}
	m = send(m, "esc")
	if m.fullDetail {
		t.Error("esc did not return to the split view")
	}
}

func TestDetailMarkdownContainsModels(t *testing.T) {
	m := NewModel(fixture())
	taskMD := m.detailMarkdown(true)
	for _, want := range []string{"# Alpha task", "## Board", "## Worklog", "open item", "next item"} {
		if !strings.Contains(taskMD, want) {
			t.Errorf("task Markdown does not contain %q:\n%s", want, taskMD)
		}
	}
	m = send(m, "tab")
	sessionMD := m.detailMarkdown(true)
	for _, want := range []string{"# opencode-20261115-ses_alpha", "## Main board", "session item"} {
		if !strings.Contains(sessionMD, want) {
			t.Errorf("session Markdown does not contain %q:\n%s", want, sessionMD)
		}
	}
}

func TestEditMissingFile(t *testing.T) {
	m := NewModel(fixture())
	m = send(m, "e")
	if !strings.Contains(m.status, "no editable file") {
		t.Errorf("status = %q, want a missing-file message", m.status)
	}
}

func TestReload(t *testing.T) {
	deps := fixture()
	deps.Reload = func() (*task.Tree, *journal.Store, error) {
		extra := &task.Task{Dir: "/repo/docs/tasks/2026-11/gamma", RelDir: "docs/tasks/2026-11/gamma", Month: "2026-11", Slug: "gamma", Status: "open"}
		return &task.Tree{Root: "/repo", Tasks: []*task.Task{extra}}, &journal.Store{Root: "/repo"}, nil
	}
	m := NewModel(deps)
	m = send(m, "r")
	if got := len(m.tasks.Items()); got != 1 {
		t.Errorf("tasks after reload = %d, want 1", got)
	}
	if !strings.Contains(m.status, "reloaded") {
		t.Errorf("status = %q, want reloaded", m.status)
	}
}

func TestWindowResizeAndViewDimensions(t *testing.T) {
	for _, size := range []struct{ width, height int }{{80, 24}, {120, 40}, {40, 12}} {
		m := NewModel(fixture())
		updated, _ := m.Update(tea.WindowSizeMsg{Width: size.width, Height: size.height})
		m = updated.(Model)
		view := m.View()
		lines := strings.Split(view, "\n")
		if len(lines) != size.height {
			t.Errorf("%dx%d: %d lines, want %d", size.width, size.height, len(lines), size.height)
		}
		for i, line := range lines {
			if width := lipgloss.Width(line); width > size.width {
				t.Errorf("%dx%d: line %d is %d wide: %q", size.width, size.height, i+1, width, stripANSI(line))
			}
		}
	}
}

func TestQuit(t *testing.T) {
	m := NewModel(fixture())
	_, cmd := m.Update(keyMsg("q"))
	if cmd == nil {
		t.Fatal("q returned no command")
	}
	if _, ok := cmd().(tea.QuitMsg); !ok {
		t.Errorf("q command = %T, want tea.QuitMsg", cmd())
	}
}

func TestDetailScroll(t *testing.T) {
	m := NewModel(fixture())
	m = send(m, "enter")
	before := m.detail.YOffset
	m = send(m, "pgdown")
	if m.detail.YOffset < before {
		t.Errorf("YOffset moved backwards: %d -> %d", before, m.detail.YOffset)
	}
}

func TestRunNonTTY(t *testing.T) {
	if err := Run(Deps{}); err == nil {
		t.Fatal("Run succeeded without a TTY")
	}
}

func TestViewContainsHelpAndTabs(t *testing.T) {
	m := NewModel(fixture())
	plain := stripANSI(m.View())
	for _, want := range []string{"kdn-journal", "Tasks", "Sessions", "enter", "filter", "quit"} {
		if !strings.Contains(plain, want) {
			t.Errorf("view does not contain %q:\n%s", want, plain)
		}
	}
}
