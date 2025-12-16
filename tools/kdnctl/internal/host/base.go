package host

import (
	"encoding/json"
	"fmt"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/nix"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/repo"
)

type Host struct {
	Name    string
	Address string
	config  *Configuration
}

type Configuration struct {
	LUKSVolumes []struct {
		Name           string `json:"name"`
		KeyFile        string `json:"keyFile"`
		HeaderPath     string `json:"headerPath"`
		CryptsetupName string `json:"cryptsetupName"`
	} `json:"luksVolumes"`
}

func New(name string, address string) *Host {
	return &Host{
		Name:    name,
		Address: address,
	}
}

func (h *Host) GatherConfig(r *repo.Repo) (*Configuration, error) {
	if h.config != nil {
		return h.config, nil
	}
	// TODO: add locking here
	config := &Configuration{}
	data, err := nix.EvalFlakeJSON(r.Root, fmt.Sprintf("hosts.%s.kdn.outputs.host", h.Name))
	if err != nil {
		return nil, fmt.Errorf("Host.GatheringFacts(%v): evaluating Nix output: %w", h.Name, err)
	}
	err = json.Unmarshal(data, &config)
	if err != nil {
		return nil, fmt.Errorf("Host.GatheringFacts(%v): decoding JSON: %w", h.Name, err)
	}
	h.config = config
	return h.config, nil
}
