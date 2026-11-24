// Package bluetooth lists paired Bluetooth devices and connects them through bluetoothctl.
//
// The tool only needs two answers: which paired devices can play audio, and connect one of them.
// bluetoothctl is the binary every BlueZ installation ships; no D-Bus dependency is worth it for
// two queries.
package bluetooth

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// Device is one known Bluetooth device.
type Device struct {
	MAC       string
	Name      string
	Icon      string
	Paired    bool
	Connected bool
}

// Audio reports whether the device can play audio.
func (d Device) Audio() bool {
	return strings.HasPrefix(d.Icon, "audio-")
}

// OfflineAudioDevices returns the paired audio devices that are not connected.
func OfflineAudioDevices(devices []Device) []Device {
	offline := []Device{}
	for _, device := range devices {
		if device.Paired && !device.Connected && device.Audio() {
			offline = append(offline, device)
		}
	}
	return offline
}

// Client is the part of BlueZ that kdn-audio needs. Tests replace it.
type Client interface {
	Devices() ([]Device, error)
	Connect(mac string) error
}

// CLI is the real bluetoothctl-backed client.
type CLI struct {
	// Timeout bounds one connect attempt. Zero means 30 seconds.
	Timeout time.Duration
}

// Devices lists every device that BlueZ knows, with its state.
func (c CLI) Devices() ([]Device, error) {
	out, err := run(20*time.Second, "bluetoothctl", "devices")
	if err != nil {
		return nil, err
	}
	known := ParseDevices(out)
	devices := make([]Device, 0, len(known))
	for _, device := range known {
		info, err := run(20*time.Second, "bluetoothctl", "info", device.MAC)
		if err != nil {
			devices = append(devices, device)
			continue
		}
		details := ParseInfo(info)
		device.Icon = details["Icon"]
		device.Paired = details["Paired"] == "yes"
		device.Connected = details["Connected"] == "yes"
		if name := details["Name"]; name != "" {
			device.Name = name
		}
		devices = append(devices, device)
	}
	return devices, nil
}

// ParseDevices reads the output of `bluetoothctl devices`.
func ParseDevices(out string) []Device {
	devices := []Device{}
	for _, line := range strings.Split(out, "\n") {
		rest, ok := strings.CutPrefix(strings.TrimSpace(line), "Device ")
		if !ok {
			continue
		}
		mac, name, _ := strings.Cut(rest, " ")
		device := Device{MAC: strings.ToUpper(mac), Name: strings.TrimSpace(name)}
		if device.Name == "" {
			device.Name = device.MAC
		}
		devices = append(devices, device)
	}
	return devices
}

// ParseInfo reads the `Key: value` lines of `bluetoothctl info`.
func ParseInfo(out string) map[string]string {
	details := map[string]string{}
	for _, line := range strings.Split(out, "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), ":")
		if !ok {
			continue
		}
		if _, seen := details[key]; seen {
			continue
		}
		details[strings.TrimSpace(key)] = strings.TrimSpace(value)
	}
	return details
}

// Connect asks BlueZ to connect the device and waits for the attempt to finish.
func (c CLI) Connect(mac string) error {
	timeout := c.Timeout
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	out, err := run(timeout, "bluetoothctl", "connect", mac)
	if err != nil {
		return err
	}
	// bluetoothctl reports a refusal on standard output with exit status 0.
	for _, failure := range []string{"Failed to connect", "not available", "Connection attempt failed"} {
		if strings.Contains(out, failure) {
			return fmt.Errorf("bluetoothctl connect %s: %s", mac, strings.TrimSpace(out))
		}
	}
	return nil
}

func run(timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	command := exec.CommandContext(ctx, name, args...)
	var stdout, stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	err := command.Run()
	if ctx.Err() != nil {
		return stdout.String(), fmt.Errorf("%s %s: timed out after %s", name, strings.Join(args, " "), timeout)
	}
	if err != nil {
		message := strings.TrimSpace(stderr.String())
		if message == "" {
			message = err.Error()
		}
		return stdout.String(), fmt.Errorf("%s %s: %s", name, strings.Join(args, " "), message)
	}
	return stdout.String(), nil
}
