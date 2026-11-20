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
}

// Accessory is the llama-swap side: which models are loaded, and unloading one by name.
type Accessory interface {
	Loaded(ctx context.Context) ([]string, error)
	Unload(ctx context.Context, model string) error
}

// Manager is the control plane: the selected profile, the drain, the journal and the HTTP API.
type Manager struct {
	Cfg     *config.Config
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

func (m *Manager) loadState() map[string]any {
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

func (m *Manager) saveState(state map[string]any) error {
	if err := os.MkdirAll(filepath.Dir(m.statePath), 0o755); err != nil {
		return err
	}
	body, err := json.Marshal(state)
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

// ---------------- switching ----------------

// Select switches, or reports what a switch would cost. The returned map is the JSON body.
func (m *Manager) Select(ctx context.Context, requested string, dryRun bool) map[string]any {
	profile := m.Cfg.Normalise(requested)
	if !config.Accepted[profile] {
		return map[string]any{"error": fmt.Sprintf("unknown profile %q", requested)}
	}

	m.mu.Lock()
	defer m.mu.Unlock()

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
		return map[string]any{"changed": false, "profile": current, "note": "already selected"}
	case profile == "auto":
		return map[string]any{"changed": false, "profile": current, "note": "auto: kept the current profile"}
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

	unloaded, _ := m.Backend.UnloadCompanions(ctx)
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
	_ = m.Journal.Append(map[string]any{"event": journal.EventEngineLoad,
		"profile": profile, "seconds": round(loadDur), "ok": err == nil})
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
	return map[string]any{"changed": true, "profile": profile, "seconds": total}
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
			for id, was := range m.companions {
				if was && !seen[id] {
					delete(m.companions, id)
					_ = m.Journal.Append(map[string]any{"event": journal.EventCompanionDown,
						"model": id, "observed": true})
				}
			}
			m.observedMu.Unlock()
		}
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
		Profile string `json:"profile"`
		DryRun  bool   `json:"dry_run"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "body must be JSON"})
		return
	}
	if !config.Accepted[m.Cfg.Normalise(body.Profile)] {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": fmt.Sprintf("unknown profile %q", body.Profile)})
		return
	}
	writeJSON(w, http.StatusOK, m.Select(r.Context(), body.Profile, body.DryRun))
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
