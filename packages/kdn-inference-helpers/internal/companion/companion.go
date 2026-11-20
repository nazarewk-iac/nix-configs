// Package companion is the gate in front of a model that may only load while the engine has a VRAM
// reserve for it (the colocated companion on brys).
//
// The colocated model only makes sense beside an engine that reserved VRAM for it. Without the
// reserve it loads anyway and runs at a fraction of its speed, silently. This gate turns that
// silent degradation into a readable refusal, and lets a caller ask for the switch in the same
// request:
//
//	POST /v1/chat/completions  {"model":"qwen3-omni","kdn_switch_to":"qfn-max-colo", …}
//
// The gate must sit in the data path, not at start time: only a process that reads the request body
// can see `kdn_switch_to`. So llama-swap starts this binary, and this binary starts the model.
package companion

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"

	"kdn-inference-helpers/internal/config"
)

// DefaultConfirmField is the request-body field that names the profile to switch to. A body field and
// not a header, because neither harness lets an agent add a header mid-session and both pass the body
// through untouched. A deployment may rename it in its gate spec.
const DefaultConfirmField = "kdn_switch_to"

// Gate answers the requests llama-swap sends to a gated model's port.
type Gate struct {
	Cfg *config.Config
	// Name is the model this gate guards; it selects the spec from the deployment config.
	Name    string
	Spec    config.GateSpec
	Manager string
	// Upstream returns the base URL of the model server, starting it when needed. Production passes
	// a supervisor; a test passes a fake URL.
	Upstream func(ctx context.Context) (string, error)

	mu    sync.Mutex
	proxy *httputil.ReverseProxy
}

// confirmField is the spec's field name, or the default.
func (g *Gate) confirmField() string {
	if g.Spec.ConfirmField != "" {
		return g.Spec.ConfirmField
	}
	return DefaultConfirmField
}

// satisfied reports whether the current profile already allows the model.
func (g *Gate) satisfied(profile string) bool {
	for _, p := range g.Spec.RequireProfiles {
		if p == profile {
			return true
		}
	}
	return false
}

// allowedTarget reports whether a caller may name this profile in the confirmation field. A target
// must be both allowed by the deployment spec and a profile the manager actually serves; the second
// check is what catches a name that survived a config change but no longer exists.
func (g *Gate) allowedTarget(ctx context.Context, name string) (string, bool) {
	profile := g.Cfg.Normalise(name)
	allowed := false
	for _, p := range g.Spec.Allow {
		if p == profile {
			allowed = true
			break
		}
	}
	if !allowed {
		return "", false
	}
	known := g.managerProfiles(ctx)
	if len(known) == 0 {
		return profile, true
	}
	for _, p := range known {
		if p == profile {
			return profile, true
		}
	}
	return "", false
}

// managerProfiles asks the manager which profiles its adapter serves.
func (g *Gate) managerProfiles(ctx context.Context) []string {
	var status struct {
		Profiles []string `json:"profiles"`
	}
	reqCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, g.Manager+"/status", nil)
	if err != nil {
		return nil
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	_ = json.NewDecoder(resp.Body).Decode(&status)
	return status.Profiles
}

func (g *Gate) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// llama-swap health-checks this port and kills the entry when the check fails. The gate is
	// alive even when it is refusing requests, and a killed gate cannot deliver the advice below.
	if r.Method == http.MethodGet && (r.URL.Path == "/health" || r.URL.Path == "/v1/health") {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"gate"}`))
		return
	}

	profile := g.currentProfile(r.Context())
	// The caller learns what actually answered: the name it asked for and the profile the manager
	// resolved it to. Same contract as the per-entry proxy.
	w.Header().Set("X-KDN-Alias", g.Name)
	if profile != "" {
		w.Header().Set("X-KDN-Profile", profile)
	}
	if g.satisfied(profile) {
		g.forward(w, r)
		return
	}

	// No reserve: the only request that may proceed is one that names a colo profile to switch to.
	body, err := io.ReadAll(r.Body)
	if err != nil {
		g.refuse(w, http.StatusBadRequest, map[string]any{"error": "the request body could not be read"})
		return
	}
	var payload map[string]any
	_ = json.Unmarshal(body, &payload)
	target := ""
	if raw, ok := payload[g.confirmField()].(string); ok {
		target = raw
	}
	if target == "" {
		g.refuse(w, http.StatusConflict, map[string]any{
			"error": fmt.Sprintf("this model needs the VRAM reserve; the engine is on the %q profile, "+
				"which gives the whole card to the frontier", profile),
			"current_profile": profile,
			"requires":        g.Spec.RequireProfiles,
			"confirm": map[string]any{
				"field": g.confirmField(),
				"value": "a profile name from alternatives",
			},
			"alternatives":   g.Spec.Allow,
			"reload_seconds": 70,
			"note":           "repeat the request with the field above, or select a colo profile first; the engine reloads once",
		})
		return
	}
	profile, ok := g.allowedTarget(r.Context(), target)
	if !ok {
		g.refuse(w, http.StatusBadRequest, map[string]any{
			"error":        fmt.Sprintf("%q is not a profile this deployment allows for %s", target, g.Name),
			"alternatives": g.Spec.Allow,
		})
		return
	}
	if err := g.selectProfile(r.Context(), profile); err != nil {
		g.refuse(w, http.StatusBadGateway, map[string]any{
			"error": "the switch to " + profile + " failed: " + err.Error(),
		})
		return
	}
	log.Printf("companion: switched to %s on request", profile)
	// The header said what was current when the request arrived; after the switch it is a lie. This
	// response is served by the new profile, and the client records what answered.
	w.Header().Set("X-KDN-Profile", profile)
	// The body was consumed; the switch must not lose it.
	r.Body = io.NopCloser(bytes.NewReader(body))
	r.ContentLength = int64(len(body))
	g.forward(w, r)
}

func (g *Gate) refuse(w http.ResponseWriter, code int, payload map[string]any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(payload)
}

func (g *Gate) currentProfile(ctx context.Context) string {
	var status struct {
		Profile string `json:"profile"`
	}
	reqCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, g.Manager+"/status", nil)
	if err != nil {
		return ""
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	_ = json.NewDecoder(resp.Body).Decode(&status)
	return status.Profile
}

func (g *Gate) selectProfile(ctx context.Context, profile string) error {
	// `keep_companions` is what stops the switch from unloading this very process: the manager
	// treats every non-frontier model as evictable, and the gate is one.
	body, _ := json.Marshal(map[string]any{"profile": profile, "keep_companions": true})
	// The switch outlives the client's connection: a client that gives up must not cancel a reload
	// that is already stopping the engine.
	req, err := http.NewRequestWithContext(context.WithoutCancel(ctx), http.MethodPost, g.Manager+"/select", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 20 * time.Minute}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var reply map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&reply)
	if e, ok := reply["error"]; ok {
		return fmt.Errorf("%v", e)
	}
	return nil
}

func (g *Gate) forward(w http.ResponseWriter, r *http.Request) {
	g.mu.Lock()
	proxy := g.proxy
	g.mu.Unlock()
	if proxy == nil {
		upstream, err := g.Upstream(r.Context())
		if err != nil {
			g.refuse(w, http.StatusBadGateway, map[string]any{"error": "the model did not start: " + err.Error()})
			return
		}
		target, err := url.Parse(upstream)
		if err != nil {
			g.refuse(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
			return
		}
		built := &httputil.ReverseProxy{
			Rewrite:       func(pr *httputil.ProxyRequest) { pr.SetURL(target) },
			FlushInterval: -1,
			Transport:     &http.Transport{DisableCompression: true, ForceAttemptHTTP2: false},
		}
		g.mu.Lock()
		g.proxy = built
		proxy = built
		g.mu.Unlock()
	}
	proxy.ServeHTTP(w, r)
}

// ---------------- the child ----------------

// Supervisor starts and owns the model server. llama-swap starts this gate, and the gate starts the
// server, because a process name decides nothing: the port the request arrives on does.
type Supervisor struct {
	Argv    []string
	LogPath string
	// Port is the public port the gate listens on; the child gets Port+Offset so the two never
	// collide (llama-swap substitutes one ${PORT} into the whole command).
	Port   int
	Offset int

	mu      sync.Mutex
	cmd     *exec.Cmd
	baseURL string
}

// PublicPort reads the `--port` value llama-swap substituted into the child argv.
func PublicPort(argv []string) (int, error) {
	for i := 0; i+1 < len(argv); i++ {
		if argv[i] == "--port" {
			var port int
			if _, err := fmt.Sscanf(argv[i+1], "%d", &port); err != nil {
				return 0, fmt.Errorf("--port %q is not a number", argv[i+1])
			}
			return port, nil
		}
	}
	return 0, fmt.Errorf("the entry command carries no --port, so llama-swap gave it no port")
}

// Upstream starts the child once and returns its base URL.
func (s *Supervisor) Upstream(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.baseURL != "" {
		return s.baseURL, nil
	}
	if s.Port == 0 {
		port, err := PublicPort(s.Argv)
		if err != nil {
			return "", err
		}
		s.Port = port
	}
	offset := s.Offset
	if offset == 0 {
		offset = 1000
	}
	childPort := s.Port + offset
	argv := make([]string, len(s.Argv))
	copy(argv, s.Argv)
	for i := 0; i+1 < len(argv); i++ {
		if argv[i] == "--port" {
			argv[i+1] = fmt.Sprint(childPort)
		}
	}
	logf, err := os.OpenFile(s.LogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return "", fmt.Errorf("cannot open the model log %s: %w", s.LogPath, err)
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Stdout = logf
	cmd.Stderr = logf
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		logf.Close()
		return "", fmt.Errorf("cannot start the model: %w", err)
	}
	s.cmd = cmd
	base := fmt.Sprintf("http://127.0.0.1:%d", childPort)

	deadline := time.Now().Add(10 * time.Minute)
	for time.Now().Before(deadline) {
		if cmd.ProcessState != nil && cmd.ProcessState.Exited() {
			return "", fmt.Errorf("the model exited during startup")
		}
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+"/health", nil)
		if resp, err := (&http.Client{Timeout: 2 * time.Second}).Do(req); err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				s.baseURL = base
				return base, nil
			}
		}
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
	return "", fmt.Errorf("the model did not answer within 10 minutes")
}

// Stop kills the child's process group.
func (s *Supervisor) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cmd != nil && s.cmd.Process != nil {
		_ = syscall.Kill(-s.cmd.Process.Pid, syscall.SIGTERM)
		s.cmd = nil
	}
	s.baseURL = ""
}

// ResolveArgv splits `-- a b c` into the child argv.
func ResolveArgv(args []string) []string {
	for i, a := range args {
		if a == "--" {
			return args[i+1:]
		}
	}
	return nil
}
