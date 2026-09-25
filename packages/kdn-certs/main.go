// kdn-certs is the declarative certificate manager of the nix-configs tree.
//
// It walks the certificate declarations of a flake, deduplicates them, and drives smallstep to
// generate and rotate them. See docs/tasks/2026-09/declarative-certificates/design.md.
package main

import (
	"fmt"
	"os"

	"kdn-certs/cmd"
)

func main() {
	if err := cmd.NewRoot().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "kdn-certs:", err)
		os.Exit(1)
	}
}
