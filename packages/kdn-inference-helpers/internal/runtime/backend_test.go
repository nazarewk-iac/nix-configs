package runtime

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"kdn-inference-helpers/internal/config"
	"kdn-inference-helpers/internal/engine"
	"kdn-inference-helpers/internal/swap"
)

// fakeAdapter is the smallest engine that satisfies the adapter contract.
type fakeAdapter struct{}

func (fakeAdapter) Name() string            { return "fake" }
func (fakeAdapter) Profiles() []string      { return []string{"max"} }
func (fakeAdapter) ReadyPath(string) string { return "/v1/models" }
func (fakeAdapter) Prepare(string) (engine.Command, error) {
	// /bin/sh exists on NixOS; /bin/true does not.
	return engine.Command{Path: "/bin/sh", Args: []string{"-c", "sleep 30"}}, nil
}
func (fakeAdapter) Stop(context.Context) error { return nil }

// fakeSwap reports a configurable set of loaded models and records unloads.
func fakeSwap(t *testing.T, loaded []string) (*swap.Client, *[]string) {
	t.Helper()
	var unloaded []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/models/unload") {
			unloaded = append(unloaded, strings.TrimPrefix(strings.TrimPrefix(r.URL.Path, "/api/models/unload"), "/"))
			w.WriteHeader(http.StatusOK)
			return
		}
		data := make([]map[string]any, 0, len(loaded))
		for _, id := range loaded {
			data = append(data, map[string]any{"id": id, "status": map[string]any{"value": "loaded"}})
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"data": data})
	}))
	t.Cleanup(srv.Close)
	return swap.New(srv.URL), &unloaded
}

func newBackend(t *testing.T, loaded []string, cacheDrop []string) (*Backend, *[]string) {
	t.Helper()
	cfg := config.Defaults()
	cfg.DataDir = t.TempDir()
	cfg.CacheDropCommand = cacheDrop
	// The frontier set is the deployment's, not the binary's: this fixture names the two ids whose
	// proxies must survive an unload.
	cfg.FrontierIDs = []string{"qfn", "qfn-max"}
	client, unloaded := fakeSwap(t, loaded)
	return &Backend{
		Supervisor: &engine.Supervisor{
			Adapter: fakeAdapter{}, EnginePort: 1, LogPath: filepath.Join(cfg.DataDir, "engine.log"),
			ReadyFn: func(context.Context) bool { return true },
		},
		Swap: client, Cfg: cfg,
	}, unloaded
}

func TestUnloadCompanionsLeavesTheFrontierAlone(t *testing.T) {
	// Two frontier names and one companion: only the companion may be unloaded, because the frontier
	// proxies are the clients of the engine the switch is about to restart.
	backend, unloaded := newBackend(t, []string{"qfn", "qfn-max", "qwen3-omni"}, nil)
	got, err := backend.UnloadCompanions(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != "qwen3-omni" {
		t.Fatalf("returned %v", got)
	}
	if len(*unloaded) != 1 || (*unloaded)[0] != "qwen3-omni" {
		t.Fatalf("unloaded %v, want only the companion", *unloaded)
	}
}

func TestUnloadCompanionsWithNothingLoadedDoesNothing(t *testing.T) {
	backend, unloaded := newBackend(t, []string{"qfn-max"}, nil)
	got, err := backend.UnloadCompanions(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 || len(*unloaded) != 0 {
		t.Fatalf("unloaded %v / %v", got, *unloaded)
	}
}

func TestDropCachesSkipsWhenTheDeploymentHasNoHook(t *testing.T) {
	// An engine whose loads do not depend on the page cache sets an empty hook; the phase must be a
	// no-op rather than an error.
	backend, _ := newBackend(t, nil, []string{})
	dur, err := backend.DropCaches(context.Background())
	if err != nil || dur != 0 {
		t.Fatalf("drop = %v, %v", dur, err)
	}
}

func TestDropCachesRunsTheConfiguredCommandAndReportsFailure(t *testing.T) {
	backend, _ := newBackend(t, nil, []string{"/bin/sh", "-c", "exit 0"})
	if _, err := backend.DropCaches(context.Background()); err != nil {
		t.Fatalf("a successful hook failed: %v", err)
	}

	failing, _ := newBackend(t, nil, []string{"/bin/sh", "-c", "echo boom >&2; exit 1"})
	if _, err := failing.DropCaches(context.Background()); err == nil || !strings.Contains(err.Error(), "boom") {
		t.Fatalf("a failing hook returned %v", err)
	}
}

func TestDropCachesRespectsTheContext(t *testing.T) {
	backend, _ := newBackend(t, nil, []string{"/bin/sh", "-c", "sleep 30"})
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	start := time.Now()
	if _, err := backend.DropCaches(ctx); err == nil {
		t.Fatal("a cancelled hook reported success")
	}
	if time.Since(start) > 5*time.Second {
		t.Fatal("the cancelled hook ran to completion")
	}
}

func TestStartAndStopDelegateToTheSupervisor(t *testing.T) {
	backend, _ := newBackend(t, nil, nil)
	dir := backend.Cfg.DataDir
	if err := os.MkdirAll(filepath.Join(dir, "strata", "profiles"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "strata", "profiles", "strata-max.json"),
		[]byte(`{"args":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := backend.StartEngine(context.Background(), "max"); err != nil {
		t.Fatalf("start: %v", err)
	}
	if !backend.EngineReady() {
		t.Fatal("the supervisor reports a ready engine as not ready")
	}
	if _, err := backend.StopEngine(context.Background()); err != nil {
		t.Fatalf("stop: %v", err)
	}
}

func TestLoadedModelsIsTheSwapView(t *testing.T) {
	backend, _ := newBackend(t, []string{"qfn", "grunt"}, nil)
	loaded, err := backend.LoadedModels(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded) != 2 {
		t.Fatalf("loaded = %v", loaded)
	}
}
