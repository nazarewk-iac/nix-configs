package pipewire

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Property keys that mark and describe a joined output.
const (
	PropCombined        = "kdn.audio.combined"
	PropMembers         = "kdn.audio.members"
	PropProfile         = "kdn.audio.profile"
	PropCreated         = "kdn.audio.created-at"
	PropPreviousDefault = "kdn.audio.previous-default"
)

// ModuleName is the PipeWire module behind a joined output.
const ModuleName = "libpipewire-module-combine-stream"

// ModuleLine builds the single pw-cli command that loads one combine stream.
//
// The module lives in the pw-cli process, so the line is handed to a long-lived pw-cli and the
// resulting sink is a native PipeWire node, not a PulseAudio compatibility sink.
func ModuleLine(spec JoinSpec, now time.Time) string {
	properties := []string{
		fmt.Sprintf("%q = %q", PropCombined, "yes"),
		fmt.Sprintf("%q = %q", PropMembers, strings.Join(spec.Members, ",")),
		fmt.Sprintf("%q = %q", PropCreated, now.UTC().Format(time.RFC3339)),
	}
	if spec.Profile != "" {
		properties = append(properties, fmt.Sprintf("%q = %q", PropProfile, spec.Profile))
	}
	if spec.PreviousDefault != "" {
		properties = append(properties, fmt.Sprintf("%q = %q", PropPreviousDefault, spec.PreviousDefault))
	}
	rules := make([]string, 0, len(spec.Members))
	for _, member := range spec.Members {
		// The actions form is an object, not an array: an array parses and matches nothing.
		rules = append(rules, fmt.Sprintf(
			`{ matches = [ { node.name = %q } ] actions = { create-stream = { } } }`, member))
	}
	return strings.Join([]string{
		"load-module " + ModuleName + " {",
		"combine.mode = sink",
		"node.name = " + spec.SinkName,
		"node.description = " + strconv.Quote(spec.Title),
		"combine.latency-compensate = true",
		"combine.props = { " + strings.Join(properties, " ") + " }",
		"stream.props = { node.passive = true }",
		"stream.rules = [ " + strings.Join(rules, " ") + " ]",
		"}",
	}, " ")
}

// Host runs the long-lived pw-cli process that hosts one combine stream.
//
// The module and its sink belong to this process, so stopping the service removes the joined
// output and everything it created, with no state left behind.
func Host(spec JoinSpec, now time.Time, stdout, stderr io.Writer) error {
	command := exec.Command("pw-cli")
	command.Stdout = stdout
	command.Stderr = stderr
	stdin, err := command.StdinPipe()
	if err != nil {
		return err
	}
	if err := command.Start(); err != nil {
		return err
	}
	if _, err := io.WriteString(stdin, ModuleLine(spec, now)+"\n"); err != nil {
		_ = command.Process.Kill()
		return err
	}

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT)
	defer signal.Stop(signals)
	go func() {
		<-signals
		_, _ = io.WriteString(stdin, "quit\n")
		time.AfterFunc(3*time.Second, func() {
			if command.Process != nil {
				_ = command.Process.Kill()
			}
		})
	}()
	return command.Wait()
}
