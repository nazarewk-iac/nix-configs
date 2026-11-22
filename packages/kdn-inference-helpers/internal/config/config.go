// Package config is the deployment's data: ports, paths, the model-name aliases, which models must
// survive a profile switch, and which privileged hooks the switch runs.
//
// The rule this package exists for: a new deployment is a JSON file, not a code change. The
// defaults below describe brys exactly, so the binary works with no file at all; a second host or a
// second engine overrides only what differs. The one exception is a profile's shape: `Profiles` is
// the whole table and has no built-in fallback (see ProfileSpec), because those numbers must have
// exactly one home.
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"kdn-inference-helpers/internal/engine/command"
)

// Config is everything the runtime needs to know that is not engine-specific.
type Config struct {
	// Engine names the adapter: "strata" today.
	Engine string `json:"engine"`
	// DataDir is the engine's data home (the Strata terminal's XDG data dir on brys).
	DataDir string `json:"dataDir"`
	// EnginePort is where the engine listens; ManagerPort is the control plane.
	EnginePort  int `json:"enginePort"`
	ManagerPort int `json:"managerPort"`
	// SwapURL is llama-swap's base URL, used for the companion view and unloading.
	SwapURL string `json:"swapURL"`
	// StrataBin is the terminal launcher that spawns the engine (adapter-specific, harmless for
	// other engines that ignore it).
	EngineBin string `json:"engineBin"`
	// Aliases maps the model names the fleet exposes onto profile names (`qfn` → `auto`).
	Aliases map[string]string `json:"aliases"`
	// FrontierIDs are the model ids that survive a switch. Every other loaded model is unloaded
	// before the engine stops: that is what frees the companion's VRAM.
	FrontierIDs []string `json:"frontierIDs"`
	// CacheDropCommand is the privileged hook the switch runs before starting the engine. An empty
	// list skips the phase entirely, which is the right answer for an engine whose loads do not
	// need the page cache released.
	CacheDropCommand []string `json:"cacheDropCommand"`
	// PolicyPath is the placement tree and the facts it decides over. Empty means the deployment
	// has not adopted the policy yet.
	PolicyPath string `json:"policyPath"`
	// EngineLog receives the engine child's stdout and stderr.
	EngineLog string `json:"engineLog"`
	// DrainTimeoutSeconds bounds how long a switch waits for in-flight requests.
	DrainTimeoutSeconds int `json:"drainTimeoutSeconds"`
	// LeaseTTLSeconds drops leases from a proxy that died without releasing (SIGKILL).
	LeaseTTLSeconds int `json:"leaseTTLSeconds"`
	// Profiles is the deployment's profile table. It is the whole definition of each operating
	// point, not a delta over a built-in table: the runtime carries no per-profile numbers for a
	// deployment, so a consumer cannot disagree with the file. A bare binary therefore knows no
	// profiles; see ProfileSpec.
	Profiles map[string]ProfileSpec `json:"profiles"`
	// Commands is the `command` adapter's profile table: profile name → argv, plus the two facts the
	// runtime would otherwise guess (the readiness path and the port flag). It exists so the whole
	// runtime can be exercised against a tiny model with no GPU, and so a second engine needs no
	// code.
	Commands map[string]command.Spec `json:"commands"`
	// TextProfiles are the profiles that serve chat. `auto` (the profile-neutral frontier name)
	// keeps only one of these: a chat request must never be answered by a diffusion server, and a
	// switch must never happen behind the caller's back. Anything outside this list is an image or
	// batch profile, and asking for `auto` while one is loaded is refused with a readable error.
	TextProfiles []string `json:"textProfiles"`
	// Gates is the policy for a gated model: which profiles satisfy it, which targets a caller may
	// ask for, and which request field carries the request. The gate itself is generic; this is the
	// deployment's data.
	Gates map[string]GateSpec `json:"gates"`
}

// GateSpec is one gated model's policy. It lives in the config so a second gated model, or a
// different colo tier, is a data change.
type GateSpec struct {
	// RequireProfiles are the profiles that already satisfy the model (they keep the reserve).
	RequireProfiles []string `json:"requireProfiles"`
	// Allow are the profiles a caller may name in the confirmation field.
	Allow []string `json:"allow"`
	// ConfirmField is the request-body field; `kdn_switch_to` when empty.
	ConfirmField string `json:"confirmField"`
}

// ProfileSpec is one operating point, declared by the deployment. It is the whole definition, not
// an override: the runtime keeps no profile table of its own, so a missing knob is a config error
// and not a quietly inherited default. The four numbers a profile cannot do without — the window,
// the slot count, the VRAM reserve and the resident K/V — are pointers on purpose, so "absent" is
// distinguishable from a real zero.
type ProfileSpec struct {
	// Base names the Terminal's per-model config the profile patches: `<dataDir>/strata/install/
	// strata-<base>.json`.
	Base string `json:"base"`
	// MaxContext is the window every slot is carved at (`--max-context`).
	MaxContext *int `json:"maxContext"`
	// Parallel is the concurrent slot count `strata serve` is asked for (engine `--batch N`).
	Parallel *int `json:"parallel"`
	// ReserveMiB is `--vram-reserve-mib`.
	ReserveMiB *int `json:"reserveMiB"`
	// KVResident is `--kv-resident`, the cells of each QSA layer kept in VRAM.
	KVResident *int `json:"kvResident"`
	// RopeScale is the yarn factor that reaches MaxContext. The deployment derives it from the
	// window and the model's native window, so it is never a second knob.
	RopeScale *float64 `json:"ropeScale"`
	// ConversationCacheMiB is `--conversation-cache-mib`. Null keeps the base config's value.
	ConversationCacheMiB *int `json:"conversationCacheMiB"`
	// PLEIO is `--ple-io`. Null keeps the base config's value.
	PLEIO *string `json:"pleIO"`
	// BatchMTP asks the engine for one MTP proposal per slot per window.
	BatchMTP bool `json:"batchMTP,omitempty"`
}

// validate names every knob a profile is missing. A deployment file is written by hand or by Nix
// and a typo there is silent until the first request, so this is a load-time error.
func (p ProfileSpec) validate(name string) error {
	var missing []string
	if p.Base == "" {
		missing = append(missing, "base")
	}
	if p.MaxContext == nil {
		missing = append(missing, "maxContext")
	}
	if p.Parallel == nil {
		missing = append(missing, "parallel")
	}
	if p.ReserveMiB == nil {
		missing = append(missing, "reserveMiB")
	}
	if p.KVResident == nil {
		missing = append(missing, "kvResident")
	}
	if p.RopeScale == nil {
		missing = append(missing, "ropeScale")
	}
	if len(missing) > 0 {
		return fmt.Errorf(
			"profile %q is missing %s: the deployment file is the only source of a profile's knobs",
			name, strings.Join(missing, ", "))
	}
	return nil
}

// Defaults is brys. Values are measured, not guessed; see docs/tasks/2026-11/brys-r9700-model-fit.
//
// There is deliberately no profile table and no name table here: a profile's window, slot count,
// reserve and resident K/V live in `data/llm.nix` only, and its alias, frontier id and text-profile
// rank reach this package through the deployment file. A binary run with no file at all therefore
// knows no profiles and no names and refuses every `/select` — the explicit fallback, because the
// alternative is a second copy of the numbers or the names that silently disagrees with the host.
func Defaults() *Config {
	return &Config{
		Engine:           "strata",
		DataDir:          "/var/lib/kdn/llms/models/.bench/xdg",
		EnginePort:       8080,
		ManagerPort:      8181,
		SwapURL:          "http://127.0.0.1:39700",
		EngineBin:        "/var/lib/kdn/llms/models/.bench/bin/strata",
		PolicyPath:       "/etc/kdn-inference-helpers/policy.json",
		CacheDropCommand: []string{"sudo", "-n", "systemctl", "start", "strata-drop-cache.service"},
		Profiles:         map[string]ProfileSpec{},
		Gates:            map[string]GateSpec{},
		// 1200 s, not 300: a Wan VACE edit measured 1039 s, and a drain shorter than the longest
		// request is a data-loss path — the switch proceeds, the proxy leaves, the edit is cut.
		DrainTimeoutSeconds: 1200,
		LeaseTTLSeconds:     1800,
	}
}

// DefaultPath is where the deployment file lives when nothing else is given: the environment wins,
// then the system path a NixOS module writes, then the built-in brys defaults.
func DefaultPath() string {
	if p := os.Getenv("KDN_INFERENCE_HELPERS_CONFIG"); p != "" {
		return p
	}
	const system = "/etc/kdn-inference-helpers/config.json"
	if _, err := os.Stat(system); err == nil {
		return system
	}
	return ""
}

// Load reads path over the defaults. An empty path returns the defaults, and a partial file only
// overrides the keys it names: a deployment file is a delta, not a full copy of the contract.
func Load(path string) (*Config, error) {
	cfg := Defaults()
	if path == "" {
		return cfg, nil
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("config %s: %w", path, err)
	}
	if err := json.Unmarshal(body, cfg); err != nil {
		return nil, fmt.Errorf("config %s: %w", path, err)
	}
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("config %s: %w", path, err)
	}
	return cfg, nil
}

// Normalise resolves a model-name alias to a profile name. An unknown value is returned unchanged
// so the caller can reject it with the exact string it received.
func (c *Config) Normalise(profile string) string {
	if mapped, ok := c.Aliases[profile]; ok {
		return mapped
	}
	return profile
}

// Accepts reports whether `/select` may receive this value after alias resolution.
//
// The set is derived, not compiled in: `auto` and `none` are the two verbs, every alias target is
// reachable, and every profile the deployment declares (text profiles and command profiles) is a
// destination. Adding an image profile is then a config change, which is the point of the file.
func (c *Config) Accepts(profile string) bool {
	switch profile {
	case "auto", "none":
		return true
	}
	for _, alias := range c.Aliases {
		if alias == profile {
			return true
		}
	}
	if contains(c.TextProfiles, profile) {
		return true
	}
	_, ok := c.Commands[profile]
	return ok
}

// IsText reports whether a profile serves chat. `auto` and `none` are not profiles: they are
// resolved before this is asked.
func (c *Config) IsText(profile string) bool { return contains(c.TextProfiles, profile) }

// DefaultTextProfile is where a batch profile returns to: the first text profile, which on brys is
// the whole-card frontier.
func (c *Config) DefaultTextProfile() string {
	if len(c.TextProfiles) == 0 {
		// No deployment, no resting profile. A literal here would be a second copy of the host's
		// resting profile, and the first time somebody changes rank 0 it would be wrong.
		return ""
	}
	return c.TextProfiles[0]
}

func contains(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
}

// Validate catches the mistakes that would otherwise surface as a confusing runtime error.
func (c *Config) Validate() error {
	if c.Engine == "" {
		return fmt.Errorf("engine must not be empty")
	}
	if c.EnginePort <= 0 || c.EnginePort > 65535 {
		return fmt.Errorf("enginePort %d is not a port", c.EnginePort)
	}
	if c.ManagerPort <= 0 || c.ManagerPort > 65535 {
		return fmt.Errorf("managerPort %d is not a port", c.ManagerPort)
	}
	if c.DataDir == "" {
		return fmt.Errorf("dataDir must not be empty")
	}
	for alias, profile := range c.Aliases {
		if alias == "" || profile == "" {
			return fmt.Errorf("alias %q -> %q is incomplete", alias, profile)
		}
	}
	for name, spec := range c.Profiles {
		if err := spec.validate(name); err != nil {
			return err
		}
	}
	if c.DrainTimeoutSeconds <= 0 {
		c.DrainTimeoutSeconds = 300
	}
	if c.LeaseTTLSeconds <= 0 {
		c.LeaseTTLSeconds = 1800
	}
	if c.EngineLog == "" {
		c.EngineLog = filepath.Join(c.DataDir, "strata", "engine.log")
	}
	return nil
}

// StatePath is where the selected profile is remembered.
func (c *Config) StatePath() string { return filepath.Join(c.DataDir, "strata", "manager-state.json") }

// EventsPath is the journal.
func (c *Config) EventsPath() string { return filepath.Join(c.DataDir, "strata", "events.jsonl") }

// IsFrontier reports whether a model id must survive a switch.
func (c *Config) IsFrontier(id string) bool {
	for _, f := range c.FrontierIDs {
		if f == id {
			return true
		}
	}
	return false
}
