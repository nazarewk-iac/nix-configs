package engine

import (
	"context"
	"fmt"
	"io"
	"net"
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
	// done receives the child's exit. Waiting in a goroutine is what makes a child that dies
	// during startup visible: `ProcessState` stays nil until `Wait` returns, so a supervisor that
	// only waits on Stop cannot tell a dead engine from a slow one and polls until the timeout.
	done chan error
	// finished is closed when the child is reaped, so "has it exited?" can be asked any number of
	// times without consuming the answer.
	finished chan struct{}
	// stdinW is the write end of the child's stdin, kept open on purpose. `sd-server` (and any
	// server that reads its control input from stdin) treats EOF as "shut down", and a nil
	// `cmd.Stdin` is /dev/null: an immediate EOF. The child loaded its model, printed its listen
	// address, and quit. Closing this file is the graceful stop.
	stdinW *os.File
	// profile is the one currently being started, kept so the readiness probe can ask the adapter
	// which path this kind of server answers on.
	profile string
	// port is the port the running child listens on.
	port int
}

// Start prepares the profile, launches it, and returns once the engine answers or the context ends.
func (s *Supervisor) Start(ctx context.Context, profile string) (time.Duration, error) {
	start := time.Now()
	s.profile = profile
	command, err := s.Adapter.Prepare(profile)
	if err != nil {
		return 0, err
	}
	port := s.EnginePort
	if command.Port > 0 {
		port = command.Port
	}
	s.port = port
	args := append([]string(nil), command.Args...)
	if command.PortFlag != "" {
		args = append(args, command.PortFlag, fmt.Sprint(port))
	}

	logf, err := os.OpenFile(s.LogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return 0, fmt.Errorf("cannot open the engine log %s: %w", s.LogPath, err)
	}
	s.logf = logf

	stdinR, stdinW, err := os.Pipe()
	if err != nil {
		logf.Close()
		return 0, fmt.Errorf("cannot open the child's stdin: %w", err)
	}

	cmd := exec.Command(command.Path, args...)
	cmd.Env = s.Env
	cmd.Stdin = stdinR
	cmd.Stdout = logf
	cmd.Stderr = logf
	// Own process group: terminate reaches the engine and anything it spawned.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		stdinR.Close()
		stdinW.Close()
		logf.Close()
		return 0, fmt.Errorf("cannot start the engine: %w", err)
	}
	// The child owns the read end now.
	_ = stdinR.Close()
	s.stdinW = stdinW
	s.done = make(chan error, 1)
	s.finished = make(chan struct{})
	go func() {
		s.done <- cmd.Wait()
		close(s.finished)
	}()
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
		// EOF first: a server that watches stdin shuts down cleanly, and one that does not is
		// killed by the signal below either way.
		if s.stdinW != nil {
			_ = s.stdinW.Close()
			s.stdinW = nil
		}
		_ = syscall.Kill(pgid, syscall.SIGTERM)
		select {
		case <-s.finished:
		case <-time.After(180 * time.Second):
			_ = syscall.Kill(pgid, syscall.SIGKILL)
			<-s.finished
		}
		s.cmd = nil
		s.done = nil
		s.finished = nil
		// The process is reaped, but the next engine binds the same port and a launcher that tests
		// it with a plain bind treats a socket the kernel is still tearing down as "already in
		// use". Measured on brys: `sd-server` stopped, the strata engine started two seconds later
		// and refused to bind 8080; the port was free a few seconds after that.
		s.waitPortFree(20 * time.Second)
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

// currentPort is the port of the running child, or the deployment's engine port when nothing has
// started yet.
func (s *Supervisor) currentPort() int {
	if s.port > 0 {
		return s.port
	}
	return s.EnginePort
}

// CurrentPort is the port a caller should proxy to for the profile that is running.
func (s *Supervisor) CurrentPort() int { return s.currentPort() }

// waitPortFree blocks until nothing answers on the engine port, then gives the kernel a moment to
// finish the teardown. It is deliberately a connect probe: a listener that is gone refuses the
// connection, while a dying one still accepts it.
func (s *Supervisor) waitPortFree(timeout time.Duration) {
	addr := fmt.Sprintf("127.0.0.1:%d", s.currentPort())
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", addr, 300*time.Millisecond)
		if err != nil {
			time.Sleep(time.Second)
			return
		}
		_ = conn.Close()
		time.Sleep(250 * time.Millisecond)
	}
}

// Ready reports whether the engine answers right now.
func (s *Supervisor) Ready(ctx context.Context) bool {
	if s.ReadyFn != nil {
		return s.ReadyFn(ctx)
	}
	reqCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	url := fmt.Sprintf("http://127.0.0.1:%d%s", s.currentPort(), s.Adapter.ReadyPath(s.profile))
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
	if s.finished == nil {
		return false
	}
	select {
	case <-s.finished:
		return true
	default:
		return false
	}
}
