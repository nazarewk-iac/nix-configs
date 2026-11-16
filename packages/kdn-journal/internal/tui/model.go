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
	"sort"
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

	allTasks      []*task.Task
	allSessions   []*journal.Session
	statusFilter  string
	harnessFilter string
	taskSort      taskSortMode
	sessionSort   sessionSortMode
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

	m.tasks = newList(nil, "Tasks", "task", "tasks", m.width, m.height)
	m.sessions = newList(nil, "Sessions", "session", "sessions", m.width, m.height)
	if deps.Tree != nil {
		m.allTasks = deps.Tree.Tasks
	}
	if deps.Store != nil {
		m.allSessions = deps.Store.Sessions
	}
	_ = m.rebuildLists()
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
	l := list.New(items, itemDelegate{}, width, height)
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
	return i.task.Slug
}

// Label returns the colored status badge.
func (i taskItem) Label() (string, lipgloss.Style) {
	return statusLabel(i.task.Status)
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
	return i.session.ID
}

// Label returns the colored harness badge.
func (i sessionItem) Label() (string, lipgloss.Style) {
	return harnessLabel(i.session.Harness)
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

func taskItems(tasks []*task.Task, mode taskSortMode) []list.Item {
	sorted := append([]*task.Task(nil), tasks...)
	sortTasks(sorted, mode)
	items := make([]list.Item, 0, len(sorted))
	for _, t := range sorted {
		items = append(items, taskItem{task: t})
	}
	return items
}

func sessionItems(sessions []*journal.Session, mode sessionSortMode) []list.Item {
	sorted := append([]*journal.Session(nil), sessions...)
	sortSessions(sorted, mode)
	items := make([]list.Item, 0, len(sorted))
	for _, s := range sorted {
		items = append(items, sessionItem{session: s})
	}
	return items
}

func (m *Model) setTree(tree *task.Tree) tea.Cmd {
	if tree != nil && m.root == "" {
		m.root = tree.Root
	}
	if tree == nil {
		m.allTasks = nil
	} else {
		m.allTasks = tree.Tasks
	}
	return m.rebuildLists()
}

func (m *Model) setStore(store *journal.Store) tea.Cmd {
	if store != nil && m.root == "" {
		m.root = store.Root
	}
	if store == nil {
		m.allSessions = nil
	} else {
		m.allSessions = store.Sessions
	}
	return m.rebuildLists()
}

// rebuildLists applies the active facet filter and sort, then hands the items to the two lists.
// SetItems returns a command that re-runs the list's fuzzy filter; the caller must return it.
func (m *Model) rebuildLists() tea.Cmd {
	taskCmd := m.tasks.SetItems(taskItems(filterTasks(m.allTasks, m.statusFilter), m.taskSort))
	sessionCmd := m.sessions.SetItems(sessionItems(filterSessions(m.allSessions, m.harnessFilter), m.sessionSort))
	return tea.Batch(taskCmd, sessionCmd)
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
	height := m.height - 3
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

// taskSortMode selects the order of the task list.
type taskSortMode int

const (
	taskSortDefault taskSortMode = iota
	taskSortTitle
	taskSortStatus
	taskSortActivity
	taskSortCount
)

func (s taskSortMode) String() string {
	switch s {
	case taskSortTitle:
		return "title"
	case taskSortStatus:
		return "status"
	case taskSortActivity:
		return "activity"
	}
	return "tree"
}

// sessionSortMode selects the order of the session list.
type sessionSortMode int

const (
	sessionSortDate sessionSortMode = iota
	sessionSortHarness
	sessionSortID
	sessionSortCount
)

func (s sessionSortMode) String() string {
	switch s {
	case sessionSortHarness:
		return "harness"
	case sessionSortID:
		return "id"
	}
	return "date"
}

// taskStatusCycle is the status filter cycle. The empty value means every status.
var taskStatusCycle = []string{"", "open", "in-progress", "blocked", "done", "not-scheduled"}

func filterTasks(tasks []*task.Task, status string) []*task.Task {
	if status == "" {
		return tasks
	}
	out := make([]*task.Task, 0, len(tasks))
	for _, t := range tasks {
		if strings.EqualFold(t.Status, status) {
			out = append(out, t)
		}
	}
	return out
}

func sortTasks(tasks []*task.Task, mode taskSortMode) {
	switch mode {
	case taskSortTitle:
		sort.SliceStable(tasks, func(i, j int) bool {
			return strings.ToLower(tasks[i].Title) < strings.ToLower(tasks[j].Title)
		})
	case taskSortStatus:
		sort.SliceStable(tasks, func(i, j int) bool {
			ri, rj := statusRank(tasks[i].Status), statusRank(tasks[j].Status)
			if ri != rj {
				return ri < rj
			}
			return tasks[i].Slug < tasks[j].Slug
		})
	case taskSortActivity:
		sort.SliceStable(tasks, func(i, j int) bool {
			return tasks[i].LastActivity.After(tasks[j].LastActivity)
		})
	}
}

// statusRank orders the statuses by urgency for the status sort.
func statusRank(status string) int {
	switch strings.ToLower(status) {
	case "blocked":
		return 0
	case "in-progress":
		return 1
	case "open":
		return 2
	case "not-scheduled":
		return 3
	case "done":
		return 4
	}
	return 5
}

func filterSessions(sessions []*journal.Session, harness string) []*journal.Session {
	if harness == "" {
		return sessions
	}
	out := make([]*journal.Session, 0, len(sessions))
	for _, s := range sessions {
		if strings.EqualFold(s.Harness, harness) {
			out = append(out, s)
		}
	}
	return out
}

func sortSessions(sessions []*journal.Session, mode sessionSortMode) {
	switch mode {
	case sessionSortHarness:
		sort.SliceStable(sessions, func(i, j int) bool {
			if sessions[i].Harness != sessions[j].Harness {
				return sessions[i].Harness < sessions[j].Harness
			}
			return sessions[i].LastTouched.After(sessions[j].LastTouched)
		})
	case sessionSortID:
		sort.SliceStable(sessions, func(i, j int) bool { return sessions[i].ID < sessions[j].ID })
	}
}

// cycleFacet advances the active tab's facet filter.
func (m *Model) cycleFacet() tea.Cmd {
	if m.tab == TabSessions {
		return m.cycleHarness()
	}
	m.statusFilter = nextInCycle(taskStatusCycle, m.statusFilter)
	cmd := m.rebuildLists()
	m.syncLayout()
	m.syncDetail()
	m.status = "status filter: " + orDefault(m.statusFilter, "all")
	return cmd
}

func (m *Model) cycleHarness() tea.Cmd {
	values := append([]string{""}, m.harnessValues()...)
	m.harnessFilter = nextInCycle(values, m.harnessFilter)
	cmd := m.rebuildLists()
	m.syncLayout()
	m.syncDetail()
	m.status = "harness filter: " + orDefault(m.harnessFilter, "all")
	return cmd
}

func (m *Model) harnessValues() []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range m.allSessions {
		harness := strings.TrimSpace(s.Harness)
		if harness == "" || seen[harness] {
			continue
		}
		seen[harness] = true
		out = append(out, harness)
	}
	sort.Strings(out)
	return out
}

// cycleSort advances the active tab's sort mode.
func (m *Model) cycleSort() tea.Cmd {
	if m.tab == TabSessions {
		m.sessionSort = (m.sessionSort + 1) % sessionSortCount
	} else {
		m.taskSort = (m.taskSort + 1) % taskSortCount
	}
	cmd := m.rebuildLists()
	m.syncLayout()
	m.syncDetail()
	m.status = "sort: " + m.sortLabel()
	return cmd
}

func (m *Model) clearFilters() tea.Cmd {
	m.statusFilter = ""
	m.harnessFilter = ""
	m.taskSort = taskSortDefault
	m.sessionSort = sessionSortDate
	m.tasks.ResetFilter()
	m.sessions.ResetFilter()
	cmd := m.rebuildLists()
	m.syncLayout()
	m.syncDetail()
	m.status = "filters cleared"
	return cmd
}

func (m Model) sortLabel() string {
	if m.tab == TabSessions {
		return m.sessionSort.String()
	}
	return m.taskSort.String()
}

func nextInCycle(values []string, current string) string {
	if len(values) == 0 {
		return ""
	}
	for i, value := range values {
		if value == current {
			return values[(i+1)%len(values)]
		}
	}
	return values[0]
}
