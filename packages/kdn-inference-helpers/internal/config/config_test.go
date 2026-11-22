package config

import (
	"os"
	"path/filepath"
	"testing"

	"kdn-inference-helpers/internal/engine/command"
)

// A binary with no deployment file knows no names. The alias, frontier and text-profile tables are
// the deployment's, so a default here would be a second copy that drifts from `data/llm.nix`.
func TestDefaultsCarryNoDeploymentNames(t *testing.T) {
	c := Defaults()
	if c.Engine != "strata" || c.EnginePort != 8080 || c.ManagerPort != 8181 {
		t.Fatalf("defaults = %+v", c)
	}
	if len(c.Aliases) != 0 || len(c.FrontierIDs) != 0 || len(c.TextProfiles) != 0 {
		t.Fatalf("names leaked into the defaults: %v %v %v", c.Aliases, c.FrontierIDs, c.TextProfiles)
	}
	if len(c.Profiles) != 0 {
		t.Fatalf("a profile table leaked into the defaults: %v", c.Profiles)
	}
	if got := c.Normalise("qfn"); got != "qfn" {
		t.Fatalf("a name changed with no deployment: %q", got)
	}
	if c.IsFrontier("qfn") {
		t.Fatal("a bare binary calls qfn a frontier id")
	}
	if c.DefaultTextProfile() != "" {
		t.Fatalf("a bare binary has a resting profile: %q", c.DefaultTextProfile())
	}
	if len(c.CacheDropCommand) == 0 {
		t.Fatal("brys needs the cache-drop hook")
	}
}

// deploymentConfig is a small deployment the tests own. It is deliberately not brys: the tests cover
// the rules, and the host's resting profile changes without rewriting them.
func deploymentConfig() *Config {
	c := Defaults()
	c.Aliases = map[string]string{
		"qfn": "auto", "qfn-max": "max", "qfn-fast-colo": "omni-fast",
	}
	c.FrontierIDs = []string{"qfn", "qfn-max", "qfn-fast-colo"}
	c.TextProfiles = []string{"max", "omni-fast"}
	c.Profiles = map[string]ProfileSpec{
		"max":       {Base: "pack", MaxContext: ptr(4096), Parallel: ptr(2), ReserveMiB: ptr(0), KVResident: ptr(0), RopeScale: ptr(1.0)},
		"omni-fast": {Base: "pack", MaxContext: ptr(4096), Parallel: ptr(1), ReserveMiB: ptr(1024), KVResident: ptr(0), RopeScale: ptr(1.0)},
	}
	return c
}

func ptr[T any](v T) *T { return &v }

func TestLoadIsADeltaOverTheDefaults(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")
	body := `{"dataDir": "/srv/engines", "aliases": {"fast": "omni-fast"}, "cacheDropCommand": []}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	c, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if c.DataDir != "/srv/engines" {
		t.Fatalf("dataDir = %q", c.DataDir)
	}
	if c.ManagerPort != 8181 || c.EnginePort != 8080 {
		t.Fatalf("ports were lost: %+v", c)
	}
	if got := c.Normalise("fast"); got != "omni-fast" {
		t.Fatalf("alias not applied: %q", got)
	}
	if len(c.CacheDropCommand) != 0 {
		t.Fatalf("an empty hook list must mean skip, got %v", c.CacheDropCommand)
	}
}

func TestLoadWithoutAFileIsTheDefaults(t *testing.T) {
	c, err := Load("")
	if err != nil || c.EnginePort != 8080 {
		t.Fatalf("Load(\"\") = %+v, %v", c, err)
	}
}

func TestValidateRejectsTheMistakesThatWouldBeConfusingLater(t *testing.T) {
	for name, mutate := range map[string]func(*Config){
		"no engine":     func(c *Config) { c.Engine = "" },
		"bad port":      func(c *Config) { c.EnginePort = 0 },
		"bad manager":   func(c *Config) { c.ManagerPort = 99999 },
		"empty dataDir": func(c *Config) { c.DataDir = "" },
		"empty alias":   func(c *Config) { c.Aliases = map[string]string{"x": ""} },
	} {
		c := Defaults()
		mutate(c)
		if err := c.Validate(); err == nil {
			t.Fatalf("%s: expected an error", name)
		}
	}
}

func TestPathsDeriveFromDataDir(t *testing.T) {
	c := Defaults()
	c.DataDir = "/d"
	c.Validate()
	if got, want := c.StatePath(), "/d/strata/manager-state.json"; got != want {
		t.Fatalf("state = %q, want %q", got, want)
	}
	if got, want := c.EventsPath(), "/d/strata/events.jsonl"; got != want {
		t.Fatalf("events = %q, want %q", got, want)
	}
	if got, want := c.EngineLog, "/d/strata/engine.log"; got != want {
		t.Fatalf("log = %q, want %q", got, want)
	}
}

// Acceptance is derived, not compiled in: a deployment that adds an image profile does not have to
// touch the runtime.
func TestAcceptsIsDerivedFromTheDeployment(t *testing.T) {
	c := deploymentConfig()
	for _, want := range []string{
		"auto", "none", "max", "omni-fast", "qfn", "qfn-max",
		"qfn-fast-colo",
	} {
		if !c.Accepts(c.Normalise(want)) {
			t.Fatalf("%q is not accepted", want)
		}
	}
	if c.Accepts("image-qwen") {
		t.Fatal("an undeclared image profile is accepted")
	}
	c.Commands = map[string]command.Spec{"image-qwen": {Argv: []string{"sd-server"}}}
	if !c.Accepts("image-qwen") {
		t.Fatal("a declared image profile is not accepted")
	}
	if c.IsText("image-qwen") {
		t.Fatal("an image profile is treated as text")
	}
	if !c.IsText("max") || c.DefaultTextProfile() != "max" {
		t.Fatalf("text profiles = %v", c.TextProfiles)
	}
}

func TestTheCommandSpecAcceptsBothShapes(t *testing.T) {
	body := []byte(`{"commands":{"tiny":["llama-server","--model","/m.gguf"],
		"image":{"argv":["sd-server"],"readyPath":"/sdapi/v1/options","portFlag":"--listen-port"}}}`)
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, body, 0o644); err != nil {
		t.Fatal(err)
	}
	c, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := c.Commands["tiny"].Argv; len(got) != 3 || got[0] != "llama-server" {
		t.Fatalf("array form = %v", got)
	}
	if got := c.Commands["image"].ReadyPath; got != "/sdapi/v1/options" {
		t.Fatalf("object form readyPath = %q", got)
	}
	if !c.Accepts("tiny") || !c.Accepts("image") {
		t.Fatal("a command profile is not accepted")
	}
}
