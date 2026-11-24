// kdn-audio joins several audio outputs into one virtual output.
//
// It drives PipeWire's PulseAudio interface: one `module-combine-sink` instance per joined output,
// with every fact about it stored as a property on the sink that the module creates. See
// docs/kdn-audio.md.
package main

import (
	"fmt"
	"os"

	"kdn-audio/cmd"
)

var version = "dev"

func main() {
	// Bubble Tea queries the terminal background in its package init. The packaged wrapper sets
	// CI=1 so termenv skips that query; restore the environment before the CLI runs so the TUI
	// and child processes see the user's real CI state.
	if os.Getenv("KDN_AUDIO_NO_OSC") == "1" {
		_ = os.Unsetenv("CI")
	}
	if err := cmd.NewRoot(version).Execute(); err != nil {
		if exit, ok := cmd.AsExitError(err); ok {
			os.Exit(exit.Code)
		}
		fmt.Fprintln(os.Stderr, "kdn-audio:", err)
		os.Exit(1)
	}
}
