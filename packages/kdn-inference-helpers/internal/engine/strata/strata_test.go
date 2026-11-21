package strata

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"kdn-inference-helpers/internal/config"
)

// baseConfig is the shape the Strata Terminal writes: tuned flags plus the profile flags.
const baseConfig = `{
 "args": [
  "--pack", "/packs/unsloth-ud-iq4_xs",
  "--native", "/models/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf",
  "--expert-cache", "auto",
  "--prefill", "auto",
  "--spec", "4",
  "--mtp", "/mtp/rt",
  "--max-context", "1048576",
  "--rope-scaling", "yarn",
  "--rope-scale", "4",
  "--kv", "k8v4",
  "--ple-io", "ram",
  "--kv-resident", "4096",
  "--vram-reserve-mib", "21500"
 ]
}`

// profileNamed is the table lookup the tests read instead of an index: the table is a decision
// surface and its order is not part of the contract.
func profileNamed(t *testing.T, name string) Profile {
	t.Helper()
	for _, p := range defaults {
		if p.Name == name {
			return p
		}
	}
	t.Fatalf("no profile %q in the table", name)
	return Profile{}
}

func argsOf(t *testing.T, out []byte) []string {
	t.Helper()
	var cfg struct {
		Args []string `json:"args"`
	}
	if err := json.Unmarshal(out, &cfg); err != nil {
		t.Fatalf("patched config is not JSON: %v", err)
	}
	return cfg.Args
}

func TestPatchConfigReplacesBothProfileFlags(t *testing.T) {
	out, err := PatchConfig([]byte(baseConfig), profileNamed(t, "omni-fast"))
	if err != nil {
		t.Fatal(err)
	}
	args := argsOf(t, out)
	if got := valueOf(args, "--vram-reserve-mib"); got != "21500" {
		t.Fatalf("reserve = %q, want 21500", got)
	}
	if got := valueOf(args, "--kv-resident"); got != "32768" {
		t.Fatalf("kv-resident = %q, want 32768", got)
	}
	// Everything else must survive untouched: the tuned flags are what make the profiles equal
	// apart from the reserve.
	for _, want := range []string{"--pack", "/packs/unsloth-ud-iq4_xs", "--spec", "4",
		"--rope-scale", "4", "--kv", "k8v4", "--ple-io", "ram", "--max-context", "1048576"} {
		if !contains(args, want) {
			t.Fatalf("tuned argument %q was lost: %v", want, args)
		}
	}
}

// A swarm profile rewrites the window, the yarn factor, the park pool and the n-gram table's
// backing store, and it asks for eight slots.
func TestPatchConfigAppliesTheSwarmShape(t *testing.T) {
	p := profileNamed(t, "max-multi")
	out, err := PatchConfig([]byte(baseConfig), p)
	if err != nil {
		t.Fatal(err)
	}
	args := argsOf(t, out)
	for flag, want := range map[string]string{
		"--vram-reserve-mib":       "1024",
		"--kv-resident":            "32768",
		"--max-context":            "524288",
		"--rope-scale":             "2",
		"--conversation-cache-mib": "2048",
		"--ple-io":                 "mmap",
	} {
		if got := valueOf(args, flag); got != want {
			t.Fatalf("%s = %q, want %q (argv %v)", flag, got, want, args)
		}
	}
	if contains(args, "--batch-mtp") {
		t.Fatalf("--batch-mtp is off by measurement but reached the argv: %v", args)
	}
}

// The long profile keeps the 1M window at its measured two slots, and 256k needs no rope at all.
func TestTheContextAndTheSlotCountTravelTogether(t *testing.T) {
	for name, want := range map[string]struct {
		context string
		rope    string
		slots   int
	}{
		"max-multi":  {"524288", "2", 6},
		"max-swarm":  {"262144", "1", 8},
		"max-long":   {"1048576", "4", 2},
		"fast-swarm": {"393216", "1.5", 8},
	} {
		p := profileNamed(t, name)
		if p.Parallel != want.slots {
			t.Fatalf("%s: Parallel = %d, want %d", name, p.Parallel, want.slots)
		}
		out, err := PatchConfig([]byte(baseConfig), p)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		args := argsOf(t, out)
		if got := valueOf(args, "--max-context"); got != want.context {
			t.Fatalf("%s: --max-context = %q, want %q", name, got, want.context)
		}
		if got := valueOf(args, "--rope-scale"); got != want.rope {
			t.Fatalf("%s: --rope-scale = %q, want %q", name, got, want.rope)
		}
	}
}

func TestPatchConfigAppendsMissingFlags(t *testing.T) {
	bare := `{"args": ["--pack", "/packs/x"]}`
	out, err := PatchConfig([]byte(bare), profileNamed(t, "max-long"))
	if err != nil {
		t.Fatal(err)
	}
	args := argsOf(t, out)
	if got := valueOf(args, "--vram-reserve-mib"); got != "1024" {
		t.Fatalf("reserve = %q, want 1024", got)
	}
	if got := valueOf(args, "--kv-resident"); got != "32768" {
		t.Fatalf("kv-resident = %q, want 32768", got)
	}
	if got := valueOf(args, "--max-context"); got != "1048576" {
		t.Fatalf("max-context = %q, want 1048576", got)
	}
	if got := valueOf(args, "--conversation-cache-mib"); got != "1024" {
		t.Fatalf("conversation-cache-mib = %q, want 1024", got)
	}
}

func TestPatchConfigRejectsAMalformedBase(t *testing.T) {
	for name, doc := range map[string]string{
		"not json":  `{`,
		"no args":   `{"pack": "x"}`,
		"bad arg":   `{"args": [1, 2]}`,
		"args null": `{"args": null}`,
	} {
		if _, err := PatchConfig([]byte(doc), defaults[0]); err == nil {
			t.Fatalf("%s: expected an error", name)
		}
	}
}

func TestPrepareWritesTheProfileAndBuildsTheCommand(t *testing.T) {
	dir := t.TempDir()
	install := filepath.Join(dir, "strata", "install")
	if err := os.MkdirAll(install, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(install, "strata-unsloth-ud-iq4_xs.json"),
		[]byte(baseConfig), 0o644); err != nil {
		t.Fatal(err)
	}
	a := New("/bin/strata", dir, nil)
	cmd, err := a.Prepare("max-multi")
	if err != nil {
		t.Fatal(err)
	}
	wantCfg := filepath.Join(dir, "strata", "profiles", "strata-max-multi.json")
	if cmd.Path != "/bin/strata" || len(cmd.Args) < 3 || cmd.Args[0] != "serve" || cmd.Args[2] != wantCfg {
		t.Fatalf("command = %+v", cmd)
	}
	body, err := os.ReadFile(wantCfg)
	if err != nil {
		t.Fatal(err)
	}
	if got := valueOf(argsOf(t, body), "--vram-reserve-mib"); got != "1024" {
		t.Fatalf("reserve = %q", got)
	}
	if _, err := a.Prepare("nope"); err == nil {
		t.Fatal("unknown profile was prepared")
	}
}

func TestProfileOverridesRetuneWithoutARebuild(t *testing.T) {
	reserve := 17000
	kv := 8192
	a := New("/bin/strata", t.TempDir(), map[string]config.ProfileOverride{
		"omni-fast": {ReserveMiB: &reserve, KVResident: &kv},
	})
	p, ok := a.Profile("omni-fast")
	if !ok {
		t.Fatal("omni-fast missing")
	}
	if p.ReserveMiB != 17000 || p.KVResident != 8192 {
		t.Fatalf("override not applied: %+v", p)
	}
	if q, _ := a.Profile("max-multi"); q.ReserveMiB != 1024 {
		t.Fatalf("max-multi was modified by an unrelated override: %+v", q)
	}
}

func TestAdapterListsEveryProfileInOrder(t *testing.T) {
	a := New("/bin/strata", t.TempDir(), nil)
	got := a.Profiles()
	want := []string{"max-multi", "max-swarm", "max-long", "fast-swarm", "omni-fast", "omni-max"}
	if len(got) != len(want) {
		t.Fatalf("profiles = %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("profiles = %v, want %v", got, want)
		}
	}
}

func valueOf(args []string, flag string) string {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == flag {
			return args[i+1]
		}
	}
	return ""
}

func contains(args []string, want string) bool {
	for _, a := range args {
		if a == want {
			return true
		}
	}
	return false
}

// Every profile asks `strata serve` for its own slot count and a 32768-cell resident window.
// `serve` turns the first into the engine's `--batch N`, so it has to be on the command line: the
// profile JSON only carries engine arguments.
func TestPrepareAsksForTheProfilesSlotCount(t *testing.T) {
	dir := t.TempDir()
	install := filepath.Join(dir, "strata", "install")
	if err := os.MkdirAll(install, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, base := range []string{"unsloth-ud-iq4_xs", "iq2_xs"} {
		if err := os.WriteFile(filepath.Join(install, "strata-"+base+".json"),
			[]byte(baseConfig), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	a := New("/bin/strata", dir, nil)
	for _, name := range a.Profiles() {
		p, _ := a.Profile(name)
		cmd, err := a.Prepare(name)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if got := valueOf(cmd.Args, "--parallel"); got != fmt.Sprint(p.Parallel) {
			t.Fatalf("%s: --parallel = %q, want %d (argv %v)", name, got, p.Parallel, cmd.Args)
		}
		body, err := os.ReadFile(filepath.Join(dir, "strata", "profiles", "strata-"+name+".json"))
		if err != nil {
			t.Fatal(err)
		}
		if got := valueOf(argsOf(t, body), "--kv-resident"); got != "32768" {
			t.Fatalf("%s: --kv-resident = %q, want 32768 (8 slots x 4k cells)", name, got)
		}
	}
}

// A deployment can retune the slot count, and zero means "leave the engine's default alone".
func TestTheSlotCountCanBeOverriddenOrLeftAlone(t *testing.T) {
	dir := t.TempDir()
	install := filepath.Join(dir, "strata", "install")
	if err := os.MkdirAll(install, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, base := range []string{"unsloth-ud-iq4_xs", "iq2_xs"} {
		if err := os.WriteFile(filepath.Join(install, "strata-"+base+".json"), []byte(baseConfig), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	four := 4
	zero := 0
	a := New("/bin/strata", dir, map[string]config.ProfileOverride{
		"omni-fast": {Parallel: &four},
		"omni-max":  {Parallel: &zero},
	})
	if p, _ := a.Profile("omni-fast"); p.Parallel != 4 {
		t.Fatalf("override not applied: %+v", p)
	}
	cmd, err := a.Prepare("omni-max")
	if err != nil {
		t.Fatal(err)
	}
	if got := valueOf(cmd.Args, "--parallel"); got != "" {
		t.Fatalf("a zero slot count still passed --parallel %q", got)
	}
}
