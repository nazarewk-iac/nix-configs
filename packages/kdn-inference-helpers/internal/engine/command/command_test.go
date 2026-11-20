package command

import (
	"context"
	"strings"
	"testing"
)

func TestPrepareReturnsTheConfiguredArgv(t *testing.T) {
	a := New(map[string]Spec{
		"max":       {Argv: []string{"llama-server", "--model", "/tiny.gguf", "--ctx-size", "512"}},
		"omni-fast": {Argv: []string{"llama-server", "--model", "/tiny.gguf"}},
	})
	cmd, err := a.Prepare("max")
	if err != nil {
		t.Fatal(err)
	}
	if cmd.Path != "llama-server" || strings.Join(cmd.Args, " ") != "--model /tiny.gguf --ctx-size 512" {
		t.Fatalf("command = %+v", cmd)
	}
}

func TestPrepareRejectsAMissingOrEmptyProfile(t *testing.T) {
	a := New(map[string]Spec{"max": {Argv: []string{"llama-server"}}, "empty": {}})
	if _, err := a.Prepare("nope"); err == nil {
		t.Fatal("an unknown profile was accepted")
	}
	// An empty argv is dropped at construction, so it is simply unknown.
	if _, err := a.Prepare("empty"); err == nil {
		t.Fatal("an empty argv was accepted")
	}
	if got := a.Profiles(); len(got) != 1 || got[0] != "max" {
		t.Fatalf("profiles = %v", got)
	}
}

func TestStopIsANoOp(t *testing.T) {
	if err := New(nil).Stop(context.Background()); err != nil {
		t.Fatalf("stop: %v", err)
	}
}

func TestTheAdapterNamesItselfSoTheBinaryCanSelectIt(t *testing.T) {
	if got := New(nil).Name(); got != "command" {
		t.Fatalf("name = %q", got)
	}
	if got := New(nil).ReadyPath("max"); got != "/v1/models" {
		t.Fatalf("ready path = %q", got)
	}
}

func TestASpecCarriesThePortFlagAndTheReadyPath(t *testing.T) {
	a := New(map[string]Spec{
		"image": {
			Argv:      []string{"sd-server", "--diffusion-model", "/q.gguf"},
			ReadyPath: "/sdapi/v1/options",
			PortFlag:  "--listen-port",
		},
	})
	cmd, err := a.Prepare("image")
	if err != nil {
		t.Fatal(err)
	}
	if cmd.PortFlag != "--listen-port" {
		t.Fatalf("port flag = %q", cmd.PortFlag)
	}
	if got := a.ReadyPath("image"); got != "/sdapi/v1/options" {
		t.Fatalf("ready path = %q", got)
	}
}

func TestDashMeansTheCommandAlreadyKnowsItsPort(t *testing.T) {
	a := New(map[string]Spec{"fixed": {Argv: []string{"server"}, PortFlag: "-"}})
	cmd, err := a.Prepare("fixed")
	if err != nil {
		t.Fatal(err)
	}
	if cmd.PortFlag != "" {
		t.Fatalf("port flag = %q, want empty", cmd.PortFlag)
	}
}

func TestTheArrayFormStillParses(t *testing.T) {
	var spec Spec
	if err := spec.UnmarshalJSON([]byte(`["llama-server","--model","/tiny.gguf"]`)); err != nil {
		t.Fatal(err)
	}
	if len(spec.Argv) != 3 || spec.Argv[0] != "llama-server" {
		t.Fatalf("argv = %v", spec.Argv)
	}
}
