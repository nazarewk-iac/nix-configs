// Package tui implements the interactive browser of kdn-okf.
package tui

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
	"golang.org/x/term"

	"kdn-okf/internal/okf"
)

const (
	defaultWidth  = 100
	defaultHeight = 30
)

// Deps is everything the model needs from the outside world.
type Deps struct {
	Bundle *okf.Bundle
	Width  int
	Height int
	Editor string
	// Reload re-reads the bundle. It may be nil, in which case `r` reports that reloading is
	// unavailable.
	Reload func() (*okf.Bundle, error)
}

// Run starts the interactive program. It requires a terminal on standard output.
func Run(deps Deps) error {
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		return errors.New("kdn-okf tui requires a terminal: stdout is not a TTY; use `kdn-okf list --json`")
	}
	program := tea.NewProgram(NewModel(deps), tea.WithAltScreen())
	_, err := program.Run()
	return err
}

type sortMode int

const (
	sortPath sortMode = iota
	sortTitle
	sortType
	sortStatus
	sortTrust
	sortStale
	sortCount
)

func (s sortMode) String() string {
	switch s {
	case sortTitle:
		return "title"
	case sortType:
		return "type"
	case sortStatus:
		return "status"
	case sortTrust:
		return "trust"
	case sortStale:
		return "stale"
	}
	return "path"
}

var (
	statusCycle = []string{"", "draft", "stable", "deprecated"}
	trustCycle  = []string{"", "unverified", "machine-confirmed", "human-reviewed"}
)

// Model is the bubbletea model of the OKF browser.
type Model struct {
	deps   Deps
	bundle *okf.Bundle
	all    []*okf.Concept

	width  int
	height int

	list   list.Model
	detail viewport.Model
	help   help.Model
	keys   keyMap

	fullDetail    bool
	view          string // preview, links, backlinks
	statusFilter  string
	trustFilter   string
	staleOnly     bool
	sortMode      sortMode
	status        string
	lastID        string
	rendered      string
	renderedID    string
	renderedWidth int
	renderedView  string
}

// NewModel builds the model from deps.
func NewModel(deps Deps) Model {
	lipgloss.SetHasDarkBackground(true)
	m := Model{
		deps:   deps,
		bundle: deps.Bundle,
		keys:   defaultKeyMap(),
		help:   help.New(),
		view:   "preview",
	}
	m.width, m.height = deps.Width, deps.Height
	if m.width <= 0 {
		m.width = defaultWidth
	}
	if m.height <= 0 {
		m.height = defaultHeight
	}
	if deps.Bundle != nil {
		m.all = deps.Bundle.Concepts
	}
	m.list = newList(nil, m.width, m.height)
	m.detail = viewport.New(m.width, m.height)
	m.rebuild()
	m.syncLayout()
	m.syncDetail()
	return m
}

func (m Model) Init() tea.Cmd { return nil }

func newList(items []list.Item, width, height int) list.Model {
	l := list.New(items, itemDelegate{}, width, height)
	l.SetShowTitle(false)
	l.SetShowHelp(false)
	l.SetShowStatusBar(true)
	l.SetShowPagination(true)
	l.SetStatusBarItemName("concept", "concepts")
	l.SetFilteringEnabled(true)
	l.KeyMap.AcceptWhileFiltering.SetKeys("enter")
	l.KeyMap.CancelWhileFiltering.SetKeys("esc")
	// Free b/l/f/u/g for the shell: the list keeps the arrows and page keys.
	l.KeyMap.NextPage.SetKeys("right", "pgdown")
	l.KeyMap.PrevPage.SetKeys("left", "pgup")
	l.KeyMap.GoToStart.SetKeys("home")
	l.KeyMap.GoToEnd.SetKeys("end")
	l.DisableQuitKeybindings()
	return l
}

func (m *Model) rebuild() {
	concepts := make([]*okf.Concept, 0, len(m.all))
	for _, concept := range m.all {
		if m.statusFilter != "" && !strings.EqualFold(concept.Status, m.statusFilter) {
			continue
		}
		if m.trustFilter != "" && !strings.EqualFold(concept.Trust.String(), m.trustFilter) {
			continue
		}
		if m.staleOnly && !concept.Stale {
			continue
		}
		concepts = append(concepts, concept)
	}
	sort.SliceStable(concepts, func(i, j int) bool {
		a, b := concepts[i], concepts[j]
		switch m.sortMode {
		case sortTitle:
			return strings.ToLower(a.Title) < strings.ToLower(b.Title)
		case sortType:
			if a.Type != b.Type {
				return a.Type < b.Type
			}
			return a.ID < b.ID
		case sortStatus:
			if a.Status != b.Status {
				return a.Status < b.Status
			}
			return a.ID < b.ID
		case sortTrust:
			if a.Trust != b.Trust {
				return a.Trust > b.Trust
			}
			return a.ID < b.ID
		case sortStale:
			if a.Stale != b.Stale {
				return a.Stale
			}
			return a.ID < b.ID
		}
		return a.ID < b.ID
	})
	items := make([]list.Item, 0, len(concepts))
	for _, concept := range concepts {
		items = append(items, conceptItem{concept: concept})
	}
	m.list.SetItems(items)
}

func (m *Model) syncLayout() {
	height := m.bodyHeight()
	left := m.leftWidth()
	m.list.SetSize(left, height)
	m.help.Width = m.width
	m.detail.Width = m.paneWidth()
	m.detail.Height = height
}

func (m *Model) syncDetail() {
	concept := m.selected()
	key := ""
	if concept != nil {
		key = concept.ID
	}
	width := m.paneWidth()
	if key != m.renderedID || width != m.renderedWidth || m.view != m.renderedView {
		m.rendered = renderMarkdown(m.detailMarkdown(concept), width)
		m.renderedID = key
		m.renderedWidth = width
		m.renderedView = m.view
		m.detail.SetContent(m.rendered)
		if key != m.lastID {
			m.detail.GotoTop()
			m.lastID = key
		}
	}
}

func (m Model) selected() *okf.Concept {
	if item, ok := m.list.SelectedItem().(conceptItem); ok {
		return item.concept
	}
	return nil
}

func (m Model) detailMarkdown(concept *okf.Concept) string {
	if concept == nil {
		return "# Nothing selected\n\nUse `j`/`k` to move and `/` to filter.\n"
	}
	if m.view == "links" || m.view == "backlinks" {
		return m.linksMarkdown(concept)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n", concept.Title)
	fmt.Fprintf(&b, "**%s** · `%s` · %s · %s", concept.Type, concept.ID, concept.Status, concept.Trust.String())
	if concept.Stale {
		b.WriteString(" · **stale**")
	}
	b.WriteString("\n\n")
	if concept.Description != "" {
		fmt.Fprintf(&b, "%s\n\n", concept.Description)
	}
	if len(concept.Tags) > 0 {
		fmt.Fprintf(&b, "Tags: %s\n\n", strings.Join(concept.Tags, ", "))
	}
	fmt.Fprintf(&b, "Links: %d · Backlinks: %d\n\n", len(concept.Links), len(concept.Backlinks))
	b.WriteString("---\n\n")
	b.Write(concept.Body)
	return b.String()
}

func (m Model) linksMarkdown(concept *okf.Concept) string {
	links := concept.Links
	title := "Links"
	if m.view == "backlinks" {
		links = concept.Backlinks
		title = "Backlinks"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# %s — %s\n\n", title, concept.Title)
	if len(links) == 0 {
		if m.view == "backlinks" {
			b.WriteString("_No backlinks. This concept is an orphan._\n")
		} else {
			b.WriteString("_No outgoing links._\n")
		}
		return b.String()
	}
	for _, link := range links {
		state := ""
		if link.Missing {
			state = " · **missing**"
		}
		target := link.Resolved
		if target == "" {
			target = link.Target
		}
		fmt.Fprintf(&b, "- `%s` — %s%s\n", target, link.Kind, state)
	}
	return b.String()
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
	width := m.width * 38 / 100
	if width < 28 {
		width = 28
	}
	if width > 56 {
		width = 56
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
	if m.fullDetail || m.width < 72 {
		return m.width
	}
	width := m.width - m.leftWidth() - 1
	if width < 1 {
		width = 1
	}
	return width
}

func (m *Model) cycle(values []string, current string) string {
	for i, value := range values {
		if value == current {
			return values[(i+1)%len(values)]
		}
	}
	return values[0]
}

func (m Model) View() string {
	if m.width <= 0 || m.height <= 0 {
		return ""
	}
	lines := make([]string, 0, m.height)
	lines = append(lines, m.headerLine())
	lines = append(lines, fit(m.facetLine(), m.width))
	lines = append(lines, m.bodyLines()...)
	if m.status != "" {
		lines = append(lines, fit(styleStatus.Render(m.status), m.width))
	}
	lines = append(lines, fit(m.help.View(m.keys), m.width))
	if len(lines) > m.height {
		lines = lines[:m.height]
	}
	for len(lines) < m.height {
		lines = append(lines, "")
	}
	return strings.Join(lines, "\n")
}

func (m Model) headerLine() string {
	name := "kdn-okf"
	if m.bundle != nil {
		name += "  " + m.bundle.Name
	}
	view := m.view
	if m.fullDetail {
		view += " (full)"
	}
	left := styleTitle.Render(name)
	gap := m.width - lipgloss.Width(left) - lipgloss.Width(view)
	if gap < 1 {
		return fit(left, m.width)
	}
	return fit(left+strings.Repeat(" ", gap)+styleTabOff.Render(view), m.width)
}

func (m Model) facetLine() string {
	parts := []string{
		"status=" + orAll(m.statusFilter),
		"trust=" + orAll(m.trustFilter),
	}
	if m.staleOnly {
		parts = append(parts, "stale=only")
	}
	parts = append(parts, "sort="+m.sortMode.String())
	text := "filters: " + strings.Join(parts, " · ") + "   f status · u trust · x stale · s/S sort · c clear"
	return styleDim.Render(text)
}

func (m Model) bodyLines() []string {
	height := m.bodyHeight()
	if m.fullDetail || m.width < 72 {
		return padLines(splitLines(m.detail.View()), m.width, height)
	}
	leftWidth := m.leftWidth()
	rightWidth := m.paneWidth()
	left := padLines(splitLines(m.list.View()), leftWidth, height)
	right := padLines(splitLines(m.detail.View()), rightWidth, height)
	rows := make([]string, height)
	for i := 0; i < height; i++ {
		rows[i] = fit(left[i], leftWidth) + styleDiv.Render("│") + fit(right[i], rightWidth)
	}
	return rows
}

func splitLines(s string) []string {
	s = strings.TrimRight(s, "\n")
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
}

func padLines(lines []string, width, height int) []string {
	out := make([]string, height)
	for i := 0; i < height; i++ {
		if i < len(lines) {
			out[i] = fit(lines[i], width)
		} else {
			out[i] = strings.Repeat(" ", width)
		}
	}
	return out
}

func fit(s string, width int) string {
	if width <= 0 {
		return ""
	}
	if ansi.StringWidth(s) > width {
		s = ansi.Truncate(s, width, "…")
	}
	if pad := width - ansi.StringWidth(s); pad > 0 {
		s += strings.Repeat(" ", pad)
	}
	return s
}

func orAll(value string) string {
	if value == "" {
		return "all"
	}
	return value
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

type editorFinishedMsg struct{ err error }

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		if m.width <= 0 {
			m.width = defaultWidth
		}
		if m.height <= 0 {
			m.height = defaultHeight
		}
		m.syncLayout()
		m.syncDetail()
		return m, nil
	case list.FilterMatchesMsg:
		var cmds []tea.Cmd
		var cmd tea.Cmd
		m.list, cmd = m.list.Update(msg)
		cmds = append(cmds, cmd)
		m.syncDetail()
		return m, tea.Batch(cmds...)
	case editorFinishedMsg:
		if msg.err != nil {
			m.status = "editor: " + msg.err.Error()
		}
		return m, nil
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	keyName := msg.String()
	if m.list.FilterState() == list.Filtering {
		if keyName == "ctrl+c" {
			return m, tea.Quit
		}
		updated, cmd := m.list.Update(msg)
		m.list = updated
		m.syncDetail()
		return m, cmd
	}
	switch keyName {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "enter":
		if !m.fullDetail {
			m.fullDetail = true
			m.status = ""
			m.syncLayout()
			m.syncDetail()
		}
		return m, nil
	case "esc":
		switch {
		case m.fullDetail:
			m.fullDetail = false
		case m.view != "preview":
			m.view = "preview"
		case m.list.FilterState() == list.FilterApplied:
			m.list.ResetFilter()
		}
		m.syncLayout()
		m.syncDetail()
		return m, nil
	case "f":
		m.statusFilter = m.cycle(statusCycle, m.statusFilter)
		m.rebuild()
		m.status = "status filter: " + orAll(m.statusFilter)
		m.syncDetail()
		return m, nil
	case "u":
		m.trustFilter = m.cycle(trustCycle, m.trustFilter)
		m.rebuild()
		m.status = "trust filter: " + orAll(m.trustFilter)
		m.syncDetail()
		return m, nil
	case "x":
		m.staleOnly = !m.staleOnly
		m.rebuild()
		m.status = "stale filter: " + map[bool]string{true: "only", false: "all"}[m.staleOnly]
		m.syncDetail()
		return m, nil
	case "s":
		m.sortMode = (m.sortMode + 1) % sortCount
		m.rebuild()
		m.status = "sort: " + m.sortMode.String()
		m.syncDetail()
		return m, nil
	case "S":
		m.sortMode = (m.sortMode + sortCount - 1) % sortCount
		m.rebuild()
		m.status = "sort: " + m.sortMode.String()
		m.syncDetail()
		return m, nil
	case "c":
		m.statusFilter = ""
		m.trustFilter = ""
		m.staleOnly = false
		m.sortMode = sortPath
		m.list.ResetFilter()
		m.rebuild()
		m.status = "filters cleared"
		m.syncDetail()
		return m, nil
	case "b":
		m.view = "backlinks"
		m.syncDetail()
		return m, nil
	case "l":
		m.view = "links"
		m.syncDetail()
		return m, nil
	case "v":
		m.view = "preview"
		m.syncDetail()
		return m, nil
	case "o":
		return m.edit()
	case "r":
		return m.reload()
	case "pgup", "ctrl+b", "pgdown", "ctrl+f":
		updated, cmd := m.detail.Update(msg)
		m.detail = updated
		return m, cmd
	case "j", "down", "k", "up", "g", "G", "home", "end":
		if m.fullDetail {
			updated, cmd := m.detail.Update(msg)
			m.detail = updated
			return m, cmd
		}
		updated, cmd := m.list.Update(msg)
		m.list = updated
		m.syncDetail()
		return m, cmd
	default:
		updated, cmd := m.list.Update(msg)
		m.list = updated
		m.syncDetail()
		return m, cmd
	}
}

func (m Model) edit() (tea.Model, tea.Cmd) {
	concept := m.selected()
	if concept == nil {
		m.status = "nothing selected"
		return m, nil
	}
	editor := m.editor()
	// #nosec G204 -- the editor comes from Deps/$EDITOR and the path from the bundle.
	command := exec.Command("sh", "-c", editor+" \"$1\"", "sh", concept.Path)
	m.status = "editing " + concept.RelPath
	return m, tea.ExecProcess(command, func(err error) tea.Msg { return editorFinishedMsg{err: err} })
}

func (m Model) reload() (tea.Model, tea.Cmd) {
	if m.deps.Reload == nil {
		m.status = "reload is unavailable"
		return m, nil
	}
	bundle, err := m.deps.Reload()
	if err != nil {
		m.status = "reload failed: " + err.Error()
		return m, nil
	}
	m.bundle = bundle
	m.all = bundle.Concepts
	m.rebuild()
	m.status = fmt.Sprintf("reloaded: %d concepts", len(m.all))
	m.syncDetail()
	return m, nil
}
