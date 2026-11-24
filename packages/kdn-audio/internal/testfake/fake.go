// Package testfake provides in-memory PipeWire and Bluetooth clients for tests.
package testfake

import (
	"strings"
	"time"

	"kdn-audio/internal/bluetooth"
	"kdn-audio/internal/pipewire"
)

// Pipewire is an in-memory graph client.
type Pipewire struct {
	SinksList []pipewire.Sink
	Default   string

	Created         []pipewire.JoinSpec
	Removed         []string
	SetDefaultCalls []string
	Moved           []string
	MoveCount       int
	CreateErr       error
	RemoveErr       error
	NextID          int
}

// Sinks returns the outputs.
func (p *Pipewire) Sinks() ([]pipewire.Sink, error) {
	sinks := make([]pipewire.Sink, len(p.SinksList))
	copy(sinks, p.SinksList)
	return sinks, nil
}

// DefaultSink returns the default output.
func (p *Pipewire) DefaultSink() (string, error) { return p.Default, nil }

// SetDefaultSink records and applies a new default output.
func (p *Pipewire) SetDefaultSink(name string) error {
	p.SetDefaultCalls = append(p.SetDefaultCalls, name)
	p.Default = name
	return nil
}

// CreateJoin records the spec and adds the node that the module would create.
func (p *Pipewire) CreateJoin(spec pipewire.JoinSpec) error {
	if p.CreateErr != nil {
		return p.CreateErr
	}
	p.Created = append(p.Created, spec)
	props := map[string]string{
		pipewire.PropCombined: "yes",
		pipewire.PropMembers:  strings.Join(spec.Members, ","),
		pipewire.PropCreated:  time.Now().UTC().Format(time.RFC3339),
	}
	if spec.Profile != "" {
		props[pipewire.PropProfile] = spec.Profile
	}
	if spec.PreviousDefault != "" {
		props[pipewire.PropPreviousDefault] = spec.PreviousDefault
	}
	p.NextID++
	p.SinksList = append(p.SinksList, pipewire.Sink{
		NodeID:      1000 + p.NextID,
		Name:        spec.SinkName,
		Description: spec.Title,
		State:       "IDLE",
		Props:       props,
	})
	return nil
}

// RemoveJoin removes the node that the module created.
func (p *Pipewire) RemoveJoin(sinkName string) error {
	if p.RemoveErr != nil {
		return p.RemoveErr
	}
	p.Removed = append(p.Removed, sinkName)
	kept := make([]pipewire.Sink, 0, len(p.SinksList))
	for _, sink := range p.SinksList {
		if sink.Name != sinkName {
			kept = append(kept, sink)
		}
	}
	p.SinksList = kept
	// The session manager re-picks a default the moment its default output disappears.
	if p.Default == sinkName {
		for _, sink := range p.SinksList {
			if sink.Props[pipewire.PropCombined] != "yes" {
				p.Default = sink.Name
				break
			}
		}
	}
	return nil
}

// MoveStreams records a stream move.
func (p *Pipewire) MoveStreams(sinkName string) (int, error) {
	p.Moved = append(p.Moved, sinkName)
	return p.MoveCount, nil
}

// Bluetooth is an in-memory Bluetooth client.
type Bluetooth struct {
	DeviceList []bluetooth.Device
	// OnConnect runs after a successful connect. Tests use it to expose the new output.
	OnConnect func(mac string)
	// ConnectErr makes every connect attempt fail.
	ConnectErr error
	Connected  []string
}

// Devices returns the known devices.
func (b *Bluetooth) Devices() ([]bluetooth.Device, error) {
	devices := make([]bluetooth.Device, len(b.DeviceList))
	copy(devices, b.DeviceList)
	return devices, nil
}

// Connect records and applies one connect.
func (b *Bluetooth) Connect(mac string) error {
	if b.ConnectErr != nil {
		return b.ConnectErr
	}
	b.Connected = append(b.Connected, mac)
	if b.OnConnect != nil {
		b.OnConnect(mac)
	}
	return nil
}

// Sink is a plain output.
func Sink(name, description, api string) pipewire.Sink {
	return pipewire.Sink{
		NodeID:      len(name) + 1,
		Name:        name,
		Description: description,
		State:       "RUNNING",
		Props:       map[string]string{"device.api": api},
	}
}

// BTSink is a Bluetooth output with its real node name.
func BTSink(mac, description string) pipewire.Sink {
	nodeName := "bluez_output." + strings.ReplaceAll(mac, ":", "_") + ".1"
	nodeID := 500
	for _, r := range mac {
		nodeID += int(r)
	}
	return pipewire.Sink{
		NodeID:      nodeID,
		Name:        nodeName,
		Description: description,
		State:       "RUNNING",
		Props: map[string]string{
			"device.api":         "bluez5",
			"device.string":      mac,
			"api.bluez5.address": mac,
		},
	}
}

// AudioDevice is a paired, offline Bluetooth audio device that a fake connect can bring online.
func AudioDevice(mac, name string) bluetooth.Device {
	return bluetooth.Device{MAC: mac, Name: name, Icon: "audio-headphones", Paired: true}
}
