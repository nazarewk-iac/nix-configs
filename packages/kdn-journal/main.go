// kdn-journal browses repository tasks and agent journals.
//
// It reads docs/tasks and .cache/agents, prints a compact summary of where the work stands, and
// browses tasks, boards and worklogs in a TUI. See docs/kdn-journal.md.
package main

import (
	_ "embed"
	"fmt"
	"os"

	"kdn-journal/cmd"
)

var version = "dev"

//go:embed skill.md
var skillMarkdown string

func main() {
	// Bubble Tea v1 queries the terminal background in its package init. The packaged wrapper
	// sets CI=1 so termenv skips that query; restore the environment before the CLI runs so the
	// TUI, the editor hand-off and child processes see the user's real CI state.
	if os.Getenv("KDN_JOURNAL_NO_OSC") == "1" {
		_ = os.Unsetenv("CI")
	}
	if err := cmd.NewRoot(version, skillMarkdown).Execute(); err != nil {
		if exit, ok := cmd.AsExitError(err); ok {
			os.Exit(exit.Code)
		}
		fmt.Fprintln(os.Stderr, "kdn-journal:", err)
		os.Exit(2)
	}
}
