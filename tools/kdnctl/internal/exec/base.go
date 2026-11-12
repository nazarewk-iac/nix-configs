package exec

import (
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"strings"

	"al.essio.dev/pkg/shellescape"
)

type Command struct{ *exec.Cmd }

// SSHNoHostKeyChecking are the options for a non-interactive connection. The host key is not
// verified here because this command WRITES the host key; a short connect timeout keeps a run over
// every host from stalling on a machine that is off.
var SSHNoHostKeyChecking = []string{
	"-o", "StrictHostKeyChecking=no",
	"-o", "UserKnownHostsFile=/dev/null",
	// The system-wide file is consulted even with StrictHostKeyChecking=no, and a pin that no
	// longer matches fails the connection outright. This command writes host keys, so it cannot
	// also be pinned to them.
	"-o", "GlobalKnownHostsFile=/dev/null",
	"-o", "ConnectTimeout=10",
}

func (c *Command) Output() ([]byte, error) {
	c.Stdout = nil
	return c.Cmd.Output()
}

func (c *Command) StdinPipe() (io.WriteCloser, error) {
	c.Stdin = nil
	return c.Cmd.StdinPipe()
}

func prepare(args ...string) *Command {
	proc := exec.Command(args[0], args[1:]...)
	proc.Stderr = os.Stderr
	proc.Stdout = os.Stdout
	proc.Stdin = os.Stdin
	return &Command{proc}
}

func LocalCommand(args ...string) *Command {
	slog.Info("preparing local command", "cmd", shellescape.QuoteCommand(args))
	return prepare(args...)
}

func RemoteCommand(host string, sshArgs []string, args ...string) *Command {
	slog.Info("preparing remote command", "cmd", shellescape.QuoteCommand(args), "host", host, "sshArgs", shellescape.QuoteCommand(sshArgs))
	sshCmd := []string{"ssh"}

	sshCmd = append(sshCmd, sshArgs...)
	sshCmd = append(sshCmd, host)
	sshCmd = append(sshCmd, shellescape.QuoteCommand(args))
	return prepare(sshCmd...)
}

func GetRemoteFile(host string, sshArgs []string, path string) ([]byte, error) {
	data, err := RemoteCommand(host, sshArgs, "sudo", "cat", path).Output()
	if err != nil {
		err = fmt.Errorf("GetRemoteFile(%s, %s): %w", host, path, err)
	}
	return data, err
}

// GetRemoteFileIfExists reads a remote file and reports whether it was there. A missing file is a
// normal state — the first deploy of a key — and must not abort a run over every host.
func GetRemoteFileIfExists(host string, sshArgs []string, path string) ([]byte, bool, error) {
	proc := RemoteCommand(host, sshArgs, "sudo", "cat", path)
	// `prepare` sends stderr straight to the terminal and stdout to the terminal; capture stderr
	// here, because the reason a read failed decides whether the file is simply absent.
	proc.Stderr = nil
	data, err := proc.Output()
	if err == nil {
		return data, true, nil
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) && strings.Contains(string(exitErr.Stderr), "No such file") {
		return nil, false, nil
	}
	if errors.As(err, &exitErr) {
		return nil, false, fmt.Errorf("GetRemoteFileIfExists(%s, %s): %w: %s", host, path, err, strings.TrimSpace(string(exitErr.Stderr)))
	}
	return nil, false, fmt.Errorf("GetRemoteFileIfExists(%s, %s): %w", host, path, err)
}
