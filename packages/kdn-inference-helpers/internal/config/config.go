// Package config is the deployment's data: ports, paths, the model-name aliases, which models must
// survive a profile switch, and which privileged hooks the switch runs.
//
// The rule this package exists for: a new deployment is a JSON file, not a code change. The
// defaults below describe brys exactly, so the binary works with no file at all; a second host or a
// second engine overrides only what differs.
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

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
	// EngineLog receives the engine child's stdout and stderr.
	EngineLog string `json:"engineLog"`
	// DrainTimeoutSeconds bounds how long a switch waits for in-flight requests.
	DrainTimeoutSeconds int `json:"drainTimeoutSeconds"`
	// LeaseTTLSeconds drops leases from a proxy that died without releasing (SIGKILL).
	LeaseTTLSeconds int `json:"leaseTTLSeconds"`
	// Profiles optionally overrides the adapter's profile table.
	Profiles map[string]ProfileOverride `json:"profiles"`
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

// ProfileOverride lets a deployment retune a profile without a rebuild: a different reserve on a
// card with more VRAM, or a smaller resident K/V.
type ProfileOverride struct {
	ReserveMiB *int `json:"reserveMiB,omitempty"`
	KVResident *int `json:"kvResident,omitempty"`
}

// Defaults is brys. Values are measured, not guessed; see docs/tasks/2026-11/brys-r9700-model-fit.
func Defaults() *Config {
	return &Config{
		Engine:      "strata",
		DataDir:     "/var/lib/kdn/llms/models/.bench/xdg",
		EnginePort:  8080,
		ManagerPort: 8181,
		SwapURL:     "http://127.0.0.1:39700",
		EngineBin:   "/var/lib/kdn/llms/models/.bench/bin/strata",
		Aliases: map[string]string{
			"qfn":           "auto",
			"qfn-max":       "max",
			"qfn-max-colo":  "omni-max",
			"qfn-fast-colo": "omni-fast",
		},
		FrontierIDs:         []string{"qfn", "qfn-max", "qfn-max-colo", "qfn-fast-colo"},
		TextProfiles:        []string{"max", "omni-max", "omni-fast"},
		CacheDropCommand:    []string{"sudo", "-n", "systemctl", "start", "strata-drop-cache.service"},
		Profiles:            map[string]ProfileOverride{},
		Gates:               map[string]GateSpec{},
		DrainTimeoutSeconds: 300,
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
		return "max"
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
