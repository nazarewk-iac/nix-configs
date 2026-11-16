// jj-meta attributes jj changes to the agent session that produced them.
//
// It appends the missing attribution trailers to the description of a mutable change, deduplicates
// them, and never deletes or rewrites existing metadata. See docs/jj-meta.md.
package main

import (
	"fmt"
	"os"

	"jj-meta/cmd"
)

var version = "dev"

func main() {
	if err := cmd.NewRoot(version).Execute(); err != nil {
		if exit, ok := cmd.AsExitError(err); ok {
			if exit.Err != nil {
				fmt.Fprintln(os.Stderr, "jj-meta:", exit.Err)
			}
			os.Exit(exit.Code)
		}
		fmt.Fprintln(os.Stderr, "jj-meta:", err)
		os.Exit(2)
	}
}
