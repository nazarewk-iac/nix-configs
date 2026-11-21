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

func intp(v int) *int           { return &v }
func floatp(v float64) *float64 { return &v }
func strp(v string) *string     { return &v }

// deployment is a synthetic profile table. The numbers are deliberately unlike the ones brys
// serves, so no test can pass by matching a built-in table: the adapter has none. The real table
// lives in hosts-den/brys/strata-profiles.nix, and checks/inference-helpers/profiles.nix proves it
// agrees with the generated config.json and with the argv strata-serve.sh builds.
func deployment() map[string]config.ProfileSpec {
	return map[string]config.ProfileSpec{
		"swarm": {
			Base:                 "unsloth-ud-iq4_xs",
			MaxContext:           intp(777000),
			Parallel:             intp(7),
			ReserveMiB:           intp(1234),
			KVResident:           intp(4321),
			RopeScale:            floatp(3),
			ConversationCacheMiB: intp(2048),
			PLEIO:                strp("mmap"),
		},
		"long": {
			Base:                 "iq2_xs",
			MaxContext:           intp(1000000),
			Parallel:             intp(2),
			ReserveMiB:           intp(21500),
			KVResident:           intp(4096),
			RopeScale:            floatp(1.5),
			ConversationCacheMiB: intp(1024),
			PLEIO:                strp("mmap"),
		},
		// A colo profile keeps the base config's park pool and n-gram backing store: the deployment
		// spells that as null, and the adapter must not invent a value for it.
		"colo": {
			Base:       "iq2_xs",
			MaxContext: intp(1000000),
			Parallel:   intp(1),
			ReserveMiB: intp(20000),
			KVResident: intp(4096),
			RopeScale:  floatp(1.5),
		},
	}
}

func adapter(t *testing.T) *Adapter {
	t.Helper()
	return New("/bin/strata", t.TempDir(), deployment())
}

func profileNamed(t *testing.T, a *Adapter, name string) Profile {
	t.Helper()
	p, ok := a.Profile(name)
	if !ok {
		t.Fatalf("no profile %q in the adapter", name)
	}
	return p
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
	out, err := PatchConfig([]byte(baseConfig), profileNamed(t, adapter(t), "colo"))
	if err != nil {
		t.Fatal(err)
	}
	args := argsOf(t, out)
	if got := valueOf(args, "--vram-reserve-mib"); got != "20000" {
		t.Fatalf("reserve = %q, want 20000", got)
	}
	if got := valueOf(args, "--kv-resident"); got != "4096" {
		t.Fatalf("kv-resident = %q, want 4096", got)
	}
	// A null in the deployment keeps the base config's value: no invented default.
	if got := valueOf(args, "--ple-io"); got != "ram" {
		t.Fatalf("ple-io = %q, want the base config's ram", got)
	}
	if got := valueOf(args, "--conversation-cache-mib"); got != "" {
		t.Fatalf("a null park pool still reached the argv: %q", got)
	}
	// Everything else must survive untouched: the tuned flags are what make the profiles equal
	// apart from the reserve.
	for _, want := range []string{
		"--pack", "/packs/unsloth-ud-iq4_xs", "--spec", "4",
		"--rope-scale", "1.5", "--kv", "k8v4", "--max-context", "1000000",
	} {
		if !contains(args, want) {
			t.Fatalf("tuned argument %q was lost: %v", want, args)
		}
	}
}

// A swarm profile rewrites the window, the yarn factor, the park pool and the n-gram table's
// backing store, and it asks for its own slot count.
func TestPatchConfigAppliesTheSwarmShape(t *testing.T) {
	p := profileNamed(t, adapter(t), "swarm")
	out, err := PatchConfig([]byte(baseConfig), p)
	if err != nil {
		t.Fatal(err)
	}
	args := argsOf(t, out)
	for flag, want := range map[string]string{
		"--vram-reserve-mib":       "1234",
		"--kv-resident":            "4321",
		"--max-context":            "777000",
		"--rope-scale":             "3",
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

// The context and the slot count are one decision and travel together: both are read from the
// deployment spec and reach their flags.
func TestTheContextAndTheSlotCountTravelTogether(t *testing.T) {
	a := adapter(t)
	for name, want := range map[string]struct {
		context string
		rope    string
		slots   int
	}{
		"swarm": {"777000", "3", 7},
		"long":  {"1000000", "1.5", 2},
		"colo":  {"1000000", "1.5", 1},
	} {
		p := profileNamed(t, a, name)
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
	out, err := PatchConfig([]byte(bare), profileNamed(t, adapter(t), "long"))
	if err != nil {
		t.Fatal(err)
	}
	args := argsOf(t, out)
	for flag, want := range map[string]string{
		"--vram-reserve-mib":       "21500",
		"--kv-resident":            "4096",
		"--max-context":            "1000000",
		"--rope-scale":             "1.5",
		"--conversation-cache-mib": "1024",
	} {
		if got := valueOf(args, flag); got != want {
			t.Fatalf("%s = %q, want %q (argv %v)", flag, got, want, args)
		}
	}
}

func TestPatchConfigRejectsAMalformedBase(t *testing.T) {
	p := profileNamed(t, adapter(t), "long")
	for name, doc := range map[string]string{
		"not json":  `{`,
		"no args":   `{"pack": "x"}`,
		"bad arg":   `{"args": [1, 2]}`,
		"args null": `{"args": null}`,
	} {
		if _, err := PatchConfig([]byte(doc), p); err == nil {
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
	a := New("/bin/strata", dir, deployment())
	cmd, err := a.Prepare("swarm")
	if err != nil {
		t.Fatal(err)
	}
	wantCfg := filepath.Join(dir, "strata", "profiles", "strata-swarm.json")
	if cmd.Path != "/bin/strata" || len(cmd.Args) < 3 || cmd.Args[0] != "serve" || cmd.Args[2] != wantCfg {
		t.Fatalf("command = %+v", cmd)
	}
	body, err := os.ReadFile(wantCfg)
	if err != nil {
		t.Fatal(err)
	}
	if got := valueOf(argsOf(t, body), "--vram-reserve-mib"); got != "1234" {
		t.Fatalf("reserve = %q", got)
	}
	if _, err := a.Prepare("nope"); err == nil {
		t.Fatal("unknown profile was prepared")
	}
}

// Every knob the adapter serves is the deployment's: there is no per-profile default left to
// disagree with the file.
func TestTheDeploymentSuppliesEveryKnob(t *testing.T) {
	a := New("/bin/strata", t.TempDir(), deployment())
	p := profileNamed(t, a, "swarm")
	if p.Base != "unsloth-ud-iq4_xs" || p.MaxContext != 777000 || p.Parallel != 7 ||
		p.ReserveMiB != 1234 || p.KVResident != 4321 || p.RopeScale != 3 ||
		p.ConversationCacheMiB != 2048 || p.PLEIO != "mmap" {
		t.Fatalf("profile = %+v", p)
	}
	if q := profileNamed(t, a, "long"); q.Base != "iq2_xs" || q.Parallel != 2 || q.ReserveMiB != 21500 {
		t.Fatalf("an unrelated profile was modified: %+v", q)
	}
}

// The table order is deterministic: map iteration is not, so the adapter sorts.
func TestAdapterListsEveryProfileInSortedOrder(t *testing.T) {
	a := New("/bin/strata", t.TempDir(), deployment())
	got := a.Profiles()
	want := []string{"colo", "long", "swarm"}
	if len(got) != len(want) {
		t.Fatalf("profiles = %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("profiles = %v, want %v", got, want)
		}
	}
}

// A bare binary is the explicit fallback: no deployment file, no profiles, and every select is
// refused. A built-in copy of the numbers would be the failure mode this guards against.
func TestABareBinaryKnowsNoProfiles(t *testing.T) {
	a := New("/bin/strata", t.TempDir(), nil)
	if got := a.Profiles(); len(got) != 0 {
		t.Fatalf("a bare adapter has profiles: %v", got)
	}
	if _, ok := a.Profile("max-multi"); ok {
		t.Fatal("a bare adapter invented a profile")
	}
	if _, err := a.Prepare("max-multi"); err == nil {
		t.Fatal("a bare adapter prepared a profile")
	}
}

// Every profile asks `strata serve` for its own slot count and its own resident window. `serve`
// turns the first into the engine's `--batch N`, so it has to be on the command line: the profile
// JSON only carries engine arguments.
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
	a := New("/bin/strata", dir, deployment())
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
		if got := valueOf(argsOf(t, body), "--kv-resident"); got != fmt.Sprint(p.KVResident) {
			t.Fatalf("%s: --kv-resident = %q, want %d", name, got, p.KVResident)
		}
	}
}

// A deployment can leave the slot count at zero, and zero means "leave the engine's default alone".
func TestTheSlotCountCanBeLeftAlone(t *testing.T) {
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
	specs := deployment()
	zero := specs["colo"]
	zero.Parallel = intp(0)
	specs["colo"] = zero
	a := New("/bin/strata", dir, specs)
	cmd, err := a.Prepare("colo")
	if err != nil {
		t.Fatal(err)
	}
	if got := valueOf(cmd.Args, "--parallel"); got != "" {
		t.Fatalf("a zero slot count still passed --parallel %q", got)
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
