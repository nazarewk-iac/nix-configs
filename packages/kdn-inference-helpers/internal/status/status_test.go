package status_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"kdn-inference-helpers/internal/policy"
	"kdn-inference-helpers/internal/status"
)

// fixture is one deployment in miniature: two text shapes, a colo pair, a companion and an image
// command. It is the brys table cut down, because the renderer must not need the real one.
func fixture() (status.Plan, func(string) status.EngineRow, *policy.Policy) {
	plan := status.Plan{
		TextProfiles: []string{"max-multi", "max-long", "omni-max"},
		Commands:     []string{"image-qwen"},
		Aliases: map[string]string{
			"qfn": "auto", "qfn-max-multi": "max-multi", "qfn-max": "max-long", "qfn-max-colo": "omni-max",
		},
		Resting: "max-multi",
		Colo:    []string{"omni-max"},
	}
	rows := map[string]status.EngineRow{
		"max-multi": {Pack: "UD-IQ4_XS", Context: 393216, Slots: 8},
		"max-long":  {Pack: "UD-IQ4_XS", Context: 1048576, Slots: 2},
		"omni-max":  {Pack: "UD-IQ4_XS", Slots: 1},
	}
	pol := &policy.Policy{
		SchemaVersion: policy.SchemaVersion,
		ColoProfiles:  []string{"omni-max"},
		Models: map[string]policy.Model{
			"qfn-max-multi": {
				Kind: "engine", Tier: "frontier", Profile: "max-multi",
				Facts: policy.Facts{VRAMMiB: 22694, KVReserveMiB: 8848, LoadSeconds: 60, SwitchSeconds: 74},
			},
			"qfn-max-long": {
				Kind: "engine", Tier: "frontier", Profile: "max-long",
				Facts: policy.Facts{VRAMMiB: 27074, KVReserveMiB: 4464},
			},
			"qfn-max-colo": {
				Kind: "engine", Tier: "frontier", Profile: "omni-max",
				Facts: policy.Facts{VRAMMiB: 10957, KVReserveMiB: 336},
			},
			"qwen3-omni": {
				Kind: "companion", Tier: "companion",
				RequiresProfile: []string{"omni-max"},
				Facts:           policy.Facts{VRAMMiB: 19149, KVReserveMiB: 1536, DecodeWithFrontier: map[string]float64{"omni-max": 6.1}},
			},
			"qwen-image-edit": {
				Kind: "engine", Tier: "frontier", Profile: "image-qwen",
				Facts: policy.Facts{VRAMMiB: 26829},
			},
		},
	}
	return plan, func(name string) status.EngineRow { return rows[name] }, pol
}

func snapshot() status.Snapshot {
	plan, engine, pol := fixture()
	return status.Snapshot{
		Host:     "brys",
		Profiles: status.FromDeployment(plan, engine, pol),
		Policy:   status.PolicyInfo{Path: "/etc/kdn-inference-helpers/policy.json", Models: len(pol.Models)},
		Manager: status.Manager{
			URL: "http://127.0.0.1:8181", Reachable: true, Profile: "none",
			Companions: []string{}, EvictionID: "18d0985d",
		},
		Swap: status.Swap{URL: "http://127.0.0.1:39700", Running: []string{"qfn"}},
		Free: status.Free{VRAMMiB: 31400, VRAMTotalMiB: 32620, RAMMiB: 108000, RAMTotalMiB: 124000},
	}
}

// The table is the configured answer: every profile, its pack, the window it serves, the names that
// reach it, the one word that says what it is for, and the resting one marked.
func TestTheTableRendersEveryProfileWithItsWindowAndAlias(t *testing.T) {
	var out bytes.Buffer
	if err := status.Render(&out, snapshot(), false); err != nil {
		t.Fatal(err)
	}
	text := out.String()
	for _, want := range []string{
		"brys · 5 profiles the deployment can serve",
		"frontier", "companion", "image",
		"*  max-multi", "UD-IQ4_XS", "384k × 8", "qfn, qfn-max-multi", "resting",
		"max-long", "1M × 2", "qfn-max", "long",
		"omni-max", "base × 1", "qfn-max-colo", "colo",
		"qwen3-omni", "qwen-image-edit",
		"now  profile none · companions none · 30.7 GiB VRAM free, 105.5 GiB RAM free",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("missing %q in:\n%s", want, text)
		}
	}
	// `qfn` reaches the resting profile only: it is profile-neutral and must not appear on another
	// row, or a caller would read it as a promise about that profile.
	var withQfn []string
	for _, line := range strings.Split(text, "\n") {
		if strings.Contains(line, "qfn, ") || strings.HasSuffix(line, " qfn") {
			withQfn = append(withQfn, line)
		}
	}
	if len(withQfn) != 1 || !strings.Contains(withQfn[0], "max-multi") {
		t.Fatalf("qfn is not on the resting row alone: %v", withQfn)
	}
	// The columns line up across the three groups: the last column starts where ROLE starts.
	roleCol := -1
	for _, line := range strings.Split(text, "\n") {
		if i := strings.Index(line, "ROLE"); i >= 0 {
			roleCol = i
			break
		}
	}
	if roleCol < 0 {
		t.Fatal("no ROLE header")
	}
	for _, line := range strings.Split(text, "\n") {
		if strings.Contains(line, "resting") && strings.Index(line, "resting") != roleCol {
			t.Fatalf("the ROLE column is not aligned in %q (want %d)", line, roleCol)
		}
	}
}

// An idle host gets the table and one trailing line; a loaded one gets the live detail, and a
// caller can ask for it either way.
func TestTheLongViewIsPromotedWhenSomethingIsLoaded(t *testing.T) {
	snap := snapshot()
	snap.Manager.Profile = "max-multi"
	snap.Manager.Companions = []string{"qwen3-omni"}
	snap.Manager.InFlight = 2
	snap.Manager.LastSwitch = &status.Switch{From: "none", To: "max-multi", Seconds: 60, Cause: "select"}
	snap.Manager.LastSwitchSecondsAgo = new(int)
	*snap.Manager.LastSwitchSecondsAgo = 120
	rate, at := 58.1, time.Now()
	snap.EngineRateTps, snap.EngineRateAt = &rate, &at

	var out bytes.Buffer
	if err := status.Render(&out, snap, false); err != nil {
		t.Fatal(err)
	}
	text := out.String()
	for _, want := range []string{
		"profile     max-multi · UD-IQ4_XS · 384k × 8 · 22.2 GiB weights + 8.6 GiB K/V",
		"rates       58.1 t/s (the engine's last completed request, just now)",
		"companions  qwen3-omni 20.2 GiB, 6.1 t/s beside omni-max",
		"leases      2 in flight, draining no",
		"eviction    18d0985d",
		"switch      none → max-multi · 60 s (select) · 120 s ago",
		"llama-swap  qfn",
		"free        VRAM 30.7 GiB of 31.9 GiB (96%) · RAM 105.5 GiB of 121.1 GiB (87%)",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("missing %q in:\n%s", want, text)
		}
	}
}

// A manager that is not running is a line of output, not a failure: the configured table is still
// the answer to most of the question.
func TestAnUnreachableManagerStillPrintsTheTable(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	base := srv.URL
	srv.Close() // the port is now refused, which is what a stopped manager looks like

	manager := status.ManagerView(context.Background(), base)
	if manager.Reachable || manager.Error == "" {
		t.Fatalf("a closed listener reported reachable=%v error=%q", manager.Reachable, manager.Error)
	}
	if manager.Companions == nil {
		t.Fatal("companions must be an empty list, not null")
	}

	snap := snapshot()
	snap.Manager = manager
	var out bytes.Buffer
	if err := status.Render(&out, snap, false); err != nil {
		t.Fatal(err)
	}
	text := out.String()
	for _, want := range []string{"*  max-multi", "now  the manager is unreachable at " + base} {
		if !strings.Contains(text, want) {
			t.Fatalf("missing %q in:\n%s", want, text)
		}
	}
	// The long view says the same thing rather than pretending the profile is empty.
	out.Reset()
	if err := status.Render(&out, snap, true); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "manager     unreachable at "+base) {
		t.Fatalf("the long view hid the failure:\n%s", out.String())
	}
}

// The JSON form carries the same facts, so a script reads what the screen shows.
func TestJSONCarriesTheSameFacts(t *testing.T) {
	snap := snapshot()
	snap.EngineRateTps = new(float64)
	*snap.EngineRateTps = 58.1
	raw, err := status.JSON(snap)
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"host", "now", "profiles", "manager", "swap", "free", "policy", "engineRateTps"} {
		if _, ok := doc[key]; !ok {
			t.Fatalf("missing top-level %q in %s", key, raw)
		}
	}
	if doc["host"] != "brys" || doc["engineRateTps"].(float64) != 58.1 {
		t.Fatalf("host/rate = %v/%v", doc["host"], doc["engineRateTps"])
	}
	profiles := doc["profiles"].([]any)
	if len(profiles) != 5 {
		t.Fatalf("profiles = %d, want 5", len(profiles))
	}
	first := profiles[0].(map[string]any)
	if first["name"] != "max-multi" || first["resting"] != true || first["role"] != "resting" {
		t.Fatalf("first profile = %v", first)
	}
	facts := first["facts"].(map[string]any)
	if facts["vramMiB"].(float64) != 22694 || facts["kvReserveMiB"].(float64) != 8848 {
		t.Fatalf("facts = %v", facts)
	}
	manager := doc["manager"].(map[string]any)
	if manager["reachable"] != true || manager["profile"] != "none" {
		t.Fatalf("manager = %v", manager)
	}
	if companions, ok := manager["companions"].([]any); !ok || len(companions) != 0 {
		t.Fatalf("manager.companions = %v, want []", manager["companions"])
	}
	free := doc["free"].(map[string]any)
	if free["vramTotalMiB"].(float64) != 32620 || free["ramMiB"].(float64) != 108000 {
		t.Fatalf("free = %v", free)
	}
}

// The live facts are read from files that exist on every Linux host: the card with the most VRAM,
// MemAvailable, and the engine's own last rate line.
func TestTheLiveProbesReadTheCardTheHostAndTheEngineLog(t *testing.T) {
	root := t.TempDir()
	for card, values := range map[string][2]string{
		"card1": {"34208743424", "74670080"},
		"card2": {"4294967296", "131747840"},
	} {
		dir := filepath.Join(root, card, "device")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		write(t, filepath.Join(dir, "mem_info_vram_total"), values[0])
		write(t, filepath.Join(dir, "mem_info_vram_used"), values[1])
	}
	free, total, ok := status.VRAM(root)
	if !ok || total != 32624 || free != 32552 {
		t.Fatalf("VRAM = %d free of %d (%v), want the 32 GiB card", free, total, ok)
	}

	meminfo := filepath.Join(root, "meminfo")
	write(t, meminfo, "MemTotal:       131802904 kB\nMemFree:         1000000 kB\nMemAvailable:   110903672 kB\n")
	free, total, ok = status.Memory(meminfo)
	if !ok || total != 128713 || free != 108304 {
		t.Fatalf("Memory = %d free of %d (%v)", free, total, ok)
	}

	log := filepath.Join(root, "engine.log")
	write(t, log, "[strata] loading\n[strata] done: 31 tokens in 2 s (58.1 tok/s) (stop, cancel=False)\n[strata] stopped\n")
	rate, at, ok := status.Rate(log)
	if !ok || rate != 58.1 || at.IsZero() {
		t.Fatalf("Rate = %v at %v (%v)", rate, at, ok)
	}
	if _, _, ok := status.Rate(filepath.Join(root, "absent.log")); ok {
		t.Fatal("a missing log reported a rate")
	}
	// A rate above the newest readiness line belongs to an engine that has since been replaced.
	write(t, log, "[strata] done: 31 tokens in 2 s (58.1 tok/s)\nready: http://127.0.0.1:8080/v1\nloading the model ...\n")
	if _, _, ok := status.Rate(log); ok {
		t.Fatal("a rate from the previous engine was reported as current")
	}
}

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
