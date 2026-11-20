// Package attribution builds the trailer set for one change from a profile set and a session.
//
// A profile is one attribution convention. Profiles compose: the default set is `agent`,
// `nixpkgs` and `asf`, so a change carries the local session key, the Nixpkgs disclosure and the
// ASF `Generated-by` line at once. `github` is the GitHub co-author convention and stays out of
// the default because it is credit, not disclosure.
package attribution

import (
	"fmt"
	"strings"

	"kdn-jj-meta/internal/session"
	"kdn-jj-meta/internal/trailer"
)

// Profile names one attribution convention.
type Profile string

const (
	// Agent writes the local session key: Session-Id, Harness and Model.
	Agent Profile = "agent"
	// Nixpkgs writes Assisted-by, the disclosure the Nixpkgs transparency policy requires.
	Nixpkgs Profile = "nixpkgs"
	// ASF writes Generated-by, the Apache-style disclosure.
	ASF Profile = "asf"
	// GitHub writes Co-authored-by, the GitHub credit convention. It needs an agent email.
	GitHub Profile = "github"
	// Full activates every profile.
	Full Profile = "full"
)

// Profiles lists the accepted profile names, in canonical order.
var Profiles = []string{string(Agent), string(Nixpkgs), string(ASF), string(GitHub), string(Full)}

// DefaultProfiles is the active set when the caller names none.
var DefaultProfiles = []Profile{Agent, Nixpkgs, ASF}

// ParseProfiles validates the profile names. Each value may hold a comma-separated list, so a
// flag can be repeated or passed once with `agent,nixpkgs,asf`. An empty list means the default
// set.
func ParseProfiles(values []string) ([]Profile, error) {
	var out []Profile
	for _, value := range values {
		for _, name := range strings.Split(value, ",") {
			name = strings.ToLower(strings.TrimSpace(name))
			if name == "" {
				continue
			}
			profile := Profile(name)
			switch profile {
			case Agent, Nixpkgs, ASF, GitHub, Full:
				out = append(out, profile)
			default:
				return nil, fmt.Errorf("unknown profile %q; use one of %s", name, strings.Join(Profiles, ", "))
			}
		}
	}
	return normalizeProfiles(out), nil
}

// normalizeProfiles expands `full`, removes duplicates and orders the set canonically.
func normalizeProfiles(profiles []Profile) []Profile {
	if len(profiles) == 0 {
		profiles = DefaultProfiles
	}
	active := make(map[Profile]bool, len(profiles))
	for _, profile := range profiles {
		if profile == Full {
			active[Agent] = true
			active[Nixpkgs] = true
			active[ASF] = true
			active[GitHub] = true
			continue
		}
		active[profile] = true
	}
	out := make([]Profile, 0, 4)
	for _, profile := range []Profile{Agent, Nixpkgs, ASF, GitHub} {
		if active[profile] {
			out = append(out, profile)
		}
	}
	return out
}

// Names renders a profile set for JSON and help output.
func Names(profiles []Profile) []string {
	out := make([]string, 0, len(profiles))
	for _, profile := range profiles {
		out = append(out, string(profile))
	}
	return out
}

// Options describes one attribution request.
type Options struct {
	// Profiles is the active set. An empty set means DefaultProfiles.
	Profiles      []Profile
	Session       session.Session
	NoSession     bool
	Coauthor      bool
	CoauthorEmail string
	Generated     bool
	Extra         []trailer.Trailer
	// LocalModels are the locally served models that produced the change, already normalised to
	// `alias=profile` by internal/localmodel. One trailer each, so a change that used qfn and an
	// image editor records both.
	LocalModels []string
}

// Plan is the trailer set to append, plus the warnings the caller should print.
type Plan struct {
	Trailers []trailer.Trailer
	Warnings []string
}

// Build returns the trailers the options describe.
//
// The order is stable: the disclosures first, then the local agent fields, then the co-author.
// Duplicate keys with equal values collapse; distinct values survive.
func Build(opts Options) (Plan, error) {
	profiles := normalizeProfiles(opts.Profiles)
	active := make(map[Profile]bool, len(profiles))
	for _, profile := range profiles {
		active[profile] = true
	}
	s := opts.Session
	var plan Plan
	add := func(key, value string) {
		value = strings.TrimSpace(value)
		if value == "" {
			return
		}
		plan.Trailers = append(plan.Trailers, trailer.Trailer{Key: key, Value: value})
	}

	agent := s.Harness
	if s.Model != "" {
		agent += ":" + s.Model
	}
	if s.Harness == "" {
		plan.Warnings = append(plan.Warnings,
			"cannot detect the agent harness; no Assisted-by trailer is written. Pass --harness (and --model)")
	} else if s.Model == "" && (active[Nixpkgs] || active[ASF]) {
		plan.Warnings = append(plan.Warnings,
			"cannot detect the model; the disclosure names the harness only. Pass --model to satisfy the Nixpkgs policy")
	}

	if active[Nixpkgs] {
		add("Assisted-by", agent)
	}
	if active[ASF] || opts.Generated {
		add("Generated-by", agent)
	}
	if active[Agent] {
		if !opts.NoSession {
			add("Session-Id", s.ID)
		}
		add("Harness", s.Harness)
		add("Model", s.Model)
	}
	seenLocal := map[string]bool{}
	for _, model := range opts.LocalModels {
		if seenLocal[model] {
			continue
		}
		seenLocal[model] = true
		add("Local-model", model)
	}
	if active[GitHub] || opts.Coauthor {
		email := strings.TrimSpace(opts.CoauthorEmail)
		if email == "" {
			return Plan{}, fmt.Errorf(
				"the github profile and --coauthor need an agent email: pass --coauthor-email or set KDN_JJ_META_COAUTHOR_EMAIL")
		}
		name := s.Harness
		if name == "" {
			name = "agent"
		}
		add("Co-authored-by", name+" <"+email+">")
	}
	for _, t := range opts.Extra {
		add(t.Key, t.Value)
	}
	if len(plan.Trailers) == 0 {
		return Plan{}, fmt.Errorf("nothing to attribute: pass --harness/--model or --trailer key=value")
	}
	return plan, nil
}
