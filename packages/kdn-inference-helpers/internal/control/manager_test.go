package control

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"kdn-inference-helpers/internal/config"
	"kdn-inference-helpers/internal/journal"
)

// recorder is a Backend that records the order of operations a switch performs.
type recorder struct {
	mu        sync.Mutex
	calls     []string
	unloaded  []string
	startErr  error
	loadedIDs []string
}

func (r *recorder) record(name string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = append(r.calls, name)
}

func (r *recorder) StartEngine(ctx context.Context, profile string) (time.Duration, error) {
	r.record("start:" + profile)
	return 42 * time.Second, r.startErr
}
func (r *recorder) StopEngine(ctx context.Context) (time.Duration, error) {
	r.record("stop")
	return 4 * time.Second, nil
}
func (r *recorder) DropCaches(ctx context.Context) (time.Duration, error) {
	r.record("drop")
	return 4 * time.Second, nil
}
func (r *recorder) UnloadCompanions(ctx context.Context) ([]string, error) {
	r.record("unload-companions")
	return r.unloaded, nil
}
func (r *recorder) LoadedModels(ctx context.Context) ([]string, error) {
	return r.loadedIDs, nil
}
func (r *recorder) EngineReady() bool { return false }

func (r *recorder) order() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.calls...)
}

type fakeAccessory struct {
	mu      sync.Mutex
	loaded  []string
	refused bool
}

func (f *fakeAccessory) Loaded(ctx context.Context) ([]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.loaded...), nil
}

func (f *fakeAccessory) Unload(ctx context.Context, model string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.refused {
		return errors.New("unload refused")
	}
	return nil
}

func newTestManager(t *testing.T, b Backend) (*Manager, *journal.Journal) {
	t.Helper()
	cfg := config.Defaults()
	cfg.DataDir = t.TempDir()
	if err := cfg.Validate(); err != nil {
		t.Fatal(err)
	}
	j := journal.New(cfg.EventsPath())
	m := NewManager(cfg, j, NewLeases(time.Minute), b, &fakeAccessory{})
	return m, j
}

func TestSelectSameProfileIsANoOp(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)
	if err := m.saveState(map[string]any{"profile": "max"}); err != nil {
		t.Fatal(err)
	}
	got := m.Select(context.Background(), "max", false)
	if got["changed"] != false || got["profile"] != "max" {
		t.Fatalf("select = %#v", got)
	}
	if len(rec.order()) != 0 {
		t.Fatalf("a no-op switch touched the engine: %v", rec.order())
	}
}

func TestSelectAliasesResolve(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)
	_ = m.saveState(map[string]any{"profile": "omni-fast"})

	// qfn -> auto keeps the current profile and touches nothing.
	got := m.Select(context.Background(), "qfn", false)
	if got["changed"] != false || got["profile"] != "omni-fast" {
		t.Fatalf("qfn select = %#v", got)
	}
	if len(rec.order()) != 0 {
		t.Fatalf("qfn touched the engine: %v", rec.order())
	}

	// qfn-max -> max switches.
	got = m.Select(context.Background(), "qfn-max", false)
	if got["changed"] != true || got["profile"] != "max" {
		t.Fatalf("qfn-max select = %#v", got)
	}
}

func TestSelectUnknownProfileIsRejectedWithoutTouchingTheEngine(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)
	got := m.Select(context.Background(), "bogus", false)
	if _, ok := got["error"]; !ok {
		t.Fatalf("unknown profile accepted: %#v", got)
	}
	if len(rec.order()) != 0 {
		t.Fatalf("unknown profile touched the engine: %v", rec.order())
	}
}

func TestDryRunReportsCostAndDoesNothing(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)
	_ = m.saveState(map[string]any{"profile": "omni-fast"})
	got := m.Select(context.Background(), "qfn-max", true)
	if got["dry_run"] != true || got["would_change"] != true || got["profile"] != "max" {
		t.Fatalf("dry run = %#v", got)
	}
	if got["expected_seconds"] != 70 {
		t.Fatalf("expected_seconds = %v", got["expected_seconds"])
	}
	if len(rec.order()) != 0 {
		t.Fatalf("a dry run touched the engine: %v", rec.order())
	}
}

func TestSwitchOrderDrainsThenUnloadsStopsDropsAndStarts(t *testing.T) {
	rec := &recorder{unloaded: []string{"qwen3-omni"}}
	m, j := newTestManager(t, rec)
	_ = m.saveState(map[string]any{"profile": "omni-fast"})

	got := m.Select(context.Background(), "max", false)
	if got["changed"] != true || got["profile"] != "max" {
		t.Fatalf("select = %#v", got)
	}
	want := []string{"unload-companions", "stop", "drop", "start:max"}
	gotOrder := rec.order()
	if strings.Join(gotOrder, ",") != strings.Join(want, ",") {
		t.Fatalf("order = %v, want %v", gotOrder, want)
	}
	if profile := m.CurrentProfile(); profile != "max" {
		t.Fatalf("state profile = %q", profile)
	}
	if last, ok := j.LastSwitch(); !ok || last["to"] != "max" || last["cause"] != "select" {
		t.Fatalf("last switch = %#v", last)
	}
	events := j.Events(0)
	var sawDown bool
	for _, e := range events {
		if e["event"] == journal.EventCompanionDown && e["cause"] == "switch" {
			sawDown = true
		}
	}
	if !sawDown {
		t.Fatal("the unloaded companion was not journaled")
	}
}

func TestSwitchFromNoneAndToNoneAreJournaled(t *testing.T) {
	rec := &recorder{}
	m, j := newTestManager(t, rec)
	_ = m.saveState(map[string]any{"profile": "max"})

	if got := m.Select(context.Background(), "none", false); got["changed"] != true {
		t.Fatalf("select none = %#v", got)
	}
	if profile := m.CurrentProfile(); profile != "none" {
		t.Fatalf("profile = %q", profile)
	}
	last, _ := j.LastSwitch()
	if last["to"] != "none" {
		t.Fatalf("last switch = %#v", last)
	}
}

func TestAFailedStartClearsTheProfileAndJournalsFailure(t *testing.T) {
	rec := &recorder{startErr: errors.New("out of memory")}
	m, j := newTestManager(t, rec)
	_ = m.saveState(map[string]any{"profile": "omni-fast"})

	got := m.Select(context.Background(), "max", false)
	if got["error"] == nil || got["profile"] != nil {
		t.Fatalf("failed switch = %#v", got)
	}
	if profile := m.CurrentProfile(); profile != "" {
		t.Fatalf("state profile = %q, want empty", profile)
	}
	last, _ := j.LastSwitch()
	if last["ok"] != false {
		t.Fatalf("last switch = %#v", last)
	}
}

func TestSwitchWaitsForAnInFlightRequest(t *testing.T) {
	rec := &recorder{}
	m, j := newTestManager(t, rec)
	_ = m.saveState(map[string]any{"profile": "omni-fast"})

	lease, ok := m.Leases.Acquire()
	if !ok {
		t.Fatal("acquire failed")
	}

	done := make(chan map[string]any, 1)
	go func() { done <- m.Select(context.Background(), "max", false) }()

	select {
	case got := <-done:
		t.Fatalf("switch finished while a lease was held: %#v", got)
	case <-time.After(150 * time.Millisecond):
	}
	if m.Leases.InFlight() != 1 {
		t.Fatalf("in flight = %d", m.Leases.InFlight())
	}

	m.Leases.Release(lease)
	select {
	case got := <-done:
		if got["changed"] != true {
			t.Fatalf("switch after release = %#v", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("switch never completed after the lease was released")
	}
	var sawDrain bool
	for _, e := range j.Events(0) {
		if e["event"] == journal.EventDrain && e["clean"] == true {
			sawDrain = true
		}
	}
	if !sawDrain {
		t.Fatal("the drain was not journaled")
	}
}

func TestRestoreStartsTheRememberedProfile(t *testing.T) {
	rec := &recorder{}
	m, j := newTestManager(t, rec)
	_ = m.saveState(map[string]any{"profile": "omni-fast"})

	m.Restore(context.Background())
	if order := rec.order(); len(order) != 1 || order[0] != "start:omni-fast" {
		t.Fatalf("restore order = %v", order)
	}
	last, ok := j.LastSwitch()
	if !ok || last["cause"] != "restore" || last["to"] != "omni-fast" {
		t.Fatalf("restore journal = %#v", last)
	}
}

func TestRestoreDoesNothingWithoutAProfileOrWithACorruptState(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)
	m.Restore(context.Background()) // no state file
	if len(rec.order()) != 0 {
		t.Fatalf("restore touched the engine with no state: %v", rec.order())
	}

	if err := os.MkdirAll(filepath.Dir(m.statePath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := writeFile(m.statePath, "{not json"); err != nil {
		t.Fatal(err)
	}
	m.Restore(context.Background())
	if len(rec.order()) != 0 {
		t.Fatalf("restore touched the engine with a corrupt state: %v", rec.order())
	}
}

func TestStatusReportsTheFieldsAnAgentReads(t *testing.T) {
	m, _ := newTestManager(t, &recorder{})
	_ = m.saveState(map[string]any{"profile": "max"})

	rec := httptest.NewRecorder()
	m.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/status", nil))
	if rec.Code != 200 {
		t.Fatalf("status code %d", rec.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"profile", "last_switch", "last_switch_seconds_ago",
		"loaded_companions", "in_flight", "draining"} {
		if _, ok := body[key]; !ok {
			t.Fatalf("status is missing %q: %#v", key, body)
		}
	}
	if body["profile"] != "max" {
		t.Fatalf("profile = %v", body["profile"])
	}
}

func TestLeaseEndpointsRefuseDuringADrainAndGrantAfter(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)

	post := func(path string, body any) map[string]any {
		raw, _ := json.Marshal(body)
		r := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
		w := httptest.NewRecorder()
		m.Handler().ServeHTTP(w, r)
		var out map[string]any
		_ = json.Unmarshal(w.Body.Bytes(), &out)
		return out
	}

	got := post("/lease", nil)
	id, ok := got["lease"].(float64)
	if !ok {
		t.Fatalf("lease = %#v", got)
	}
	if released := post("/release", map[string]any{"lease": int64(id)}); released["released"] != id {
		t.Fatalf("release = %#v", released)
	}

	// Refuse while a switch is in progress.
	m.Leases.BeginDrain(context.Background())
	if got := post("/lease", nil); got["wait"] != true {
		t.Fatalf("lease during drain = %#v", got)
	}
	m.Leases.EndDrain()
	if got := post("/lease", nil); got["lease"] == nil {
		t.Fatalf("lease after drain = %#v", got)
	}
}

func TestUnloadRefusesAFrontierModelAndUnloadsACompanion(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)
	acc := &fakeAccessory{loaded: []string{"qwen3-omni"}}
	m.Accessories = acc

	post := func(body any) map[string]any {
		raw, _ := json.Marshal(body)
		r := httptest.NewRequest(http.MethodPost, "/unload", bytes.NewReader(raw))
		w := httptest.NewRecorder()
		m.Handler().ServeHTTP(w, r)
		var out map[string]any
		_ = json.Unmarshal(w.Body.Bytes(), &out)
		return out
	}

	if got := post(map[string]string{"model": "qfn"}); got["ok"] != false {
		t.Fatalf("a frontier model was unloaded: %#v", got)
	}
	if got := post(map[string]string{"model": "qwen3-omni"}); got["ok"] != true {
		t.Fatalf("companion unload = %#v", got)
	}
}

func TestCompanionWatcherJournalsUpAndDown(t *testing.T) {
	rec := &recorder{}
	m, j := newTestManager(t, rec)
	acc := &fakeAccessory{}
	m.Accessories = acc

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go m.WatchCompanions(ctx, 20*time.Millisecond)

	acc.mu.Lock()
	acc.loaded = []string{"qfn", "qwen3-omni"} // qfn is a frontier id and must be ignored
	acc.mu.Unlock()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && len(m.LoadedCompanions()) == 0 {
		time.Sleep(10 * time.Millisecond)
	}
	if got := m.LoadedCompanions(); len(got) != 1 || got[0] != "qwen3-omni" {
		t.Fatalf("companions = %v", got)
	}

	acc.mu.Lock()
	acc.loaded = nil
	acc.mu.Unlock()
	deadline = time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && len(m.LoadedCompanions()) != 0 {
		time.Sleep(10 * time.Millisecond)
	}
	if got := m.LoadedCompanions(); len(got) != 0 {
		t.Fatalf("companions after unload = %v", got)
	}

	var ups, downs int
	for _, e := range j.Events(0) {
		switch e["event"] {
		case journal.EventCompanionUp:
			ups++
		case journal.EventCompanionDown:
			downs++
		}
	}
	if ups < 1 || downs < 1 {
		t.Fatalf("companion journal ups=%d downs=%d", ups, downs)
	}
}

func writeFile(path, body string) error {
	return os.WriteFile(path, []byte(body), 0o644)
}

func TestAutoStartsMaxWhenNothingIsLoadedAndNeverSwitchesARunningProfile(t *testing.T) {
	rec := &recorder{}
	m, _ := newTestManager(t, rec)

	// Nothing loaded: `qfn` is the first request of the day and must start the best profile.
	got := m.Select(context.Background(), "qfn", false)
	if got["changed"] != true || got["profile"] != "max" {
		t.Fatalf("first qfn request = %#v, want max", got)
	}

	// Running: `qfn` must not touch it, whatever it is.
	for _, profile := range []string{"omni-fast", "omni-max", "max"} {
		_ = m.saveState(map[string]any{"profile": profile})
		before := len(rec.order())
		got := m.Select(context.Background(), "qfn", false)
		if got["changed"] != false || got["profile"] != profile {
			t.Fatalf("qfn while %s = %#v", profile, got)
		}
		if len(rec.order()) != before {
			t.Fatalf("qfn touched the engine while %s was running: %v", profile, rec.order()[before:])
		}
	}
}

func TestLastCompanionUnloadReturnsTheEngineToMax(t *testing.T) {
	rec := &recorder{}
	m, j := newTestManager(t, rec)
	acc := &fakeAccessory{loaded: []string{"qwen3-omni"}}
	m.Accessories = acc
	_ = m.saveState(map[string]any{"profile": "omni-fast"})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go m.WatchCompanions(ctx, 20*time.Millisecond)

	// First observation: the companion is loaded, nothing to revert.
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && len(m.LoadedCompanions()) == 0 {
		time.Sleep(10 * time.Millisecond)
	}

	// The companion goes away (llama-swap's ttl, or an explicit unload). The engine must return to
	// the whole-card profile on its own.
	acc.mu.Lock()
	acc.loaded = nil
	acc.mu.Unlock()

	deadline = time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if m.CurrentProfile() == "max" {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if got := m.CurrentProfile(); got != "max" {
		t.Fatalf("profile = %q after the companion unloaded, want max", got)
	}
	var reverted bool
	for _, e := range j.Events(0) {
		if e["event"] == "companion_revert" {
			reverted = true
		}
	}
	if !reverted {
		t.Fatal("the revert was not journaled")
	}
}
