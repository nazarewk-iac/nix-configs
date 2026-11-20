// Package strata is the first engine adapter: it knows Strata's profile flags, how to materialise a
// profile config from the one the Terminal wrote, and how to stop an engine it did not spawn.
//
// Everything here is specific to Strata on purpose. The core (proxy, leases, drain, journal) never
// imports this package; the binary wires it in by name.
package strata

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"kdn-inference-helpers/internal/config"
	"kdn-inference-helpers/internal/engine"
)

// Profile is one operating point: a base config, a VRAM reserve and how much K/V stays resident.
type Profile struct {
	Name       string
	Base       string
	ReserveMiB int
	KVResident int
}

// defaults is the measured table for brys (docs/tasks/2026-11/brys-r9700-model-fit). A deployment
// can retune a row through `config.Profiles` without a rebuild.
var defaults = []Profile{
	{Name: "max", Base: "unsloth-ud-iq4_xs", ReserveMiB: 1024, KVResident: 32768},
	{Name: "omni-fast", Base: "iq2_xs", ReserveMiB: 21500, KVResident: 4096},
	{Name: "omni-max", Base: "unsloth-ud-iq4_xs", ReserveMiB: 21500, KVResident: 4096},
}

// Adapter serves Strata profiles.
type Adapter struct {
	Bin      string
	DataDir  string
	profiles map[string]Profile
	order    []string
}

// New builds the adapter, applying the deployment's profile overrides.
func New(bin, dataDir string, overrides map[string]config.ProfileOverride) *Adapter {
	a := &Adapter{Bin: bin, DataDir: dataDir, profiles: map[string]Profile{}}
	for _, p := range defaults {
		if o, ok := overrides[p.Name]; ok {
			if o.ReserveMiB != nil {
				p.ReserveMiB = *o.ReserveMiB
			}
			if o.KVResident != nil {
				p.KVResident = *o.KVResident
			}
		}
		a.profiles[p.Name] = p
		a.order = append(a.order, p.Name)
	}
	return a
}

// Name is the value `--engine` accepts.
func (a *Adapter) Name() string { return "strata" }

// Profiles lists the operating points in table order.
func (a *Adapter) Profiles() []string { return append([]string(nil), a.order...) }

// Profile returns one row, for the manager's expected-cost table.
func (a *Adapter) Profile(name string) (Profile, bool) {
	p, ok := a.profiles[name]
	return p, ok
}

// ReadyPath is the endpoint that answers 200 once the engine serves.
func (a *Adapter) ReadyPath(string) string { return "/v1/models" }

// Prepare materialises `<data>/strata/profiles/strata-<profile>.json` from the base config and
// returns the command that serves it.
func (a *Adapter) Prepare(profile string) (engine.Command, error) {
	p, ok := a.profiles[profile]
	if !ok {
		return engine.Command{}, fmt.Errorf("unknown profile %q", profile)
	}
	cfgPath, err := a.materialise(p)
	if err != nil {
		return engine.Command{}, err
	}
	return engine.Command{
		Path:     a.Bin,
		Args:     []string{"serve", "--profile", cfgPath, "--host", "127.0.0.1"},
		PortFlag: "--port",
	}, nil
}

func (a *Adapter) materialise(p Profile) (string, error) {
	basePath := filepath.Join(a.DataDir, "strata", "install", "strata-"+p.Base+".json")
	base, err := os.ReadFile(basePath)
	if err != nil {
		return "", fmt.Errorf("no base config at %s; run `strata serve --profile` once for it: %w", basePath, err)
	}
	patched, err := PatchConfig(base, p)
	if err != nil {
		return "", fmt.Errorf("%s: %w", basePath, err)
	}
	outDir := filepath.Join(a.DataDir, "strata", "profiles")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return "", err
	}
	outPath := filepath.Join(outDir, "strata-"+p.Name+".json")
	if err := os.WriteFile(outPath, patched, 0o644); err != nil {
		return "", err
	}
	return outPath, nil
}

// Stop asks the Terminal to stop an engine this runtime did not spawn. The supervisor already kills
// its own child with a process-group signal; this catches a leftover from another manager instance or
// the manual `strata-frontier` fallback, which `serve` cannot identify on its own.
func (a *Adapter) Stop(ctx context.Context) error {
	if a.Bin == "" {
		return nil
	}
	cmd := exec.CommandContext(ctx, a.Bin, "launch", "--stop")
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("strata launch --stop: %w", err)
	}
	return nil
}

// PatchConfig applies a profile to a base config's `args`. Only the two profile flags change; every
// other argument is preserved verbatim, which is what keeps the tuned flags (dflash2, k8v4, rope,
// MTP) identical across profiles.
func PatchConfig(base []byte, p Profile) ([]byte, error) {
	var cfg map[string]any
	if err := json.Unmarshal(base, &cfg); err != nil {
		return nil, fmt.Errorf("base config is not a JSON object: %w", err)
	}
	rawArgs, ok := cfg["args"].([]any)
	if !ok {
		return nil, fmt.Errorf("base config has no args array")
	}
	args := make([]string, 0, len(rawArgs)+4)
	for _, raw := range rawArgs {
		s, ok := raw.(string)
		if !ok {
			return nil, fmt.Errorf("base config has a non-string argument: %v", raw)
		}
		args = append(args, s)
	}
	args = setFlag(args, "--vram-reserve-mib", fmt.Sprint(p.ReserveMiB))
	args = setFlag(args, "--kv-resident", fmt.Sprint(p.KVResident))
	out := make([]any, len(args))
	for i, a := range args {
		out[i] = a
	}
	cfg["args"] = out
	return json.MarshalIndent(cfg, "", " ")
}

func setFlag(args []string, flag, value string) []string {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == flag {
			args[i+1] = value
			return args
		}
	}
	return append(args, flag, value)
}
