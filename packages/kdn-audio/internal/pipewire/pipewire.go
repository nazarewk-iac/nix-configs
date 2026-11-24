// Package pipewire reads and changes the PipeWire graph through its own tools.
//
// Nothing here goes through the PulseAudio compatibility layer: state comes from `pw-dump`, the
// default output from the `default` metadata, and a joined output is a native
// `libpipewire-module-combine-stream` instance hosted by a transient systemd user service.
package pipewire

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Sink is one audio output node.
type Sink struct {
	NodeID      int
	Name        string
	Description string
	State       string
	Props       map[string]string
}

// Kind classifies the sink by its origin.
func (s Sink) Kind() string {
	switch {
	case s.Props["kdn.audio.combined"] == "yes":
		return "combined"
	case s.Props["device.api"] == "bluez5":
		return "bluetooth"
	case s.Props["device.api"] == "alsa":
		return "alsa"
	default:
		return "virtual"
	}
}

// Detail returns the codec, profile or card name of the sink, or an empty string.
func (s Sink) Detail() string {
	keys := []string{"device.profile.description", "device.profile.name"}
	switch s.Kind() {
	case "bluetooth":
		keys = append([]string{"bluetooth.codec", "api.bluez5.codec"}, keys...)
	case "alsa":
		keys = append(keys, "alsa.card_name")
	}
	for _, key := range keys {
		if value := s.Props[key]; value != "" {
			return value
		}
	}
	return ""
}

// IDForNodeName builds the id of a node that is not in the graph right now.
//
// It applies the same rules as Sink.ID, so a missing member can be named by the id that a
// profile would use for it.
func IDForNodeName(name string) string {
	if rest, ok := strings.CutPrefix(name, "bluez_output."); ok {
		if mac := NormalizeMAC(strings.TrimSuffix(rest, ".1")); mac != "" {
			return "bt:" + mac
		}
	}
	if card, profile, ok := splitALSA(name); ok {
		return "alsa:" + card + "/" + profile
	}
	if strings.HasPrefix(name, "combined_") {
		return "join:" + name
	}
	return "node:" + name
}

// ID returns the stable identifier of the output, which is what a profile stores.
//
// A Bluetooth output is identified by its address, an ALSA output by its card and profile, and
// anything else by its node name. The node id is never used: PipeWire hands out a new one on
// every start, so it cannot name a device in a profile.
func (s Sink) ID() string {
	switch s.Kind() {
	case "bluetooth":
		if mac := s.MAC(); mac != "" {
			return "bt:" + mac
		}
	case "alsa":
		if card, profile, ok := splitALSA(s.Name); ok {
			return "alsa:" + card + "/" + profile
		}
	}
	return IDForNodeName(s.Name)
}

// MAC returns the Bluetooth address of the sink, or an empty string.
func (s Sink) MAC() string {
	if s.Props["device.api"] != "bluez5" {
		return ""
	}
	for _, key := range []string{"api.bluez5.address", "device.string", "device.address"} {
		if mac := NormalizeMAC(s.Props[key]); mac != "" {
			return mac
		}
	}
	name := strings.TrimPrefix(s.Name, "bluez_output.")
	name = strings.TrimSuffix(name, ".1")
	return NormalizeMAC(name)
}

// NormalizeMAC returns an upper-case, colon-separated Bluetooth address, or an empty string.
func NormalizeMAC(raw string) string {
	raw = strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(raw), "_", ":"))
	if len(raw) != 17 {
		return ""
	}
	for i, r := range raw {
		if i%3 == 2 {
			if r != ':' {
				return ""
			}
			continue
		}
		if !strings.ContainsRune("0123456789ABCDEF", r) {
			return ""
		}
	}
	return raw
}

// splitALSA splits a sink name into its card and profile.
func splitALSA(name string) (string, string, bool) {
	rest, ok := strings.CutPrefix(name, "alsa_output.")
	if !ok {
		return "", "", false
	}
	index := strings.LastIndex(rest, ".")
	if index <= 0 {
		return "", "", false
	}
	return rest[:index], rest[index+1:], true
}

// JoinSpec is one joined output to create.
type JoinSpec struct {
	SinkName        string
	Title           string
	Members         []string
	Profile         string
	PreviousDefault string
}

// Client is the part of the graph that kdn-audio needs. Tests replace it.
type Client interface {
	Sinks() ([]Sink, error)
	DefaultSink() (string, error)
	SetDefaultSink(name string) error
	CreateJoin(spec JoinSpec) error
	RemoveJoin(sinkName string) error
	MoveStreams(sinkName string) (int, error)
}

// CLI is the real pw-dump/pw-cli/pw-metadata-backed client.
type CLI struct{}

func run(name string, args ...string) (string, error) {
	command := exec.Command(name, args...)
	var stdout, stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		message := strings.TrimSpace(stderr.String())
		if message == "" {
			message = strings.TrimSpace(stdout.String())
		}
		if message == "" {
			message = err.Error()
		}
		return stdout.String(), fmt.Errorf("%s %s: %s", name, strings.Join(args, " "), message)
	}
	return stdout.String(), nil
}

// Sinks lists every audio output in the graph.
func (CLI) Sinks() ([]Sink, error) {
	out, err := run("pw-dump")
	if err != nil {
		return nil, err
	}
	dump, err := ParseDump(out)
	if err != nil {
		return nil, err
	}
	return dump.Sinks(), nil
}

// DefaultSink returns the name of the default output.
func (CLI) DefaultSink() (string, error) {
	out, err := run("pw-metadata", "-n", "default", "0", "default.audio.sink")
	if err != nil {
		return "", err
	}
	return parseDefaultSink(out), nil
}

var metadataValue = regexp.MustCompile(`value:'(.*)' type:`)

func parseDefaultSink(out string) string {
	matches := metadataValue.FindStringSubmatch(out)
	if len(matches) < 2 {
		return ""
	}
	var value struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal([]byte(matches[1]), &value); err != nil {
		return ""
	}
	return value.Name
}

// SetDefaultSink makes name the default output.
func (CLI) SetDefaultSink(name string) error {
	value := fmt.Sprintf(`{"name":%q}`, name)
	_, err := run("pw-metadata", "-n", "default", "0", "default.audio.sink", value, "Spa:String:JSON")
	return err
}

// CreateJoin starts the transient service that hosts one combine-stream module.
func (CLI) CreateJoin(spec JoinSpec) error {
	unit := UnitName(spec.SinkName)
	_ = exec.Command("systemctl", "--user", "stop", unit).Run()
	self, err := os.Executable()
	if err != nil {
		self = "kdn-audio"
	}
	args := []string{
		"--user",
		"--unit", strings.TrimSuffix(unit, ".service"),
		"--collect",
		"--quiet",
		"--description", "kdn-audio joined output: " + spec.Title,
		self, "host",
		"--sink-name", spec.SinkName,
		"--title", spec.Title,
	}
	for _, member := range spec.Members {
		args = append(args, "--member", member)
	}
	if spec.Profile != "" {
		args = append(args, "--profile", spec.Profile)
	}
	if out, err := exec.Command("systemd-run", args...).CombinedOutput(); err != nil {
		message := strings.TrimSpace(string(out))
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("systemd-run %s: %s", unit, message)
	}
	return nil
}

// RemoveJoin stops the service that hosts the joined output.
func (CLI) RemoveJoin(sinkName string) error {
	unit := UnitName(sinkName)
	if out, err := exec.Command("systemctl", "--user", "stop", unit).CombinedOutput(); err != nil {
		message := strings.TrimSpace(string(out))
		if strings.Contains(message, "not loaded") {
			return nil
		}
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("systemctl --user stop %s: %s", unit, message)
	}
	return nil
}

// UnitName is the deterministic systemd unit name of a joined output.
func UnitName(sinkName string) string {
	var builder strings.Builder
	for _, r := range sinkName {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-':
			builder.WriteRune(r)
		default:
			builder.WriteByte('-')
		}
	}
	return "kdn-audio-" + builder.String() + ".service"
}

// MoveStreams moves every playing stream to the sink and returns how many moved.
//
// PipeWire moves a stream by relinking its output ports. The module streams of a joined output
// are skipped: relinking those would rewire the join itself.
func (c CLI) MoveStreams(sinkName string) (int, error) {
	out, err := run("pw-dump")
	if err != nil {
		return 0, err
	}
	dump, err := ParseDump(out)
	if err != nil {
		return 0, err
	}
	target, ok := dump.Sink(sinkName)
	if !ok {
		return 0, fmt.Errorf("no output named %q", sinkName)
	}
	targetPorts := dump.InputPorts(target.NodeID)
	moved := 0
	for _, stream := range dump.Streams() {
		if dump.Internal(stream) {
			continue
		}
		ports := dump.OutputPorts(stream.ID)
		if len(ports) == 0 {
			continue
		}
		if err := dump.Relink(stream.ID, ports, target.NodeID, targetPorts); err != nil {
			return moved, err
		}
		moved++
	}
	return moved, nil
}

// Node is one object of the graph, narrowed to what kdn-audio reads.
type Node struct {
	ID    int
	Type  string
	State string
	Props map[string]string
}

// Dump is a parsed `pw-dump` output.
type Dump struct {
	Objects []Node
	Links   []Link
	// Ports by node id.
	Ports map[int][]Port
}

// Link is one graph link.
type Link struct {
	ID      int
	Output  int
	Input   int
	OutPort int
	InPort  int
}

// Port is one node port.
type Port struct {
	ID        int
	NodeID    int
	Direction string
	Name      string
}

type rawDump struct {
	ID   int    `json:"id"`
	Type string `json:"type"`
	Info struct {
		State      string         `json:"state"`
		Direction  string         `json:"direction"`
		Props      map[string]any `json:"props"`
		OutputNode int            `json:"output-node-id"`
		OutputPort int            `json:"output-port-id"`
		InputNode  int            `json:"input-node-id"`
		InputPort  int            `json:"input-port-id"`
	} `json:"info"`
}

// ParseDump reads the JSON that `pw-dump` prints.
func ParseDump(out string) (*Dump, error) {
	var raw []rawDump
	if err := json.Unmarshal([]byte(out), &raw); err != nil {
		return nil, fmt.Errorf("parse pw-dump JSON: %w", err)
	}
	dump := &Dump{Ports: map[int][]Port{}}
	for _, item := range raw {
		props := map[string]string{}
		for key, value := range item.Info.Props {
			props[key] = stringify(value)
		}
		switch item.Type {
		case "PipeWire:Interface:Node":
			dump.Objects = append(dump.Objects, Node{
				ID:    item.ID,
				Type:  props["media.class"],
				State: item.Info.State,
				Props: props,
			})
		case "PipeWire:Interface:Link":
			dump.Links = append(dump.Links, Link{
				ID:      item.ID,
				Output:  item.Info.OutputNode,
				Input:   item.Info.InputNode,
				OutPort: item.Info.OutputPort,
				InPort:  item.Info.InputPort,
			})
		case "PipeWire:Interface:Port":
			nodeID, err := strconv.Atoi(props["node.id"])
			if err != nil {
				continue
			}
			port := Port{
				ID:        item.ID,
				NodeID:    nodeID,
				Direction: strings.ToLower(item.Info.Direction),
				Name:      props["port.name"],
			}
			dump.Ports[nodeID] = append(dump.Ports[nodeID], port)
		}
	}
	return dump, nil
}

func stringify(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	case bool:
		return strconv.FormatBool(typed)
	default:
		return ""
	}
}

// Sinks returns every output node.
func (d *Dump) Sinks() []Sink {
	sinks := []Sink{}
	for _, node := range d.Objects {
		if node.Type != "Audio/Sink" {
			continue
		}
		sinks = append(sinks, Sink{
			NodeID:      node.ID,
			Name:        node.Props["node.name"],
			Description: node.Props["node.description"],
			State:       strings.ToUpper(node.State),
			Props:       node.Props,
		})
	}
	sort.SliceStable(sinks, func(i, j int) bool { return sinks[i].NodeID < sinks[j].NodeID })
	return sinks
}

// Sink finds one output by node name.
func (d *Dump) Sink(name string) (Sink, bool) {
	for _, sink := range d.Sinks() {
		if sink.Name == name {
			return sink, true
		}
	}
	return Sink{}, false
}

// Streams returns every playback stream node.
func (d *Dump) Streams() []Node {
	streams := []Node{}
	for _, node := range d.Objects {
		if node.Type == "Stream/Output/Audio" {
			streams = append(streams, node)
		}
	}
	return streams
}

// Internal reports whether the stream belongs to a combine module.
//
// PipeWire publishes those as ordinary stream nodes, marked by `node.virtual` and a
// `combine-` node group; moving one would rewire the join itself. `object.register` is not a
// usable marker: pw-dump reports false for every client stream, including a player.
func (d *Dump) Internal(node Node) bool {
	if node.Props["node.virtual"] == "true" {
		return true
	}
	return strings.HasPrefix(node.Props["node.group"], "combine-")
}

// InputPorts returns the input ports of a node.
func (d *Dump) InputPorts(nodeID int) []Port {
	return d.ports(nodeID, "input")
}

// OutputPorts returns the output ports of a node.
func (d *Dump) OutputPorts(nodeID int) []Port {
	return d.ports(nodeID, "output")
}

func (d *Dump) ports(nodeID int, direction string) []Port {
	ports := []Port{}
	for _, port := range d.Ports[nodeID] {
		if port.Direction == direction {
			ports = append(ports, port)
		}
	}
	sort.SliceStable(ports, func(i, j int) bool { return ports[i].Name < ports[j].Name })
	return ports
}

// Relink moves a stream to another sink by replacing its links.
func (d *Dump) Relink(streamID int, outputs []Port, sinkID int, inputs []Port) error {
	for _, link := range d.Links {
		if link.Output != streamID {
			continue
		}
		if _, err := run("pw-link", "-d", strconv.Itoa(link.ID)); err != nil {
			return err
		}
	}
	for _, output := range outputs {
		input, ok := matchChannel(output.Name, inputs)
		if !ok {
			continue
		}
		streamName := d.nodeName(streamID)
		sinkName := d.nodeName(sinkID)
		if _, err := run("pw-link", streamName+":"+output.Name, sinkName+":"+input.Name); err != nil {
			return err
		}
	}
	return nil
}

func (d *Dump) nodeName(id int) string {
	for _, node := range d.Objects {
		if node.ID == id {
			return node.Props["node.name"]
		}
	}
	return ""
}

// matchChannel finds the input port with the same channel suffix as the output port.
func matchChannel(output string, inputs []Port) (Port, bool) {
	channel := output
	if index := strings.LastIndex(output, "_"); index >= 0 {
		channel = output[index+1:]
	}
	for _, input := range inputs {
		if strings.HasSuffix(input.Name, "_"+channel) {
			return input, true
		}
	}
	return Port{}, false
}

// ConfigDir returns the directory that holds the profiles.
func ConfigDir() string {
	if dir := os.Getenv("KDN_AUDIO_PROFILES"); dir != "" {
		return dir
	}
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "kdn-audio", "profiles")
}
