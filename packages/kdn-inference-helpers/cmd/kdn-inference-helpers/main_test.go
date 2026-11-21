package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestParsePositionalThenFlagsAcceptsBothOrders(t *testing.T) {
	known := map[string]bool{"--port": true, "--manager": true}
	cases := []struct {
		args      []string
		profile   string
		port      string
		expectErr bool
	}{
		{[]string{"max", "--port", "10009"}, "max", "10009", false},
		{[]string{"--port", "10009", "max"}, "max", "10009", false},
		{[]string{"qfn-colo", "--port", "10010", "--manager", "http://x"}, "qfn-colo", "10010", false},
		{[]string{"max", "--bogus", "1"}, "", "", true},
		{[]string{"max", "--port"}, "", "", true},
		{[]string{"a", "b"}, "", "", true},
	}
	for _, c := range cases {
		profile, flags, err := parsePositionalThenFlags(c.args, known)
		if c.expectErr {
			if err == nil {
				t.Fatalf("%v: expected an error", c.args)
			}
			continue
		}
		if err != nil {
			t.Fatalf("%v: %v", c.args, err)
		}
		if profile != c.profile || flags["--port"] != c.port {
			t.Fatalf("%v -> profile=%q port=%q", c.args, profile, flags["--port"])
		}
	}
}

func TestExecReplacePassesTheProgramAsArgvZero(t *testing.T) {
	// syscall.Exec does not add argv[0]; the launcher parses argv[1] as its subcommand, so a missing
	// argv[0] shifts every argument by one and the profile path becomes the command.
	var gotPath string
	var gotArgv []string
	original := syscallExec
	syscallExec = func(path string, argv, env []string) error {
		gotPath, gotArgv = path, argv
		return nil
	}
	defer func() { syscallExec = original }()

	err := execReplace("/bin/strata", []string{"serve", "--profile", "/cfg.json", "--port", "8099"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if gotPath != "/bin/strata" || len(gotArgv) != 6 || gotArgv[0] != "/bin/strata" || gotArgv[1] != "serve" {
		t.Fatalf("argv = %v", gotArgv)
	}
}

// A listener that served an explicit profile must leave when the manager moves away from it:
// llama-swap's unload runs `cmdStop` and then waits for this process to exit, so a proxy that stays
// alive blocks the next model until the 15-minute kill timeout.
func TestTheProxyLeavesWhenTheProfileChanges(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"profile":"none","draining":false}`))
	}))
	defer srv.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stopped := make(chan struct{})
	done := make(chan struct{})
	go func() {
		watchProfile(ctx, func() { close(stopped) }, srv.URL, "image-qwen", func() int64 { return 0 }, func() bool { return false })
		close(done)
	}()
	select {
	case <-stopped:
	case <-time.After(10 * time.Second):
		t.Fatal("the proxy did not leave after the profile changed")
	}
	<-done
}

// A listener that still holds a request must not leave: the switch waits for it, the response
// finishes, and only then does the listener go.
func TestTheProxyWaitsForItsRequestBeforeLeaving(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"profile":"none"}`))
	}))
	defer srv.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var inFlight atomic.Int64
	inFlight.Store(1)
	stopped := make(chan struct{})
	go watchProfile(ctx, func() { close(stopped) }, srv.URL, "image-qwen", inFlight.Load, func() bool { return false })

	select {
	case <-stopped:
		t.Fatal("the listener left while it still held a request")
	case <-time.After(4 * time.Second):
	}
	inFlight.Store(0)
	select {
	case <-stopped:
	case <-time.After(6 * time.Second):
		t.Fatal("the listener never left after its request finished")
	}
}

// A deploy replaces the binary; the listener leaves once idle so the next request spawns the new
// build. Restarting llama-swap instead would cut every running request.
func TestTheProxyLeavesWhenItsBinaryIsStale(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"profile":"image-qwen"}`))
	}))
	defer srv.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stopped := make(chan struct{})
	go watchProfile(ctx, func() { close(stopped) }, srv.URL, "image-qwen", func() int64 { return 0 }, func() bool { return true })
	select {
	case <-stopped:
	case <-time.After(6 * time.Second):
		t.Fatal("a stale listener stayed")
	}
}

func TestTheProxyStaysWhileItsProfileIsCurrent(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"profile":"image-qwen","draining":false}`))
	}))
	defer srv.Close()

	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan struct{})
	go watchProfile(ctx, func() { close(stopped) }, srv.URL, "image-qwen", func() int64 { return 0 }, func() bool { return false })
	select {
	case <-stopped:
		t.Fatal("the proxy left while its profile was still current")
	case <-time.After(4 * time.Second):
	}
	cancel()
}
