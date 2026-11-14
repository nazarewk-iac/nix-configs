// Package tui implements the interactive terminal interface of kdn-journal.
//
// The shell uses the charmbracelet components for the work they own: bubbles/list for the
// browsable list, filtering and pagination; bubbles/viewport for the detail scroll; bubbles/help
// and bubbles/key for the footer; glamour for the Markdown detail. The only write is the
// `$EDITOR` hand-off.
package tui

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
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

	tasks    list.Model
	sessions list.Model
	detail   viewport.Model
	help     help.Model
	keys     keyMap

	fullDetail bool
	status     string
	lastSelect string
}

// NewModel builds the model from deps. It never fails; a nil tree or store is an empty list.
func NewModel(deps Deps) Model {
	// The list delegate and the help styles use adaptive colors. Set the background explicitly so
	// lipgloss does not send an OSC 11 query; a late response would leak into the shell after the
	// TUI exits.
	lipgloss.SetHasDarkBackground(true)
	m := Model{
		deps: deps,
		tab:  TabTasks,
		keys: defaultKeyMap(),
		help: help.New(),
	}
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

	m.tasks = newList(taskItems(deps.Tree), "Tasks", "task", "tasks", m.width, m.height)
	m.sessions = newList(sessionItems(deps.Store), "Sessions", "session", "sessions", m.width, m.height)
	m.detail = viewport.New(m.width, m.height)
	m.syncLayout()
	m.syncDetail()
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

// Init satisfies tea.Model. The components need no start-up command.
func (m Model) Init() tea.Cmd { return nil }

func newList(items []list.Item, title, singular, plural string, width, height int) list.Model {
	delegate := list.NewDefaultDelegate()
	delegate.SetSpacing(0)
	l := list.New(items, delegate, width, height)
	l.Title = title
	l.SetShowTitle(false)
	l.SetShowHelp(false)
	l.SetShowStatusBar(true)
	l.SetShowPagination(true)
	l.SetStatusBarItemName(singular, plural)
	l.SetFilteringEnabled(true)
	l.KeyMap.AcceptWhileFiltering.SetKeys("enter")
	l.KeyMap.CancelWhileFiltering.SetKeys("esc")
	l.DisableQuitKeybindings()
	return l
}

// taskItem adapts a task to list.DefaultItem.
type taskItem struct{ task *task.Task }

func (i taskItem) Title() string {
	return fmt.Sprintf("[%s] %s", i.task.Status, i.task.Slug)
}

func (i taskItem) Description() string {
	parts := []string{i.task.Month}
	if i.task.Description != "" {
		parts = append(parts, i.task.Description)
	}
	if !i.task.LastActivity.IsZero() {
		parts = append(parts, "last "+i.task.LastActivity.Format("2006-01-02"))
	}
	return strings.Join(parts, " · ")
}

func (i taskItem) FilterValue() string {
	return strings.Join([]string{
		i.task.Slug, i.task.Title, i.task.Description, i.task.Status,
		i.task.Month, i.task.RelDir, i.task.AuthoredBy,
	}, " ")
}

// sessionItem adapts a session to list.DefaultItem.
type sessionItem struct{ session *journal.Session }

func (i sessionItem) Title() string {
	return fmt.Sprintf("%s %s", i.session.Harness, i.session.ID)
}

func (i sessionItem) Description() string {
	date := i.session.Date
	if !i.session.DateParsed.IsZero() {
		date = i.session.DateParsed.Format("2006-01-02")
	}
	parts := []string{date, fmt.Sprintf("%d boards", len(i.session.Boards))}
	if i.session.Worklog != nil {
		parts = append(parts, fmt.Sprintf("%d log entries", len(i.session.Worklog.Entries)))
	}
	return strings.Join(parts, " · ")
}

func (i sessionItem) FilterValue() string {
	parts := []string{i.session.Name, i.session.ID, i.session.Harness, i.session.Date, i.session.RelDir}
	parts = append(parts, i.session.TaskRefs...)
	return strings.Join(parts, " ")
}

func taskItems(tree *task.Tree) []list.Item {
	if tree == nil {
		return nil
	}
	items := make([]list.Item, 0, len(tree.Tasks))
	for _, t := range tree.Tasks {
		items = append(items, taskItem{task: t})
	}
	return items
}

func sessionItems(store *journal.Store) []list.Item {
	if store == nil {
		return nil
	}
	items := make([]list.Item, 0, len(store.Sessions))
	for _, s := range store.Sessions {
		items = append(items, sessionItem{session: s})
	}
	return items
}

func (m *Model) setTree(tree *task.Tree) {
	if tree != nil && m.root == "" {
		m.root = tree.Root
	}
	m.tasks.SetItems(taskItems(tree))
}

func (m *Model) setStore(store *journal.Store) {
	if store != nil && m.root == "" {
		m.root = store.Root
	}
	m.sessions.SetItems(sessionItems(store))
}

func (m *Model) activeList() *list.Model {
	if m.tab == TabSessions {
		return &m.sessions
	}
	return &m.tasks
}

func (m Model) listModel() list.Model {
	if m.tab == TabSessions {
		return m.sessions
	}
	return m.tasks
}

func (m Model) selectedTask() *task.Task {
	if m.tab != TabTasks {
		return nil
	}
	if item, ok := m.tasks.SelectedItem().(taskItem); ok {
		return item.task
	}
	return nil
}

func (m Model) selectedSession() *journal.Session {
	if m.tab != TabSessions {
		return nil
	}
	if item, ok := m.sessions.SelectedItem().(sessionItem); ok {
		return item.session
	}
	return nil
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
// main board.
func (m Model) primaryPath() string {
	if m.tab == TabSessions {
		s := m.selectedSession()
		if s == nil || len(s.Boards) == 0 {
			return ""
		}
		return s.Boards[0].Path
	}
	t := m.selectedTask()
	if t == nil {
		return ""
	}
	return t.DefinitionPath
}

func (m Model) editor() string {
	if editor := strings.TrimSpace(m.deps.Editor); editor != "" {
		return editor
	}
	if editor := strings.TrimSpace(os.Getenv("EDITOR")); editor != "" {
		return editor
	}
	return "vi"
}

func (m *Model) syncLayout() {
	height := m.bodyHeight()
	left := m.leftWidth()
	m.tasks.SetSize(left, height)
	m.sessions.SetSize(left, height)
	m.help.Width = m.width
	m.detail.Width = m.paneWidth()
	m.detail.Height = height
}

// syncDetail re-renders the selected item into the viewport.
func (m *Model) syncDetail() {
	width := m.paneWidth()
	markdown := m.detailMarkdown(m.fullDetail)
	m.detail.SetContent(renderMarkdown(markdown, width))
	if m.selectedLabel() != m.lastSelect {
		m.detail.GotoTop()
		m.lastSelect = m.selectedLabel()
	}
	if m.detail.YOffset > m.detail.TotalLineCount() {
		m.detail.SetYOffset(max(0, m.detail.TotalLineCount()-m.detail.Height))
	}
}

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

func (m Model) leftWidth() int {
	width := m.width / 3
	if width < 24 {
		width = 24
	}
	if width > 48 {
		width = 48
	}
	if width > m.width-8 {
		width = m.width - 8
	}
	if width < 1 {
		width = 1
	}
	return width
}

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

func (m *Model) toggleDetail() {
	if m.listModel().SelectedItem() == nil {
		m.status = "nothing to open"
		return
	}
	m.fullDetail = !m.fullDetail
	m.status = ""
	m.syncLayout()
	m.syncDetail()
	m.detail.GotoTop()
}

func (m *Model) switchTab() {
	if m.tab == TabTasks {
		m.tab = TabSessions
	} else {
		m.tab = TabTasks
	}
	m.fullDetail = false
	m.status = ""
	m.syncLayout()
	m.syncDetail()
}
