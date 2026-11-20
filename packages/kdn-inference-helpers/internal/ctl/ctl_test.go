package ctl

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

func TestSelectPostsTheProfileAndDryRun(t *testing.T) {
	var gotPath, gotMethod string
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotMethod = r.URL.Path, r.Method
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_ = json.NewEncoder(w).Encode(map[string]any{"changed": true, "profile": "max"})
	}))
	defer srv.Close()

	body, err := New(srv.URL).Select(context.Background(), "qfn-max", true)
	if err != nil {
		t.Fatal(err)
	}
	if gotMethod != http.MethodPost || gotPath != "/select" {
		t.Fatalf("%s %s", gotMethod, gotPath)
	}
	if gotBody["profile"] != "qfn-max" || gotBody["dry_run"] != true {
		t.Fatalf("body = %#v", gotBody)
	}
	if body["changed"] != true || body["profile"] != "max" {
		t.Fatalf("reply = %#v", body)
	}
}

func TestUnloadPostsTheModel(t *testing.T) {
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/unload" {
			t.Errorf("path = %s", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_ = json.NewEncoder(w).Encode(map[string]any{"ok": true})
	}))
	defer srv.Close()

	if _, err := New(srv.URL).Unload(context.Background(), "qwen3-omni"); err != nil {
		t.Fatal(err)
	}
	if gotBody["model"] != "qwen3-omni" {
		t.Fatalf("body = %#v", gotBody)
	}
}

func TestStatusDecodesTheJSON(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/status" {
			t.Errorf("path = %s", r.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"profile": "omni-fast", "in_flight": 2})
	}))
	defer srv.Close()

	body, err := New(srv.URL).Status(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if body["profile"] != "omni-fast" || body["in_flight"].(float64) != 2 {
		t.Fatalf("body = %#v", body)
	}
}

func TestNonTwoHundredIsAnErrorWithTheBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"unknown profile"}`))
	}))
	defer srv.Close()

	_, err := New(srv.URL).Select(context.Background(), "bogus", false)
	if err == nil || !strings.Contains(err.Error(), "unknown profile") {
		t.Fatalf("err = %v", err)
	}
}

func TestRevertCommandArgvIsExact(t *testing.T) {
	got := revertCommand("http://127.0.0.1:8181", "2h")
	want := []string{"sudo", "-n", "systemd-run", "--unit=strata-revert", "--on-active=2h", "--collect",
		"--", "curl", "-sS", "-m", "900", "-X", "POST", "http://127.0.0.1:8181/select",
		"-H", "Content-Type: application/json", "-d", `{"profile":"qfn"}`}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("argv = %v\nwant   %v", got, want)
	}
}

func TestUpWithoutTTLNeverSchedulesARevert(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"changed": false, "profile": "qfn"})
	}))
	defer srv.Close()

	var mu sync.Mutex
	called := false
	original := execRevert
	execRevert = func(context.Context, []string) error {
		mu.Lock()
		called = true
		mu.Unlock()
		return nil
	}
	defer func() { execRevert = original }()

	var out bytes.Buffer
	if err := Run(context.Background(), srv.URL, []string{"up"}, &out); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	defer mu.Unlock()
	if called {
		t.Fatal("`up` without --ttl scheduled a revert")
	}
	if !strings.Contains(out.String(), "profile") {
		t.Fatalf("reply was not printed: %q", out.String())
	}
}

func TestUpWithTTLSchedulesTheRevert(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"changed": true, "profile": "max"})
	}))
	defer srv.Close()

	var gotArgv []string
	original := execRevert
	execRevert = func(_ context.Context, argv []string) error {
		gotArgv = argv
		return nil
	}
	defer func() { execRevert = original }()

	var out bytes.Buffer
	if err := Run(context.Background(), srv.URL, []string{"up", "--profile", "qfn-max", "--ttl", "30m"}, &out); err != nil {
		t.Fatal(err)
	}
	if len(gotArgv) == 0 || gotArgv[4] != "--on-active=30m" {
		t.Fatalf("argv = %v", gotArgv)
	}
	if !strings.Contains(out.String(), "scheduled") {
		t.Fatalf("output = %q", out.String())
	}
}

func TestUnknownSubcommandMentionsUsage(t *testing.T) {
	var out bytes.Buffer
	err := Run(context.Background(), "http://127.0.0.1:1", []string{"bogus"}, &out)
	if err == nil || !strings.Contains(err.Error(), "usage") {
		t.Fatalf("err = %v", err)
	}
}
