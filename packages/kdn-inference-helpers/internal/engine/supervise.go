package engine

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"syscall"
	"time"
)

// Supervisor owns the one engine child. It asks the adapter to prepare a profile, starts the
// resulting command, waits until the engine answers, and stops it with a process-group signal so a
// crash leaves nothing behind.
//
// It knows nothing about which engine is behind the adapter: the readiness path comes from the
// adapter, the command comes from the adapter, and the fallback stop does too.
type Supervisor struct {
	// Adapter is the engine under supervision.
	Adapter Adapter
	// EnginePort is where the engine listens.
	EnginePort int
	// Env is the child's environment: HOME, XDG_DATA_HOME, STRATA_DATA_HOME and the ROCm shim.
	Env []string
	// LogPath receives the child's stdout and stderr.
	LogPath string
	// ReadyTimeout bounds the readiness wait; a cold 55 GiB load is slow.
	ReadyTimeout time.Duration
	// ReadyFn overrides the readiness probe in tests.
	ReadyFn func(ctx context.Context) bool

	cmd  *exec.Cmd
	logf *os.File
}

// Start prepares the profile, launches it, and returns once the engine answers or the context ends.
func (s *Supervisor) Start(ctx context.Context, profile string) (time.Duration, error) {
	start := time.Now()
	command, err := s.Adapter.Prepare(profile)
	if err != nil {
		return 0, err
	}
	args := append([]string(nil), command.Args...)
	args = append(args, "--port", fmt.Sprint(s.EnginePort))

	logf, err := os.OpenFile(s.LogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return 0, fmt.Errorf("cannot open the engine log %s: %w", s.LogPath, err)
	}
	s.logf = logf

	cmd := exec.Command(command.Path, args...)
	cmd.Env = s.Env
	cmd.Stdout = logf
	cmd.Stderr = logf
	// Own process group: terminate reaches the engine and anything it spawned.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		logf.Close()
		return 0, fmt.Errorf("cannot start the engine: %w", err)
	}
	s.cmd = cmd

	timeout := s.ReadyTimeout
	if timeout <= 0 {
		timeout = 15 * time.Minute
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if s.exited() {
			return time.Since(start), fmt.Errorf("the engine exited during startup")
		}
		if s.Ready(ctx) {
			return time.Since(start), nil
		}
		select {
		case <-ctx.Done():
			return time.Since(start), ctx.Err()
		case <-time.After(3 * time.Second):
		}
	}
	return time.Since(start), fmt.Errorf("the engine did not answer within %s", timeout)
}

// Stop terminates the child and then asks the adapter to clean up whatever it did not spawn. The
// second step matters: a previous manager instance, or a manual unit, can leave an engine behind.
func (s *Supervisor) Stop(ctx context.Context) (time.Duration, error) {
	start := time.Now()
	if s.cmd != nil && s.cmd.Process != nil {
		pgid := -s.cmd.Process.Pid
		_ = syscall.Kill(pgid, syscall.SIGTERM)
		done := make(chan error, 1)
		go func() { done <- s.cmd.Wait() }()
		select {
		case <-done:
		case <-time.After(180 * time.Second):
			_ = syscall.Kill(pgid, syscall.SIGKILL)
			<-done
		}
		s.cmd = nil
	}
	if s.logf != nil {
		s.logf.Close()
		s.logf = nil
	}
	stopCtx, cancel := context.WithTimeout(ctx, 300*time.Second)
	defer cancel()
	if err := s.Adapter.Stop(stopCtx); err != nil && stopCtx.Err() == nil {
		return time.Since(start), err
	}
	return time.Since(start), nil
}

// Ready reports whether the engine answers right now.
func (s *Supervisor) Ready(ctx context.Context) bool {
	if s.ReadyFn != nil {
		return s.ReadyFn(ctx)
	}
	reqCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	url := fmt.Sprintf("http://127.0.0.1:%d%s", s.EnginePort, s.Adapter.ReadyPath())
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, url, nil)
	if err != nil {
		return false
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode == http.StatusOK
}

func (s *Supervisor) exited() bool {
	if s.cmd == nil || s.cmd.ProcessState == nil {
		return false
	}
	return s.cmd.ProcessState.Exited()
}
