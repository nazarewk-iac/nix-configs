// kdn-okf indexes, searches and browses Open Knowledge Format v0.2 bundles.
//
// It walks a bundle, parses every concept, and exposes the knowledge graph, trust and freshness as
// a CLI and a TUI. See docs/kdn-okf.md.
package main

import (
	_ "embed"
	"fmt"
	"os"

	"kdn-okf/cmd"
)

var version = "dev"

//go:embed skill.md
var skillMarkdown string

func main() {
	// Bubble Tea v1 queries the terminal background in its package init. The packaged wrapper
	// sets CI=1 so termenv skips that query; restore the environment before the CLI runs so the
	// TUI, the editor hand-off and child processes see the user's real CI state. Without this, a
	// late OSC 11 response prints into the shell after `kdn-okf version`.
	if os.Getenv("KDN_OKF_NO_OSC") == "1" {
		_ = os.Unsetenv("CI")
	}
	if err := cmd.NewRoot(version, skillMarkdown).Execute(); err != nil {
		if exit, ok := cmd.AsExitError(err); ok {
			if exit.Err != nil {
				fmt.Fprintln(os.Stderr, "kdn-okf:", exit.Err)
			}
			os.Exit(exit.Code)
		}
		fmt.Fprintln(os.Stderr, "kdn-okf:", err)
		os.Exit(2)
	}
}
