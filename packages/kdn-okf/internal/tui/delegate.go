package tui

import (
	"fmt"
	"io"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"kdn-okf/internal/okf"
)

var (
	styleTitle      = lipgloss.NewStyle().Bold(true)
	styleTabOff     = lipgloss.NewStyle().Faint(true)
	styleDim        = lipgloss.NewStyle().Faint(true)
	styleStatus     = lipgloss.NewStyle().Faint(true).Italic(true)
	styleDiv        = lipgloss.NewStyle().Faint(true)
	styleItemTitle  = lipgloss.NewStyle().Bold(true)
	styleItemDesc   = lipgloss.NewStyle().Faint(true)
	styleItemMarker = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))

	chipDraft      = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("60")).Foreground(lipgloss.Color("231"))
	chipStable     = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("35")).Foreground(lipgloss.Color("16"))
	chipDeprecated = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("130")).Foreground(lipgloss.Color("231"))
	chipUnknown    = lipgloss.NewStyle().Background(lipgloss.Color("90")).Foreground(lipgloss.Color("231"))
)

// conceptItem adapts a concept to the list.
type conceptItem struct{ concept *okf.Concept }

func (i conceptItem) Title() string { return i.concept.Title }

func (i conceptItem) Description() string {
	parts := []string{i.concept.Type, i.concept.Status, i.concept.Trust.String()}
	if i.concept.Stale {
		parts = append(parts, "stale")
	}
	if i.concept.Description != "" {
		parts = append(parts, i.concept.Description)
	}
	return strings.Join(parts, " · ")
}

func (i conceptItem) FilterValue() string {
	return strings.Join([]string{
		i.concept.ID,
		i.concept.Title,
		i.concept.Type,
		i.concept.Status,
		i.concept.Trust.String(),
		strings.Join(i.concept.Tags, " "),
	}, " ")
}

// Label returns the status chip.
func (i conceptItem) Label() (string, lipgloss.Style) {
	return statusChip(i.concept.Status)
}

func statusChip(status string) (string, lipgloss.Style) {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "draft":
		return "◇ draft", chipDraft
	case "stable":
		return "◆ stable", chipStable
	case "deprecated":
		return "⊘ deprecated", chipDeprecated
	}
	return "? " + status, chipUnknown
}

// itemDelegate renders two lines per concept: a status chip plus the title, then a dim summary.
type itemDelegate struct{}

func (d itemDelegate) Height() int  { return 2 }
func (d itemDelegate) Spacing() int { return 0 }

func (d itemDelegate) Update(tea.Msg, *list.Model) tea.Cmd { return nil }

func (d itemDelegate) Render(w io.Writer, m list.Model, index int, item list.Item) {
	concept, ok := item.(conceptItem)
	if !ok {
		return
	}
	width := m.Width() - 2
	if width < 10 {
		width = 10
	}
	marker := "  "
	title := concept.Title()
	if index == m.Index() {
		marker = styleItemMarker.Render("▸ ")
		title = styleItemTitle.Render(title)
	}
	label, style := concept.Label()
	chip := style.Render(fmt.Sprintf("%-16s", label))
	line1 := marker + chip + " " + title
	line2 := "  " + styleItemDesc.Render(concept.Description())
	fmt.Fprint(w, fit(line1, width)+"\n"+fit(line2, width))
}
