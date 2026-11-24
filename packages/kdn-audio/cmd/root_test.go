package cmd

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"kdn-audio/internal/audio"
	"kdn-audio/internal/pipewire"
	"kdn-audio/internal/profile"
	"kdn-audio/internal/testfake"
)

const (
	alsaSink    = "alsa_output.pci-0000_07_00.6.analog-stereo"
	earmuffs    = "bluez_output.60_AB_D2_77_07_56.1"
	jbl         = "bluez_output.38_D5_18_B6_64_93.1"
	earmuffsMAC = "60:AB:D2:77:07:56"
	jblMAC      = "38:D5:18:B6:64:93"
)

var fixedNow = time.Date(2026, 11, 24, 12, 0, 0, 0, time.UTC)

func newTestApp(t *testing.T) (*App, *bytes.Buffer, *testfake.Pipewire) {
	t.Helper()
	p := &testfake.Pipewire{
		SinksList: []pipewire.Sink{
			testfake.Sink(alsaSink, "Ryzen HD Audio", "alsa"),
			testfake.BTSink(earmuffsMAC, "Earmuffs"),
			testfake.BTSink(jblMAC, "JBL Endurance Peak 4"),
		},
		Default: alsaSink,
	}
	out := &bytes.Buffer{}
	logs := &bytes.Buffer{}
	app := &App{
		Out:      out,
		Err:      out,
		Version:  "test",
		Now:      func() time.Time { return fixedNow },
		LookPath: func(string) (string, error) { return "/run/current-system/sw/bin/pw-dump", nil },
	}
	app.Manager = audio.New(p, &testfake.Bluetooth{})
	app.Manager.ProfilesDir = t.TempDir()
	// Progress messages go to their own buffer so a test can assert on the command output.
	app.Manager.Log = func(format string, args ...any) { fmt.Fprintf(logs, "kdn-audio: "+format+"\n", args...) }
	return app, out, p
}

func run(t *testing.T, app *App, args ...string) error {
	t.Helper()
	root := NewRootWithApp(app)
	root.SetArgs(args)
	root.SetOut(app.Out)
	root.SetErr(app.Err)
	return root.Execute()
}

func TestDevicesJSON(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "devices", "--json"); err != nil {
		t.Fatalf("devices: %v", err)
	}
	var envelope struct {
		SchemaVersion int             `json:"schema_version"`
		Command       string          `json:"command"`
		Data          json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(out.Bytes(), &envelope); err != nil {
		t.Fatalf("output is not JSON: %v\n%s", err, out.String())
	}
	if envelope.SchemaVersion != 1 || envelope.Command != "devices" {
		t.Errorf("envelope = %+v", envelope)
	}
	var data struct {
		Sinks []sinkView `json:"sinks"`
	}
	if err := json.Unmarshal(envelope.Data, &data); err != nil {
		t.Fatalf("data: %v", err)
	}
	if len(data.Sinks) != 3 {
		t.Fatalf("sinks = %d, want 3", len(data.Sinks))
	}
	if data.Sinks[0].Kind != "bluetooth" || data.Sinks[0].ID != "bt:"+earmuffsMAC {
		t.Errorf("first sink = %+v, want the Bluetooth id first", data.Sinks[0])
	}
}

func TestDevicesIDs(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "devices", "--ids"); err != nil {
		t.Fatalf("devices: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 3 {
		t.Fatalf("lines = %v", lines)
	}
	if lines[0] != "bt:"+earmuffsMAC {
		t.Errorf("first id = %q", lines[0])
	}
}

func TestStatusHuman(t *testing.T) {
	app, out, _ := newTestApp(t)
	if _, err := app.Manager.Create(audio.CreateOptions{
		Title: "Both Ears", Members: []string{"Earmuffs", "JBL"}, MakeDefault: true,
	}); err != nil {
		t.Fatalf("create: %v", err)
	}
	out.Reset()
	if err := run(t, app, "status"); err != nil {
		t.Fatalf("status: %v", err)
	}
	for _, want := range []string{"Both Ears", "Earmuffs", "JBL Endurance Peak 4", "default"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("status lost %q:\n%s", want, out.String())
		}
	}
}

func TestStatusWithoutGroups(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "status"); err != nil {
		t.Fatalf("status: %v", err)
	}
	if !strings.Contains(out.String(), "no joined output") {
		t.Errorf("status = %q", out.String())
	}
}

func TestStatusMentionsStoredProfilesWhenNothingIsJoined(t *testing.T) {
	app, out, _ := newTestApp(t)
	if _, err := (profile.Profile{
		Name:    "Both Ears",
		Outputs: []string{"bt:" + earmuffsMAC, "bt:" + jblMAC},
	}).Save(app.Manager.ProfilesDir); err != nil {
		t.Fatalf("save profile: %v", err)
	}
	if err := run(t, app, "status"); err != nil {
		t.Fatalf("status: %v", err)
	}
	if !strings.Contains(out.String(), "profiles apply") {
		t.Errorf("status = %q, want the next step for the matching profile", out.String())
	}
}

func TestStatusNamesAMissingMember(t *testing.T) {
	app, out, p := newTestApp(t)
	if _, err := app.Manager.Create(audio.CreateOptions{Title: "Both", Members: []string{"Earmuffs", "JBL"}}); err != nil {
		t.Fatalf("create: %v", err)
	}
	kept := make([]pipewire.Sink, 0, len(p.SinksList))
	for _, sink := range p.SinksList {
		if sink.Name != jbl {
			kept = append(kept, sink)
		}
	}
	p.SinksList = kept
	out.Reset()
	if err := run(t, app, "status"); err != nil {
		t.Fatalf("status: %v", err)
	}
	if !strings.Contains(out.String(), "bt:"+jblMAC) {
		t.Errorf("status = %q, want the missing device id", out.String())
	}
}

func TestCreateJSON(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "create", "--name", "Both Ears", "Earmuffs", "JBL", "--json"); err != nil {
		t.Fatalf("create: %v", err)
	}
	var envelope struct {
		Command string          `json:"command"`
		Data    json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(out.Bytes(), &envelope); err != nil {
		t.Fatalf("output is not JSON: %v\n%s", err, out.String())
	}
	if envelope.Command != "create" {
		t.Errorf("command = %q", envelope.Command)
	}
	var data struct {
		Group groupView `json:"group"`
	}
	if err := json.Unmarshal(envelope.Data, &data); err != nil {
		t.Fatalf("data: %v", err)
	}
	if data.Group.Title != "Both Ears" || data.Group.SinkName != "combined_both_ears" {
		t.Errorf("group = %+v", data.Group)
	}
	if len(data.Group.Members) != 2 {
		t.Errorf("members = %v", data.Group.Members)
	}
}

func TestCreateHumanOutput(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "create", "--name", "Both Ears", "Earmuffs", "JBL"); err != nil {
		t.Fatalf("create: %v", err)
	}
	for _, want := range []string{"joined \"Both Ears\"", "Earmuffs + JBL Endurance Peak 4", "remove with", "routing unchanged"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output lost %q:\n%s", want, out.String())
		}
	}
}

func TestCreateByID(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "create", "--name", "Both Ears", "bt:"+earmuffsMAC, "bt:"+jblMAC); err != nil {
		t.Fatalf("create: %v", err)
	}
	if !strings.Contains(out.String(), "Earmuffs + JBL Endurance Peak 4") {
		t.Errorf("output = %q", out.String())
	}
}

func TestCreateReportsAnUnknownOutput(t *testing.T) {
	app, _, _ := newTestApp(t)
	err := run(t, app, "create", "--name", "X", "Nothing")
	if err == nil || !strings.Contains(err.Error(), "no output matches") {
		t.Fatalf("create = %v", err)
	}
}

func TestCreateReportsAmbiguity(t *testing.T) {
	app, _, p := newTestApp(t)
	p.SinksList = append(p.SinksList, testfake.BTSink("AA:BB:CC:DD:EE:FF", "Earmuffs Old"))
	err := run(t, app, "create", "--name", "X", "armuff")
	if err == nil || !strings.Contains(err.Error(), "matches 2") {
		t.Fatalf("create = %v", err)
	}
}

func TestRemoveAll(t *testing.T) {
	app, out, _ := newTestApp(t)
	for _, title := range []string{"First", "Second"} {
		if _, err := app.Manager.Create(audio.CreateOptions{Title: title, Members: []string{"Earmuffs", "JBL"}}); err != nil {
			t.Fatalf("create %s: %v", title, err)
		}
	}
	out.Reset()
	if err := run(t, app, "remove", "--all"); err != nil {
		t.Fatalf("remove --all: %v", err)
	}
	if strings.Count(out.String(), "unlinked") != 2 {
		t.Errorf("output = %q", out.String())
	}
}

func TestUnlinkAllWithoutGroups(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "unlink-all"); err != nil {
		t.Fatalf("unlink-all: %v", err)
	}
	if !strings.Contains(out.String(), "no joined output to remove") {
		t.Errorf("output = %q", out.String())
	}
}

func TestShow(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "show", "Earmuffs"); err != nil {
		t.Fatalf("show: %v", err)
	}
	for _, want := range []string{"id:", "bt:" + earmuffsMAC, "device.api=bluez5"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("show lost %q:\n%s", want, out.String())
		}
	}
}

func TestIntro(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "intro"); err != nil {
		t.Fatalf("intro: %v", err)
	}
	for _, want := range []string{"WHAT IT DOES", "kdn-audio devices", "USE THE FULL-SCREEN LIST", "kdn-audio unlink-all", "MAKE IT AUTOMATIC", "space"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("intro lost %q", want)
		}
	}
}

func TestRootHelpNamesTheWizardAndTheIntro(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "--help"); err != nil {
		t.Fatalf("help: %v", err)
	}
	for _, want := range []string{"In one minute", "full-screen list", "kdn-audio intro"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("help lost %q: %s", want, out.String())
		}
	}
}

func TestVersion(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "version"); err != nil {
		t.Fatalf("version: %v", err)
	}
	if strings.TrimSpace(out.String()) != "test" {
		t.Errorf("version = %q", out.String())
	}
}

func TestUnknownCommand(t *testing.T) {
	app, _, _ := newTestApp(t)
	if err := run(t, app, "nope"); err == nil {
		t.Fatal("unknown command was accepted")
	}
}

func TestMissingPipewireIsReported(t *testing.T) {
	app, _, _ := newTestApp(t)
	app.LookPath = func(string) (string, error) { return "", errLookPath }
	if err := run(t, app, "devices"); err == nil || !strings.Contains(err.Error(), "pw-dump is not in PATH") {
		t.Fatalf("devices = %v", err)
	}
}

var errLookPath = &lookPathError{}

type lookPathError struct{}

func (*lookPathError) Error() string { return "not found" }

func TestProfilesSaveListAndApply(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "profiles", "save", "Both Ears",
		"--output", "bt:"+earmuffsMAC, "--output", "bt:"+jblMAC, "--default", "--priority", "5"); err != nil {
		t.Fatalf("profiles save: %v", err)
	}
	if !strings.Contains(out.String(), "wrote") || !strings.Contains(out.String(), "profiles apply") {
		t.Errorf("save output = %q", out.String())
	}

	out.Reset()
	if err := run(t, app, "profiles", "list", "--json"); err != nil {
		t.Fatalf("profiles list: %v", err)
	}
	var envelope struct {
		Data struct {
			Profiles []profileView `json:"profiles"`
		} `json:"data"`
	}
	if err := json.Unmarshal(out.Bytes(), &envelope); err != nil {
		t.Fatalf("output is not JSON: %v\n%s", err, out.String())
	}
	if len(envelope.Data.Profiles) != 1 {
		t.Fatalf("profiles = %+v", envelope.Data.Profiles)
	}
	view := envelope.Data.Profiles[0]
	if view.Name != "Both Ears" || !view.Matches || view.Priority != 5 || !view.Default {
		t.Errorf("profile = %+v", view)
	}

	out.Reset()
	if err := run(t, app, "profiles", "active"); err != nil {
		t.Fatalf("profiles active: %v", err)
	}
	if !strings.Contains(out.String(), "no active profile") {
		t.Errorf("active = %q", out.String())
	}

	out.Reset()
	if err := run(t, app, "profiles", "apply", "Both Ears"); err != nil {
		t.Fatalf("profiles apply: %v", err)
	}
	if !strings.Contains(out.String(), "activated profile") {
		t.Errorf("apply output = %q", out.String())
	}

	out.Reset()
	if err := run(t, app, "profiles", "active"); err != nil {
		t.Fatalf("profiles active: %v", err)
	}
	if !strings.Contains(out.String(), "Both Ears") {
		t.Errorf("active = %q", out.String())
	}
}

func TestProfilesRemove(t *testing.T) {
	app, out, _ := newTestApp(t)
	for _, name := range []string{"One", "Two"} {
		if _, err := (profile.Profile{
			Name:    name,
			Outputs: []string{"bt:" + earmuffsMAC, "bt:" + jblMAC},
		}).Save(app.Manager.ProfilesDir); err != nil {
			t.Fatalf("save: %v", err)
		}
	}
	out.Reset()
	if err := run(t, app, "profiles", "remove", "One"); err != nil {
		t.Fatalf("profiles remove: %v", err)
	}
	if !strings.Contains(out.String(), "removed") {
		t.Errorf("output = %q", out.String())
	}
	if profiles, err := app.Manager.Profiles(); err != nil || len(profiles) != 1 || profiles[0].Name != "Two" {
		t.Errorf("profiles = %+v, %v", profiles, err)
	}
	if err := run(t, app, "profiles", "remove", "Nothing"); err == nil {
		t.Error("profiles remove accepted an unknown name")
	}
	out.Reset()
	if err := run(t, app, "profiles", "remove", "--all"); err != nil {
		t.Fatalf("profiles remove --all: %v", err)
	}
	if profiles, err := app.Manager.Profiles(); err != nil || len(profiles) != 0 {
		t.Errorf("profiles = %+v, %v", profiles, err)
	}
}

func TestProfilesSaveReplaces(t *testing.T) {
	app, out, _ := newTestApp(t)
	args := []string{"profiles", "save", "Both", "--output", "bt:" + earmuffsMAC, "--output", "bt:" + jblMAC}
	if err := run(t, app, args...); err != nil {
		t.Fatalf("save: %v", err)
	}
	out.Reset()
	if err := run(t, app, args...); err != nil {
		t.Fatalf("save again: %v", err)
	}
	if !strings.Contains(out.String(), "replaced") {
		t.Errorf("output = %q, want replaced", out.String())
	}
}

func TestProfilesDir(t *testing.T) {
	app, out, _ := newTestApp(t)
	if err := run(t, app, "profiles", "dir"); err != nil {
		t.Fatalf("profiles dir: %v", err)
	}
	if strings.TrimSpace(out.String()) != app.Manager.ProfilesDir {
		t.Errorf("dir = %q, want %q", out.String(), app.Manager.ProfilesDir)
	}
}

func TestDaemonOnce(t *testing.T) {
	app, out, _ := newTestApp(t)
	if _, err := (profile.Profile{
		Name:    "Both Ears",
		Outputs: []string{"bt:" + earmuffsMAC, "bt:" + jblMAC},
	}).Save(app.Manager.ProfilesDir); err != nil {
		t.Fatalf("save profile: %v", err)
	}
	if err := run(t, app, "daemon", "--once"); err != nil {
		t.Fatalf("daemon --once: %v", err)
	}
	if !strings.Contains(out.String(), "activated profile") {
		t.Errorf("output = %q", out.String())
	}
}

func TestProfilesCheckReportsMissingDevices(t *testing.T) {
	app, out, _ := newTestApp(t)
	if _, err := (profile.Profile{
		Name:    "Ghost",
		Outputs: []string{"bt:" + earmuffsMAC, "bt:AA:BB:CC:DD:EE:FF"},
	}).Save(app.Manager.ProfilesDir); err != nil {
		t.Fatalf("save profile: %v", err)
	}
	if err := run(t, app, "profiles", "check"); err != nil {
		t.Fatalf("profiles check: %v", err)
	}
	if !strings.Contains(out.String(), "AA:BB:CC:DD:EE:FF") {
		t.Errorf("output = %q", out.String())
	}
}
