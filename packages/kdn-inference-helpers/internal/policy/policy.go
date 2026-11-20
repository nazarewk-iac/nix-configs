// Package policy is the placement policy: one behaviour tree, defined in the deployment config,
// that decides whether a model may run, beside what, and what has to leave first.
//
// The tree is data. The verbs it names are here, small and tested, and an unknown verb is a
// load-time error: a typo that silently degraded to "allow" is the worst failure this design can
// have. The evaluator never touches the card; it returns a plan and the reasoning, and the manager
// applies the plan under its switch lock.
package policy

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
)

// Facts are the measured numbers a model needs to be placed. They come from stage 0, not from
// guesswork, and `Measured`/`Source` are what stop a stale table from silently admitting the wrong
// thing.
type Facts struct {
	VRAMMiB             int                `json:"vramMiB"`
	RAMMiB              int                `json:"ramMiB"`
	LoadBurstMiB        int                `json:"loadBurstMiB,omitempty"`
	LoadSeconds         int                `json:"loadSeconds,omitempty"`
	SwitchSeconds       int                `json:"switchSeconds,omitempty"`
	DecodeTps           float64            `json:"decodeTps,omitempty"`
	DecodeWithFrontier  map[string]float64 `json:"decodeWithFrontier,omitempty"`
	MinResidencySeconds int                `json:"minResidencySeconds,omitempty"`
	Measured            string             `json:"measured,omitempty"`
	Source              string             `json:"source,omitempty"`
}

// Measured reports whether this model carries real numbers.
func (f Facts) IsMeasured() bool { return f.VRAMMiB > 0 && f.Measured != "" }

// Model is one catalogue entry as the policy sees it.
type Model struct {
	Kind            string   `json:"kind"` // engine | companion | editor | small
	Tier            string   `json:"tier"` // frontier | companion | small
	Profile         string   `json:"profile,omitempty"`
	RequiresProfile []string `json:"requiresProfile,omitempty"`
	Persistent      bool     `json:"persistent,omitempty"`
	SpillOk         bool     `json:"spillOk,omitempty"`
	Disabled        bool     `json:"disabled,omitempty"`
	Facts
}

// Active is one model that is resident right now. `LoadingSince` and `LoadedAt` are what make a
// concurrent decision safe: between "start" and "ready" the model is neither loaded nor absent.
type Active struct {
	Model          string     `json:"model"`
	Kind           string     `json:"kind,omitempty"`
	Tier           string     `json:"tier,omitempty"`
	Profile        string     `json:"profile,omitempty"`
	VRAMMiB        int        `json:"vramMiB,omitempty"`
	RAMMiB         int        `json:"ramMiB,omitempty"`
	LoadingSince   *time.Time `json:"loadingSince,omitempty"`
	LoadedAt       *time.Time `json:"loadedAt,omitempty"`
	LastFinishedAt *time.Time `json:"lastFinishedAt,omitempty"`
	Leases         int        `json:"leases,omitempty"`
}

// Request is the ask.
type Request struct {
	Model           string            `json:"model"`
	Class           string            `json:"class,omitempty"` // human | agent | batch
	DeadlineSeconds int               `json:"deadlineSeconds,omitempty"`
	Confirm         map[string]string `json:"confirm,omitempty"`
}

// State is the card and the clock.
type State struct {
	// Profile is the engine profile that is current right now.
	Profile             string     `json:"profile,omitempty"`
	VRAMFreeMiB         int        `json:"vramFreeMiB"`
	RAMFreeMiB          int        `json:"ramFreeMiB"`
	CacheReclaimableMiB int        `json:"cacheReclaimableMiB,omitempty"`
	LastSwitchAt        *time.Time `json:"lastSwitchAt,omitempty"`
	Draining            bool       `json:"draining,omitempty"`
	Now                 time.Time  `json:"now,omitempty"`
}

// Budget is what the host has.
type Budget struct {
	VRAMMiB         int `json:"vramMiB"`
	RAMMiB          int `json:"ramMiB"`
	LoadBurstRAMMiB int `json:"loadBurstRAMMiB,omitempty"`
}

// Node is one node of the tree. `selector` tries children until one succeeds; `sequence` requires
// all of them; `check` is a predicate with facts; `action` mutates the plan or ends the decision.
type Node struct {
	Type     string         `json:"type"`
	Verb     string         `json:"verb,omitempty"`
	Args     map[string]any `json:"args,omitempty"`
	Children []Node         `json:"children,omitempty"`
}

// Policy is the deployment's placement policy: the tree plus the facts it decides over.
type Policy struct {
	SchemaVersion         int              `json:"schemaVersion"`
	Budget                Budget           `json:"budget"`
	SwitchCooldownSeconds int              `json:"switchCooldownSeconds,omitempty"`
	DefaultDeadline       int              `json:"defaultDeadlineSeconds,omitempty"`
	MinDecodeTps          float64          `json:"minDecodeTps,omitempty"`
	AllowUnmeasured       bool             `json:"allowUnmeasured,omitempty"`
	Tree                  Node             `json:"tree"`
	Models                map[string]Model `json:"models"`
}

// Defaults are the values a deployment may omit.
const (
	DefaultCooldownSeconds = 30
	DefaultDeadlineSeconds = 120
	SchemaVersion          = 1
)

// Load reads the policy from a JSON file and validates it.
func Load(path string) (*Policy, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var p Policy
	if err := json.Unmarshal(body, &p); err != nil {
		return nil, fmt.Errorf("policy %s: %w", path, err)
	}
	if err := p.Validate(); err != nil {
		return nil, fmt.Errorf("policy %s: %w", path, err)
	}
	return &p, nil
}

// Validate refuses a policy that cannot be trusted. Every check here is one that would otherwise
// surface as a wrong admission at three in the morning.
func (p *Policy) Validate() error {
	if p.SchemaVersion != SchemaVersion {
		return fmt.Errorf("schemaVersion %d, this build understands %d", p.SchemaVersion, SchemaVersion)
	}
	if p.Budget.VRAMMiB <= 0 {
		return fmt.Errorf("budget.vramMiB must be positive")
	}
	if p.Budget.RAMMiB <= 0 {
		return fmt.Errorf("budget.ramMiB must be positive")
	}
	if p.Tree.Type == "" || len(p.Tree.Children) == 0 {
		return fmt.Errorf("tree is empty")
	}
	if err := validateNode(p.Tree, "root"); err != nil {
		return err
	}
	for name, m := range p.Models {
		if m.Kind == "" {
			return fmt.Errorf("model %q has no kind", name)
		}
		if m.Kind == "engine" && m.Profile == "" && len(m.RequiresProfile) == 0 {
			return fmt.Errorf("engine %q has neither a profile nor a required profile set", name)
		}
		if !m.IsMeasured() && !p.AllowUnmeasured {
			return fmt.Errorf("model %q has no measured facts; set measured+source or allowUnmeasured", name)
		}
	}
	if p.SwitchCooldownSeconds == 0 {
		p.SwitchCooldownSeconds = DefaultCooldownSeconds
	}
	if p.DefaultDeadline == 0 {
		p.DefaultDeadline = DefaultDeadlineSeconds
	}
	return nil
}

func validateNode(n Node, path string) error {
	switch n.Type {
	case "selector", "sequence":
		if len(n.Children) == 0 {
			return fmt.Errorf("%s: %s has no children", path, n.Type)
		}
		for i, child := range n.Children {
			if err := validateNode(child, fmt.Sprintf("%s.%d", path, i)); err != nil {
				return err
			}
		}
	case "check":
		if _, ok := checks[n.Verb]; !ok {
			return fmt.Errorf("%s: unknown check %q", path, n.Verb)
		}
	case "action":
		if _, ok := actions[n.Verb]; !ok {
			return fmt.Errorf("%s: unknown action %q", path, n.Verb)
		}
	default:
		return fmt.Errorf("%s: unknown node type %q (selector, sequence, check, action)", path, n.Type)
	}
	return nil
}
