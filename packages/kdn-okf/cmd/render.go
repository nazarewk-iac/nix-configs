package cmd

import (
	"strings"

	"github.com/charmbracelet/glamour"
)

// renderMarkdown renders Markdown for the terminal. The CLI uses it only for `show --render`.
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
