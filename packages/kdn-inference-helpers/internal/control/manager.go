package control

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"kdn-inference-helpers/internal/config"
	"kdn-inference-helpers/internal/journal"
	"kdn-inference-helpers/internal/policy"
)

// Backend is what the control plane needs from the engine. The supervisor and the llama-swap client
// implement it; a test implements it with a recorder.
//
// The manager never learns the engine's name: it asks for profiles to be started, stopped, and for
// the page cache to be released through a hook the deployment configured.
type Backend interface {
	StartEngine(ctx context.Context, profile string) (time.Duration, error)
	StopEngine(ctx context.Context) (time.Duration, error)
	DropCaches(ctx context.Context) (time.Duration, error)
	UnloadCompanions(ctx context.Context) ([]string, error)
	LoadedModels(ctx context.Context) ([]string, error)
	EngineReady() bool
	// CurrentPort is where the running profile listens. The frontier uses the deployment's engine
	// port; a diffusion server gets its own, so a caller proxies to the right one.
	CurrentPort() int
	// Profiles is the adapter's table, so a gate can check a requested target against what this
	// deployment can actually serve.
	Profiles() []string
}

// Accessory is the llama-swap side: which models are loaded, and unloading one by name.
type Accessory interface {
	Loaded(ctx context.Context) ([]string, error)
	Unload(ctx context.Context, model string) error
}

// Manager is the control plane: the selected profile, the drain, the journal and the HTTP API.
type Manager struct {
	Cfg *config.Config
	// Policy is the placement tree, loaded from the deployment. Nil means the deployment has not
	// adopted it yet, and `/decide` answers 501 rather than inventing a decision.
	Policy  *policy.Policy
	Journal *journal.Journal
	Leases  *Leases
	Backend Backend
	// Accessories is the llama-swap client, used by `/unload` and by the companion watcher.
	Accessories Accessory
	// ExpectedSeconds is the cost table a dry run reports; a deployment can tune it.
	ExpectedSeconds map[string]int

	mu         sync.Mutex // serialises switches
	statePath  string
	companions map[string]bool // model id -> loaded, as last observed
	observedMu sync.Mutex
	// stateMu guards the state file. The profile and the eviction epoch live in the same file, and
	// a read-modify-write that lost one of them would either drop the selected profile or let a
	// stale eviction plan through, so every access takes this lock.
	stateMu sync.Mutex
}

// NewManager wires the control plane. It does not start anything; call Restore for that.
func NewManager(cfg *config.Config, j *journal.Journal, leases *Leases, backend Backend, acc Accessory) *Manager {
	expected := map[string]int{"max": 70, "omni-max": 70, "omni-fast": 55}
	return &Manager{
		Cfg: cfg, Journal: j, Leases: leases, Backend: backend, Accessories: acc,
		ExpectedSeconds: expected, statePath: cfg.StatePath(), companions: map[string]bool{},
	}
}

// ---------------- state ----------------

// loadState reads the state file. A missing or corrupt file reads as an empty state: "no profile"
// is a safe answer, and a crash here would leave the card unattended.
func (m *Manager) loadState() map[string]any {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	return m.loadStateLocked()
}

func (m *Manager) loadStateLocked() map[string]any {
	body, err := os.ReadFile(m.statePath)
	if err != nil {
		return map[string]any{}
	}
	var state map[string]any
	if err := json.Unmarshal(body, &state); err != nil {
		return map[string]any{} // a corrupt file means "no profile", never a crash
	}
	return state
}

// saveState writes the given keys and keeps the ones already on disk. The profile and the eviction
// epoch are written by different callers, and a caller that sets one key must not erase the other.
func (m *Manager) saveState(state map[string]any) error {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	return m.saveStateLocked(state)
}

func (m *Manager) saveStateLocked(state map[string]any) error {
	if err := os.MkdirAll(filepath.Dir(m.statePath), 0o755); err != nil {
		return err
	}
	merged := m.loadStateLocked()
	for k, v := range state {
		merged[k] = v
	}
	body, err := json.Marshal(merged)
	if err != nil {
		return err
	}
	return os.WriteFile(m.statePath, body, 0o644)
}

// CurrentProfile is the profile the state file remembers.
func (m *Manager) CurrentProfile() string {
	state := m.loadState()
	p, _ := state["profile"].(string)
	return p
}

// EvictionID is the current eviction epoch: the token a caller must echo back to `/admit` to prove
// its plan is still the one the manager would apply. It is created on first use, so a manager that
// has just started still answers `/decide` with an id a caller can quote.
func (m *Manager) EvictionID() string {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	state := m.loadStateLocked()
	if id, ok := state["last_eviction_id"].(string); ok && id != "" {
		return id
	}
	id := newUUIDv4()
	if err := m.saveStateLocked(map[string]any{"last_eviction_id": id}); err != nil {
		log.Printf("could not persist the eviction id: %v", err)
	}
	return id
}

// rotateEvictionID starts a new epoch and returns its id. Every applied plan rotates it: after an
// eviction the world the caller decided on no longer exists, so its token must stop working.
func (m *Manager) rotateEvictionID() string {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	id := newUUIDv4()
	if err := m.saveStateLocked(map[string]any{"last_eviction_id": id}); err != nil {
		log.Printf("could not persist the eviction id: %v", err)
	}
	return id
}

// ---------------- switching ----------------

// Select switches, or reports what a switch would cost. The returned map is the JSON body.
func (m *Manager) Select(ctx context.Context, requested string, dryRun bool) map[string]any {
	return m.SelectKeeping(ctx, requested, dryRun, false)
}

// SelectKeeping is Select with one knob: a switch asked for by the companion gate keeps the gate
// alive. Without it the switch unloads every non-frontier model — including the gate process that
// is waiting on this very call, which cancels the call and fails the switch it asked for.
func (m *Manager) SelectKeeping(ctx context.Context, requested string, dryRun, keepCompanions bool) map[string]any {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.selectLocked(ctx, requested, dryRun, keepCompanions)
}

// selectLocked is the switch itself, for a caller that already holds the switch lock. `/admit`
// decides under that lock and then has to apply a plan that may name a profile, so it cannot go
// through SelectKeeping: a `sync.Mutex` is not reentrant, and taking it twice deadlocks the manager
// on the first companion that needs a colo profile.
func (m *Manager) selectLocked(ctx context.Context, requested string, dryRun, keepCompanions bool) map[string]any {
	profile := m.Cfg.Normalise(requested)
	if !m.Cfg.Accepts(profile) {
		return map[string]any{"error": fmt.Sprintf("unknown profile %q", requested)}
	}

	current := m.CurrentProfile()
	switch {
	case profile == "none":
		if dryRun {
			return map[string]any{"dry_run": true, "would_change": current != "" && current != "none",
				"current": current, "profile": "none"}
		}
		start := time.Now()
		_, _ = m.Backend.UnloadCompanions(ctx)
		_, _ = m.Backend.StopEngine(ctx)
		_ = m.saveState(map[string]any{"profile": "none"})
		m.journalSwitch(current, "none", round(time.Since(start)), true, "select")
		return map[string]any{"changed": current != "" && current != "none", "profile": "none"}
	case profile == current:
		return map[string]any{"changed": false, "profile": current, "note": "already selected",
			"port": m.Backend.CurrentPort()}
	case profile == "auto":
		// `qfn` must never switch a running model. With nothing loaded it starts the best profile,
		// which is the "first request of the day" case.
		if current != "" && current != "none" {
			// ...but "never switch" must not become "serve chat from whatever is loaded". A
			// diffusion server answers no chat, so a kept image profile would turn a model name into
			// a 404 from the wrong process. Refuse, and name the way out.
			if !m.Cfg.IsText(current) {
				return map[string]any{
					"error": fmt.Sprintf(
						"profile %q serves images, not chat; switch to a text profile first (kdn_switch_to: %q)",
						current, m.Cfg.DefaultTextProfile()),
					"profile":       current,
					"kdn_switch_to": m.Cfg.DefaultTextProfile(),
					"changed":       false,
				}
			}
			return map[string]any{"changed": false, "profile": current, "note": "auto: kept the current profile"}
		}
		profile = m.Cfg.DefaultTextProfile()
	case dryRun:
		body := map[string]any{"dry_run": true, "would_change": true, "current": current,
			"profile": profile, "expected_seconds": m.ExpectedSeconds[profile]}
		if last, ok := m.Journal.LastSwitch(); ok {
			if ts, ok := last["ts"].(float64); ok {
				body["last_switch_seconds_ago"] = int(time.Since(time.Unix(0, int64(ts*1e9))).Seconds())
			}
			body["last_switch"] = last
		}
		return body
	}

	start := time.Now()
	// Phase 1: stop accepting work and wait for the leases already granted. A request on the stable
	// name is delayed by this, never cut.
	drainCtx, cancel := context.WithTimeout(ctx, time.Duration(m.Cfg.DrainTimeoutSeconds)*time.Second)
	defer cancel()
	if stale := m.Leases.ExpireStale(); stale > 0 {
		_ = m.Journal.Append(map[string]any{"event": "stale_lease", "count": stale})
	}
	waited, clean := m.Leases.BeginDrain(drainCtx)
	if waited > 0 || !clean {
		_ = m.Journal.Append(map[string]any{"event": journal.EventDrain,
			"seconds": round(waited), "clean": clean})
	}

	var unloaded []string
	if !keepCompanions {
		unloaded, _ = m.Backend.UnloadCompanions(ctx)
	}
	if len(unloaded) > 0 {
		_ = m.Journal.Append(map[string]any{"event": journal.EventCompanionDown,
			"model": strings.Join(unloaded, ","), "cause": "switch"})
	}
	if d, err := m.Backend.StopEngine(ctx); err == nil {
		_ = m.Journal.Append(map[string]any{"event": journal.EventEngineStop, "seconds": round(d)})
	}
	if d, err := m.Backend.DropCaches(ctx); err == nil {
		_ = m.Journal.Append(map[string]any{"event": journal.EventCacheDrop, "seconds": round(d), "ok": true})
	}
	loadStart := time.Now()
	loadDur, err := m.Backend.StartEngine(ctx, profile)
	loadEvent := map[string]any{"event": journal.EventEngineLoad,
		"profile": profile, "seconds": round(loadDur), "ok": err == nil}
	if err != nil {
		// Without the reason a failed switch is indistinguishable from a slow one.
		loadEvent["error"] = err.Error()
		log.Printf("switch to %s failed: %v", profile, err)
	}
	_ = m.Journal.Append(loadEvent)
	// Phase 2 ends here: whatever was running is gone and the new engine either answers or failed.
	m.Leases.EndDrain()

	total := round(time.Since(start))
	if err != nil {
		_ = m.saveState(map[string]any{"profile": nil})
		m.journalSwitch(current, profile, total, false, "select")
		return map[string]any{"error": err.Error(), "profile": nil}
	}
	_ = m.saveState(map[string]any{"profile": profile})
	_ = loadStart
	m.journalSwitch(current, profile, total, true, "select")
	return map[string]any{"changed": true, "profile": profile, "seconds": total,
		"port": m.Backend.CurrentPort()}
}

func (m *Manager) journalSwitch(from, to string, seconds int, ok bool, cause string) {
	_ = m.Journal.Append(map[string]any{"event": journal.EventSwitch, "from": from, "to": to,
		"seconds": seconds, "ok": ok, "cause": cause})
}

// Restore brings back the profile the last run left selected. Without it a reboot leaves the state
// file claiming a profile that nothing serves.
func (m *Manager) Restore(ctx context.Context) {
	profile := m.CurrentProfile()
	if profile == "" || profile == "none" {
		return
	}
	if m.Backend.EngineReady() {
		return
	}
	start := time.Now()
	loadStart := time.Now()
	loadDur, err := m.Backend.StartEngine(ctx, profile)
	_ = m.Journal.Append(map[string]any{"event": journal.EventEngineLoad,
		"profile": profile, "seconds": round(loadDur), "ok": err == nil})
	_ = loadStart
	if err != nil {
		// The reason goes to the journal as well as stderr: a restore that fails is the first thing
		// anyone looks at after a reboot, and "ok:false" alone says nothing.
		log.Printf("restore of %s failed: %v", profile, err)
		_ = m.Journal.Append(map[string]any{"event": journal.EventEngineLoad,
			"profile": profile, "seconds": round(loadDur), "ok": false, "error": err.Error()})
		_ = m.saveState(map[string]any{"profile": nil})
		m.journalSwitch("", profile, round(time.Since(start)), false, "restore")
		return
	}
	m.journalSwitch("", profile, round(time.Since(start)), true, "restore")
}

// ---------------- companions ----------------

// WatchCompanions records llama-swap's view of the non-frontier models, so `/status` can report them
// and the journal can time their stays. It runs until ctx ends.
func (m *Manager) WatchCompanions(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = 3 * time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			loaded, err := m.Accessories.Loaded(ctx)
			if err != nil {
				continue
			}
			now := time.Now()
			seen := map[string]bool{}
			for _, id := range loaded {
				if m.Cfg.IsFrontier(id) {
					continue
				}
				seen[id] = true
				m.observedMu.Lock()
				was := m.companions[id]
				m.companions[id] = true
				m.observedMu.Unlock()
				if !was {
					_ = m.Journal.Append(map[string]any{"event": journal.EventCompanionUp,
						"model": id, "observed": true, "at": now.Unix()})
				}
			}
			m.observedMu.Lock()
			lastGone := ""
			for id, was := range m.companions {
				if was && !seen[id] {
					delete(m.companions, id)
					lastGone = id
					_ = m.Journal.Append(map[string]any{"event": journal.EventCompanionDown,
						"model": id, "observed": true})
				}
			}
			left := len(m.companions) == 0
			m.observedMu.Unlock()
			// The reserve exists for the companion. When the last one goes away, the engine goes
			// back to the whole card on its own: `qfn` would otherwise keep paying for a reserve
			// nothing is using.
			if lastGone != "" && left {
				m.revertToDefault(ctx)
			}
		}
	}
}

// revertToDefault switches back to `max` after the last companion unloaded, unless the deployment's
// aliases say a different resting profile. It runs in the watcher goroutine and takes the switch
// lock, so it queues behind any explicit selection.
func (m *Manager) revertToDefault(ctx context.Context) {
	resting := "max"
	if named, ok := m.Cfg.Aliases["qfn-default"]; ok && named != "" && named != "auto" {
		resting = named
	}
	current := m.CurrentProfile()
	if current == "" || current == "none" || current == resting {
		return
	}
	_ = m.Journal.Append(map[string]any{"event": "companion_revert", "from": current, "to": resting})
	go m.Select(context.WithoutCancel(ctx), resting, false)
}

// HasReserve reports whether a profile keeps VRAM aside for a companion. The companion entry uses
// this to decide between serving and answering the confirmation error.
func (m *Manager) HasReserve() bool {
	switch m.CurrentProfile() {
	case "omni-max", "omni-fast":
		return true
	default:
		return false
	}
}

// LoadedCompanions is what `/status` reports.
func (m *Manager) LoadedCompanions() []string {
	m.observedMu.Lock()
	defer m.observedMu.Unlock()
	out := make([]string, 0, len(m.companions))
	for id := range m.companions {
		out = append(out, id)
	}
	return out
}

// ---------------- HTTP ----------------

// Handler returns the control API.
func (m *Manager) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/status", m.handleStatus)
	mux.HandleFunc("/stats", m.handleStats)
	mux.HandleFunc("/events", m.handleEvents)
	mux.HandleFunc("/select", m.handleSelect)
	mux.HandleFunc("/lease", m.handleLease)
	mux.HandleFunc("/release", m.handleRelease)
	mux.HandleFunc("/unload", m.handleUnload)
	mux.HandleFunc("/decide", m.handleDecide)
	mux.HandleFunc("/admit", m.handleAdmit)
	return mux
}

func writeJSON(w http.ResponseWriter, code int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(body)
}

func (m *Manager) handleStatus(w http.ResponseWriter, r *http.Request) {
	body := map[string]any{
		"profile":           m.CurrentProfile(),
		"loaded_companions": m.LoadedCompanions(),
		"in_flight":         m.Leases.InFlight(),
		"draining":          m.Leases.Draining(),
		// The epoch a caller must quote back to `/admit`. It is here as well as in `/decide` so an
		// operator can see which plan the manager would accept without asking for a new one.
		"eviction_id": m.EvictionID(),
	}
	if last, ok := m.Journal.LastSwitch(); ok {
		body["last_switch"] = last
		if ts, ok := last["ts"].(float64); ok {
			body["last_switch_seconds_ago"] = int(time.Since(time.Unix(0, int64(ts*1e9))).Seconds())
		}
	} else {
		body["last_switch"] = nil
		body["last_switch_seconds_ago"] = nil
	}
	writeJSON(w, http.StatusOK, body)
}

func (m *Manager) handleStats(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, m.Journal.Stats())
}

func (m *Manager) handleEvents(w http.ResponseWriter, r *http.Request) {
	limit := 100
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			limit = n
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"events": m.Journal.Events(limit)})
}

func (m *Manager) handleSelect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "POST only"})
		return
	}
	var body struct {
		Profile        string `json:"profile"`
		DryRun         bool   `json:"dry_run"`
		KeepCompanions bool   `json:"keep_companions"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "body must be JSON"})
		return
	}
	if !m.Cfg.Accepts(m.Cfg.Normalise(body.Profile)) {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": fmt.Sprintf("unknown profile %q", body.Profile)})
		return
	}
	// A switch that has started must finish. The client may time out, lose its connection or be a
	// `curl` that was interrupted; none of that is a reason to leave the engine half-loaded and the
	// recorded profile out of step with what is actually resident. Detach the work from the request
	// context and let the response fail if nobody is listening.
	writeJSON(w, http.StatusOK, m.SelectKeeping(context.WithoutCancel(r.Context()), body.Profile, body.DryRun, body.KeepCompanions))
}

// decision is the `/decide` body: the tree's answer plus the epoch it was decided against. The
// epoch is the manager's, not the policy's, so the policy package stays a pure decision engine.
type decision struct {
	policy.Result
	EvictionID string `json:"eviction_id"`
}

// handleDecide runs the placement tree and returns the verdict with its trace. It is advisory: it
// reads the state, it changes nothing, and it is deliberately not run under the switch lock.
func (m *Manager) handleDecide(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "POST only"})
		return
	}
	if m.Policy == nil {
		writeJSON(w, http.StatusNotImplemented, map[string]any{
			"error": "this deployment has no placement policy",
		})
		return
	}
	var req policy.Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "body must be JSON"})
		return
	}
	if req.Model == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "request.model is required"})
		return
	}
	// `qfn` is an alias the manager owns: resolve it before the policy sees it. `auto` means "the
	// profile that is current", which is the profile-neutral engine in the policy's own table.
	req.Model = m.Cfg.Normalise(req.Model)
	switch req.Model {
	case "auto":
		req.Model = m.profileNeutralEngine()
	case "none":
		writeJSON(w, http.StatusConflict, map[string]any{
			"error":       "the engine is stopped; select a profile first",
			"eviction_id": m.EvictionID(),
		})
		return
	}
	res := m.Policy.Decide(req, m.activeForPolicy(r.Context()), m.policyState())
	writeJSON(w, http.StatusOK, decision{Result: res, EvictionID: m.EvictionID()})
}

// admitRequest is `/decide`'s request plus the act: the set the caller wants evicted, and the epoch
// it decided against.
type admitRequest struct {
	policy.Request
	// Evict is the set to unload, which may differ from the plan's suggestion: the caller may have
	// decided to keep a model the policy would have taken. Absent means "apply the plan".
	Evict []string `json:"evict"`
	// ExpectedEvictionID is the compare-and-swap token. Empty means the caller did not take part in
	// the epoch protocol (the `admit` wrapper in every llama-swap entry), and the plan is applied
	// unconditionally, as before this field existed.
	ExpectedEvictionID string `json:"expected_eviction_id"`
}

// handleAdmit is `/decide` plus the act: it re-decides under the switch lock, applies the plan and
// answers 200 so the caller may start its server. A refusal is returned verbatim, body and all, so
// the wrapper can print it and llama-swap logs the reason instead of a bare exit code.
//
// The eviction epoch makes the two-step decide/admit safe. A caller quotes the id it decided
// against; if another plan was applied in between, the id has rotated and the answer is 409 with
// the fresh suggestion, so two callers can never evict the same victim twice.
func (m *Manager) handleAdmit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "POST only"})
		return
	}
	if m.Policy == nil {
		writeJSON(w, http.StatusNotImplemented, map[string]any{"error": "this deployment has no placement policy"})
		return
	}
	var body admitRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "body must be JSON"})
		return
	}
	req := body.Request
	if req.Model == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "request.model is required"})
		return
	}
	req.Model = m.Cfg.Normalise(req.Model)
	if req.Model == "auto" {
		req.Model = m.profileNeutralEngine()
	}
	if req.Model == "" || req.Model == "none" {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "no profile is selected"})
		return
	}

	// The decision is taken under the same lock the switch takes: two admissions that both read
	// "10 GiB free" and both say yes is exactly the race this endpoint exists to stop.
	m.mu.Lock()
	defer m.mu.Unlock()

	// llama-swap lists an entry as running the moment it spawns it, which is *before* this call:
	// counting the model we are about to start as already resident makes every admission a no-op.
	active := m.activeForPolicy(r.Context())
	filtered := active[:0]
	for _, a := range active {
		if a.Model != req.Model {
			filtered = append(filtered, a)
		}
	}
	res := m.Policy.Decide(req, filtered, m.policyStateFor(filtered))
	if res.Verdict != policyVerdictAdmit {
		code := http.StatusConflict
		if res.Refusal != nil && res.Refusal.Code != 0 {
			code = res.Refusal.Code
		}
		writeJSON(w, code, decision{Result: res, EvictionID: m.EvictionID()})
		return
	}

	// The plan was decided against an epoch. If the epoch moved, the suggestion is stale and the
	// caller must decide again rather than act on a world that no longer exists.
	current := m.EvictionID()
	if body.ExpectedEvictionID != "" && body.ExpectedEvictionID != current {
		writeJSON(w, http.StatusConflict, map[string]any{
			"verdict":              res.Verdict,
			"error":                "the eviction plan is stale: another plan was applied since this decision",
			"plan":                 res.Plan,
			"why":                  res.Why,
			"resulting":            res.Resulting,
			"eviction_id":          current,
			"expected_eviction_id": body.ExpectedEvictionID,
		})
		return
	}
	cas := "matched"
	if body.ExpectedEvictionID == "" {
		cas = "skipped"
	}

	// The caller's set wins over the suggestion, so a caller that decided to keep a model is not
	// overruled by a decision it already saw.
	applied := res.Plan.Evict
	if body.Evict != nil {
		applied = body.Evict
	}
	switching := res.Plan.Profile != "" && res.Plan.Profile != m.CurrentProfile()
	// A switch stops the engine and unloads the companions by itself; the set only names what the
	// caller expects to leave. Without a switch the set is the act, and the engine is not a victim:
	// only a profile switch may stop it, so a caller that names it is refused rather than allowed to
	// drop the frontier for a companion.
	if !switching {
		for _, name := range applied {
			if model, ok := m.Policy.Models[name]; ok && model.Kind == "engine" {
				writeJSON(w, http.StatusConflict, map[string]any{
					"error":       fmt.Sprintf("%q is an engine; it leaves only through a profile switch", name),
					"eviction_id": current,
					"plan":        res.Plan,
				})
				return
			}
		}
	}

	if switching {
		reply := m.selectLocked(r.Context(), res.Plan.Profile, false, false)
		if e, ok := reply["error"]; ok {
			writeJSON(w, http.StatusBadGateway, map[string]any{"error": e, "plan": res.Plan, "why": res.Why})
			return
		}
	} else if len(applied) > 0 {
		if m.Accessories == nil {
			// A deployment without llama-swap owns no companion to unload one at a time; the
			// backend's own unload is the only path, and it takes everything.
			if _, err := m.Backend.UnloadCompanions(r.Context()); err != nil {
				writeJSON(w, http.StatusBadGateway, map[string]any{"error": err.Error()})
				return
			}
		} else {
			for _, name := range applied {
				if err := m.Accessories.Unload(r.Context(), name); err != nil {
					writeJSON(w, http.StatusBadGateway, map[string]any{"error": err.Error(), "evicted": name})
					return
				}
			}
		}
	}
	next := m.rotateEvictionID()
	_ = m.Journal.Append(map[string]any{"event": "admit", "model": req.Model,
		"profile": m.CurrentProfile(), "plan": res.Plan, "vram_mib": res.Resulting.VRAMMiB,
		"evicted": applied, "eviction_id": next, "previous_eviction_id": current,
		"expected_eviction_id": body.ExpectedEvictionID, "cas": cas})
	writeJSON(w, http.StatusOK, map[string]any{
		"verdict":     "admit",
		"model":       req.Model,
		"profile":     m.CurrentProfile(),
		"port":        m.Backend.CurrentPort(),
		"plan":        res.Plan,
		"why":         res.Why,
		"evicted":     applied,
		"eviction_id": next,
	})
}

// policyVerdictAdmit is the tree's word for "start it".
const policyVerdictAdmit = "admit"

// activeForPolicy is the resident set as the policy sees it: the engine that serves the current
// profile plus every model llama-swap reports running.
func (m *Manager) activeForPolicy(ctx context.Context) []policy.Active {
	profile := m.CurrentProfile()
	var out []policy.Active
	// One engine is resident, never two: prefer the entry that names this profile exactly, and fall
	// back to the profile-neutral one (`qfn`) only when nothing does.
	engine := ""
	for name, model := range m.Policy.Models {
		if model.Kind == "engine" && model.Profile == profile {
			engine = name
			break
		}
	}
	if engine == "" {
		engine = m.profileNeutralEngine()
	}
	if engine != "" {
		model := m.Policy.Models[engine]
		out = append(out, policy.Active{
			Model: engine, Kind: model.Kind, Tier: model.Tier, Profile: profile,
			VRAMMiB: model.VRAMMiB, KVReserveMiB: model.KVReserveMiB, RAMMiB: model.RAMMiB,
		})
	}
	for _, name := range m.safeLoaded(ctx) {
		model, ok := m.Policy.Models[name]
		if !ok || model.Kind == "engine" {
			continue
		}
		out = append(out, policy.Active{
			Model: name, Kind: model.Kind, Tier: model.Tier, Profile: model.Profile,
			VRAMMiB: model.VRAMMiB, KVReserveMiB: model.KVReserveMiB, RAMMiB: model.RAMMiB,
		})
	}
	return out
}

// profileNeutralEngine is the model the policy uses for "whatever text profile is current".
func (m *Manager) profileNeutralEngine() string {
	profile := m.CurrentProfile()
	for name, model := range m.Policy.Models {
		if model.Kind != "engine" || model.Profile != "" {
			continue
		}
		if containsString(model.RequiresProfile, profile) {
			return name
		}
	}
	return ""
}

func (m *Manager) policyState() policy.State {
	return m.policyStateFor(m.activeForPolicy(context.Background()))
}

// policyStateFor is the state for a caller that has already decided which models are resident.
// `/admit` removes the model it is admitting from the active set — llama-swap lists an entry as
// running before the call — and the free VRAM has to be computed from that same set, or the model
// is counted twice and a companion that fits is refused as too large.
func (m *Manager) policyStateFor(active []policy.Active) policy.State {
	st := policy.State{
		Profile:  m.CurrentProfile(),
		Draining: m.Leases.Draining(),
	}
	used := 0
	for _, a := range active {
		used += a.VRAMMiB
	}
	st.VRAMFreeMiB = m.Policy.Budget.VRAMMiB - used
	if st.Profile == "" || st.Profile == "none" {
		// An unknown engine state means an unknown card: refuse rather than admit against a number
		// nobody measured. Measured 2026-11-21: a 35B slipped in while the profile was briefly
		// empty after a restart, and the card ended at 30.7 GiB with two large models on it.
		st.VRAMFreeMiB = 0
	}
	if st.VRAMFreeMiB < 0 {
		st.VRAMFreeMiB = 0
	}
	// RAM is a real constraint here: the host has no swap and a Strata load takes a ~95 GiB burst.
	// `MemAvailable` is the number the kernel would hand out, which is what an admission needs.
	st.RAMFreeMiB = memAvailableMiB()
	if last, ok := m.Journal.LastSwitch(); ok {
		if ts, ok := last["ts"].(float64); ok {
			t := time.Unix(0, int64(ts*1e9))
			st.LastSwitchAt = &t
		}
	}
	return st
}

// memAvailableMiB reads /proc/meminfo. A missing file leaves the value at zero, and a zero RAM
// budget makes the policy refuse rather than admit blind — the failure is in the safe direction.
func memAvailableMiB() int {
	body, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0
	}
	for _, line := range strings.Split(string(body), "\n") {
		if !strings.HasPrefix(line, "MemAvailable:") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			return 0
		}
		kib, err := strconv.Atoi(fields[1])
		if err != nil {
			return 0
		}
		return kib / 1024
	}
	return 0
}

func containsString(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
}

func (m *Manager) handleLease(w http.ResponseWriter, r *http.Request) {
	if id, ok := m.Leases.Acquire(); ok {
		writeJSON(w, http.StatusOK, map[string]any{"lease": id})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"wait": true, "reason": "the engine is switching profiles"})
}

func (m *Manager) handleRelease(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Lease int64 `json:"lease"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "lease must be an integer"})
		return
	}
	m.Leases.Release(body.Lease)
	writeJSON(w, http.StatusOK, map[string]any{"released": body.Lease})
}

func (m *Manager) handleUnload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "POST only"})
		return
	}
	var body struct {
		Model string `json:"model"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.Model == "" {
		unloaded, err := m.Backend.UnloadCompanions(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"ok": false, "error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "unloaded": unloaded, "still_loaded": m.safeLoaded(r.Context())})
		return
	}
	if m.Cfg.IsFrontier(body.Model) {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false,
			"error": fmt.Sprintf("%q proxies to the engine; nothing to free", body.Model)})
		return
	}
	if err := m.Accessories.Unload(r.Context(), body.Model); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "unloaded": body.Model, "still_loaded": m.safeLoaded(r.Context())})
}

func (m *Manager) safeLoaded(ctx context.Context) []string {
	loaded, err := m.Backend.LoadedModels(ctx)
	if err != nil {
		return nil
	}
	return loaded
}

func round(d time.Duration) int { return int(d.Round(time.Second).Seconds()) }
