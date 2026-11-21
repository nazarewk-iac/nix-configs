package control

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"testing"
	"time"

	"kdn-inference-helpers/internal/policy"
)

// uuidV4 matches a version 4 UUID. The epoch is a compare-and-swap token, so its shape is part of
// the contract a caller can rely on (and the reason two ids are never equal).
var uuidV4 = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

// companionPolicy is the brys tree in miniature: one engine per profile, one companion tier, and a
// small tier that fits beside the frontier. It is loaded from JSON on purpose — the manager reads
// the same file a deployment writes, so a field the policy does not understand fails here too.
const companionPolicy = `{
  "schemaVersion": 1,
  "budget": { "vramMiB": 32620, "ramMiB": 124000 },
  "defaultDeadlineSeconds": 120,
  "tree": {
    "type": "selector", "children": [
      { "type": "sequence", "children": [
        { "type": "check", "verb": "model-unknown" },
        { "type": "action", "verb": "refuse", "args": { "code": 400, "reason": "unknown model" } } ] },
      { "type": "sequence", "children": [
        { "type": "check", "verb": "already-satisfied" },
        { "type": "action", "verb": "serve" } ] },
      { "type": "sequence", "children": [
        { "type": "check", "verb": "join-in-flight" },
        { "type": "action", "verb": "wait" } ] },
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
    "qfn":           { "kind": "engine", "tier": "frontier", "persistent": true,
                       "requiresProfile": ["max", "omni-fast"],
                       "vramMiB": 10957, "ramMiB": 60000, "measured": "2026-11-20" },
    "qfn-max":       { "kind": "engine", "tier": "frontier", "profile": "max", "persistent": true,
                       "vramMiB": 31539, "ramMiB": 62000, "measured": "2026-11-20" },
    "qfn-fast-colo": { "kind": "engine", "tier": "frontier", "profile": "omni-fast", "persistent": true,
                       "vramMiB": 10957, "ramMiB": 60000, "measured": "2026-11-20" },
    "qwen3-omni":    { "kind": "companion", "tier": "companion",
                       "requiresProfile": ["omni-fast"],
                       "vramMiB": 20685, "ramMiB": 21000, "measured": "2026-11-20" },
    "qwen2.5-vl-7b": { "kind": "companion", "tier": "companion",
                       "requiresProfile": ["omni-fast"],
                       "vramMiB": 12595, "ramMiB": 11000, "measured": "2026-11-20" },
    "whisper-large-v3-turbo": { "kind": "small", "tier": "small",
                       "vramMiB": 2048, "ramMiB": 4096, "measured": "2026-11-20" }
  }
}`

// withPolicy gives the manager the placement tree a deployment would mount.
func withPolicy(t *testing.T, m *Manager) *Manager {
	t.Helper()
	path := filepath.Join(t.TempDir(), "policy.json")
	if err := os.WriteFile(path, []byte(companionPolicy), 0o644); err != nil {
		t.Fatal(err)
	}
	p, err := policy.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	m.Policy = p
	return m
}

// coloManager is the state the eviction tests start from: `omni-fast` is selected and the companion
// fills the reserve, so a newcomer has to take the card from it.
func coloManager(t *testing.T) (*Manager, *fakeAccessory, *recorder) {
	t.Helper()
	rec := &recorder{loadedIDs: []string{"qwen3-omni"}}
	m, _ := newTestManager(t, rec)
	acc := &fakeAccessory{}
	m.Accessories = acc
	withPolicy(t, m)
	if err := m.saveState(map[string]any{"profile": "omni-fast"}); err != nil {
		t.Fatal(err)
	}
	return m, acc, rec
}

// call posts a JSON body to the manager's API and returns the status code and the decoded answer.
func call(t *testing.T, m *Manager, path string, body any) (int, map[string]any) {
	t.Helper()
	code, out, err := callRaw(m, path, body)
	if err != nil {
		t.Fatalf("%s: %v", path, err)
	}
	return code, out
}

// callRaw is call for a goroutine: a test that fails inside one cannot call t.Fatalf.
func callRaw(m *Manager, path string, body any) (int, map[string]any, error) {
	raw, err := json.Marshal(body)
	if err != nil {
		return 0, nil, err
	}
	r := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	w := httptest.NewRecorder()
	m.Handler().ServeHTTP(w, r)
	var out map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		return w.Code, nil, fmt.Errorf("%s answered %d with a non-JSON body %q", path, w.Code, w.Body.String())
	}
	return w.Code, out, nil
}

func TestDecideReturnsTheEvictionEpochAndKeepsIt(t *testing.T) {
	m, _, _ := coloManager(t)

	code, body := call(t, m, "/decide", map[string]any{"model": "qwen2.5-vl-7b"})
	if code != http.StatusOK {
		t.Fatalf("decide = %d %v", code, body)
	}
	id, _ := body["eviction_id"].(string)
	if !uuidV4.MatchString(id) {
		t.Fatalf("eviction_id %q is not a version 4 UUID", id)
	}
	// The plan is the suggestion the caller quotes the id for.
	plan, _ := body["plan"].(map[string]any)
	if evict, _ := plan["evict"].([]any); len(evict) != 1 || evict[0] != "qwen3-omni" {
		t.Fatalf("plan = %v", plan)
	}

	// The same id on the next call: a decision must not rotate the epoch, or no caller could ever
	// act on the suggestion it was given.
	if _, again := call(t, m, "/decide", map[string]any{"model": "qwen2.5-vl-7b"}); again["eviction_id"] != id {
		t.Fatalf("decide rotated the epoch: %v then %v", id, again["eviction_id"])
	}

	// It lives in the state file, so a manager restart does not hand out a different token for a
	// plan a caller is holding.
	state, err := os.ReadFile(m.statePath)
	if err != nil {
		t.Fatal(err)
	}
	var saved map[string]any
	if err := json.Unmarshal(state, &saved); err != nil {
		t.Fatal(err)
	}
	if saved["last_eviction_id"] != id {
		t.Fatalf("state file has %v, want %v", saved["last_eviction_id"], id)
	}
	restarted := NewManager(m.Cfg, m.Journal, m.Leases, &recorder{}, &fakeAccessory{})
	restarted.statePath = m.statePath
	if got := restarted.EvictionID(); got != id {
		t.Fatalf("after a restart the epoch is %q, want %q", got, id)
	}
}

func TestAdmitWithAStaleEpochIsRefusedAndEvictsNothing(t *testing.T) {
	m, acc, _ := coloManager(t)
	current := m.EvictionID()

	code, body := call(t, m, "/admit", map[string]any{
		"model": "qwen2.5-vl-7b", "evict": []string{"qwen3-omni"},
		"expected_eviction_id": "9f8b6a54-0000-4000-8000-000000000000",
	})
	if code != http.StatusConflict {
		t.Fatalf("a stale epoch was admitted: %d %v", code, body)
	}
	if got := len(acc.unloads()); got != 0 {
		t.Fatalf("a stale plan evicted %v", acc.unloads())
	}
	// The refusal is actionable: it carries the fresh suggestion and the id to retry with.
	if body["eviction_id"] != current {
		t.Fatalf("the refusal does not name the current epoch: %v", body)
	}
	if plan, _ := body["plan"].(map[string]any); plan == nil {
		t.Fatalf("the refusal carries no fresh suggestion: %v", body)
	}
	if m.EvictionID() != current {
		t.Fatal("a refused admit rotated the epoch")
	}
}

func TestAdmitWithTheCurrentEpochAppliesThePlanAndRotatesTheId(t *testing.T) {
	m, acc, _ := coloManager(t)
	before := m.EvictionID()

	code, body := call(t, m, "/admit", map[string]any{
		"model": "qwen2.5-vl-7b", "expected_eviction_id": before,
	})
	if code != http.StatusOK {
		t.Fatalf("admit = %d %v", code, body)
	}
	if got := acc.unloads(); len(got) != 1 || got[0] != "qwen3-omni" {
		t.Fatalf("unloaded %v, want the plan's victim", got)
	}
	after, _ := body["eviction_id"].(string)
	if !uuidV4.MatchString(after) || after == before {
		t.Fatalf("the epoch did not rotate: %q -> %q", before, after)
	}
	if m.EvictionID() != after {
		t.Fatalf("the answer says %q, the state says %q", after, m.EvictionID())
	}

	// The journal is what correlates decide -> admit -> apply: the applied plan, both epochs, and
	// whether the caller took part in the protocol.
	var admit map[string]any
	for _, e := range m.Journal.Events(0) {
		if e["event"] == "admit" {
			admit = e
		}
	}
	if admit == nil {
		t.Fatal("the admission was not journaled")
	}
	if admit["eviction_id"] != after || admit["previous_eviction_id"] != before {
		t.Fatalf("journaled epochs = %v / %v, want %v / %v",
			admit["eviction_id"], admit["previous_eviction_id"], after, before)
	}
	if admit["cas"] != "matched" {
		t.Fatalf("cas = %v, want matched", admit["cas"])
	}
	if evicted, _ := admit["evicted"].([]any); len(evicted) != 1 || evicted[0] != "qwen3-omni" {
		t.Fatalf("journaled eviction = %v", admit["evicted"])
	}
}

// The caller's set wins: it may differ from the suggestion, and an empty set means "evict nothing",
// which is not the same as leaving the field out.
func TestAdmitAppliesExactlyTheSetTheCallerGave(t *testing.T) {
	m, acc, _ := coloManager(t)

	code, body := call(t, m, "/admit", map[string]any{
		"model": "whisper-large-v3-turbo", "evict": []string{}, "expected_eviction_id": m.EvictionID(),
	})
	if code != http.StatusOK {
		t.Fatalf("admit = %d %v", code, body)
	}
	// The tree would have taken the companion to make room; the caller said no.
	plan, _ := body["plan"].(map[string]any)
	if evict, _ := plan["evict"].([]any); len(evict) != 1 {
		t.Fatalf("the fixture no longer suggests an eviction: %v", plan)
	}
	if got := acc.unloads(); len(got) != 0 {
		t.Fatalf("the caller's empty set was overruled: unloaded %v", got)
	}
	if applied, _ := body["evicted"].([]any); len(applied) != 0 {
		t.Fatalf("the answer claims an eviction: %v", body["evicted"])
	}
}

// A caller that omits the id is the `admit` wrapper in every llama-swap entry: it has no decision to
// protect and the plan is applied unconditionally, as before the epoch existed.
func TestAdmitWithoutAnEpochStillAppliesThePlan(t *testing.T) {
	m, acc, _ := coloManager(t)
	before := m.EvictionID()

	code, body := call(t, m, "/admit", map[string]any{"model": "qwen2.5-vl-7b"})
	if code != http.StatusOK {
		t.Fatalf("admit = %d %v", code, body)
	}
	if got := acc.unloads(); len(got) != 1 || got[0] != "qwen3-omni" {
		t.Fatalf("unloaded %v", got)
	}
	if body["eviction_id"] == before {
		t.Fatal("the epoch did not rotate")
	}
	var admit map[string]any
	for _, e := range m.Journal.Events(0) {
		if e["event"] == "admit" {
			admit = e
		}
	}
	if admit["cas"] != "skipped" {
		t.Fatalf("cas = %v, want skipped", admit["cas"])
	}
}

// Two callers that decided against the same epoch must not both act on it. One wins, one is told to
// decide again; the victim is evicted once.
func TestTwoConcurrentAdmitsWithOneEpochAdmitExactlyOne(t *testing.T) {
	m, acc, _ := coloManager(t)
	epoch := m.EvictionID()

	type outcome struct {
		code int
		body map[string]any
	}
	results := make([]outcome, 2)
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			code, body, err := callRaw(m, "/admit", map[string]any{
				"model": "qwen2.5-vl-7b", "evict": []string{"qwen3-omni"},
				"expected_eviction_id": epoch,
			})
			if err != nil {
				results[i] = outcome{code: -1, body: map[string]any{"error": err.Error()}}
				return
			}
			results[i] = outcome{code, body}
		}(i)
	}
	close(start)
	wg.Wait()

	var ok, stale int
	for _, r := range results {
		switch r.code {
		case http.StatusOK:
			ok++
		case http.StatusConflict:
			stale++
		default:
			t.Fatalf("unexpected answer %d: %v", r.code, r.body)
		}
	}
	if ok != 1 || stale != 1 {
		t.Fatalf("ok=%d stale=%d, want one of each: %v", ok, stale, results)
	}
	if got := acc.unloads(); len(got) != 1 {
		t.Fatalf("the victim was evicted %d times: %v", len(got), got)
	}
}

// The engine is not a victim: only a profile switch may stop it, and a caller that names it is
// refused rather than allowed to drop the frontier for a companion.
func TestAdmitRefusesToEvictTheEngine(t *testing.T) {
	m, acc, _ := coloManager(t)

	code, body := call(t, m, "/admit", map[string]any{
		"model": "whisper-large-v3-turbo", "evict": []string{"qfn-fast-colo"},
		"expected_eviction_id": m.EvictionID(),
	})
	if code != http.StatusConflict {
		t.Fatalf("the engine was accepted as a victim: %d %v", code, body)
	}
	if got := acc.unloads(); len(got) != 0 {
		t.Fatalf("unloaded %v", got)
	}
}

// A plan that names a profile is applied under the switch lock the admission already holds. This is
// the path that deadlocked the manager before the lock was split: `sync.Mutex` is not reentrant.
func TestAdmitAppliesAProfileSwitchWithoutDeadlocking(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)
	m.Accessories = &fakeAccessory{}
	withPolicy(t, m)
	if err := m.saveState(map[string]any{"profile": "max"}); err != nil {
		t.Fatal(err)
	}

	done := make(chan struct{})
	go func() {
		defer close(done)
		code, body, err := callRaw(m, "/admit", map[string]any{
			"model":                "qwen3-omni",
			"confirm":              map[string]string{"kdn_switch_to": "omni-fast"},
			"expected_eviction_id": m.EvictionID(),
		})
		if err != nil {
			t.Errorf("admit: %v", err)
			return
		}
		if code != http.StatusOK {
			t.Errorf("admit = %d %v", code, body)
		}
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("a plan that switches the profile never returned: the switch lock was taken twice")
	}
	if got := m.CurrentProfile(); got != "omni-fast" {
		t.Fatalf("profile = %q, want omni-fast", got)
	}
}
