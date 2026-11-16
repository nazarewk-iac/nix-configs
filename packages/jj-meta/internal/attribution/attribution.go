// Package attribution builds the trailer set for one change from a profile and a session.
//
// A profile is the set of conventions one project accepts. `portable` is the default because the
// Nixpkgs, OpenInfra, LocalAI, Flux and Fedora policies all accept a dedicated `Assisted-by`
// disclosure. `Co-authored-by` is a GitHub credit mechanism, not a disclosure, so it stays out of
// the default and always names the agent, never the human author.
package attribution

import (
	"fmt"
	"strings"

	"jj-meta/internal/session"
	"jj-meta/internal/trailer"
)

// Profile names the trailer convention a repository accepts.
type Profile string

const (
	// Portable is the default: Assisted-by, Session-Id, Harness, Model.
	Portable Profile = "portable"
	// GitHub adds the agent Co-authored-by line for the GitHub avatar convention.
	GitHub Profile = "github"
	// ASF uses Generated-by instead of Assisted-by, for Apache-style projects.
	ASF Profile = "asf"
	// Full writes every supported field.
	Full Profile = "full"
)

// Profiles lists the accepted profile names, in help order.
var Profiles = []string{string(Portable), string(GitHub), string(ASF), string(Full)}

// ParseProfile validates a profile name. An empty name means Portable.
func ParseProfile(name string) (Profile, error) {
	switch p := Profile(strings.ToLower(strings.TrimSpace(name))); p {
	case "":
		return Portable, nil
	case Portable, GitHub, ASF, Full:
		return p, nil
	default:
		return "", fmt.Errorf("unknown profile %q; use one of %s", name, strings.Join(Profiles, ", "))
	}
}

// Options describes one attribution request.
type Options struct {
	Profile       Profile
	Session       session.Session
	NoSession     bool
	Coauthor      bool
	CoauthorEmail string
	Generated     bool
	Extra         []trailer.Trailer
}

// Plan is the trailer set to append, plus the warnings the caller should print.
type Plan struct {
	Trailers []trailer.Trailer
	Warnings []string
}

// Build returns the trailers the options describe.
//
// The order is stable: the disclosure first, then the agent co-author, then the session fields.
// Duplicate keys with equal values collapse; distinct values survive.
func Build(opts Options) (Plan, error) {
	profile, err := ParseProfile(string(opts.Profile))
	if err != nil {
		return Plan{}, err
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
	} else if s.Model == "" {
		plan.Warnings = append(plan.Warnings,
			"cannot detect the model; Assisted-by names the harness only. Pass --model to satisfy the Nixpkgs policy")
	}

	switch profile {
	case Portable, Full:
		add("Assisted-by", agent)
	}
	switch profile {
	case ASF, Full:
		add("Generated-by", agent)
	}
	if opts.Generated {
		add("Generated-by", agent)
	}
	if profile == GitHub || profile == Full || opts.Coauthor {
		email := strings.TrimSpace(opts.CoauthorEmail)
		if email == "" {
			return Plan{}, fmt.Errorf(
				"profile %s and --coauthor need an agent email: pass --coauthor-email or set JJ_META_COAUTHOR_EMAIL", profile)
		}
		name := s.Harness
		if name == "" {
			name = "agent"
		}
		add("Co-authored-by", name+" <"+email+">")
	}
	if !opts.NoSession {
		add("Session-Id", s.ID)
	}
	add("Harness", s.Harness)
	add("Model", s.Model)
	for _, t := range opts.Extra {
		add(t.Key, t.Value)
	}
	if len(plan.Trailers) == 0 {
		return Plan{}, fmt.Errorf("nothing to attribute: pass --harness/--model or --trailer key=value")
	}
	return plan, nil
}
