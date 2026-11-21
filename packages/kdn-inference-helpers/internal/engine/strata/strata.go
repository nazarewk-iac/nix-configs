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

// defaults is the measured table for brys (docs/tasks/2026-11/brys-r9700-model-fit, "The swarm
// profiles").
// A deployment can retune a row through `config.Profiles` without a rebuild.
//
// `KVResident` is 32768 cells of each QSA layer for every frontier profile: it is a per-layer
// streaming window shared by the slots, not a per-slot allocation, so 32768 is what 8 slots x 4k
// needs. The omni profiles used to run 4096, which at 8 slots is 512 cells per slot.
//
// The four `max-*`/`fast-swarm` rows are one decision, taken 2026-11-21: the resting profile is a
// swarm, not the single 1M session it used to be. The reason is concurrency — an agent fleet asks
// for several short sessions far more often than for one million-token one — and 1M is now an
// explicit request (`max-long`) instead of the default. The older decision of the same day ("`max`
// is the primary and resting profile") is overridden, not forgotten.
//
// Measured on the R9700, 125 GiB RAM, no swap, one load per row, five concurrent 64-token requests
// plus a saturated batch of one request per slot:
//
//	profile      pack         ctx  slots  K/V total  MemAvailable  VRAM    aggregate t/s
//	max-multi    UD-IQ4_XS    512k     6     28.7 GiB       6.6 GiB  30.8 GiB   30.7 saturated
//	max-swarm    UD-IQ4_XS    256k     8     19.1 GiB      18.4 GiB  30.8 GiB   36.2 saturated
//	max-long     UD-IQ4_XS     1M      2     19.1 GiB      10.5 GiB  30.8 GiB   29.7 saturated
//	fast-swarm   IQ2_XS        384k     8     28.7 GiB      31.4 GiB  30.8 GiB   61.0 saturated
//
// Every row is the maximum slot count that fits: eight is the engine's cap (SLOTS_MAX), and 1M at
// two slots is where the long profile stops — three would fit arithmetically but the host has
// hard-reset twice under a long prefill, so the window keeps one slot of headroom for it.
//
// `max-multi` moved from 384k x 8 to 512k x 6 by the owner's decision of 2026-11-21: the same
// 28.7 GiB of pinned K/V buys a longer window per slot, at 6.6 GiB of MemAvailable instead of 8.1
// (and 2.9 GiB while two `rustc` builds run). Seven slots measured 2.0 GiB and a 130 s load, so the
// count stops at six; five would leave 12.0 GiB and decodes no faster (31.9 against 30.7 t/s
// saturated), because the expert cache shrinks as the slot sessions grow.
//
// `fast-swarm` carries the concurrency (IQ2_XS is 22 GiB of experts lighter, so 1.9x the aggregate
// of the same shape on the better pack); `max-multi` rests because it is the better pack at the
// same slot count, and the fleet can switch to `fast-swarm` when throughput matters more than the
// 88.9% top-token agreement.
var defaults = []Profile{
	{
		Name: "max-multi", Base: "unsloth-ud-iq4_xs", ReserveMiB: 1024, KVResident: 32768, Parallel: 6,
		MaxContext: 524288, RopeScale: 2, ConversationCacheMiB: 2048, PLEIO: "mmap",
	},
	{
		Name: "max-swarm", Base: "unsloth-ud-iq4_xs", ReserveMiB: 1024, KVResident: 32768, Parallel: 8,
		MaxContext: 262144, RopeScale: 1, ConversationCacheMiB: 2048, PLEIO: "mmap",
	},
	{
		Name: "max-long", Base: "unsloth-ud-iq4_xs", ReserveMiB: 1024, KVResident: 32768, Parallel: 2,
		MaxContext: 1048576, RopeScale: 4, ConversationCacheMiB: 1024, PLEIO: "mmap",
	},
	{
		Name: "fast-swarm", Base: "iq2_xs", ReserveMiB: 1024, KVResident: 32768, Parallel: 8,
		MaxContext: 393216, RopeScale: 1.5, ConversationCacheMiB: 2048, PLEIO: "mmap",
	},
	{Name: "omni-fast", Base: "iq2_xs", ReserveMiB: 21500, KVResident: 32768, Parallel: 8},
	{Name: "omni-max", Base: "unsloth-ud-iq4_xs", ReserveMiB: 21500, KVResident: 32768, Parallel: 8},
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
			if o.Parallel != nil {
				p.Parallel = *o.Parallel
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
