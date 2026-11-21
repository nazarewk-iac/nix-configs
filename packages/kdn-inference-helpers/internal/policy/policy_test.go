package policy

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// fixture is the brys policy: the pruned catalogue, the measured footprints, and the tree.
func fixture(t *testing.T) *Policy {
	t.Helper()
	body := `{
  "schemaVersion": 1,
  "budget": { "vramMiB": 32620, "ramMiB": 124000, "loadBurstRAMMiB": 60000 },
  "switchCooldownSeconds": 30,
  "defaultDeadlineSeconds": 120,
  "minDecodeTps": 20,
  "tree": {
    "type": "selector", "children": [
      { "type": "sequence", "children": [
        { "type": "check", "verb": "model-unknown" },
        { "type": "action", "verb": "refuse", "args": { "code": 400, "reason": "unknown model" } } ] },
      { "type": "sequence", "children": [
        { "type": "check", "verb": "model-disabled" },
        { "type": "action", "verb": "refuse", "args": { "code": 400, "reason": "model is disabled" } } ] },
      { "type": "sequence", "children": [
        { "type": "check", "verb": "already-satisfied" },
        { "type": "action", "verb": "serve" } ] },
      { "type": "sequence", "children": [
        { "type": "check", "verb": "join-in-flight" },
        { "type": "action", "verb": "wait" } ] },
      { "type": "sequence", "children": [
        { "type": "check", "verb": "cooldown-active" },
        { "type": "action", "verb": "refuse", "args": { "code": 429, "reason": "a switch just happened; retry shortly" } } ] },
      { "type": "selector", "children": [
        { "type": "sequence", "children": [
          { "type": "check", "verb": "profile-met" },
          { "type": "check", "verb": "tier-free" },
          { "type": "check", "verb": "fits-beside" },
          { "type": "action", "verb": "load" },
          { "type": "action", "verb": "serve" } ] },
        { "type": "sequence", "children": [
          { "type": "check", "verb": "profile-met" },
          { "type": "check", "verb": "victim-available" },
          { "type": "check", "verb": "victim-idle" },
          { "type": "check", "verb": "victim-settled" },
          { "type": "check", "verb": "victim-evictable" },
          { "type": "action", "verb": "evict" },
          { "type": "action", "verb": "load" },
          { "type": "action", "verb": "serve" } ] },
        { "type": "sequence", "children": [
          { "type": "check", "verb": "confirmed-profile" },
          { "type": "check", "verb": "switch-affordable" },
          { "type": "action", "verb": "switch-profile" },
          { "type": "action", "verb": "load" },
          { "type": "action", "verb": "serve" } ] },
        { "type": "action", "verb": "refuse", "args": { "code": 409, "reason": "no room and no permitted profile" } } ] }
    ]
  },
  "models": {
    "qfn":            { "kind": "engine", "tier": "frontier", "persistent": true,
                        "requiresProfile": ["max", "omni-max", "omni-fast"],
                        "vramMiB": 10957, "ramMiB": 60000, "measured": "2026-11-20" },
    "qfn-max":        { "kind": "engine", "tier": "frontier", "profile": "max", "persistent": true,
                        "vramMiB": 31539, "ramMiB": 62000, "switchSeconds": 72, "measured": "2026-11-20" },
    "qfn-fast-colo":  { "kind": "engine", "tier": "frontier", "profile": "omni-fast", "persistent": true,
                        "vramMiB": 10957, "ramMiB": 60000, "switchSeconds": 55, "measured": "2026-11-20" },
    "qwen-image-edit":{ "kind": "engine", "tier": "frontier", "profile": "image-qwen",
                        "vramMiB": 26829, "ramMiB": 24000, "loadSeconds": 40, "measured": "2026-11-20" },
    "wan-vace-14b":   { "kind": "engine", "tier": "frontier", "profile": "image-vace",
                        "vramMiB": 29286, "ramMiB": 26000, "loadSeconds": 40, "measured": "2026-11-20" },
    "qwen3-omni":     { "kind": "companion", "tier": "companion",
                        "requiresProfile": ["omni-max", "omni-fast"],
                        "vramMiB": 20685, "ramMiB": 21000, "decodeWithFrontier": { "omni-fast": 98.8, "max": 6.1 },
                        "minResidencySeconds": 60, "measured": "2026-11-20" },
    "qwen2.5-vl-7b":  { "kind": "companion", "tier": "companion",
                        "requiresProfile": ["omni-max", "omni-fast"],
                        "vramMiB": 12595, "ramMiB": 11000, "decodeWithFrontier": { "omni-fast": 40 },
                        "minResidencySeconds": 60, "measured": "2026-11-20" },
    "whisper-large-v3-turbo": { "kind": "small", "tier": "small", "vramMiB": 2048, "ramMiB": 4096,
                        "minResidencySeconds": 10, "measured": "2026-11-20" },
    "kokoro-82m":     { "kind": "small", "tier": "small", "vramMiB": 512, "ramMiB": 1024,
                        "minResidencySeconds": 10, "measured": "2026-11-20" }
  }
}`
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	p, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func ago(d time.Duration) *time.Time {
	t := time.Now().Add(-d)
	return &t
}

// The five audit cases, as decisions.

func TestQfnKeepsAValidTextProfile(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "qfn"},
		[]Active{{Model: "qfn", Kind: "engine", Tier: "frontier", Profile: "max", VRAMMiB: 31539}},
		State{Profile: "max", VRAMFreeMiB: 1000},
	)
	if res.Verdict != verdictAdmit || len(res.Plan.Evict) != 0 {
		t.Fatalf("qfn on max = %+v", res)
	}
}

func TestQfnRefusesAnImageProfileAndNamesTheWayOut(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "qfn"},
		[]Active{{Model: "qwen-image-edit", Kind: "engine", Tier: "frontier", Profile: "image-qwen", VRAMMiB: 26829}},
		State{Profile: "image-qwen", VRAMFreeMiB: 5000},
	)
	if res.Verdict != verdictRefuse {
		t.Fatalf("qfn kept an image profile: %+v", res)
	}
	if res.Refusal == nil || len(res.Refusal.Alternatives) == 0 || res.Refusal.ConfirmField != "kdn_switch_to" {
		t.Fatalf("refusal is not actionable: %+v", res.Refusal)
	}
}

func TestCompanionOnMaxIsRefusedWithAlternatives(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "qwen3-omni"},
		[]Active{{Model: "qfn-max", Kind: "engine", Tier: "frontier", Profile: "max", VRAMMiB: 31539}},
		State{Profile: "max", VRAMFreeMiB: 1000},
	)
	if res.Verdict != verdictRefuse || res.Refusal == nil {
		t.Fatalf("companion admitted on max: %+v", res)
	}
	if len(res.Refusal.Alternatives) != 2 {
		t.Fatalf("alternatives = %v", res.Refusal.Alternatives)
	}
}

func TestCompanionWithConfirmationSwitchesAndServes(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "qwen3-omni", Confirm: map[string]string{"kdn_switch_to": "omni-fast"}},
		[]Active{{Model: "qfn-max", Kind: "engine", Tier: "frontier", Profile: "max", VRAMMiB: 31539}},
		State{Profile: "max", VRAMFreeMiB: 1000},
	)
	if res.Verdict != verdictAdmit || res.Plan.Profile != "omni-fast" {
		t.Fatalf("confirmed switch = %+v", res)
	}
}

func TestAnEditorEvictsTheFrontier(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "qwen-image-edit"},
		[]Active{{Model: "qfn-max", Kind: "engine", Tier: "frontier", Profile: "max", VRAMMiB: 31539}},
		State{Profile: "max", VRAMFreeMiB: 1000},
	)
	if res.Verdict != verdictAdmit {
		t.Fatalf("editor refused on max: %+v", res)
	}
	if res.Plan.Profile != "image-qwen" || len(res.Plan.Evict) != 1 {
		t.Fatalf("editor plan = %+v", res.Plan)
	}
}

func TestASmallModelLoadsBesideTheFrontier(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "whisper-large-v3-turbo"},
		[]Active{{Model: "qfn-fast-colo", Kind: "engine", Tier: "frontier", Profile: "omni-fast", VRAMMiB: 10957}},
		State{Profile: "omni-fast", VRAMFreeMiB: 21000, RAMFreeMiB: 50000},
	)
	if res.Verdict != verdictAdmit || len(res.Plan.Evict) != 0 {
		t.Fatalf("small model = %+v", res)
	}
}

func TestABusyModelIsNeverTheVictim(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "qwen2.5-vl-7b"},
		[]Active{
			{Model: "qfn-fast-colo", Kind: "engine", Tier: "frontier", Profile: "omni-fast", VRAMMiB: 10957},
			{Model: "qwen3-omni", Kind: "companion", Tier: "companion", VRAMMiB: 20685, Leases: 1},
		},
		State{Profile: "omni-fast", VRAMFreeMiB: 1000, RAMFreeMiB: 50000},
	)
	if res.Verdict != verdictRefuse {
		t.Fatalf("a busy model was evicted: %+v", res)
	}
}

func TestACooldownRefusesButABatchJobIsExempt(t *testing.T) {
	p := fixture(t)
	active := []Active{{Model: "qfn-max", Kind: "engine", Tier: "frontier", Profile: "max", VRAMMiB: 31539}}
	state := State{Profile: "max", VRAMFreeMiB: 1000, LastSwitchAt: ago(5 * time.Second)}

	if res := p.Decide(Request{Model: "qwen-image-edit"}, active, state); res.Verdict != verdictRefuse || res.Refusal.Code != 429 {
		t.Fatalf("cooldown not applied: %+v", res)
	}
	if res := p.Decide(Request{Model: "qwen-image-edit", Class: "batch"}, active, state); res.Verdict != verdictAdmit {
		t.Fatalf("batch was not exempt: %+v", res)
	}
}

func TestADrainingSwitchIsJoinedNotRaced(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "qwen-image-edit"},
		[]Active{{Model: "qfn-max", Kind: "engine", Tier: "frontier", Profile: "max", VRAMMiB: 31539}},
		State{Profile: "max", VRAMFreeMiB: 1000, Draining: true},
	)
	if res.Verdict != verdictWait {
		t.Fatalf("a draining switch was raced: %+v", res)
	}
}

func TestAnUnknownModelIsRefusedSpecifically(t *testing.T) {
	p := fixture(t)
	res := p.Decide(Request{Model: "gpt-9"}, nil, State{VRAMFreeMiB: 30000})
	if res.Verdict != verdictRefuse || res.Refusal.Code != 400 {
		t.Fatalf("unknown model = %+v", res)
	}
}

// ---------------------------------------------------------------- invariants

// I1: the resulting set never exceeds the card.
// I2: no two models of one tier.
// I3: every model in the result satisfies its profile requirement.
// I4: the decision is total.
func TestInvariantsHoldOnGeneratedCases(t *testing.T) {
	p := fixture(t)
	names := make([]string, 0, len(p.Models))
	for name := range p.Models {
		names = append(names, name)
	}
	profiles := []string{"max", "omni-fast", "image-qwen", "image-vace", "none"}
	classes := []string{"", "agent", "human", "batch"}

	rng := rand.New(rand.NewSource(1))
	for i := 0; i < 5000; i++ {
		req := Request{Model: names[rng.Intn(len(names))], Class: classes[rng.Intn(len(classes))]}
		if rng.Intn(3) == 0 {
			req.Confirm = map[string]string{"kdn_switch_to": profiles[rng.Intn(len(profiles))]}
		}
		// A legal pre-state: one profile, the engine that serves it, at most one companion that the
		// profile allows, at most one small model. An illegal state is not a policy bug, and
		// admitting one would turn every generated case into a false positive.
		profile := profiles[rng.Intn(len(profiles)-1)] // never "none" as a resident profile
		var active []Active
		add := func(name string) {
			m := p.Models[name]
			active = append(active, Active{
				Model: name, Kind: m.Kind, Tier: m.Tier, Profile: m.Profile,
				VRAMMiB: m.VRAMMiB, RAMMiB: m.RAMMiB,
				Leases: rng.Intn(2), LoadedAt: ago(time.Duration(rng.Intn(600)) * time.Second),
			})
		}
		switch profile {
		case "max":
			add("qfn-max")
		case "omni-fast":
			add("qfn-fast-colo")
			if rng.Intn(2) == 0 {
				add([]string{"qwen3-omni", "qwen2.5-vl-7b"}[rng.Intn(2)])
			}
		case "image-qwen":
			add("qwen-image-edit")
		case "image-vace":
			add("wan-vace-14b")
		}
		// Only add a small model when the card can actually hold it beside the engine; an
		// over-budget pre-state is not a policy bug.
		if rng.Intn(3) == 0 {
			used := 0
			for _, a := range active {
				used += a.VRAMMiB
			}
			name := []string{"whisper-large-v3-turbo", "kokoro-82m"}[rng.Intn(2)]
			if used+p.Models[name].VRAMMiB <= p.Budget.VRAMMiB {
				add(name)
			}
		}
		// Free memory is what the card has left after the resident set: a random number here would
		// make the generator lie about the card and every admission would be a false positive.
		usedVRAM, usedRAM := 0, 0
		for _, a := range active {
			usedVRAM += a.VRAMMiB
			usedRAM += a.RAMMiB
		}
		state := State{
			Profile:      profile,
			VRAMFreeMiB:  max(0, p.Budget.VRAMMiB-usedVRAM),
			RAMFreeMiB:   max(0, p.Budget.RAMMiB-usedRAM),
			LastSwitchAt: ago(time.Duration(rng.Intn(600)) * time.Second),
		}
		res := p.Decide(req, active, state)

		if res.Verdict != verdictAdmit && res.Verdict != verdictRefuse && res.Verdict != verdictWait {
			t.Fatalf("I4 not total: %+v", res)
		}
		if res.Verdict != verdictAdmit {
			if res.Refusal == nil {
				t.Fatalf("I5 refusal without a reason: %+v", res)
			}
			continue
		}
		if res.Resulting.VRAMMiB > p.Budget.VRAMMiB {
			t.Fatalf("I1 breach: %d > %d (request %+v, profile %q, active %v, plan %+v)",
				res.Resulting.VRAMMiB, p.Budget.VRAMMiB, req, state.Profile, active, res.Plan)
		}
		tiers := map[string]string{}
		for _, id := range res.Resulting.Models {
			m, ok := p.Models[id]
			if !ok {
				t.Fatalf("I3 unknown model in result: %q", id)
			}
			if other, clash := tiers[m.Tier]; clash && other != id {
				t.Fatalf("I2 breach: %q and %q both in tier %q (request %+v, plan %+v)", other, id, m.Tier, req, res.Plan)
			}
			tiers[m.Tier] = id
			if len(m.RequiresProfile) > 0 && id != req.Model {
				// a resident model must still satisfy its requirement
				if !contains(m.RequiresProfile, res.Plan.Profile) && !contains(m.RequiresProfile, state.Profile) {
					t.Fatalf("I3 breach: %q resident on %q", id, state.Profile)
				}
			}
		}
	}
}

func TestTheTraceExplainsARefusal(t *testing.T) {
	p := fixture(t)
	res := p.Decide(
		Request{Model: "qwen3-omni"},
		[]Active{{Model: "qfn-max", Kind: "engine", Tier: "frontier", Profile: "max", VRAMMiB: 31539}},
		State{Profile: "max", VRAMFreeMiB: 1000},
	)
	if len(res.Why) < 3 {
		t.Fatalf("trace too short: %v", res.Why)
	}
	found := false
	for _, step := range res.Why {
		if step.Verb == "profile-met" && step.Result == statusFailure {
			found = true
			if step.Facts["profile"] != "max" {
				t.Fatalf("the failing check did not record the profile: %+v", step.Facts)
			}
		}
	}
	if !found {
		t.Fatalf("the trace does not show the failing profile check: %v", res.Why)
	}
	if _, err := json.Marshal(res); err != nil {
		t.Fatalf("the result does not serialise: %v", err)
	}
}

// An unknown verb must refuse to load: a typo that silently allows is the worst failure mode.
func TestAnUnknownVerbRefusesToLoad(t *testing.T) {
	body := `{"schemaVersion":1,"budget":{"vramMiB":1,"ramMiB":1},
	  "tree":{"type":"selector","children":[{"type":"check","verb":"modle-known"}]},"models":{}}`
	path := filepath.Join(t.TempDir(), "p.json")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path); err == nil {
		t.Fatal("a policy with an unknown verb loaded")
	}
}

// A model without measured facts must not be admitted silently.
func TestAnUnmeasuredModelRefusesToLoad(t *testing.T) {
	body := `{"schemaVersion":1,"budget":{"vramMiB":1,"ramMiB":1},
	  "tree":{"type":"selector","children":[{"type":"action","verb":"refuse"}]},
	  "models":{"x":{"kind":"small"}}}`
	path := filepath.Join(t.TempDir(), "p.json")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := Load(path)
	if err == nil {
		t.Fatal("a policy with an unmeasured model loaded")
	}
	if !contains([]string{fmt.Sprint(err)}, "") && err.Error() == "" {
		t.Fatal("empty error")
	}
}

// ---------------------------------------------------------------- the KV reserve

// withReserve is the fixture with one model's KV reserve set, so a test can change one number and
// see exactly what it decides.
func withReserve(t *testing.T, model string, reserve int) *Policy {
	t.Helper()
	p := fixture(t)
	m, ok := p.Models[model]
	if !ok {
		t.Fatalf("the fixture has no %q", model)
	}
	m.KVReserveMiB = reserve
	p.Models[model] = m
	return p
}

// The newcomer's own KV is part of what it needs: a model whose footprint fits but whose cache does
// not is refused, not admitted into an oversubscribed card.
func TestTheKVReserveOfTheNewcomerIsCounted(t *testing.T) {
	active := []Active{{Model: "qfn-fast-colo", Kind: "engine", Tier: "frontier", Profile: "omni-fast", VRAMMiB: 10957}}
	state := State{Profile: "omni-fast", VRAMFreeMiB: 3000, RAMFreeMiB: 50000}

	without := fixture(t)
	if res := without.Decide(Request{Model: "whisper-large-v3-turbo"}, active, state); res.Verdict != verdictAdmit {
		t.Fatalf("the fixture no longer admits a 2 GiB model with 3 GiB free: %+v", res)
	}

	with := withReserve(t, "whisper-large-v3-turbo", 2000)
	res := with.Decide(Request{Model: "whisper-large-v3-turbo"}, active, state)
	if res.Verdict != verdictRefuse {
		t.Fatalf("a 2 GiB footprint plus a 2 GiB reserve was admitted with 3 GiB free: %+v", res)
	}
	// The refusal carries the arithmetic, so an operator can see which half did not fit.
	var facts map[string]any
	for _, step := range res.Why {
		if step.Verb == "fits-beside" {
			facts = step.Facts
		}
	}
	if facts == nil {
		t.Fatalf("no fits-beside step in the trace: %+v", res.Why)
	}
	if facts["needMiB"] != 4048 || facts["kvReserveMiB"] != 2000 || facts["footprintMiB"] != 2048 {
		t.Fatalf("the trace does not show the reserve: %v", facts)
	}
}

// The resident models' reserves are not free VRAM either: the same request that fits beside an
// engine alone has to evict a companion when that companion's cache is counted. The manager fills
// `Active.KVReserveMiB` from the model's facts, so the test sets both.
func TestTheKVReserveOfResidentsIsCounted(t *testing.T) {
	state := State{Profile: "omni-fast", VRAMFreeMiB: 3000, RAMFreeMiB: 50000}
	resident := func(reserve int) []Active {
		return []Active{
			{Model: "qfn-fast-colo", Kind: "engine", Tier: "frontier", Profile: "omni-fast", VRAMMiB: 10957},
			{Model: "qwen3-omni", Kind: "companion", Tier: "companion", VRAMMiB: 20685, KVReserveMiB: reserve},
		}
	}

	without := fixture(t)
	if res := without.Decide(Request{Model: "whisper-large-v3-turbo"}, resident(0), state); res.Verdict != verdictAdmit ||
		len(res.Plan.Evict) != 0 {
		t.Fatalf("the fixture no longer loads beside the companion: %+v", res)
	}

	with := withReserve(t, "qwen3-omni", 1536)
	res := with.Decide(Request{Model: "whisper-large-v3-turbo"}, resident(1536), state)
	if res.Verdict != verdictAdmit || len(res.Plan.Evict) != 1 || res.Plan.Evict[0] != "qwen3-omni" {
		t.Fatalf("the resident reserve did not narrow the card: %+v", res)
	}
}

// The predicted end state counts the reserve too, or an operator comparing it with the card reads a
// number that is too small by exactly the KV.
func TestTheResultingVRAMCountsTheReserve(t *testing.T) {
	p := withReserve(t, "qfn-fast-colo", 336)
	res := p.Decide(
		Request{Model: "qfn"},
		[]Active{{Model: "qfn-fast-colo", Kind: "engine", Tier: "frontier", Profile: "omni-fast",
			VRAMMiB: 10957, KVReserveMiB: 336}},
		State{Profile: "omni-fast", VRAMFreeMiB: 20000},
	)
	if res.Verdict != verdictAdmit {
		t.Fatalf("qfn on its own profile = %+v", res)
	}
	if res.Resulting.VRAMMiB != 11293 {
		t.Fatalf("resulting = %d MiB, want 11293 (10957 + 336)", res.Resulting.VRAMMiB)
	}
}
