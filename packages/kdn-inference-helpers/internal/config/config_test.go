package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultsDescribeBrys(t *testing.T) {
	c := Defaults()
	if c.Engine != "strata" || c.EnginePort != 8080 || c.ManagerPort != 8181 {
		t.Fatalf("defaults = %+v", c)
	}
	if got := c.Normalise("qfn"); got != "auto" {
		t.Fatalf("qfn normalised to %q", got)
	}
	if got := c.Normalise("qfn-max-colo"); got != "omni-max" {
		t.Fatalf("qfn-max-colo normalised to %q", got)
	}
	if got := c.Normalise("qfn-fast-colo"); got != "omni-fast" {
		t.Fatalf("qfn-fast-colo normalised to %q", got)
	}
	if got := c.Normalise("bogus"); got != "bogus" {
		t.Fatalf("unknown name changed to %q", got)
	}
	if !c.IsFrontier("qfn") || !c.IsFrontier("qfn-fast-colo") || c.IsFrontier("qwen3-omni") {
		t.Fatalf("frontier set = %v", c.FrontierIDs)
	}
	if len(c.CacheDropCommand) == 0 {
		t.Fatal("brys needs the cache-drop hook")
	}
}

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
