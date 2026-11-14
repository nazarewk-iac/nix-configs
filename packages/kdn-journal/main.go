// kdn-journal browses repository tasks and agent journals.
//
// It reads docs/tasks and .cache/agents, prints a compact summary of where the work stands, and
// browses tasks, boards and worklogs in a TUI. See docs/kdn-journal.md.
package main

import (
	"fmt"
	"os"

	"kdn-journal/cmd"
)

var version = "dev"

func main() {
	if err := cmd.NewRoot(version).Execute(); err != nil {
		if exit, ok := cmd.AsExitError(err); ok {
			os.Exit(exit.Code)
		}
		fmt.Fprintln(os.Stderr, "kdn-journal:", err)
		os.Exit(2)
	}
}
