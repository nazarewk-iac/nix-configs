package router

import (
	"context"
	"strings"
	"testing"

	"kdn-inference-helpers/internal/engine"
)

// fake is a minimal adapter: a name, a profile list, and the argv it hands back.
type fake struct {
	name     string
	profiles []string
	ready    string
	portFlag string
	stopped  *bool
}

func (f *fake) Name() string       { return f.name }
func (f *fake) Profiles() []string { return f.profiles }
func (f *fake) ReadyPath(string) string {
	if f.ready == "" {
		return "/v1/models"
	}
	return f.ready
}
func (f *fake) Prepare(profile string) (engine.Command, error) {
	for _, p := range f.profiles {
		if p == profile {
			return engine.Command{Path: f.name + "-" + profile, PortFlag: f.portFlag}, nil
		}
	}
	return engine.Command{}, errUnknown(profile)
}
func (f *fake) Stop(ctx context.Context) error {
	if f.stopped != nil {
		*f.stopped = true
	}
	return nil
}

type unknownProfile string

func (u unknownProfile) Error() string { return "unknown profile " + string(u) }

func errUnknown(p string) error { return unknownProfile(p) }

func TestProfilesAreTheUnionPrimaryFirst(t *testing.T) {
	a := New(
		&fake{name: "strata", profiles: []string{"max", "omni-fast"}},
		&fake{name: "command", profiles: []string{"image-qwen"}},
	)
	got := strings.Join(a.Profiles(), ",")
	if got != "max,omni-fast,image-qwen" {
		t.Fatalf("profiles = %q", got)
	}
}

func TestPrepareDispatchesToTheOwningEngine(t *testing.T) {
	a := New(
		&fake{name: "strata", profiles: []string{"max"}, portFlag: "--port"},
		&fake{name: "command", profiles: []string{"image-qwen"}, portFlag: "--listen-port"},
	)
	text, err := a.Prepare("max")
	if err != nil {
		t.Fatal(err)
	}
	if text.Path != "strata-max" || text.PortFlag != "--port" {
		t.Fatalf("text command = %+v", text)
	}
	image, err := a.Prepare("image-qwen")
	if err != nil {
		t.Fatal(err)
	}
	if image.Path != "command-image-qwen" || image.PortFlag != "--listen-port" {
		t.Fatalf("image command = %+v", image)
	}
}

func TestReadyPathFollowsTheProfile(t *testing.T) {
	a := New(
		&fake{name: "strata", profiles: []string{"max"}, ready: "/v1/models"},
		&fake{name: "command", profiles: []string{"image-qwen"}, ready: "/sdapi/v1/options"},
	)
	if got := a.ReadyPath("max"); got != "/v1/models" {
		t.Fatalf("text ready path = %q", got)
	}
	if got := a.ReadyPath("image-qwen"); got != "/sdapi/v1/options" {
		t.Fatalf("image ready path = %q", got)
	}
}

func TestAnUnknownProfileIsRefused(t *testing.T) {
	a := New(&fake{name: "strata", profiles: []string{"max"}})
	if _, err := a.Prepare("image-qwen"); err == nil {
		t.Fatal("an unknown profile was prepared")
	}
}

// Stop must reach every engine: the router cannot know which one a previous manager instance left
// running, so a leftover child of either kind has to be cleaned up.
func TestStopReachesEveryEngine(t *testing.T) {
	textStopped, imageStopped := false, false
	a := New(
		&fake{name: "strata", profiles: []string{"max"}, stopped: &textStopped},
		&fake{name: "command", profiles: []string{"image-qwen"}, stopped: &imageStopped},
	)
	if err := a.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !textStopped || !imageStopped {
		t.Fatalf("stop reached text=%v image=%v", textStopped, imageStopped)
	}
}

func TestAnEngineWithNoProfilesIsDropped(t *testing.T) {
	a := New(&fake{name: "strata", profiles: []string{"max"}}, &fake{name: "command"})
	if len(a.Extras) != 0 {
		t.Fatalf("an empty engine was kept: %v", a.Extras)
	}
	if a.Name() != "router(strata)" {
		t.Fatalf("name = %q", a.Name())
	}
}
