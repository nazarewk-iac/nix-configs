package pipewire

import (
	"strings"
	"testing"
	"time"
)

const sampleDump = `[
 {"id":62,"type":"PipeWire:Interface:Node","info":{"state":"suspended","props":{
   "media.class":"Audio/Sink","node.name":"alsa_output.pci-0000_07_00.6.analog-stereo",
   "node.description":"Ryzen HD Audio Controller Analog Stereo","device.api":"alsa",
   "device.profile.name":"analog-stereo","priority.driver":1000}}},
 {"id":71,"type":"PipeWire:Interface:Node","info":{"state":"idle","props":{
   "media.class":"Audio/Sink","node.name":"bluez_output.60_AB_D2_77_07_56.1",
   "node.description":"Earmuffs","device.api":"bluez5","device.string":"60:AB:D2:77:07:56",
   "bluetooth.codec":"sbc"}}},
 {"id":82,"type":"PipeWire:Interface:Node","info":{"state":"idle","props":{
   "media.class":"Audio/Sink","node.name":"combined_both","node.description":"Both Ears",
   "kdn.audio.combined":"yes","kdn.audio.members":"a,b"}}},
 {"id":144,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{
   "media.class":"Stream/Output/Audio","node.name":"output.combined_both_a",
   "node.virtual":true,"object.register":false}}},
 {"id":171,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{
   "media.class":"Stream/Output/Audio","node.name":"Tidal HiFi","application.name":"Tidal HiFi",
   "object.register":false}}},
 {"id":53,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{
   "node.id":62,"port.name":"playback_FL"}}},
 {"id":54,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{
   "node.id":62,"port.name":"playback_FR"}}},
 {"id":88,"type":"PipeWire:Interface:Port","info":{"direction":"output","props":{
   "node.id":144,"port.name":"output_FL"}}},
 {"id":89,"type":"PipeWire:Interface:Port","info":{"direction":"output","props":{
   "node.id":144,"port.name":"output_FR"}}},
 {"id":148,"type":"PipeWire:Interface:Link","info":{"output-node-id":144,"output-port-id":88,
   "input-node-id":62,"input-port-id":53,"state":"paused"}}
]`

func TestParseDump(t *testing.T) {
	dump, err := ParseDump(sampleDump)
	if err != nil {
		t.Fatalf("ParseDump: %v", err)
	}
	sinks := dump.Sinks()
	if len(sinks) != 3 {
		t.Fatalf("sinks = %d, want 3", len(sinks))
	}
	alsa, bluetooth, combined := sinks[0], sinks[1], sinks[2]
	if alsa.Kind() != "alsa" || alsa.Detail() != "analog-stereo" {
		t.Errorf("alsa = %q/%q", alsa.Kind(), alsa.Detail())
	}
	if bluetooth.Kind() != "bluetooth" || bluetooth.MAC() != "60:AB:D2:77:07:56" {
		t.Errorf("bluetooth = %q/%q", bluetooth.Kind(), bluetooth.MAC())
	}
	if bluetooth.Detail() != "sbc" {
		t.Errorf("bluetooth detail = %q", bluetooth.Detail())
	}
	if combined.Kind() != "combined" {
		t.Errorf("combined kind = %q", combined.Kind())
	}
	if len(dump.Streams()) != 2 {
		t.Errorf("streams = %d, want 2", len(dump.Streams()))
	}
	if !dump.Internal(dump.Streams()[0]) {
		t.Error("the combine loopback is not marked internal")
	}
	if dump.Internal(dump.Streams()[1]) {
		t.Error("a player stream is marked internal: object.register=false must not count")
	}
	if len(dump.InputPorts(62)) != 2 || len(dump.OutputPorts(144)) != 2 {
		t.Errorf("ports: in=%d out=%d", len(dump.InputPorts(62)), len(dump.OutputPorts(144)))
	}
	if len(dump.Links) != 1 || dump.Links[0].Output != 144 || dump.Links[0].Input != 62 {
		t.Errorf("links = %+v", dump.Links)
	}
}

func TestSinkID(t *testing.T) {
	cases := []struct {
		sink Sink
		want string
	}{
		{Sink{Name: "bluez_output.60_AB_D2_77_07_56.1", Props: map[string]string{
			"device.api": "bluez5", "device.string": "60:AB:D2:77:07:56"}}, "bt:60:AB:D2:77:07:56"},
		{Sink{Name: "bluez_output.38_D5_18_B6_64_93.1", Props: map[string]string{
			"device.api": "bluez5"}}, "bt:38:D5:18:B6:64:93"},
		{Sink{Name: "alsa_output.pci-0000_07_00.6.analog-stereo", Props: map[string]string{
			"device.api": "alsa"}}, "alsa:pci-0000_07_00.6/analog-stereo"},
		{Sink{Name: "alsa_output.usb-Topping_E30-00.analog-stereo", Props: map[string]string{
			"device.api": "alsa"}}, "alsa:usb-Topping_E30-00/analog-stereo"},
		{Sink{Name: "combined_both", Props: map[string]string{
			"kdn.audio.combined": "yes"}}, "join:combined_both"},
		{Sink{Name: "zz_desk", Props: map[string]string{}}, "node:zz_desk"},
	}
	for _, test := range cases {
		if got := test.sink.ID(); got != test.want {
			t.Errorf("ID(%q) = %q, want %q", test.sink.Name, got, test.want)
		}
	}
}

func TestIDForNodeName(t *testing.T) {
	cases := map[string]string{
		"bluez_output.60_AB_D2_77_07_56.1":           "bt:60:AB:D2:77:07:56",
		"alsa_output.pci-0000_07_00.6.analog-stereo": "alsa:pci-0000_07_00.6/analog-stereo",
		"combined_both": "join:combined_both",
		"zz_desk":       "node:zz_desk",
	}
	for name, want := range cases {
		if got := IDForNodeName(name); got != want {
			t.Errorf("IDForNodeName(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestParseDefaultSink(t *testing.T) {
	line := `update: id:0 key:'default.audio.sink' value:'{"name":"alsa_output.pci-0000_07_00.6.analog-stereo"}' type:'Spa:String:JSON'`
	got := parseDefaultSink(line)
	if got != "alsa_output.pci-0000_07_00.6.analog-stereo" {
		t.Errorf("parseDefaultSink = %q", got)
	}
	if parseDefaultSink("nothing here") != "" {
		t.Error("parseDefaultSink invented a name")
	}
}

func TestUnitName(t *testing.T) {
	if got := UnitName("combined_both_ears"); got != "kdn-audio-combined-both-ears.service" {
		t.Errorf("UnitName = %q", got)
	}
}

func TestModuleLine(t *testing.T) {
	spec := JoinSpec{
		SinkName:        "combined_both",
		Title:           "Both Ears",
		Members:         []string{"zz_a", "zz_b"},
		Profile:         "both",
		PreviousDefault: "alsa_output.x",
	}
	line := ModuleLine(spec, time.Date(2026, 11, 24, 12, 0, 0, 0, time.UTC))
	if strings.Contains(line, "\n") {
		t.Fatal("the module line must stay on one line for pw-cli")
	}
	for _, want := range []string{
		"load-module libpipewire-module-combine-stream",
		"combine.mode = sink",
		"node.name = combined_both",
		`node.description = "Both Ears"`,
		`"kdn.audio.combined" = "yes"`,
		`"kdn.audio.members" = "zz_a,zz_b"`,
		`"kdn.audio.created-at" = "2026-11-24T12:00:00Z"`,
		`"kdn.audio.profile" = "both"`,
		`"kdn.audio.previous-default" = "alsa_output.x"`,
		`{ matches = [ { node.name = "zz_a" } ] actions = { create-stream = { } } }`,
		`{ matches = [ { node.name = "zz_b" } ] actions = { create-stream = { } } }`,
	} {
		if !strings.Contains(line, want) {
			t.Errorf("module line lost %q\n%s", want, line)
		}
	}
	if got := strings.Count(line, "load-module"); got != 1 {
		t.Errorf("module line has %d load-module commands", got)
	}
}

func TestMatchChannel(t *testing.T) {
	inputs := []Port{{Name: "playback_FL"}, {Name: "playback_FR"}}
	if port, ok := matchChannel("output_FL", inputs); !ok || port.Name != "playback_FL" {
		t.Errorf("matchChannel = %+v, %v", port, ok)
	}
	if port, ok := matchChannel("output_FR", inputs); !ok || port.Name != "playback_FR" {
		t.Errorf("matchChannel = %+v, %v", port, ok)
	}
	if _, ok := matchChannel("output_LFE", inputs); ok {
		t.Error("matchChannel matched a missing channel")
	}
}

func TestSinkMACFromName(t *testing.T) {
	sink := Sink{Name: "bluez_output.38_D5_18_B6_64_93.1", Props: map[string]string{"device.api": "bluez5"}}
	if got := sink.MAC(); got != "38:D5:18:B6:64:93" {
		t.Errorf("MAC = %q", got)
	}
}
