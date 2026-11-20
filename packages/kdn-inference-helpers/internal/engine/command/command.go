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
	"encoding/json"
	"fmt"

	"kdn-inference-helpers/internal/engine"
)

// Spec is one profile: the argv, plus the two facts the runtime would otherwise have to guess.
//
// A diffusion server is the reason this exists. `sd-server` calls its port flag `--listen-port`
// and answers its own API root rather than `/v1/models`, and both facts belong to the deployment,
// not to the runtime.
type Spec struct {
	Argv []string `json:"argv"`
	// ReadyPath is the HTTP path that answers 200 once the profile serves. Empty means
	// `/v1/models`, which is llama-server's answer and the historical default.
	ReadyPath string `json:"readyPath,omitempty"`
	// Port is where this profile listens. Empty means the deployment's engine port; a diffusion
	// server gets its own, so the frontier's port is never left in TIME_WAIT by it.
	Port int `json:"port,omitempty"`
	// PortFlag is the flag the supervisor appends the port to. Empty means `--port`; the literal
	// value `-` means "this command already knows its port", and nothing is appended.
	PortFlag string `json:"portFlag,omitempty"`
}

// UnmarshalJSON accepts both shapes a person writes: a bare argv array (the original form, still
// used by the GPU-free check) and the object form that carries the two optional facts.
func (s *Spec) UnmarshalJSON(body []byte) error {
	var argv []string
	if err := json.Unmarshal(body, &argv); err == nil {
		s.Argv = argv
		return nil
	}
	type plain Spec
	var p plain
	if err := json.Unmarshal(body, &p); err != nil {
		return fmt.Errorf("a command profile is an argv array or an object with argv/readyPath/portFlag: %w", err)
	}
	*s = Spec(p)
	return nil
}

// Adapter runs one command per profile.
type Adapter struct {
	// Table is the deployment config's profile → spec map.
	Table map[string]Spec
	Order []string
}

// New builds the adapter from the deployment's `commands` block.
func New(commands map[string]Spec) *Adapter {
	a := &Adapter{Table: map[string]Spec{}}
	for name, spec := range commands {
		if len(spec.Argv) == 0 {
			continue
		}
		a.Table[name] = spec
		a.Order = append(a.Order, name)
	}
	return a
}

// Name is the value `--engine` accepts.
func (a *Adapter) Name() string { return "command" }

// Profiles lists the configured profiles.
func (a *Adapter) Profiles() []string { return append([]string(nil), a.Order...) }

// ReadyPath is what the server must answer before the manager calls it ready.
func (a *Adapter) ReadyPath(profile string) string {
	if spec, ok := a.Table[profile]; ok && spec.ReadyPath != "" {
		return spec.ReadyPath
	}
	return "/v1/models"
}

// Prepare returns the configured argv for a profile, with the port flag the supervisor appends.
func (a *Adapter) Prepare(profile string) (engine.Command, error) {
	spec, ok := a.Table[profile]
	if !ok {
		return engine.Command{}, fmt.Errorf("profile %q has no command in the deployment config", profile)
	}
	portFlag := spec.PortFlag
	if portFlag == "" {
		portFlag = "--port"
	}
	if portFlag == "-" {
		portFlag = ""
	}
	return engine.Command{
		Path:     spec.Argv[0],
		Args:     append([]string(nil), spec.Argv[1:]...),
		Port:     spec.Port,
		PortFlag: portFlag,
	}, nil
}

// Stop is a no-op: the supervisor already killed its own child, and a command adapter has no
// side-channel to stop something it did not start.
func (a *Adapter) Stop(ctx context.Context) error {
	_ = ctx
	return nil
}
