// Package tui implements the interactive join/unlink wizard of kdn-audio.
package tui

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"golang.org/x/term"

	"kdn-audio/internal/audio"
	"kdn-audio/internal/combine"
	"kdn-audio/internal/pipewire"
)

type screen int

const (
	screenMain screen = iota
	screenName
	screenConfirm
)

// pane is the list that has the focus.
type pane int

const (
	paneOutputs pane = iota
	paneJoined
)

// Model is the bubbletea model of the wizard.
type Model struct {
	mgr *audio.Manager

	width  int
	height int

	sinks    []pipewire.Sink
	groups   []combine.Group
	selected map[string]bool

	cursor      int
	offset      int
	groupCursor int
	groupOffset int
	focus       pane

	screen  screen
	name    textinput.Model
	status  string
	busy    bool
	quitErr error

	// Routing choices; both are off, so joining never disturbs what plays and where.
	routeDefault bool
	moveStreams  bool
}

var (
	styleTitle    = lipgloss.NewStyle().Bold(true)
	styleDim      = lipgloss.NewStyle().Faint(true)
	styleCursor   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12"))
	styleSelected = lipgloss.NewStyle().Foreground(lipgloss.Color("10"))
	styleWarn     = lipgloss.NewStyle().Foreground(lipgloss.Color("11"))
	styleError    = lipgloss.NewStyle().Foreground(lipgloss.Color("9"))
	styleHeader   = lipgloss.NewStyle().Underline(true)
	styleHelp     = lipgloss.NewStyle().Faint(true)
)

// Run starts the wizard. It needs a terminal on standard output.
func Run(mgr *audio.Manager) error {
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		return errors.New("kdn-audio needs a terminal; use `kdn-audio list`, `kdn-audio create` and `kdn-audio unlink-all` instead")
	}
	model := New(mgr)
	program := tea.NewProgram(model, tea.WithAltScreen())
	final, err := program.Run()
	if err != nil {
		return err
	}
	if done, ok := final.(Model); ok && done.quitErr != nil {
		return done.quitErr
	}
	return nil
}

// New builds the wizard model.
func New(mgr *audio.Manager) Model {
	input := textinput.New()
	input.Placeholder = "name of the joined output"
	input.CharLimit = 64
	input.Width = 44
	return Model{
		mgr:      mgr,
		selected: map[string]bool{},
		name:     input,
	}
}

type loadedMsg struct {
	sinks  []pipewire.Sink
	groups []combine.Group
	err    error
}

type createdMsg struct {
	created audio.Created
	err     error
}

type unlinkedMsg struct {
	titles []string
	err    error
}

type connectedMsg struct {
	results []audio.Connected
}

// Init loads the current state.
func (m Model) Init() tea.Cmd { return m.load() }

func (m Model) load() tea.Cmd {
	mgr := m.mgr
	return func() tea.Msg {
		sinks, err := mgr.Sinks()
		if err != nil {
			return loadedMsg{err: err}
		}
		groups, err := mgr.Groups()
		if err != nil {
			return loadedMsg{err: err}
		}
		return loadedMsg{sinks: sinks, groups: groups}
	}
}

func (m Model) create() tea.Cmd {
	mgr := m.mgr
	title := strings.TrimSpace(m.name.Value())
	members := m.memberNames()
	return func() tea.Msg {
		created, err := mgr.Create(audio.CreateOptions{
			Title:       title,
			Members:     members,
			MakeDefault: m.routeDefault,
			MoveStreams: m.moveStreams,
		})
		return createdMsg{created: created, err: err}
	}
}

func (m Model) unlink(group combine.Group) tea.Cmd {
	mgr := m.mgr
	return func() tea.Msg {
		title, err := mgr.Unlink(group.SinkName)
		if title == "" {
			title = group.Title
		}
		if err != nil {
			return unlinkedMsg{err: err}
		}
		return unlinkedMsg{titles: []string{title}}
	}
}

func (m Model) unlinkAll() tea.Cmd {
	mgr := m.mgr
	return func() tea.Msg {
		titles, err := mgr.UnlinkAll()
		return unlinkedMsg{titles: titles, err: err}
	}
}

func (m Model) connectOffline() tea.Cmd {
	mgr := m.mgr
	return func() tea.Msg {
		return connectedMsg{results: mgr.Connect(nil)}
	}
}

// Update handles one message.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case loadedMsg:
		m.busy = false
		if msg.err != nil {
			m.status = styleError.Render("error: " + msg.err.Error())
			return m, nil
		}
		m.sinks, m.groups = msg.sinks, msg.groups
		m = m.clampCursors()
		return m, nil
	case createdMsg:
		m.busy = false
		if msg.err != nil {
			m.status = styleError.Render("error: " + msg.err.Error())
			return m, nil
		}
		m.screen = screenMain
		m.selected = map[string]bool{}
		// The new join is the interesting object now, so the unlink key works right away.
		m.focus = paneJoined
		m.groupCursor = 0
		var message strings.Builder
		fmt.Fprintf(&message, "joined %q: %s", msg.created.Group.Title, m.memberTitles(msg.created.Group.Members))
		if msg.created.Group.Default {
			message.WriteString("; default output")
		}
		if msg.created.MovedStreams > 0 {
			fmt.Fprintf(&message, "; moved %d stream(s)", msg.created.MovedStreams)
		}
		if !msg.created.Group.Default && msg.created.MovedStreams == 0 {
			message.WriteString("; routing unchanged")
		}
		m.status = styleSelected.Render(message.String())
		if len(msg.created.Warnings) > 0 {
			m.status += " " + styleWarn.Render(msg.created.Warnings[0])
		}
		return m, m.load()
	case unlinkedMsg:
		m.busy = false
		if msg.err != nil {
			m.status = styleError.Render("error: " + msg.err.Error())
			return m, m.load()
		}
		m.status = styleSelected.Render("unlinked " + quoteList(msg.titles))
		if len(m.groups) <= len(msg.titles) {
			m.groupCursor = 0
			m.focus = paneOutputs
		}
		return m, m.load()
	case connectedMsg:
		m.busy = false
		m.status = describeConnections(msg.results)
		return m, m.load()
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.busy {
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}
		return m, nil
	}
	switch m.screen {
	case screenName:
		return m.handleNameKey(msg)
	case screenConfirm:
		return m.handleConfirmKey(msg)
	}
	return m.handleMainKey(msg)
}

func (m Model) handleMainKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "tab":
		if len(m.groups) > 0 {
			m.focus = (m.focus + 1) % 2
		} else {
			m.focus = paneOutputs
		}
	case "up", "k":
		m = m.moveCursor(-1)
	case "down", "j":
		m = m.moveCursor(1)
	case "pgup", "ctrl+b":
		m = m.moveCursor(-5)
	case "pgdown", "ctrl+f":
		m = m.moveCursor(5)
	case "home", "g":
		m.cursor, m.groupCursor = 0, 0
	case "end", "G":
		m.cursor = max(0, len(m.sinks)-1)
		m.groupCursor = max(0, len(m.groups)-1)
	case " ":
		m = m.toggle()
	case "a":
		m = m.toggleAll()
	case "s":
		m.routeDefault = !m.routeDefault
	case "m":
		m.moveStreams = !m.moveStreams
	case "enter":
		if m.focus == paneJoined {
			m.status = styleDim.Render("press d to unlink the highlighted joined output")
			return m, nil
		}
		if len(m.selected) < 2 {
			m.status = styleWarn.Render("select at least two outputs with space")
			return m, nil
		}
		m.screen = screenName
		m.name.SetValue(m.defaultTitle())
		m.name.CursorEnd()
		m.name.Focus()
		return m, textinput.Blink
	case "d", "delete":
		if len(m.groups) == 0 {
			m.status = styleDim.Render("no joined output to unlink")
			return m, nil
		}
		if m.focus != paneJoined {
			m.status = styleDim.Render("tab to the joined list to unlink one")
			return m, nil
		}
		m.busy = true
		m.status = styleDim.Render("unlinking " + m.groups[m.groupCursor].Title + "...")
		return m, m.unlink(m.groups[m.groupCursor])
	case "D":
		if len(m.groups) == 0 {
			m.status = styleDim.Render("no joined output to unlink")
			return m, nil
		}
		m.screen = screenConfirm
	case "c":
		m.busy = true
		m.status = styleDim.Render("connecting paired Bluetooth audio devices...")
		return m, m.connectOffline()
	case "r":
		m.busy = true
		m.status = styleDim.Render("reloading...")
		return m, m.load()
	case "esc":
		if len(m.selected) > 0 {
			m.status = styleDim.Render("selection cleared")
		}
		m.selected = map[string]bool{}
	}
	return m, nil
}

func (m Model) handleNameKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.screen = screenMain
		m.name.Blur()
		return m, nil
	case "enter":
		m.busy = true
		m.status = styleDim.Render("joining...")
		return m, m.create()
	}
	var cmd tea.Cmd
	m.name, cmd = m.name.Update(msg)
	return m, cmd
}

func (m Model) handleConfirmKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "y", "Y":
		m.screen = screenMain
		m.busy = true
		m.status = styleDim.Render("unlinking every joined output...")
		return m, m.unlinkAll()
	case "n", "N", "esc", "q", "ctrl+c":
		m.screen = screenMain
		m.status = styleDim.Render("kept the joined outputs")
	}
	return m, nil
}

func (m Model) moveCursor(delta int) Model {
	if m.focus == paneJoined {
		m.groupCursor = clamp(m.groupCursor+delta, 0, max(0, len(m.groups)-1))
		return m
	}
	m.cursor = clamp(m.cursor+delta, 0, max(0, len(m.sinks)-1))
	return m
}

func (m Model) toggle() Model {
	if m.focus != paneOutputs || len(m.sinks) == 0 {
		return m
	}
	sink := m.sinks[m.cursor]
	if combine.IsCombined(sink) {
		m.status = styleWarn.Render("a joined output cannot be a member; unlink it first")
		return m
	}
	if m.selected[sink.Name] {
		delete(m.selected, sink.Name)
		return m
	}
	if len(m.selected) >= 8 {
		m.status = styleWarn.Render("eight outputs is the limit for one join")
		return m
	}
	m.selected[sink.Name] = true
	return m
}

func (m Model) toggleAll() Model {
	if m.focus != paneOutputs {
		return m
	}
	selectable := 0
	for _, sink := range m.sinks {
		if !combine.IsCombined(sink) {
			selectable++
		}
	}
	if len(m.selected) == selectable && selectable > 0 {
		m.selected = map[string]bool{}
		return m
	}
	for _, sink := range m.sinks {
		if !combine.IsCombined(sink) {
			m.selected[sink.Name] = true
		}
	}
	return m
}

func (m Model) clampCursors() Model {
	m.cursor = clamp(m.cursor, 0, max(0, len(m.sinks)-1))
	m.groupCursor = clamp(m.groupCursor, 0, max(0, len(m.groups)-1))
	return m
}

// memberNames returns the selected sinks in display order.
func (m Model) memberNames() []string {
	names := make([]string, 0, len(m.selected))
	for _, sink := range m.sinks {
		if m.selected[sink.Name] {
			names = append(names, sink.Name)
		}
	}
	return names
}

// defaultTitle builds the name that the wizard offers.
func (m Model) defaultTitle() string {
	descriptions := make([]string, 0, len(m.selected))
	for _, sink := range m.sinks {
		if m.selected[sink.Name] {
			descriptions = append(descriptions, sink.Description)
		}
	}
	return strings.Join(descriptions, " + ")
}

func (m Model) memberTitles(members []string) string {
	descriptions := make([]string, 0, len(members))
	for _, member := range members {
		descriptions = append(descriptions, m.describe(member))
	}
	return strings.Join(descriptions, " + ")
}

func (m Model) describe(sinkName string) string {
	for _, sink := range m.sinks {
		if sink.Name == sinkName {
			return sink.Description
		}
	}
	return strings.TrimSuffix(strings.TrimPrefix(sinkName, "bluez_output."), ".1")
}

func describeConnections(results []audio.Connected) string {
	if len(results) == 0 {
		return styleDim.Render("every paired Bluetooth audio device is already connected")
	}
	var lines []string
	for _, result := range results {
		switch {
		case result.Err != nil:
			lines = append(lines, styleError.Render(result.Device.Name+": "+result.Err.Error()))
		case result.Sink != "":
			lines = append(lines, styleSelected.Render("connected "+result.Device.Name))
		}
	}
	return strings.Join(lines, " ")
}

// View renders the wizard.
func (m Model) View() string {
	if m.width < 48 || m.height < 12 {
		return "kdn-audio needs a terminal of at least 48x12"
	}
	if m.screen == screenName {
		return m.nameView()
	}
	if m.screen == screenConfirm {
		return m.confirmView()
	}
	return m.mainView()
}

func (m Model) mainView() string {
	lines := []string{m.titleLine(), ""}
	body := m.height - 7
	if body < 3 {
		body = 3
	}
	joinedBody := 1
	if len(m.groups) > 0 {
		joinedBody = body * 2 / 5
	}
	if joinedBody < 1 {
		joinedBody = 1
	}
	outputBody := body - joinedBody
	if outputBody < 1 {
		outputBody = 1
		joinedBody = body - 1
	}
	lines = append(lines, m.headerLine(fmt.Sprintf("Outputs (%d of %d selected)", len(m.selected), m.selectableCount())))
	lines = append(lines, m.outputLines(outputBody)...)
	lines = append(lines, m.headerLine(fmt.Sprintf("Joined outputs (%d)", len(m.groups))))
	lines = append(lines, m.joinedLines(joinedBody)...)
	lines = append(lines, fit(styleDim.Render(m.routingLine()), m.width))
	lines = append(lines, fitOrEmpty(m.status, m.width))
	lines = append(lines, styleHelp.Render(fit(m.helpLine(), m.width)))
	return strings.Join(lines, "\n")
}

func (m Model) titleLine() string {
	left := styleTitle.Render("kdn-audio")
	right := ""
	if def, ok := m.defaultSink(); ok {
		right = styleDim.Render("default: " + def)
	}
	gap := m.width - lipgloss.Width(left) - lipgloss.Width(right)
	if gap < 1 {
		return fit(left, m.width)
	}
	return fit(left+strings.Repeat(" ", gap)+right, m.width)
}

func (m Model) defaultSink() (string, bool) {
	for _, group := range m.groups {
		if group.Default {
			return group.Title, true
		}
	}
	return "", false
}

func (m Model) headerLine(text string) string {
	return fit(styleHeader.Render(text), m.width)
}

func (m Model) selectableCount() int {
	count := 0
	for _, sink := range m.sinks {
		if !combine.IsCombined(sink) {
			count++
		}
	}
	return count
}

func (m Model) outputLines(height int) []string {
	if len(m.sinks) == 0 {
		return padLines([]string{styleDim.Render("  no audio output found")}, m.width, height)
	}
	m.offset = normalizeOffset(m.offset, m.cursor, height, len(m.sinks))
	descWidth := m.descriptionWidth()
	rows := make([]string, 0, height)
	for index := m.offset; index < len(m.sinks) && len(rows) < height; index++ {
		sink := m.sinks[index]
		cursor := "  "
		if index == m.cursor {
			if m.focus == paneOutputs {
				cursor = "> "
			} else {
				cursor = "| "
			}
		}
		mark := "[ ]"
		if combine.IsCombined(sink) {
			mark = " - "
		} else if m.selected[sink.Name] {
			mark = "[x]"
		}
		row := fmt.Sprintf("%s%s %s %-10s %-12s %s",
			cursor,
			styleSelected.Render(mark),
			pad(sink.Description, descWidth),
			sink.Kind(),
			truncate(sink.Detail(), 12),
			sink.State,
		)
		if index == m.cursor {
			row = styleCursor.Render(row)
		}
		rows = append(rows, fit(row, m.width))
	}
	return padLines(rows, m.width, height)
}

func (m Model) joinedLines(height int) []string {
	if len(m.groups) == 0 {
		return padLines([]string{styleDim.Render("  none; select two or more outputs and press enter")}, m.width, height)
	}
	m.groupOffset = normalizeOffset(m.groupOffset, m.groupCursor, height, len(m.groups))
	rows := make([]string, 0, height)
	for index := m.groupOffset; index < len(m.groups) && len(rows) < height; index++ {
		group := m.groups[index]
		cursor := "  "
		if index == m.groupCursor {
			if m.focus == paneJoined {
				cursor = "> "
			} else {
				cursor = "| "
			}
		}
		suffix := ""
		if len(group.PreviousDefault) > 0 && group.Default {
			suffix = "  previous: " + m.describe(group.PreviousDefault)
		}
		row := fmt.Sprintf("%s%s  %s  [%s]%s",
			cursor,
			pad(group.Title, m.descriptionWidth()),
			m.memberTitles(group.Members),
			statusWord(group),
			suffix,
		)
		if index == m.groupCursor {
			row = styleCursor.Render(row)
		}
		rows = append(rows, fit(row, m.width))
	}
	return padLines(rows, m.width, height)
}

func statusWord(group combine.Group) string {
	if group.Default {
		return "default"
	}
	return "joined"
}

func (m Model) descriptionWidth() int {
	width := 32
	for _, sink := range m.sinks {
		if len(sink.Description) > width {
			width = len(sink.Description)
		}
	}
	if width > m.width-40 {
		width = m.width - 40
	}
	if width < 12 {
		width = 12
	}
	return width
}

func (m Model) routingLine() string {
	mark := func(on bool) string {
		if on {
			return "[x]"
		}
		return "[ ]"
	}
	return fmt.Sprintf("after joining: %s set as default (s)   %s move playing streams (m)",
		mark(m.routeDefault), mark(m.moveStreams))
}

func (m Model) helpLine() string {
	switch m.focus {
	case paneJoined:
		return "tab back · d unlink · D unlink all · s default · m move · c connect · r reload · q quit"
	}
	return "space select · a all/none · enter join · tab joined · s default · m move · c connect · q quit"
}

func (m Model) nameView() string {
	var builder strings.Builder
	builder.WriteString(styleTitle.Render("Name the joined output"))
	builder.WriteString("\n\n")
	builder.WriteString("  " + m.memberTitles(m.memberNames()))
	builder.WriteString("\n\n")
	builder.WriteString("  " + m.name.View())
	builder.WriteString("\n\n")
	builder.WriteString(styleHelp.Render("  enter join · esc back"))
	return builder.String()
}

func (m Model) confirmView() string {
	titles := make([]string, 0, len(m.groups))
	for _, group := range m.groups {
		titles = append(titles, group.Title)
	}
	return strings.Join([]string{
		styleTitle.Render("Unlink every joined output?"),
		"",
		"  " + strings.Join(titles, ", "),
		"",
		styleWarn.Render("  y unlink · n keep"),
	}, "\n")
}

func normalizeOffset(offset, cursor, height, total int) int {
	if height <= 0 {
		return 0
	}
	if cursor < offset {
		offset = cursor
	}
	if cursor >= offset+height {
		offset = cursor - height + 1
	}
	if offset > total-height {
		offset = max(0, total-height)
	}
	if offset < 0 {
		offset = 0
	}
	return offset
}

func pad(text string, width int) string {
	if len(text) > width {
		text = truncate(text, width)
	}
	if missing := width - len(text); missing > 0 {
		text += strings.Repeat(" ", missing)
	}
	return text
}

func truncate(text string, width int) string {
	if width <= 0 {
		return ""
	}
	runes := []rune(text)
	if len(runes) <= width {
		return text
	}
	if width == 1 {
		return "…"
	}
	return string(runes[:width-1]) + "…"
}

func fit(text string, width int) string {
	if lipgloss.Width(text) > width {
		return truncate(text, width)
	}
	return text
}

func fitOrEmpty(text string, width int) string {
	if text == "" {
		return strings.Repeat(" ", width)
	}
	return fit(text, width)
}

func padLines(lines []string, width, height int) []string {
	out := make([]string, height)
	for index := 0; index < height; index++ {
		if index < len(lines) {
			out[index] = fit(lines[index], width)
			continue
		}
		out[index] = strings.Repeat(" ", width)
	}
	return out
}

func clamp(value, low, high int) int {
	if value < low {
		return low
	}
	if value > high {
		return high
	}
	return value
}

func quoteList(items []string) string {
	quoted := make([]string, 0, len(items))
	for _, item := range items {
		quoted = append(quoted, fmt.Sprintf("%q", item))
	}
	return strings.Join(quoted, ", ")
}
