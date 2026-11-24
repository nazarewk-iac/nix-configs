package bluetooth

import "testing"

func TestParseDevices(t *testing.T) {
	out := "Device 60:AB:D2:77:07:56 Earmuffs\n" +
		"Device 38:D5:18:B6:64:93 JBL Endurance Peak 4\n" +
		"Device A4:53:85:96:C4:FD\n" +
		"Controller AA:BB:CC:DD:EE:FF oams\n"
	devices := ParseDevices(out)
	if len(devices) != 3 {
		t.Fatalf("got %d devices, want 3", len(devices))
	}
	if devices[1].Name != "JBL Endurance Peak 4" {
		t.Errorf("name with spaces = %q", devices[1].Name)
	}
	if devices[1].MAC != "38:D5:18:B6:64:93" {
		t.Errorf("mac = %q", devices[1].MAC)
	}
	if devices[2].Name != "A4:53:85:96:C4:FD" {
		t.Errorf("nameless device falls back to the address, got %q", devices[2].Name)
	}
}

func TestParseInfo(t *testing.T) {
	out := `Device 60:AB:D2:77:07:56 (public)
	Name: Earmuffs
	Alias: Earmuffs
	Class: 0x00240418 (2360344)
	Icon: audio-headphones
	Paired: yes
	Bonded: yes
	Connected: no
	UUID: Headset                   (00001108-0000-1000-8000-00805f9b34fb)`
	info := ParseInfo(out)
	if info["Icon"] != "audio-headphones" {
		t.Errorf("icon = %q", info["Icon"])
	}
	if info["Paired"] != "yes" || info["Connected"] != "no" {
		t.Errorf("paired=%q connected=%q", info["Paired"], info["Connected"])
	}
	if info["Name"] != "Earmuffs" {
		t.Errorf("name = %q, want the first occurrence", info["Name"])
	}
}

func TestOfflineAudioDevices(t *testing.T) {
	devices := []Device{
		{MAC: "60:AB:D2:77:07:56", Name: "Earmuffs", Icon: "audio-headphones", Paired: true},
		{MAC: "38:D5:18:B6:64:93", Name: "JBL", Icon: "audio-headset", Paired: true, Connected: true},
		{MAC: "A4:53:85:96:C4:FD", Name: "Gamepad", Icon: "input-gaming", Paired: true},
		{MAC: "AA:BB:CC:DD:EE:FF", Name: "Phone", Icon: "phone", Paired: false},
	}
	offline := OfflineAudioDevices(devices)
	if len(offline) != 1 || offline[0].Name != "Earmuffs" {
		t.Fatalf("offline = %+v, want only Earmuffs", offline)
	}
}
