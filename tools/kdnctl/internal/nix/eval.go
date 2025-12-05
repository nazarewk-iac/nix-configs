package nix

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"os/exec"

	"al.essio.dev/pkg/shellescape"
)

func EvalFlakeJSON(flake string, output string) (value json.RawMessage, err error) {
	args := []string{"nix", "eval", "--json",
		fmt.Sprintf("%s#self", flake),
		"--apply",
		fmt.Sprintf("self: with self; %s", output)}

	slog.Info("running command", "cmd", shellescape.QuoteCommand(args))
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stderr = os.Stderr
	value, err = cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("error in nix eval: %w", err)
	}
	return
}
