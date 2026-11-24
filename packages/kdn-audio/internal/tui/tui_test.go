package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"

	"kdn-audio/internal/audio"
	"kdn-audio/internal/pipewire"
	"kdn-audio/internal/testfake"
)

const (
	alsaSink    = "alsa_output.pci-0000_07_00.6.analog-stereo"
	earmuffs    = "bluez_output.60_AB_D2_77_07_56.1"
	jbl         = "bluez_output.38_D5_18_B6_64_93.1"
	earmuffsMAC = "60:AB:D2:77:07:56"
	jblMAC      = "38:D5:18:B6:64:93"
)

func newTestModel(t *testing.T) (Model, *testfake.Pipewire) {
	t.Helper()
	p := &testfake.Pipewire{
		SinksList: []pipewire.Sink{
			testfake.Sink(alsaSink, "Ryzen HD Audio", "alsa"),
			testfake.BTSink(earmuffsMAC, "Earmuffs"),
			testfake.BTSink(jblMAC, "JBL Endurance Peak 4"),
		},
		Default: alsaSink,
	}
	model := New(audio.New(p, &testfake.Bluetooth{}))
	model.width, model.height = 100, 30
	loaded, _ := model.Update(model.Init()())
	return loaded.(Model), p
}

func key(model Model, msg tea.KeyMsg) Model {
	updated, _ := model.Update(msg)
	return updated.(Model)
}

func TestWizardSelectsAndJoins(t *testing.T) {
	model, p := newTestModel(t)
	if len(model.sinks) != 3 {
		t.Fatalf("sinks = %d, want 3", len(model.sinks))
	}
	if model.sinks[0].Description != "Earmuffs" {
		t.Fatalf("first sink = %q, want Bluetooth first", model.sinks[0].Description)
	}

	model = key(model, tea.KeyMsg{Type: tea.KeySpace})
	model = key(model, tea.KeyMsg{Type: tea.KeyDown})
	model = key(model, tea.KeyMsg{Type: tea.KeySpace})
	if len(model.selected) != 2 {
		t.Fatalf("selected = %d, want 2", len(model.selected))
	}
	if got := model.defaultTitle(); got != "Earmuffs + JBL Endurance Peak 4" {
		t.Fatalf("default title = %q", got)
	}

	model = key(model, tea.KeyMsg{Type: tea.KeyEnter})
	if model.screen != screenName {
		t.Fatalf("screen = %v, want the name screen", model.screen)
	}
	if model.name.Value() != "Earmuffs + JBL Endurance Peak 4" {
		t.Errorf("name = %q", model.name.Value())
	}

	updated, cmd := model.Update(tea.KeyMsg{Type: tea.KeyEnter})
	model = updated.(Model)
	if cmd == nil {
		t.Fatal("enter on the name screen returned no command")
	}
	created, ok := cmd().(createdMsg)
	if !ok {
		t.Fatal("the create command returned the wrong message")
	}
	if created.err != nil {
		t.Fatalf("create: %v", created.err)
	}
	loaded, _ := model.Update(created)
	model = loaded.(Model)
	if model.screen != screenMain {
		t.Errorf("screen = %v after create, want main", model.screen)
	}
	if p.Default != alsaSink {
		t.Errorf("default = %q, want the default left alone", p.Default)
	}
	if len(p.Moved) != 0 {
		t.Errorf("moved = %v, want no stream moved", p.Moved)
	}
	if !strings.Contains(model.status, "joined") {
		t.Errorf("status = %q", model.status)
	}
	if model.focus != paneJoined {
		t.Errorf("focus = %v after a join, want the joined pane", model.focus)
	}
}

func TestWizardRoutesOnlyOnRequest(t *testing.T) {
	model, p := newTestModel(t)
	model = key(model, tea.KeyMsg{Type: tea.KeySpace})
	model = key(model, tea.KeyMsg{Type: tea.KeyDown})
	model = key(model, tea.KeyMsg{Type: tea.KeySpace})
	model = key(model, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("s")})
	model = key(model, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("m")})
	if !model.routeDefault || !model.moveStreams {
		t.Fatalf("routing toggles = %v/%v, want both on", model.routeDefault, model.moveStreams)
	}
	model = key(model, tea.KeyMsg{Type: tea.KeyEnter})
	updated, cmd := model.Update(tea.KeyMsg{Type: tea.KeyEnter})
	model = updated.(Model)
	created, ok := cmd().(createdMsg)
	if !ok || created.err != nil {
		t.Fatalf("create: %+v", cmd())
	}
	if p.Default != "combined_earmuffs_jbl_endurance_peak_4" {
		t.Errorf("default = %q, want the joined output", p.Default)
	}
	if len(p.Moved) != 1 {
		t.Errorf("moved = %v, want the playing streams moved", p.Moved)
	}
}

func TestWizardNeedsTwoOutputs(t *testing.T) {
	model, _ := newTestModel(t)
	model = key(model, tea.KeyMsg{Type: tea.KeySpace})
	model = key(model, tea.KeyMsg{Type: tea.KeyEnter})
	if model.screen != screenMain {
		t.Fatalf("screen = %v, want main", model.screen)
	}
	if !strings.Contains(model.status, "at least two") {
		t.Errorf("status = %q", model.status)
	}
}

func TestWizardUnlinkAllConfirmation(t *testing.T) {
	model, p := newTestModel(t)
	if _, err := model.mgr.Create(audio.CreateOptions{Title: "Both", Members: []string{"Earmuffs", "JBL"}}); err != nil {
		t.Fatalf("create: %v", err)
	}
	loaded, _ := model.Update(model.load()())
	model = loaded.(Model)
	if len(model.groups) != 1 {
		t.Fatalf("groups = %d, want 1", len(model.groups))
	}

	model = key(model, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("D")})
	if model.screen != screenConfirm {
		t.Fatalf("screen = %v, want the confirmation screen", model.screen)
	}
	updated, cmd := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("y")})
	model = updated.(Model)
	if cmd == nil {
		t.Fatal("confirmation returned no command")
	}
	if unlinked, ok := cmd().(unlinkedMsg); !ok || unlinked.err != nil {
		t.Fatalf("unlink all = %+v", cmd())
	}
	if len(p.Removed) != 1 {
		t.Errorf("removed = %v", p.Removed)
	}
}

func TestWizardRefusesAJoinedOutputAsMember(t *testing.T) {
	model, _ := newTestModel(t)
	if _, err := model.mgr.Create(audio.CreateOptions{Title: "Both", Members: []string{"Earmuffs", "JBL"}}); err != nil {
		t.Fatalf("create: %v", err)
	}
	loaded, _ := model.Update(model.load()())
	model = loaded.(Model)
	model.cursor = len(model.sinks) - 1
	model = key(model, tea.KeyMsg{Type: tea.KeySpace})
	if len(model.selected) != 0 {
		t.Fatalf("selected a joined output: %v", model.selected)
	}
	if !strings.Contains(model.status, "cannot be a member") {
		t.Errorf("status = %q", model.status)
	}
}

func TestViewRendersEveryScreen(t *testing.T) {
	model, _ := newTestModel(t)
	for _, screen := range []screen{screenMain, screenName, screenConfirm} {
		model.screen = screen
		view := model.View()
		if view == "" {
			t.Errorf("screen %v rendered nothing", screen)
		}
		if !strings.Contains(view, "kdn-audio") && screen == screenMain {
			t.Errorf("main view lost its title: %q", view)
		}
	}
}
