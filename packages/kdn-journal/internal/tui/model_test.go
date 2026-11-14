package tui

import (
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"kdn-journal/internal/board"
	"kdn-journal/internal/journal"
	"kdn-journal/internal/task"
	"kdn-journal/internal/worklog"
)

// fixture builds a small tree and store with parsed boards and worklogs. No file is required:
// every path is synthetic and does not exist on disk, which is what the `e` no-op test needs.
func fixture(t *testing.T) Deps {
	t.Helper()
	now := time.Now()

	taskBoard, err := board.Parse([]byte(""+
		"# Board — Alpha\n\n"+
		"## Now\n"+
		"- [ ] open item\n"+
		"- [x] done item\n\n"+
		"## Next\n"+
		"- follow up\n\n"+
		"## Blocked\n"+
		"- waits for review\n"), "/synthetic/alpha/.board.md", now)
	if err != nil {
		t.Fatalf("parse task board: %v", err)
	}
	taskWorklog := worklog.Parse([]byte(""+
		"## 2026-11-15 — first entry\nbody\n"+
		"## 2026-11-16 — second entry\nbody\n"), "/synthetic/alpha/.worklog.md", now)

	alpha := &task.Task{
		Dir:            "/synthetic/alpha",
		RelDir:         "docs/tasks/2026-11/alpha",
		Month:          "2026-11",
		Slug:           "alpha",
		DefinitionPath: "/synthetic/alpha/definition.md",
		Title:          "Alpha task",
		Description:    "the first synthetic task",
		Status:         "in-progress",
		LastActivity:   now.Add(-time.Hour),
		Board:          taskBoard,
		Worklog:        taskWorklog,
		HasBoard:       true,
		HasWorklog:     true,
		OpenItems:      2,
		DoneItems:      1,
		BlockedItems:   1,
		Files: []task.File{
			{Name: "definition.md", Kind: "definition"},
			{Name: ".board.md", Kind: "board"},
		},
	}
	alpha.Subtasks = []*task.Task{{
		Dir:       "/synthetic/alpha/sub",
		RelDir:    "docs/tasks/2026-11/alpha/sub",
		Month:     "2026-11",
		Slug:      "alpha-sub",
		Status:    "open",
		Depth:     1,
		Title:     "Sub task",
		ParentDir: "/synthetic/alpha",
	}}
	beta := &task.Task{
		Dir:            "/synthetic/beta",
		RelDir:         "docs/tasks/2026-11/beta",
		Month:          "2026-11",
		Slug:           "beta",
		DefinitionPath: "/synthetic/beta/definition.md",
		Title:          "Beta task",
		Description:    "the second synthetic task",
		Status:         "open",
		LastActivity:   now.Add(-2 * time.Hour),
	}
	gamma := &task.Task{
		Dir:            "/synthetic/gamma",
		RelDir:         "docs/tasks/2026-10/gamma",
		Month:          "2026-10",
		Slug:           "gamma",
		DefinitionPath: "/synthetic/gamma/definition.md",
		Title:          "Gamma task",
		Status:         "done",
		LastActivity:   now.Add(-48 * time.Hour),
	}

	sessionBoard, err := board.Parse([]byte(""+
		"# Board — Session\n\n"+
		"## Now\n"+
		"- [ ] session item\n"), "/synthetic/session/board.md", now)
	if err != nil {
		t.Fatalf("parse session board: %v", err)
	}
	trackBoard, err := board.Parse([]byte(""+
		"# Board — Track\n\n"+
		"## Blocked\n"+
		"- track item\n"), "/synthetic/session/board-track.md", now)
	if err != nil {
		t.Fatalf("parse track board: %v", err)
	}
	sessionWorklog := worklog.Parse([]byte("## 2026-11-15T10:00:00Z — session entry\nbody\n"),
		"/synthetic/session/worklog.md", now)

	sessions := []*journal.Session{
		{
			Dir:         "/synthetic/session",
			RelDir:      ".cache/agents/opencode-20261115-ses_alpha",
			Name:        "opencode-20261115-ses_alpha",
			Harness:     "opencode",
			Date:        "20261115",
			ID:          "ses_alpha",
			LastTouched: now.Add(-30 * time.Minute),
			Boards:      []*board.Board{sessionBoard, trackBoard},
			Worklog:     sessionWorklog,
			TaskRefs:    []string{"docs/tasks/2026-11/alpha"},
		},
		{
			Dir:         "/synthetic/session2",
			RelDir:      ".cache/agents/opencode-20261114-ses_beta",
			Name:        "opencode-20261114-ses_beta",
			Harness:     "opencode",
			Date:        "20261114",
			ID:          "ses_beta",
			LastTouched: now.Add(-3 * time.Hour),
		},
	}

	return Deps{
		Root:   "/synthetic/repo",
		Tree:   &task.Tree{Root: "/synthetic/repo", Tasks: []*task.Task{alpha, beta, gamma}},
		Store:  &journal.Store{Root: "/synthetic/repo", Sessions: sessions},
		Width:  100,
		Height: 30,
		Editor: "true",
	}
}

// send applies messages in order and returns the resulting model and the last command.
func send(m Model, msgs ...tea.Msg) (Model, tea.Cmd) {
	var cmd tea.Cmd
	for _, msg := range msgs {
		var next tea.Model
		next, cmd = m.Update(msg)
		m = next.(Model)
	}
	return m, cmd
}

func runeKey(text string) tea.KeyMsg {
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(text)}
}

func TestNewModel(t *testing.T) {
	m := NewModel(fixture(t))

	if m.tab != TabTasks {
		t.Fatalf("tab = %v, want TabTasks", m.tab)
	}
	if len(m.tasks) != 3 {
		t.Fatalf("tasks = %d, want 3", len(m.tasks))
	}
	if len(m.sessions) != 2 {
		t.Fatalf("sessions = %d, want 2", len(m.sessions))
	}
	if m.cursor != 0 {
		t.Fatalf("cursor = %d, want 0", m.cursor)
	}
	if m.width != 100 || m.height != 30 {
		t.Fatalf("size = %dx%d, want 100x30", m.width, m.height)
	}
	if got := m.selectedTask(); got == nil || got.Slug != "alpha" {
		t.Fatalf("selected task = %v, want alpha", got)
	}
}

func TestNewModelDefaultsSize(t *testing.T) {
	deps := fixture(t)
	deps.Width, deps.Height = 0, 0
	m := NewModel(deps)
	if m.width != defaultWidth || m.height != defaultHeight {
		t.Fatalf("size = %dx%d, want defaults %dx%d", m.width, m.height, defaultWidth, defaultHeight)
	}
}

func TestTabSwitch(t *testing.T) {
	m := NewModel(fixture(t))
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyTab})
	if m.tab != TabSessions {
		t.Fatalf("tab = %v, want TabSessions", m.tab)
	}
	if m.selectedSession() == nil || m.selectedSession().ID != "ses_alpha" {
		t.Fatalf("selected session = %v, want ses_alpha", m.selectedSession())
	}
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyTab})
	if m.tab != TabTasks {
		t.Fatalf("tab = %v, want TabTasks", m.tab)
	}
	// shift+tab also switches.
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyShiftTab})
	if m.tab != TabSessions {
		t.Fatalf("tab after shift+tab = %v, want TabSessions", m.tab)
	}
}

func TestCursorMovement(t *testing.T) {
	m := NewModel(fixture(t))
	m, _ = send(m, runeKey("j"))
	if m.cursor != 1 {
		t.Fatalf("cursor after j = %d, want 1", m.cursor)
	}
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyDown})
	if m.cursor != 2 {
		t.Fatalf("cursor after down = %d, want 2", m.cursor)
	}
	m, _ = send(m, runeKey("j"))
	if m.cursor != 2 {
		t.Fatalf("cursor past the end = %d, want 2", m.cursor)
	}
	m, _ = send(m, runeKey("k"))
	if m.cursor != 1 {
		t.Fatalf("cursor after k = %d, want 1", m.cursor)
	}
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyUp})
	if m.cursor != 0 {
		t.Fatalf("cursor after up = %d, want 0", m.cursor)
	}
	m, _ = send(m, runeKey("k"))
	if m.cursor != 0 {
		t.Fatalf("cursor before the start = %d, want 0", m.cursor)
	}
	m, _ = send(m, runeKey("G"))
	if m.cursor != 2 {
		t.Fatalf("cursor after G = %d, want 2", m.cursor)
	}
	m, _ = send(m, runeKey("g"))
	if m.cursor != 0 {
		t.Fatalf("cursor after g = %d, want 0", m.cursor)
	}
}

func TestFilterCapturesQ(t *testing.T) {
	m := NewModel(fixture(t))

	m, cmd := send(m, runeKey("/"))
	if !m.filterMode {
		t.Fatal("filter mode is not active after /")
	}
	if cmd != nil {
		t.Fatal("/ returned a command, want nil")
	}

	// Every key goes to the query, including q, j and tab.
	m, cmd = send(m, runeKey("q"), runeKey("j"), tea.KeyMsg{Type: tea.KeyTab})
	if cmd != nil {
		t.Fatalf("typing returned a command, want nil (cmd=%v)", cmd)
	}
	if m.filter != "qj" {
		t.Fatalf("filter = %q, want %q", m.filter, "qj")
	}
	if m.tab != TabTasks {
		t.Fatalf("tab = %v, want TabTasks: tab must be captured by the filter", m.tab)
	}

	// Backspace edits the query.
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyBackspace})
	if m.filter != "q" {
		t.Fatalf("filter after backspace = %q, want %q", m.filter, "q")
	}

	// esc cancels and restores the previous (empty) query.
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyEsc})
	if m.filterMode {
		t.Fatal("filter mode is still active after esc")
	}
	if m.filter != "" {
		t.Fatalf("filter after cancel = %q, want empty", m.filter)
	}
	if len(m.tasks) != 3 {
		t.Fatalf("tasks after cancel = %d, want 3", len(m.tasks))
	}
}

func TestFilterApply(t *testing.T) {
	m := NewModel(fixture(t))

	m, _ = send(m, runeKey("/"), runeKey("beta"))
	if m.filter != "beta" {
		t.Fatalf("filter = %q, want beta", m.filter)
	}
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyEnter})
	if m.filterMode {
		t.Fatal("filter mode is still active after enter")
	}
	if len(m.tasks) != 1 || m.tasks[0].Slug != "beta" {
		t.Fatalf("filtered tasks = %v, want only beta", m.tasks)
	}
	if m.status == "" {
		t.Fatal("applying a filter left no status message")
	}

	// q quits again once filter mode is closed.
	m, cmd := send(m, runeKey("q"))
	if cmd == nil {
		t.Fatal("q returned no command, want tea.Quit")
	}
}

func TestFilterEscKeepsPriorQuery(t *testing.T) {
	m := NewModel(fixture(t))
	m, _ = send(m, runeKey("/"), runeKey("alpha"), tea.KeyMsg{Type: tea.KeyEnter})
	if m.filter != "alpha" {
		t.Fatalf("filter = %q, want alpha", m.filter)
	}
	m, _ = send(m, runeKey("/"), runeKey("zzz"))
	if m.filter != "alphazzz" {
		t.Fatalf("filter = %q, want alphazzz", m.filter)
	}
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyEsc})
	if m.filter != "alpha" {
		t.Fatalf("filter after esc = %q, want the previous query alpha", m.filter)
	}
}

func TestEnterEscDetail(t *testing.T) {
	m := NewModel(fixture(t))

	m, _ = send(m, tea.KeyMsg{Type: tea.KeyEnter})
	if !m.fullDetail {
		t.Fatal("enter did not open the full detail")
	}
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyEsc})
	if m.fullDetail {
		t.Fatal("esc did not return to the list")
	}
	if m.tab != TabTasks {
		t.Fatalf("tab = %v, want TabTasks", m.tab)
	}
}

func TestEditNoopWhenFileAbsent(t *testing.T) {
	m := NewModel(fixture(t))
	// The fixture definition path does not exist on disk.
	m, cmd := send(m, runeKey("e"))
	if cmd != nil {
		t.Fatalf("e returned a command for a missing file: %v", cmd)
	}
	if m.status == "" {
		t.Fatal("e left no status message for a missing file")
	}
	if !containsFold(m.status, "no editable file") {
		t.Fatalf("status = %q, want a no-editable-file message", m.status)
	}
}

func TestEditSessionUsesBoard(t *testing.T) {
	m := NewModel(fixture(t))
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyTab})
	// The fixture session board does not exist, so the hand-off is refused.
	m, cmd := send(m, runeKey("e"))
	if cmd != nil {
		t.Fatalf("e returned a command for a missing board: %v", cmd)
	}
	if m.status == "" {
		t.Fatal("e left no status message")
	}
}

func TestReload(t *testing.T) {
	deps := fixture(t)
	calls := 0
	deps.Reload = func() (*task.Tree, *journal.Store, error) {
		calls++
		return &task.Tree{Root: deps.Root, Tasks: []*task.Task{{Slug: "fresh", Status: "open"}}},
			&journal.Store{Root: deps.Root}, nil
	}
	m := NewModel(deps)
	m, _ = send(m, runeKey("r"))
	if calls != 1 {
		t.Fatalf("Reload calls = %d, want 1", calls)
	}
	if len(m.tasks) != 1 || m.tasks[0].Slug != "fresh" {
		t.Fatalf("tasks after reload = %v, want only fresh", m.tasks)
	}
	if !containsFold(m.status, "reloaded") {
		t.Fatalf("status = %q, want a reloaded message", m.status)
	}
}

func TestReloadUnavailable(t *testing.T) {
	m := NewModel(fixture(t))
	m, _ = send(m, runeKey("r"))
	if !containsFold(m.status, "unavailable") {
		t.Fatalf("status = %q, want an unavailable message", m.status)
	}
}

func TestScrollDetail(t *testing.T) {
	m := NewModel(fixture(t))
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyPgUp})
	if m.detailScroll != 0 {
		t.Fatalf("detailScroll = %d, want 0 at the top", m.detailScroll)
	}
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyPgDown})
	if m.detailScroll != 0 {
		// The fixture is short; the scroll is clamped to the content.
		t.Fatalf("detailScroll = %d, want 0 when content fits", m.detailScroll)
	}
	m, _ = send(m, tea.KeyMsg{Type: tea.KeyEnter}, runeKey("G"))
	if m.detailScroll != 0 {
		t.Fatalf("detailScroll = %d, want 0 when the full detail fits", m.detailScroll)
	}
}

func TestWindowSize(t *testing.T) {
	m := NewModel(fixture(t))
	m, _ = send(m, tea.WindowSizeMsg{Width: 60, Height: 20})
	if m.width != 60 || m.height != 20 {
		t.Fatalf("size = %dx%d, want 60x20", m.width, m.height)
	}
	m, _ = send(m, tea.WindowSizeMsg{Width: 0, Height: 0})
	if m.width != defaultWidth || m.height != defaultHeight {
		t.Fatalf("size = %dx%d, want defaults", m.width, m.height)
	}
}

func TestViewLayout(t *testing.T) {
	deps := fixture(t)
	m := NewModel(deps)

	for _, size := range [][2]int{{100, 30}, {60, 20}, {40, 12}} {
		model, _ := send(m, tea.WindowSizeMsg{Width: size[0], Height: size[1]})
		view := model.View()
		lines := splitLines(view)
		if len(lines) != size[1] {
			t.Fatalf("%dx%d: %d lines, want %d", size[0], size[1], len(lines), size[1])
		}
		for i, line := range lines {
			if got := lipgloss.Width(line); got > size[0] {
				t.Fatalf("%dx%d: line %d is %d wide: %q", size[0], size[1], i, got, line)
			}
		}
	}
}

func TestViewBothTabsAndModes(t *testing.T) {
	m := NewModel(fixture(t))
	if view := m.View(); !containsFold(view, "Tasks") || !containsFold(view, "Sessions") {
		t.Fatalf("header is missing the tabs:\n%s", view)
	}
	if view := m.View(); !containsFold(view, "alpha") {
		t.Fatalf("list is missing the alpha task:\n%s", view)
	}
	if view := m.View(); !containsFold(view, "BOARD") {
		t.Fatalf("preview is missing the board section:\n%s", view)
	}

	sessions, _ := send(m, tea.KeyMsg{Type: tea.KeyTab})
	if view := sessions.View(); !containsFold(view, "ses_alpha") {
		t.Fatalf("session list is missing the session:\n%s", view)
	}
	if view := sessions.View(); !containsFold(view, "MAIN BOARD") {
		t.Fatalf("session preview is missing the main board:\n%s", view)
	}

	detail, _ := send(m, tea.KeyMsg{Type: tea.KeyEnter})
	view := detail.View()
	if !containsFold(view, "esc back") {
		t.Fatalf("full detail footer is missing the esc key:\n%s", view)
	}
	if containsFold(view, "tab switch") {
		t.Fatalf("full detail footer still shows the list keys:\n%s", view)
	}
}

func TestViewFilterPrompt(t *testing.T) {
	m := NewModel(fixture(t))
	m, _ = send(m, runeKey("/"), runeKey("a"))
	view := m.View()
	if !containsFold(view, "/a") {
		t.Fatalf("filter prompt is not rendered:\n%s", view)
	}
	if !containsFold(view, "esc cancel") {
		t.Fatalf("filter footer is missing the esc hint:\n%s", view)
	}
}

func TestViewEmptyModel(t *testing.T) {
	m := NewModel(Deps{Root: "/empty", Width: 80, Height: 24})
	if view := m.View(); !containsFold(view, "no entries") {
		t.Fatalf("empty list is missing a placeholder:\n%s", view)
	}
	if m.View() == "" {
		t.Fatal("empty model rendered nothing")
	}
}

func TestQuitKeys(t *testing.T) {
	m := NewModel(fixture(t))
	if _, cmd := send(m, runeKey("q")); cmd == nil {
		t.Fatal("q returned no command, want tea.Quit")
	}
	if _, cmd := send(m, tea.KeyMsg{Type: tea.KeyCtrlC}); cmd == nil {
		t.Fatal("ctrl+c returned no command, want tea.Quit")
	}
}

func TestRunRequiresTTY(t *testing.T) {
	// A test binary's stdout is not a character device.
	if err := Run(fixture(t)); err == nil {
		t.Fatal("Run returned nil without a TTY, want an error")
	}
}

func splitLines(text string) []string {
	lines := make([]string, 0, 32)
	current := ""
	for _, r := range text {
		if r == '\n' {
			lines = append(lines, current)
			current = ""
			continue
		}
		current += string(r)
	}
	return append(lines, current)
}
