// Package router dispatches a profile to one of several engines.
//
// One card, one server at a time, but not one *kind* of server. The frontier is Strata; an image
// editor is `sd-server` with a different model set. Both are profiles of the same manager, so both
// obey the same drain, the same leases and the same gate — the card cannot be double-booked by a
// deployment that forgot to make them exclusive.
//
// The router is the adapter the manager sees; the engines behind it never learn about each other.
package router

import (
	"context"
	"fmt"

	"kdn-inference-helpers/internal/engine"
)

// Adapter routes each profile to the engine that owns it.
type Adapter struct {
	// Primary is the engine that serves the deployment's main profiles (Strata on brys).
	Primary engine.Adapter
	// Extras own their own profiles and are consulted only for those.
	Extras []engine.Adapter
}

// New builds the router. Extras with no profiles are dropped.
func New(primary engine.Adapter, extras ...engine.Adapter) *Adapter {
	a := &Adapter{Primary: primary}
	for _, e := range extras {
		if e != nil && len(e.Profiles()) > 0 {
			a.Extras = append(a.Extras, e)
		}
	}
	return a
}

// Name is the value `--engine` accepts.
func (a *Adapter) Name() string {
	names := []string{a.Primary.Name()}
	for _, e := range a.Extras {
		names = append(names, e.Name())
	}
	return fmt.Sprintf("router(%s)", join(names))
}

// Profiles lists every profile the deployment can serve, primary first.
func (a *Adapter) Profiles() []string {
	out := append([]string(nil), a.Primary.Profiles()...)
	for _, e := range a.Extras {
		out = append(out, e.Profiles()...)
	}
	return out
}

// owner finds the engine for a profile.
func (a *Adapter) owner(profile string) (engine.Adapter, error) {
	if contains(a.Primary.Profiles(), profile) {
		return a.Primary, nil
	}
	for _, e := range a.Extras {
		if contains(e.Profiles(), profile) {
			return e, nil
		}
	}
	return nil, fmt.Errorf("no engine serves profile %q", profile)
}

// Prepare materialises the profile through the engine that owns it.
func (a *Adapter) Prepare(profile string) (engine.Command, error) {
	owner, err := a.owner(profile)
	if err != nil {
		return engine.Command{}, err
	}
	return owner.Prepare(profile)
}

// ReadyPath is the path the owning engine answers on.
func (a *Adapter) ReadyPath(profile string) string {
	owner, err := a.owner(profile)
	if err != nil {
		return "/v1/models"
	}
	return owner.ReadyPath(profile)
}

// Stop asks every engine to clean up. Each adapter's Stop is already a no-op when it has nothing
// left, so calling all of them is the only safe order: the router does not know which one the
// previous manager instance left running.
func (a *Adapter) Stop(ctx context.Context) error {
	var first error
	if err := a.Primary.Stop(ctx); err != nil {
		first = err
	}
	for _, e := range a.Extras {
		if err := e.Stop(ctx); err != nil && first == nil {
			first = err
		}
	}
	return first
}

// OwnedBy reports which adapter serves a profile, for the manager's "is this a text profile"
// question and for the journal.
func (a *Adapter) OwnedBy(profile string) string {
	if owner, err := a.owner(profile); err == nil {
		return owner.Name()
	}
	return ""
}

func contains(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
}

func join(list []string) string {
	out := ""
	for i, v := range list {
		if i > 0 {
			out += "+"
		}
		out += v
	}
	return out
}
