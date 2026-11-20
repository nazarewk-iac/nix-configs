// Package command is the second engine adapter: a profile is any command, and the runtime does not
// know or care what serves the port.
//
// It exists for two reasons. It proves the adapter boundary is real — a second engine is a Go file
// plus configuration, not a change to the core — and it makes the whole runtime testable with a
// tiny model and no GPU: a Nix check starts llama-server on `stories260K`, hands it to the manager
// as an "engine", and the switch, the drain and the companion gate all run for real.
package command

import (
	"context"
	"fmt"
	"kdn-inference-helpers/internal/engine"
)

// Adapter runs one command per profile.
type Adapter struct {
	// Table is the deployment config's profile → argv map.
	Table map[string][]string
	Order []string
}

// New builds the adapter from the deployment's `commands` block.
func New(commands map[string][]string) *Adapter {
	a := &Adapter{Table: map[string][]string{}}
	for name, argv := range commands {
		if len(argv) == 0 {
			continue
		}
		a.Table[name] = argv
		a.Order = append(a.Order, name)
	}
	return a
}

// Name is the value `--engine` accepts.
func (a *Adapter) Name() string { return "command" }

// Profiles lists the configured profiles.
func (a *Adapter) Profiles() []string { return append([]string(nil), a.Order...) }

// ReadyPath is what the engine must answer before the manager calls it ready.
func (a *Adapter) ReadyPath() string { return "/v1/models" }

// Prepare returns the configured argv for a profile, appending the port the supervisor adds.
func (a *Adapter) Prepare(profile string) (engine.Command, error) {
	argv, ok := a.Table[profile]
	if !ok {
		return engine.Command{}, fmt.Errorf("profile %q has no command in the deployment config", profile)
	}
	return engine.Command{Path: argv[0], Args: append([]string(nil), argv[1:]...)}, nil
}

// Stop is a no-op: the supervisor already killed its own child, and a command adapter has no
// side-channel to stop something it did not start.
func (a *Adapter) Stop(ctx context.Context) error {
	_ = ctx
	return nil
}
