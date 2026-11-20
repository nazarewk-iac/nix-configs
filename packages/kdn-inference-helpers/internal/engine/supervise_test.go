package engine

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// fakeAdapter stands in for a real engine: it hands the supervisor a shell script and records
// whether the fallback stop ran.
type fakeAdapter struct {
	bin      string
	stopRuns int
}

func (f *fakeAdapter) Name() string       { return "fake" }
func (f *fakeAdapter) Profiles() []string { return []string{"max"} }
func (f *fakeAdapter) ReadyPath() string  { return "/v1/models" }
func (f *fakeAdapter) Prepare(profile string) (Command, error) {
	return Command{Path: f.bin, Args: []string{"serve", "--profile", profile, "--host", "127.0.0.1"}}, nil
}
func (f *fakeAdapter) Stop(ctx context.Context) error {
	f.stopRuns++
	return nil
}

const fakeEngine = `#!/bin/sh
echo "loading the model" >&2
trap 'exit 0' TERM
while :; do sleep 0.1; done
`

func newFake(t *testing.T) *fakeAdapter {
	t.Helper()
	dir := t.TempDir()
	bin := filepath.Join(dir, "engine")
	if err := os.WriteFile(bin, []byte(fakeEngine), 0o755); err != nil {
		t.Fatal(err)
	}
	return &fakeAdapter{bin: bin}
}

func TestStartWaitsForReadinessAndStopTerminatesTheChild(t *testing.T) {
	a := newFake(t)
	ready := make(chan struct{})
	s := &Supervisor{
		Adapter: a, EnginePort: 1,
		LogPath:      filepath.Join(t.TempDir(), "engine.log"),
		ReadyTimeout: 5 * time.Second,
		ReadyFn: func(context.Context) bool {
			select {
			case <-ready:
				return true
			default:
				return false
			}
		},
	}

	done := make(chan error, 1)
	go func() { _, err := s.Start(context.Background(), "max"); done <- err }()

	select {
	case err := <-done:
		t.Fatalf("Start returned before readiness: %v", err)
	case <-time.After(200 * time.Millisecond):
	}

	close(ready)
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Start: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("Start never returned after readiness")
	}

	stopped := make(chan error, 1)
	go func() { _, err := s.Stop(context.Background()); stopped <- err }()
	select {
	case err := <-stopped:
		if err != nil {
			t.Fatalf("Stop: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("Stop did not return; the child was not terminated")
	}
	if a.stopRuns != 1 {
		t.Fatalf("the adapter's fallback stop ran %d times, want 1", a.stopRuns)
	}
}

func TestPrepareErrorIsReportedBeforeAnyProcessStarts(t *testing.T) {
	s := &Supervisor{Adapter: &errAdapter{}, EnginePort: 1, LogPath: filepath.Join(t.TempDir(), "l")}
	if _, err := s.Start(context.Background(), "max"); err == nil {
		t.Fatal("a prepare error was swallowed")
	}
}

func TestEngineLogCapturesChildOutput(t *testing.T) {
	a := newFake(t)
	logPath := filepath.Join(t.TempDir(), "engine.log")
	s := &Supervisor{
		Adapter: a, EnginePort: 1, LogPath: logPath, ReadyTimeout: 5 * time.Second,
		ReadyFn: func(context.Context) bool { return true },
	}
	if _, err := s.Start(context.Background(), "max"); err != nil {
		t.Fatal(err)
	}
	defer s.Stop(context.Background())

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if body, _ := os.ReadFile(logPath); len(body) > 0 {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("the engine log stayed empty; the child's stderr was not captured")
}

type errAdapter struct{}

func (errAdapter) Name() string                    { return "err" }
func (errAdapter) Profiles() []string              { return nil }
func (errAdapter) ReadyPath() string               { return "/v1/models" }
func (errAdapter) Prepare(string) (Command, error) { return Command{}, context.Canceled }
func (errAdapter) Stop(context.Context) error      { return nil }
