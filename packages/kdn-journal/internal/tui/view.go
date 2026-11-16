package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

var (
	styleTitle  = lipgloss.NewStyle().Bold(true)
	styleTabOn  = lipgloss.NewStyle().Bold(true).Reverse(true)
	styleTabOff = lipgloss.NewStyle().Faint(true)
	styleDim    = lipgloss.NewStyle().Faint(true)
	styleStatus = lipgloss.NewStyle().Faint(true).Italic(true)
	styleDiv    = lipgloss.NewStyle().Faint(true)
)

// View renders the whole screen.
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

// facetLine shows the active facet filter and sort mode, and the keys that change them.
func (m Model) facetLine() string {
	parts := []string{}
	if m.tab == TabSessions {
		parts = append(parts, "harness="+orDefault(m.harnessFilter, "all"))
	} else {
		parts = append(parts, "status="+orDefault(m.statusFilter, "all"))
	}
	parts = append(parts, "sort="+m.sortLabel())
	return styleDim.Render("filters: " + strings.Join(parts, " · ") + "   f facet · s sort · c clear")
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

// bodyLines renders the list and the detail, or the detail alone in full mode.
func (m Model) bodyLines() []string {
	height := m.bodyHeight()
	if m.fullDetail {
		return padLines(splitLines(m.detail.View()), m.width, height)
	}
	leftWidth := m.leftWidth()
	rightWidth := m.paneWidth()
	left := padLines(splitLines(m.listModel().View()), leftWidth, height)
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

// fit pads or truncates one line to exactly width columns. ANSI sequences do not count.
func fit(s string, width int) string {
	if width <= 0 {
		return ""
	}
	if lipgloss.Width(s) > width {
		s = ansi.Truncate(s, width, "…")
	}
	if pad := width - lipgloss.Width(s); pad > 0 {
		s += strings.Repeat(" ", pad)
	}
	return s
}

func trunc(s string, width int) string {
	if width <= 0 {
		return ""
	}
	if lipgloss.Width(s) <= width {
		return s
	}
	return ansi.Truncate(s, width, "…")
}
