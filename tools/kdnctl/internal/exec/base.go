package exec

import (
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"

	"al.essio.dev/pkg/shellescape"
)

type Command struct{ *exec.Cmd }

var SSHNoHostKeyChecking = []string{"-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"}

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
