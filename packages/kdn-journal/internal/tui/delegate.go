package tui

import (
	"fmt"
	"io"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// labeledItem is a list item that carries a colored badge: a status for a task, a harness for a
// session. The delegate renders the badge in a fixed-width column so the titles line up.
type labeledItem interface {
	list.Item
	Title() string
	Description() string
	Label() (string, lipgloss.Style)
}

// Badges are filled chips: a glyph, a word and a background. The foreground is chosen for the
// chip's own background, so the palette works on a dark and a light terminal. lipgloss drops the
// background and the color under NO_COLOR, which leaves the glyph and the word readable.
var (
	chipOpen         = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("25")).Foreground(lipgloss.Color("231"))
	chipInProgress   = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("214")).Foreground(lipgloss.Color("16"))
	chipBlocked      = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("160")).Foreground(lipgloss.Color("231"))
	chipDone         = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("35")).Foreground(lipgloss.Color("16"))
	chipNotScheduled = lipgloss.NewStyle().Background(lipgloss.Color("240")).Foreground(lipgloss.Color("231"))
	chipUnknown      = lipgloss.NewStyle().Background(lipgloss.Color("90")).Foreground(lipgloss.Color("231"))
	chipOpenCode     = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("25")).Foreground(lipgloss.Color("231"))
	chipPi           = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("60")).Foreground(lipgloss.Color("231"))
	chipClaude       = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("130")).Foreground(lipgloss.Color("231"))
	chipCodex        = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("24")).Foreground(lipgloss.Color("231"))
	styleItemTitle   = lipgloss.NewStyle().Bold(true)
	styleItemDesc    = lipgloss.NewStyle().Faint(true)
	styleItemMarker  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
)

// statusLabel maps a task status to a glyph and a chip.
func statusLabel(status string) (string, lipgloss.Style) {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "open":
		return "○ open", chipOpen
	case "in-progress":
		return "◐ in-progress", chipInProgress
	case "blocked":
		return "✖ blocked", chipBlocked
	case "done":
		return "✔ done", chipDone
	case "not-scheduled":
		return "· not-scheduled", chipNotScheduled
	case "":
		return "? unknown", chipUnknown
	}
	return "? " + status, chipUnknown
}

// harnessLabel maps a session harness to a chip.
func harnessLabel(harness string) (string, lipgloss.Style) {
	switch strings.ToLower(strings.TrimSpace(harness)) {
	case "opencode":
		return "◆ opencode", chipOpenCode
	case "pi":
		return "◆ pi", chipPi
	case "claude":
		return "◆ claude", chipClaude
	case "codex":
		return "◆ codex", chipCodex
	case "":
		return "? unknown", chipUnknown
	}
	return "◆ " + harness, chipUnknown
}

// itemDelegate renders two lines per item: a colored chip plus the title, then a dim description.
// It keeps the list's selection marker and works with the list's built-in filter.
type itemDelegate struct{}

func (d itemDelegate) Height() int  { return 2 }
func (d itemDelegate) Spacing() int { return 0 }

func (d itemDelegate) Update(tea.Msg, *list.Model) tea.Cmd { return nil }

func (d itemDelegate) Render(w io.Writer, m list.Model, index int, item list.Item) {
	labeled, ok := item.(labeledItem)
	if !ok {
		return
	}
	width := m.Width() - 2
	if width < 10 {
		width = 10
	}
	marker := "  "
	title := labeled.Title()
	if index == m.Index() {
		marker = styleItemMarker.Render("▸ ")
		title = styleItemTitle.Render(title)
	}
	label, style := labeled.Label()
	chip := style.Render(fmt.Sprintf("%-16s", label))
	line1 := marker + chip + " " + title
	line2 := "  " + styleItemDesc.Render(labeled.Description())
	fmt.Fprint(w, fit(line1, width)+"\n"+fit(line2, width))
}
