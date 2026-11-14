// Package tui implements the interactive terminal interface of kdn-journal.
//
// It is a read-only browser over the loaded task tree and agent session store. The only write it
// can cause is the `$EDITOR` hand-off, which runs an external program and then asks the caller to
// reload. Every model is built from injected dependencies, so a test can drive it without a
// terminal.
package tui

import (
	"errors"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"golang.org/x/term"

	"kdn-journal/internal/journal"
	"kdn-journal/internal/task"
)

// Tab selects which list the model shows.
type Tab int

const (
	// TabTasks is the repository task tree.
	TabTasks Tab = iota
	// TabSessions is the agent session store.
	TabSessions
)

// String returns the tab label.
func (t Tab) String() string {
	if t == TabSessions {
		return "Sessions"
	}
	return "Tasks"
}

const (
	defaultWidth  = 100
	defaultHeight = 30

	// listOffsetStep is how many items one page jump moves the list.
	listOffsetStep = 10
)

// Deps is everything the model needs from the outside world.
type Deps struct {
	Root   string
	Tree   *task.Tree
	Store  *journal.Store
	Width  int
	Height int
	Editor string
	// Reload re-reads the tree and the store from disk. It may be nil, in which case `r`
	// reports that reloading is unavailable.
	Reload func() (*task.Tree, *journal.Store, error)
}

// Model is the bubbletea model of the journal browser.
type Model struct {
	deps Deps

	tab  Tab
	root string

	width  int
	height int

	// list state
	cursor     int
	listOffset int

	// right pane state
	detailScroll int
	fullDetail   bool

	// filter state
	filterMode   bool
	filter       string
	filterBefore string

	status string

	// allTasks and allSessions are the unfiltered backing lists.
	allTasks    []*task.Task
	allSessions []*journal.Session

	// tasks and sessions are the filtered lists the cursor walks.
	tasks    []*task.Task
	sessions []*journal.Session
}

// NewModel builds the model from deps. It never fails; a nil tree or store is an empty list.
func NewModel(deps Deps) Model {
	m := Model{deps: deps, tab: TabTasks}
	m.width, m.height = deps.Width, deps.Height
	if m.width <= 0 {
		m.width = defaultWidth
	}
	if m.height <= 0 {
		m.height = defaultHeight
	}
	m.root = deps.Root
	if m.root == "" && deps.Tree != nil {
		m.root = deps.Tree.Root
	}
	if m.root == "" && deps.Store != nil {
		m.root = deps.Store.Root
	}
	m.setTree(deps.Tree)
	m.setStore(deps.Store)
	m.refilter()
	return m
}

// Run starts the interactive program. It requires a terminal on standard output.
func Run(deps Deps) error {
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		return errors.New("kdn-journal tui requires a terminal: stdout is not a TTY")
	}
	program := tea.NewProgram(NewModel(deps), tea.WithAltScreen())
	_, err := program.Run()
	return err
}

// Init satisfies tea.Model. The model needs no start-up command.
func (m Model) Init() tea.Cmd { return nil }

func (m *Model) setTree(tree *task.Tree) {
	m.allTasks = nil
	if tree != nil {
		m.allTasks = append(m.allTasks, tree.Tasks...)
	}
}

func (m *Model) setStore(store *journal.Store) {
	m.allSessions = nil
	if store != nil {
		m.allSessions = append(m.allSessions, store.Sessions...)
	}
}

// refilter rebuilds the visible lists from the current query and clamps the cursor.
func (m *Model) refilter() {
	query := lowerTrim(m.filter)
	m.tasks = nil
	for _, t := range m.allTasks {
		if query == "" || containsFold(taskHaystack(t), query) {
			m.tasks = append(m.tasks, t)
		}
	}
	m.sessions = nil
	for _, s := range m.allSessions {
		if query == "" || containsFold(sessionHaystack(s), query) {
			m.sessions = append(m.sessions, s)
		}
	}
	m.clampCursor(true)
}

// clampCursor keeps the cursor inside the active list. When reset is true the list scroll and the
// detail scroll also return to the top.
func (m *Model) clampCursor(reset bool) {
	limit := m.listLen()
	switch {
	case limit == 0:
		m.cursor = 0
	case m.cursor >= limit:
		m.cursor = limit - 1
	case m.cursor < 0:
		m.cursor = 0
	}
	if reset {
		m.listOffset = 0
		m.detailScroll = 0
	}
}

func (m Model) listLen() int {
	if m.tab == TabSessions {
		return len(m.sessions)
	}
	return len(m.tasks)
}

func (m Model) selectedTask() *task.Task {
	if m.tab != TabTasks || m.cursor < 0 || m.cursor >= len(m.tasks) {
		return nil
	}
	return m.tasks[m.cursor]
}

func (m Model) selectedSession() *journal.Session {
	if m.tab != TabSessions || m.cursor < 0 || m.cursor >= len(m.sessions) {
		return nil
	}
	return m.sessions[m.cursor]
}

// selectedLabel is the human name of the current selection, used in the detail header.
func (m Model) selectedLabel() string {
	if m.tab == TabSessions {
		if s := m.selectedSession(); s != nil {
			return s.RelDir
		}
		return ""
	}
	if t := m.selectedTask(); t != nil {
		return t.RelDir
	}
	return ""
}

// primaryPath returns the file that `e` hands to the editor: the task definition, or the session
// board.md.
func (m Model) primaryPath() string {
	if m.tab == TabSessions {
		s := m.selectedSession()
		if s == nil {
			return ""
		}
		return existingFile(s.Dir + "/board.md")
	}
	t := m.selectedTask()
	if t == nil {
		return ""
	}
	return existingFile(t.DefinitionPath)
}

func existingFile(path string) string {
	if path == "" {
		return ""
	}
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return ""
	}
	return path
}

func (m Model) editor() string {
	if editor := trimSpace(m.deps.Editor); editor != "" {
		return editor
	}
	if editor := trimSpace(os.Getenv("EDITOR")); editor != "" {
		return editor
	}
	return "vi"
}
