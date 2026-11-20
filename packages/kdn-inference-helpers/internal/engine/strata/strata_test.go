package strata

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"kdn-inference-helpers/internal/config"
)

// baseConfig is the shape the Strata Terminal writes: tuned flags plus the two profile flags.
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
	out, err := PatchConfig([]byte(baseConfig), defaults[0])
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
	// Everything else must survive untouched: the tuned flags are what make the profiles equal
	// apart from the reserve.
	for _, want := range []string{"--pack", "/packs/unsloth-ud-iq4_xs", "--spec", "4",
		"--rope-scale", "4", "--kv", "k8v4", "--ple-io", "ram", "--max-context", "1048576"} {
		if !contains(args, want) {
			t.Fatalf("tuned argument %q was lost: %v", want, args)
		}
	}
}

func TestPatchConfigAppendsAMissingFlag(t *testing.T) {
	bare := `{"args": ["--pack", "/packs/x"]}`
	out, err := PatchConfig([]byte(bare), defaults[1])
	if err != nil {
		t.Fatal(err)
	}
	args := argsOf(t, out)
	if got := valueOf(args, "--vram-reserve-mib"); got != "21500" {
		t.Fatalf("reserve = %q, want 21500", got)
	}
	if got := valueOf(args, "--kv-resident"); got != "4096" {
		t.Fatalf("kv-resident = %q, want 4096", got)
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
	cmd, err := a.Prepare("max")
	if err != nil {
		t.Fatal(err)
	}
	wantCfg := filepath.Join(dir, "strata", "profiles", "strata-max.json")
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
	if q, _ := a.Profile("max"); q.ReserveMiB != 1024 {
		t.Fatalf("max was modified by an unrelated override: %+v", q)
	}
}

func TestAdapterListsEveryProfileInOrder(t *testing.T) {
	a := New("/bin/strata", t.TempDir(), nil)
	got := a.Profiles()
	want := []string{"max", "omni-fast", "omni-max"}
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
