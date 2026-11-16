// kdn-jj-meta attributes jj changes to the agent session that produced them.
//
// It appends the missing attribution trailers to the description of a mutable change, deduplicates
// them, and never deletes or rewrites existing metadata. See docs/kdn-jj-meta.md.
package main

import (
	_ "embed"
	"fmt"
	"os"

	"kdn-jj-meta/cmd"
)

var version = "dev"

//go:embed skill.md
var skillMarkdown string

func main() {
	if err := cmd.NewRoot(version, skillMarkdown).Execute(); err != nil {
		if exit, ok := cmd.AsExitError(err); ok {
			if exit.Err != nil {
				fmt.Fprintln(os.Stderr, "kdn-jj-meta:", exit.Err)
			}
			os.Exit(exit.Code)
		}
		fmt.Fprintln(os.Stderr, "kdn-jj-meta:", err)
		os.Exit(2)
	}
}
