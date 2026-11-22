package companion

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"kdn-inference-helpers/internal/config"
)

func newGate(t *testing.T, profile string, upstream string) (*Gate, *int32) {
	t.Helper()
	cfg := config.Defaults()
	// The alias is the deployment's: the gate must resolve the llama-swap name to a profile before
	// it checks the allow-list, so the fixture carries that one mapping.
	cfg.Aliases = map[string]string{"qfn-max-colo": "omni-max"}
	var selectCalls int32
	manager := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/status":
			_ = json.NewEncoder(w).Encode(map[string]any{"profile": profile})
		case "/select":
			atomic.AddInt32(&selectCalls, 1)
			var body struct {
				Profile string `json:"profile"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			profile = body.Profile
			_ = json.NewEncoder(w).Encode(map[string]any{"changed": true, "profile": body.Profile})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(manager.Close)

	gate := &Gate{
		Cfg: cfg, Name: "qwen3-omni", Manager: manager.URL,
		Spec: config.GateSpec{
			RequireProfiles: []string{"omni-max", "omni-fast"},
			Allow:           []string{"omni-max", "omni-fast"},
			ConfirmField:    DefaultConfirmField,
		},
		Upstream: func(context.Context) (string, error) { return upstream, nil },
	}
	return gate, &selectCalls
}

func TestNoReserveRefusesWithAReadableConfirmationRequest(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("the companion was reached without a reserve")
	}))
	defer upstream.Close()
	gate, selects := newGate(t, "max", upstream.URL)

	body := `{"model":"qwen3-omni","messages":[{"role":"user","content":"hi"}]}`
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(body))
	rec := httptest.NewRecorder()
	gate.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rec.Code)
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("409 body is not JSON: %v", err)
	}
	for _, key := range []string{"error", "current_profile", "requires", "confirm", "alternatives"} {
		if _, ok := payload[key]; !ok {
			t.Fatalf("409 is missing %q: %#v", key, payload)
		}
	}
	confirm, _ := payload["confirm"].(map[string]any)
	if confirm["field"] != DefaultConfirmField {
		t.Fatalf("confirm.field = %v", confirm["field"])
	}
	if atomic.LoadInt32(selects) != 0 {
		t.Fatal("a refused request still switched the profile")
	}
}

func TestSwitchToAColoProfileSwitchesAndForwards(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if !strings.Contains(string(body), "the screenshot") {
			t.Errorf("the forwarded body lost its content: %q", body)
		}
		_, _ = w.Write([]byte("described"))
	}))
	defer upstream.Close()
	gate, selects := newGate(t, "max", upstream.URL)

	body := `{"model":"qwen3-omni","kdn_switch_to":"qfn-max-colo","messages":[{"role":"user","content":"the screenshot"}]}`
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(body))
	rec := httptest.NewRecorder()
	gate.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK || strings.TrimSpace(rec.Body.String()) != "described" {
		t.Fatalf("status %d body %q", rec.Code, rec.Body.String())
	}
	if atomic.LoadInt32(selects) != 1 {
		t.Fatalf("select calls = %d, want 1", atomic.LoadInt32(selects))
	}
}

func TestSwitchToANonColoProfileIsRejected(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Fatal("reached the companion after an invalid switch target")
	}))
	defer upstream.Close()
	gate, selects := newGate(t, "max", upstream.URL)

	body := `{"model":"qwen3-omni","kdn_switch_to":"qfn-max"}`
	rec := httptest.NewRecorder()
	gate.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(body)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
	if atomic.LoadInt32(selects) != 0 {
		t.Fatal("an invalid target switched the profile")
	}
}

func TestWithAReserveTheGateForwardsWithoutSwitchingOrAsking(t *testing.T) {
	var hits int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&hits, 1)
		_, _ = w.Write([]byte("ok"))
	}))
	defer upstream.Close()
	gate, selects := newGate(t, "omni-fast", upstream.URL)

	body := `{"model":"qwen3-omni","messages":[]}`
	rec := httptest.NewRecorder()
	gate.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(body)))
	if rec.Code != http.StatusOK || atomic.LoadInt32(&hits) != 1 {
		t.Fatalf("status %d hits %d", rec.Code, hits)
	}
	if atomic.LoadInt32(selects) != 0 {
		t.Fatal("a colocated request switched the profile")
	}
}

func TestHealthAlwaysAnswersSoLlamaSwapKeepsTheEntry(t *testing.T) {
	gate, _ := newGate(t, "max", "http://127.0.0.1:1")
	rec := httptest.NewRecorder()
	gate.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("health = %d, want 200 even while refusing requests", rec.Code)
	}
}

func TestPublicPortReadsWhatLlamaSwapSubstituted(t *testing.T) {
	port, err := PublicPort([]string{"llama-server", "--port", "10013", "--host", "127.0.0.1"})
	if err != nil || port != 10013 {
		t.Fatalf("port = %d, err = %v", port, err)
	}
	if _, err := PublicPort([]string{"llama-server"}); err == nil {
		t.Fatal("an argv with no port was accepted")
	}
}

func TestResolveArgvSplitsAfterTheSeparator(t *testing.T) {
	argv := ResolveArgv([]string{"--port", "1", "--", "llama-server", "--port", "10013"})
	if len(argv) != 3 || argv[0] != "llama-server" {
		t.Fatalf("argv = %v", argv)
	}
}

// A request that switches must report the profile that served it, not the one that was current when
// the request arrived. Otherwise a client records the wrong variant for exactly the requests that
// changed it.
func TestTheGateReportsTheProfileThatServedAfterASwitch(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer upstream.Close()
	gate, selects := newGate(t, "max", upstream.URL)

	body := `{"model":"qwen3-omni","kdn_switch_to":"omni-fast","messages":[{"role":"user","content":"hi"}]}`
	rec := httptest.NewRecorder()
	gate.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(body)))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("X-KDN-Profile"); got != "omni-fast" {
		t.Fatalf("profile header = %q, want the profile that served", got)
	}
	if *selects != 1 {
		t.Fatalf("the switch ran %d times", *selects)
	}
}
