package swap

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakeSwap answers the two endpoints the runtime uses, with a configurable model list.
func fakeSwap(t *testing.T, loaded map[string]bool) (*httptest.Server, *[]string) {
	t.Helper()
	var unloaded []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/v1/models":
			data := make([]map[string]any, 0, len(loaded))
			for id, isLoaded := range loaded {
				status := "unloaded"
				if isLoaded {
					status = "loaded"
				}
				data = append(data, map[string]any{"id": id, "status": map[string]any{"value": status}})
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"data": data})
		case strings.HasPrefix(r.URL.Path, "/api/models/unload"):
			name := strings.TrimPrefix(r.URL.Path, "/api/models/unload")
			name = strings.TrimPrefix(name, "/")
			unloaded = append(unloaded, name)
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("OK"))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv, &unloaded
}

func TestLoadedReturnsOnlyTheLoadedIDs(t *testing.T) {
	srv, _ := fakeSwap(t, map[string]bool{"qfn": true, "qwen3-omni": true, "grunt": false})
	loaded, err := New(srv.URL).Loaded(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded) != 2 {
		t.Fatalf("loaded = %v, want two", loaded)
	}
	seen := map[string]bool{}
	for _, id := range loaded {
		seen[id] = true
	}
	if !seen["qfn"] || !seen["qwen3-omni"] {
		t.Fatalf("loaded = %v", loaded)
	}
}

func TestUnloadOneModelUsesThePerModelPath(t *testing.T) {
	srv, unloaded := fakeSwap(t, nil)
	if err := New(srv.URL).Unload(context.Background(), "qwen3-omni"); err != nil {
		t.Fatal(err)
	}
	if len(*unloaded) != 1 || (*unloaded)[0] != "qwen3-omni" {
		t.Fatalf("unloaded = %v", *unloaded)
	}
}

func TestUnloadEscapesTheModelName(t *testing.T) {
	srv, unloaded := fakeSwap(t, nil)
	if err := New(srv.URL).Unload(context.Background(), "a b/c"); err != nil {
		t.Fatal(err)
	}
	if got := (*unloaded)[0]; got != "a b/c" {
		t.Fatalf("path escaped badly: %q", got)
	}
}

func TestUnloadWithNoModelHitsTheAllEndpoint(t *testing.T) {
	srv, unloaded := fakeSwap(t, nil)
	if err := New(srv.URL).Unload(context.Background(), ""); err != nil {
		t.Fatal(err)
	}
	if len(*unloaded) != 1 || (*unloaded)[0] != "" {
		t.Fatalf("unloaded = %v (an empty name must mean the all endpoint)", *unloaded)
	}
}

func TestANonTwoHundredIsAnErrorWithTheBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("boom"))
	}))
	defer srv.Close()

	if err := New(srv.URL).Unload(context.Background(), "qwen3-omni"); err == nil || !strings.Contains(err.Error(), "boom") {
		t.Fatalf("err = %v", err)
	}
	if _, err := New(srv.URL).Loaded(context.Background()); err == nil {
		t.Fatal("Loaded accepted a 500")
	}
}

func TestAnUnreachableSwapIsAnErrorNotAPanic(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	dead := srv.URL
	srv.Close()
	if _, err := New(dead).Loaded(context.Background()); err == nil {
		t.Fatal("Loaded succeeded against a dead server")
	}
	if err := New(dead).Unload(context.Background(), "x"); err == nil {
		t.Fatal("Unload succeeded against a dead server")
	}
}
