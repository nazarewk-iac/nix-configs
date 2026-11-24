package audio

import (
	"context"
	"strings"
	"testing"
	"time"

	"kdn-audio/internal/bluetooth"
	"kdn-audio/internal/combine"
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

func baseGraph() *testfake.Pipewire {
	return &testfake.Pipewire{
		SinksList: []pipewire.Sink{
			testfake.BTSink(earmuffsMAC, "Earmuffs"),
			testfake.BTSink(jblMAC, "JBL Endurance Peak 4"),
			testfake.Sink(alsaSink, "Ryzen HD Audio Controller Analog Stereo", "alsa"),
		},
		Default: alsaSink,
	}
}

func newManager(p *testfake.Pipewire, b *testfake.Bluetooth) *Manager {
	manager := New(p, b)
	manager.Now = func() time.Time { return fixedNow }
	manager.ProfilesDir = ""
	return manager
}

func TestCreateJoinsOutputs(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})

	created, err := m.Create(CreateOptions{
		Title:       "Both Ears",
		Members:     []string{"Earmuffs", "JBL Endurance Peak 4"},
		MakeDefault: true,
		MoveStreams: true,
	})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if created.Group.SinkName != "combined_both_ears" {
		t.Errorf("sink name = %q", created.Group.SinkName)
	}
	if created.Group.Title != "Both Ears" {
		t.Errorf("title = %q", created.Group.Title)
	}
	if len(created.MemberTitles) != 2 || created.MemberTitles[0] != "Earmuffs" {
		t.Errorf("member titles = %v", created.MemberTitles)
	}
	if !created.Group.Default || p.Default != "combined_both_ears" {
		t.Errorf("default = %q, want combined_both_ears", p.Default)
	}
	if len(p.Created) != 1 || len(p.Created[0].Members) != 2 {
		t.Fatalf("created specs = %+v", p.Created)
	}
	if p.Created[0].PreviousDefault != alsaSink {
		t.Errorf("previous default = %q", p.Created[0].PreviousDefault)
	}
	if len(p.Moved) != 1 {
		t.Errorf("moved = %v", p.Moved)
	}
}

func TestCreateLeavesRoutingAlone(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	created, err := m.Create(CreateOptions{Title: "Both Ears", Members: []string{"Earmuffs", "JBL"}})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if created.Group.Default || p.Default != alsaSink {
		t.Errorf("default = %q, want it left alone", p.Default)
	}
	if len(p.Moved) != 0 || created.MovedStreams != 0 {
		t.Errorf("moved = %v / %d, want none", p.Moved, created.MovedStreams)
	}
}

func TestCreateBuildsNameFromMembers(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	created, err := m.Create(CreateOptions{Members: []string{"Earmuffs", "JBL"}})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if created.Group.Title != "Earmuffs + JBL Endurance Peak 4" {
		t.Errorf("title = %q", created.Group.Title)
	}
	if created.Group.SinkName != "combined_earmuffs_jbl_endurance_peak_4" {
		t.Errorf("sink name = %q", created.Group.SinkName)
	}
}

func TestCreateRejectsJoinedMember(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	if _, err := m.Create(CreateOptions{Title: "First", Members: []string{"Earmuffs", "JBL"}}); err != nil {
		t.Fatalf("first create: %v", err)
	}
	_, err := m.Create(CreateOptions{Title: "Second", Members: []string{"First", "Earmuffs"}})
	if err == nil || !strings.Contains(err.Error(), "joined output") {
		t.Fatalf("second create = %v, want a rejection of a joined member", err)
	}
}

func TestCreateWarnsAboutTheHeadsetProfile(t *testing.T) {
	p := baseGraph()
	p.SinksList[1].Props["device.profile.name"] = "headset-head-unit"
	m := newManager(p, &testfake.Bluetooth{})
	created, err := m.Create(CreateOptions{Title: "Call", Members: []string{"Earmuffs", "JBL"}})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if len(created.Warnings) != 1 || !strings.Contains(created.Warnings[0], "a2dp") {
		t.Fatalf("warnings = %v", created.Warnings)
	}
}

func TestCreateReplacesTheSameName(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	options := CreateOptions{Title: "Both Ears", Members: []string{"Earmuffs", "JBL"}}
	if _, err := m.Create(options); err != nil {
		t.Fatalf("first create: %v", err)
	}
	if _, err := m.Create(options); err != nil {
		t.Fatalf("second create: %v", err)
	}
	if len(p.Created) != 2 || len(p.Removed) != 1 {
		t.Errorf("created = %d, removed = %v", len(p.Created), p.Removed)
	}
	groups, err := m.Groups()
	if err != nil {
		t.Fatalf("Groups: %v", err)
	}
	if len(groups) != 1 {
		t.Errorf("groups = %d, want 1", len(groups))
	}
}

func TestCreateInheritsTheDefaultWhenReplacing(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	options := CreateOptions{Title: "Both Ears", Members: []string{"Earmuffs", "JBL"}, MakeDefault: true}
	if _, err := m.Create(options); err != nil {
		t.Fatalf("first create: %v", err)
	}
	options.MakeDefault = false
	created, err := m.Create(options)
	if err != nil {
		t.Fatalf("second create: %v", err)
	}
	if p.Default != "combined_both_ears" {
		t.Errorf("default = %q, want the replaced join to keep it", p.Default)
	}
	if !created.InheritedDefault {
		t.Error("InheritedDefault = false, want true")
	}
}

func TestCreateNeedsTwoOutputs(t *testing.T) {
	m := newManager(baseGraph(), &testfake.Bluetooth{})
	if _, err := m.Create(CreateOptions{Title: "One", Members: []string{"Earmuffs"}}); err == nil {
		t.Fatal("Create accepted one member")
	}
	if _, err := m.Create(CreateOptions{Title: "Same", Members: []string{"Earmuffs", "Earmuffs"}}); err == nil {
		t.Fatal("Create accepted the same output twice")
	}
}

func TestCreateWithConnect(t *testing.T) {
	p := &testfake.Pipewire{
		SinksList: []pipewire.Sink{testfake.Sink(alsaSink, "Speakers", "alsa")},
		Default:   alsaSink,
	}
	names := map[string]string{earmuffsMAC: "Earmuffs", jblMAC: "JBL Endurance Peak 4"}
	bt := &testfake.Bluetooth{
		DeviceList: []bluetooth.Device{
			testfake.AudioDevice(earmuffsMAC, "Earmuffs"),
			testfake.AudioDevice(jblMAC, "JBL Endurance Peak 4"),
		},
	}
	bt.OnConnect = func(mac string) {
		p.SinksList = append(p.SinksList, testfake.BTSink(mac, names[mac]))
	}
	m := newManager(p, bt)

	created, err := m.Create(CreateOptions{
		Title:   "Both Ears",
		Members: []string{"Earmuffs", "JBL"},
		Connect: true,
	})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if len(bt.Connected) != 2 {
		t.Fatalf("connected = %v, want both devices", bt.Connected)
	}
	if len(created.Group.Members) != 2 {
		t.Errorf("members = %v", created.Group.Members)
	}
}

func TestConnectReportsFailures(t *testing.T) {
	bt := &testfake.Bluetooth{
		DeviceList: []bluetooth.Device{testfake.AudioDevice(earmuffsMAC, "Earmuffs")},
		ConnectErr: errConnect,
	}
	m := newManager(baseGraph(), bt)
	results := m.Connect(nil)
	if len(results) != 1 || results[0].Err == nil {
		t.Fatalf("results = %+v, want one failure", results)
	}
}

var errConnect = &connectError{}

type connectError struct{}

func (*connectError) Error() string { return "simulated connect failure" }

func TestResolveSinkPrecedence(t *testing.T) {
	p := baseGraph()
	p.SinksList = append(p.SinksList, testfake.BTSink("AA:BB:CC:DD:EE:FF", "Earmuffs Old"))
	m := newManager(p, &testfake.Bluetooth{})

	sinks, err := m.ResolveSinks([]string{"Earmuffs"})
	if err != nil {
		t.Fatalf("ResolveSinks: %v", err)
	}
	if sinks[0].Name != earmuffs {
		t.Errorf("exact description lost: %q", sinks[0].Name)
	}
	// An id picks the same output as its name.
	if sinks, err := m.ResolveSinks([]string{"bt:" + earmuffsMAC}); err != nil || sinks[0].Name != earmuffs {
		t.Errorf("id lookup = %+v, %v", sinks, err)
	}
	// The ALSA id round-trips.
	if sinks, err := m.ResolveSinks([]string{"alsa:pci-0000_07_00.6/analog-stereo"}); err != nil || sinks[0].Name != alsaSink {
		t.Errorf("alsa id lookup = %+v, %v", sinks, err)
	}
	if _, err := m.ResolveSinks([]string{"armuff"}); err == nil || !strings.Contains(err.Error(), "matches 2") {
		t.Errorf("ambiguous pattern = %v, want a two-candidate error", err)
	}
	if _, err := m.ResolveSinks([]string{"Nothing"}); err == nil {
		t.Error("ResolveSinks accepted an unknown output")
	}
}

func TestUnlinkRestoresDefault(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	if _, err := m.Create(CreateOptions{Title: "Both Ears", Members: []string{"Earmuffs", "JBL"}, MakeDefault: true}); err != nil {
		t.Fatalf("Create: %v", err)
	}
	title, err := m.Unlink("Both Ears")
	if err != nil {
		t.Fatalf("Unlink: %v", err)
	}
	if title != "Both Ears" {
		t.Errorf("title = %q", title)
	}
	if len(p.Removed) != 1 {
		t.Errorf("removed = %v", p.Removed)
	}
	if p.Default != alsaSink {
		t.Errorf("default = %q, want the previous default", p.Default)
	}
}

func TestUnlinkAllSkipsADeadPreviousDefault(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	if _, err := m.Create(CreateOptions{Title: "First", Members: []string{"Earmuffs", "JBL"}, MakeDefault: true}); err != nil {
		t.Fatalf("first create: %v", err)
	}
	if _, err := m.Create(CreateOptions{Title: "Second", Members: []string{"Earmuffs", "JBL"}, MakeDefault: true}); err != nil {
		t.Fatalf("second create: %v", err)
	}
	if p.Default != "combined_second" {
		t.Fatalf("default = %q, want combined_second", p.Default)
	}
	p.SetDefaultCalls = nil
	titles, err := m.UnlinkAll()
	if err != nil {
		t.Fatalf("UnlinkAll: %v", err)
	}
	if len(titles) != 2 {
		t.Errorf("titles = %v", titles)
	}
	for _, name := range p.SetDefaultCalls {
		if name == "combined_first" {
			t.Errorf("restored the default to a joined output that was just removed: %v", p.SetDefaultCalls)
		}
	}
}

func TestUnlinkUnknown(t *testing.T) {
	m := newManager(baseGraph(), &testfake.Bluetooth{})
	if _, err := m.Unlink("Nothing"); err == nil || !strings.Contains(err.Error(), "no joined output") {
		t.Fatalf("Unlink = %v, want a no-joined-output error", err)
	}
}

func TestUnlinkAllWithoutGroups(t *testing.T) {
	m := newManager(baseGraph(), &testfake.Bluetooth{})
	titles, err := m.UnlinkAll()
	if err != nil {
		t.Fatalf("UnlinkAll: %v", err)
	}
	if len(titles) != 0 {
		t.Errorf("titles = %v", titles)
	}
}

func TestGroupsReportsMissingMembers(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	if _, err := m.Create(CreateOptions{Title: "Both Ears", Members: []string{"Earmuffs", "JBL"}}); err != nil {
		t.Fatalf("Create: %v", err)
	}
	kept := make([]pipewire.Sink, 0, len(p.SinksList))
	for _, sink := range p.SinksList {
		if sink.Name != jbl {
			kept = append(kept, sink)
		}
	}
	p.SinksList = kept
	groups, err := m.Groups()
	if err != nil {
		t.Fatalf("Groups: %v", err)
	}
	if missing := combine.MissingMembers(groups[0], p.SinksList); len(missing) != 1 || missing[0] != jbl {
		t.Errorf("missing = %v", missing)
	}
}

func saveProfile(t *testing.T, dir string, p profile.Profile) {
	t.Helper()
	if _, err := p.Save(dir); err != nil {
		t.Fatalf("save profile: %v", err)
	}
}

func TestAutoActivateAppliesTheMatchingProfile(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	m.ProfilesDir = t.TempDir()
	saveProfile(t, m.ProfilesDir, profile.Profile{
		Name:    "Both Ears",
		Outputs: []string{"bt:" + earmuffsMAC, "bt:" + jblMAC},
	})

	activation, err := m.AutoActivate()
	if err != nil {
		t.Fatalf("AutoActivate: %v", err)
	}
	if !activation.Created || activation.Profile != "Both Ears" {
		t.Fatalf("activation = %+v", activation)
	}
	group, ok, err := m.ActiveProfile()
	if err != nil || !ok {
		t.Fatalf("ActiveProfile = %+v, %v", group, err)
	}
	if group.Profile != "Both Ears" || len(group.Members) != 2 {
		t.Errorf("group = %+v", group)
	}
}

func TestAutoActivateRemovesAProfileJoinWhenTheMixBreaks(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	m.ProfilesDir = t.TempDir()
	saveProfile(t, m.ProfilesDir, profile.Profile{
		Name:    "Both Ears",
		Outputs: []string{"bt:" + earmuffsMAC, "bt:" + jblMAC},
	})
	if _, err := m.AutoActivate(); err != nil {
		t.Fatalf("first pass: %v", err)
	}

	// The earbuds go away.
	kept := make([]pipewire.Sink, 0, len(p.SinksList))
	for _, sink := range p.SinksList {
		if sink.Name != jbl {
			kept = append(kept, sink)
		}
	}
	p.SinksList = kept

	activation, err := m.AutoActivate()
	if err != nil {
		t.Fatalf("second pass: %v", err)
	}
	if activation.Created || len(activation.Removed) != 1 {
		t.Fatalf("activation = %+v", activation)
	}
	if groups, err := m.Groups(); err != nil || len(groups) != 0 {
		t.Errorf("groups = %+v, %v", groups, err)
	}
}

func TestAutoActivateKeepsManualJoins(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	m.ProfilesDir = t.TempDir()
	if _, err := m.Create(CreateOptions{Title: "Manual", Members: []string{"Earmuffs", "JBL"}}); err != nil {
		t.Fatalf("Create: %v", err)
	}
	activation, err := m.AutoActivate()
	if err != nil {
		t.Fatalf("AutoActivate: %v", err)
	}
	if activation.Created || len(activation.Removed) != 0 {
		t.Fatalf("activation = %+v", activation)
	}
	groups, err := m.Groups()
	if err != nil || len(groups) != 1 || groups[0].Title != "Manual" {
		t.Errorf("manual join was touched: %+v, %v", groups, err)
	}
}

func TestAutoActivatePrefersHigherPriority(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	m.ProfilesDir = t.TempDir()
	saveProfile(t, m.ProfilesDir, profile.Profile{
		Name: "Broad", Priority: 1, Outputs: []string{"bt:" + earmuffsMAC, "alsa:pci-0000_07_00.6/analog-stereo"},
	})
	saveProfile(t, m.ProfilesDir, profile.Profile{
		Name: "Narrow", Priority: 5, Outputs: []string{"Earmuffs", "JBL"},
	})
	activation, err := m.AutoActivate()
	if err != nil {
		t.Fatalf("AutoActivate: %v", err)
	}
	if activation.Profile != "Narrow" {
		t.Errorf("chose %q, want the higher priority profile", activation.Profile)
	}
}

func TestProfileAbsentBlocks(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	m.ProfilesDir = t.TempDir()
	saveProfile(t, m.ProfilesDir, profile.Profile{
		Name:    "Both Ears",
		Outputs: []string{"bt:" + earmuffsMAC, "bt:" + jblMAC},
		Absent:  []string{alsaSink},
	})
	activation, err := m.AutoActivate()
	if err != nil {
		t.Fatalf("AutoActivate: %v", err)
	}
	if activation.Created {
		t.Errorf("a blocked profile was applied: %+v", activation)
	}
}

func TestApplyProfileRefusesAMissingDevice(t *testing.T) {
	p := baseGraph()
	m := newManager(p, &testfake.Bluetooth{})
	m.ProfilesDir = t.TempDir()
	missing := "bt:AA:BB:CC:DD:EE:FF"
	saveProfile(t, m.ProfilesDir, profile.Profile{
		Name:    "Missing",
		Outputs: []string{"bt:" + earmuffsMAC, missing},
	})
	if _, err := m.ApplyProfile("Missing"); err == nil {
		t.Fatal("ApplyProfile activated a profile whose device is absent")
	}
}

func TestDaemonStopsOnContext(t *testing.T) {
	m := newManager(baseGraph(), &testfake.Bluetooth{})
	m.ProfilesDir = t.TempDir()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- m.Daemon(ctx, 10*time.Millisecond) }()
	time.Sleep(30 * time.Millisecond)
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Daemon: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("Daemon did not stop when its context was cancelled")
	}
}
