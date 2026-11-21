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
	"sort"
	"strconv"

	"kdn-inference-helpers/internal/config"
	"kdn-inference-helpers/internal/engine"
)

// Profile is one operating point: a base config, a VRAM reserve, how much K/V stays resident, how
// many requests may decode at once, and the window those slots are carved at.
type Profile struct {
	Name       string
	Base       string
	ReserveMiB int
	KVResident int
	// Parallel is the number of concurrent slots `strata serve` is asked for. It reaches the engine
	// as `--batch N` (verified with `strata serve --plan`), and the engine documents 2..8, so 8 is
	// the maximum. Zero leaves the engine's own default alone.
	Parallel int
	// MaxContext is the window every slot is carved at, and RopeScale is the yarn factor that
	// reaches it (the window over the model's trained 262144). The K/V is carved per slot and is
	// linear in this number: 9.56 KiB per cell with k8v4, so 2.39 GiB for a 256k slot, 3.59 GiB for
	// a 384k slot and 9.56 GiB for a 1M slot. Zero leaves the base config's values alone.
	MaxContext int
	RopeScale  float64
	// ConversationCacheMiB caps the pool that parks idle conversations. It is the one RAM pool a
	// swarm can trade for another live slot, so a multi-slot profile runs it small.
	ConversationCacheMiB int
	// PLEIO is the n-gram table's backing store. `ram` locks about 30 GiB of it; `mmap` leaves it
	// in the page cache, which the kernel reclaims under pressure instead of OOM-killing the
	// engine. Measured 2026-11-21: mmap freed 22-25 GiB and was not slower. Empty keeps the base
	// config's value.
	PLEIO string
	// BatchMTP asks the engine for one MTP proposal per slot per window. Measured 2026-11-21:
	// drafting does survive the batch (140 of 174 proposals accepted, 80.5%) but the eight-slot
	// aggregate falls 12% (61.0 -> 54.0 t/s) and it costs about 3 GiB of RAM, so it stays off.
	BatchMTP bool
}

// There is deliberately no built-in table here. A profile's base config, window, slot count, VRAM
// reserve, resident K/V, park pool, n-gram backing store and rope factor come from the deployment
// file (`config.ProfileSpec`), which on brys is generated from `hosts-den/brys/strata-profiles.nix`
// — the one place they are written. The drift this rule exists for was real: the slot count lived
// here, in the Nix file and in `strata-serve.sh` at the same time, and this package served the two
// omni profiles with 8 slots while the Nix file said 1 and 2.
//
// Explicit fallback for a bare binary: with no deployment file the adapter knows no profiles, so
// `Profiles()` is empty and every `/select` is refused with `unknown profile`. That is intended —
// a built-in copy of the numbers is the failure mode, not the safety net.

// Adapter serves Strata profiles.
type Adapter struct {
	Bin      string
	DataDir  string
	profiles map[string]Profile
	order    []string
}

// New builds the adapter from the deployment's profile table. Every number it serves comes from
// `specs`; there is no table to fall back to, and the order is sorted so it is deterministic (map
// iteration is not).
func New(bin, dataDir string, specs map[string]config.ProfileSpec) *Adapter {
	a := &Adapter{Bin: bin, DataDir: dataDir, profiles: make(map[string]Profile, len(specs))}
	names := make([]string, 0, len(specs))
	for name := range specs {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		s := specs[name]
		p := Profile{Name: name, Base: s.Base, BatchMTP: s.BatchMTP}
		if s.ReserveMiB != nil {
			p.ReserveMiB = *s.ReserveMiB
		}
		if s.KVResident != nil {
			p.KVResident = *s.KVResident
		}
		if s.Parallel != nil {
			p.Parallel = *s.Parallel
		}
		if s.MaxContext != nil {
			p.MaxContext = *s.MaxContext
		}
		if s.RopeScale != nil {
			p.RopeScale = *s.RopeScale
		}
		if s.ConversationCacheMiB != nil {
			p.ConversationCacheMiB = *s.ConversationCacheMiB
		}
		if s.PLEIO != nil {
			p.PLEIO = *s.PLEIO
		}
		a.profiles[name] = p
		a.order = append(a.order, name)
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
	args := []string{"serve", "--profile", cfgPath, "--host", "127.0.0.1"}
	if p.Parallel > 0 {
		// `strata serve` turns this into the engine's `--batch N`, one session per slot.
		args = append(args, "--parallel", strconv.Itoa(p.Parallel))
	}
	return engine.Command{
		Path:     a.Bin,
		Args:     args,
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

// PatchConfig applies a profile to a base config's `args`. The profile flags change — the VRAM
// reserve, the resident window, and (when the profile names them) the context, the yarn factor,
// the parked-conversation pool, the n-gram table's backing store and per-slot MTP drafting — and
// every other argument is preserved verbatim, which is what keeps the tuned flags (dflash2, k8v4,
// rope, MTP) identical across profiles.
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
	if p.MaxContext > 0 {
		args = setFlag(args, "--max-context", fmt.Sprint(p.MaxContext))
	}
	if p.RopeScale > 0 {
		// `1.5`, `1`, `4`: the engine parses a float, and a bare `1` is what its own help prints.
		args = setFlag(args, "--rope-scale", strconv.FormatFloat(p.RopeScale, 'g', -1, 64))
	}
	if p.ConversationCacheMiB > 0 {
		args = setFlag(args, "--conversation-cache-mib", fmt.Sprint(p.ConversationCacheMiB))
	}
	if p.PLEIO != "" {
		args = setFlag(args, "--ple-io", p.PLEIO)
	}
	args = setBoolFlag(args, "--batch-mtp", p.BatchMTP)
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

// setBoolFlag adds or removes a valueless engine flag. The base configs never carry `--batch-mtp`,
// so this mostly guards a hand-edited config that does.
func setBoolFlag(args []string, flag string, on bool) []string {
	kept := args[:0]
	for _, a := range args {
		if a != flag {
			kept = append(kept, a)
		}
	}
	if on {
		kept = append(kept, flag)
	}
	return kept
}
