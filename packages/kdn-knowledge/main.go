// kdn-knowledge turns finished agent sessions into short, deduplicated knowledge and skill
// proposals. It reads the OpenCode SQLite database through the sqlite3 CLI, extracts durable
// items with a model of the local fleet, and writes a proposal directory for review.
//
// See docs/tasks/2026-11/knowledge-pipeline/design.md.
package main

import (
	"fmt"
	"os"

	"kdn-knowledge/cmd"
)

var version = "dev"

func main() {
	if err := cmd.Main(os.Args[1:], version, os.Stdout, os.Stderr); err != nil {
		if exit, ok := err.(*cmd.ExitError); ok {
			if exit.Err != nil {
				fmt.Fprintln(os.Stderr, "kdn-knowledge:", exit.Err)
			}
			os.Exit(exit.Code)
		}
		fmt.Fprintln(os.Stderr, "kdn-knowledge:", err)
		os.Exit(2)
	}
}
