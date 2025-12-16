package nix

import (
	"encoding/json"
	"fmt"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/exec"
)

func EvalFlakeJSON(flake string, output string) (value json.RawMessage, err error) {
	args := []string{
		"nix", "eval", "--json",
		fmt.Sprintf("%s#self", flake),
		"--apply",
		fmt.Sprintf("self: with self; %s", output),
	}

	cmd := exec.LocalCommand(args...)
	value, err = cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("EvalFlakeJSON: running evaluation: %w", err)
	}
	return
}
