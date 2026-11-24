// Package audio holds the operations that both the CLI and the TUI call.
package audio

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"kdn-audio/internal/bluetooth"
	"kdn-audio/internal/combine"
	"kdn-audio/internal/pipewire"
	"kdn-audio/internal/profile"
)

// ErrNotFound marks a pattern that matches no output.
var ErrNotFound = errors.New("no output matches")

// Manager performs the audio operations over the PipeWire graph and a Bluetooth client.
type Manager struct {
	PW          pipewire.Client
	BT          bluetooth.Client
	Now         func() time.Time
	Log         func(format string, args ...any)
	ProfilesDir string
}

// New returns a manager over the given clients.
func New(pw pipewire.Client, bt bluetooth.Client) *Manager {
	return &Manager{PW: pw, BT: bt, Now: time.Now, ProfilesDir: pipewire.ConfigDir()}
}

func (m *Manager) logf(format string, args ...any) {
	if m.Log != nil {
		m.Log(format, args...)
	}
}

func (m *Manager) now() time.Time {
	if m.Now != nil {
		return m.Now()
	}
	return time.Now()
}

// Sinks returns every output, in display order.
func (m *Manager) Sinks() ([]pipewire.Sink, error) {
	sinks, err := m.PW.Sinks()
	if err != nil {
		return nil, err
	}
	SortSinks(sinks)
	return sinks, nil
}

// Groups returns every joined output.
func (m *Manager) Groups() ([]combine.Group, error) {
	sinks, err := m.PW.Sinks()
	if err != nil {
		return nil, err
	}
	def, err := m.PW.DefaultSink()
	if err != nil {
		return nil, err
	}
	return combine.FromSinks(sinks, def), nil
}

// SortSinks orders outputs by how likely they are the ones a user wants: Bluetooth first, then
// sound cards, then virtual sinks, and joined outputs last.
func SortSinks(sinks []pipewire.Sink) {
	rank := func(kind string) int {
		switch kind {
		case "bluetooth":
			return 0
		case "alsa":
			return 1
		case "virtual":
			return 2
		default:
			return 3
		}
	}
	sort.SliceStable(sinks, func(i, j int) bool {
		ri, rj := rank(sinks[i].Kind()), rank(sinks[j].Kind())
		if ri != rj {
			return ri < rj
		}
		return strings.ToLower(sinks[i].Description) < strings.ToLower(sinks[j].Description)
	})
}

// CreateOptions holds the inputs of one join.
type CreateOptions struct {
	// Title is the displayed name. Empty means a name built from the members.
	Title string
	// Members are sink patterns or exact node names.
	Members []string
	// Connect tries to connect a matching paired Bluetooth device when a pattern matches no sink.
	Connect bool
	// MakeDefault makes the joined output the default output.
	MakeDefault bool
	// MoveStreams moves the streams that play now.
	MoveStreams bool
	// Profile records the profile that asked for this join. Empty for a manual join.
	Profile string
}

// Created describes one new joined output.
type Created struct {
	Group            combine.Group
	MemberTitles     []string
	MovedStreams     int
	InheritedDefault bool
	Warnings         []string
}

// Create joins several outputs behind one virtual output.
func (m *Manager) Create(opts CreateOptions) (Created, error) {
	unlock, err := Lock()
	if err != nil {
		return Created{}, err
	}
	defer unlock()

	members, err := m.resolveSinks(opts.Members, opts.Connect)
	if err != nil {
		return Created{}, err
	}
	if len(members) < 2 {
		return Created{}, fmt.Errorf("a joined output needs at least two outputs, got %d", len(members))
	}

	title := strings.TrimSpace(opts.Title)
	if title == "" {
		title = combine.Title(members)
	}
	if err := combine.ValidateTitle(title); err != nil {
		return Created{}, err
	}

	sinks, err := m.PW.Sinks()
	if err != nil {
		return Created{}, err
	}
	sinkName := combine.SinkName(title)
	for _, sink := range sinks {
		if strings.EqualFold(sink.Name, sinkName) && !combine.IsCombined(sink) {
			return Created{}, fmt.Errorf("the name %q is already taken by %q; pick another name", sinkName, sink.Description)
		}
	}

	// Re-running create with the same name replaces the old joined output, and a join that held
	// the default keeps it through its replacement, so existing routing does not drift away.
	replaceWasDefault := false
	groups, err := m.Groups()
	if err != nil {
		return Created{}, err
	}
	for _, group := range groups {
		if group.SinkName != sinkName {
			continue
		}
		replaceWasDefault = replaceWasDefault || group.Default
		if err := m.PW.RemoveJoin(group.SinkName); err != nil {
			return Created{}, fmt.Errorf("replace the existing joined output %q: %w", group.Title, err)
		}
		m.waitForSinkGone(group.SinkName, 2*time.Second)
		m.logf("replaced the joined output %q", group.Title)
	}

	previous, err := m.PW.DefaultSink()
	if err != nil {
		return Created{}, err
	}
	previous = usablePreviousDefault(members, previous)

	spec := pipewire.JoinSpec{
		SinkName:        sinkName,
		Title:           title,
		Members:         combine.MemberNames(members),
		Profile:         opts.Profile,
		PreviousDefault: previous,
	}
	if err := m.PW.CreateJoin(spec); err != nil {
		return Created{}, err
	}
	if _, err := m.waitForSink(sinkName, 5*time.Second); err != nil {
		_ = m.PW.RemoveJoin(sinkName)
		return Created{}, fmt.Errorf("the joined output did not appear: %w", err)
	}

	created := Created{Group: combine.Group{
		SinkName:        sinkName,
		Title:           title,
		Members:         combine.MemberNames(members),
		Profile:         opts.Profile,
		PreviousDefault: previous,
	}, MemberTitles: memberTitles(members)}

	for _, member := range members {
		if profileName := member.Props["device.profile.name"]; strings.HasPrefix(profileName, "headset") {
			created.Warnings = append(created.Warnings,
				fmt.Sprintf("%s plays in profile %q (mono call audio); switch the card to a2dp-sink for music",
					member.Description, profileName))
		}
	}

	makeDefault := opts.MakeDefault || replaceWasDefault
	if makeDefault {
		if err := m.setDefault(sinkName); err != nil {
			created.Warnings = append(created.Warnings, fmt.Sprintf("could not set the default output: %v", err))
		} else {
			created.Group.Default = true
			created.InheritedDefault = replaceWasDefault && !opts.MakeDefault
		}
	}
	if opts.MoveStreams {
		moved, err := m.PW.MoveStreams(sinkName)
		if err != nil {
			created.Warnings = append(created.Warnings, fmt.Sprintf("could not move the playing streams: %v", err))
		}
		created.MovedStreams = moved
	}
	return created, nil
}

// usablePreviousDefault keeps a previous default out of the member list: a joined output must never
// become the "previous" of the next one, or removing them in the wrong order restores a dead sink.
func usablePreviousDefault(members []pipewire.Sink, previous string) string {
	for _, member := range members {
		if member.Name == previous {
			return ""
		}
	}
	return previous
}

// Unlink removes one joined output and returns its title.
func (m *Manager) Unlink(pattern string) (string, error) {
	unlock, err := Lock()
	if err != nil {
		return "", err
	}
	defer unlock()

	groups, err := m.Groups()
	if err != nil {
		return "", err
	}
	if len(groups) == 0 {
		return "", fmt.Errorf("no joined output exists")
	}
	group, err := resolveGroup(pattern, groups)
	if err != nil {
		return "", err
	}
	if err := m.PW.RemoveJoin(group.SinkName); err != nil {
		return group.Title, err
	}
	m.waitForSinkGone(group.SinkName, 5*time.Second)
	m.logf("unlinked %q", group.Title)
	if err := m.promoteDefault(removedFrom(group)); err != nil {
		return group.Title, err
	}
	return group.Title, nil
}

// UnlinkAll removes every joined output and returns their titles.
func (m *Manager) UnlinkAll() ([]string, error) {
	unlock, err := Lock()
	if err != nil {
		return nil, err
	}
	defer unlock()

	groups, err := m.Groups()
	if err != nil {
		return nil, err
	}
	titles := make([]string, 0, len(groups))
	var removed []RemovedGroup
	var failures []string
	for _, group := range groups {
		if err := m.PW.RemoveJoin(group.SinkName); err != nil {
			failures = append(failures, fmt.Sprintf("%s: %v", group.Title, err))
			continue
		}
		m.waitForSinkGone(group.SinkName, 5*time.Second)
		m.logf("unlinked %q", group.Title)
		titles = append(titles, group.Title)
		removed = append(removed, removedFrom(group))
	}
	if err := m.promoteDefault(removed...); err != nil {
		failures = append(failures, err.Error())
	}
	if len(failures) > 0 {
		return titles, fmt.Errorf("%s", strings.Join(failures, "; "))
	}
	return titles, nil
}

// RemovedGroup records how one joined output looked before it went away.
type RemovedGroup struct {
	SinkName        string
	PreviousDefault string
	Default         bool
}

func removedFrom(group combine.Group) RemovedGroup {
	return RemovedGroup{
		SinkName:        group.SinkName,
		PreviousDefault: group.PreviousDefault,
		Default:         group.Default,
	}
}

// promoteDefault puts the default output back on a live sink after a join disappears.
func (m *Manager) promoteDefault(removed ...RemovedGroup) error {
	lostDefault := false
	for _, group := range removed {
		if group.Default {
			lostDefault = true
		}
	}
	if !lostDefault {
		return nil
	}
	sinks, err := m.PW.Sinks()
	if err != nil {
		return nil
	}
	gone := map[string]bool{}
	for _, group := range removed {
		gone[group.SinkName] = true
	}
	for _, group := range removed {
		previous := group.PreviousDefault
		if previous == "" || gone[previous] {
			continue
		}
		for _, sink := range sinks {
			if sink.Name == previous {
				return m.setDefault(previous)
			}
		}
	}
	for _, sink := range sinks {
		if !combine.IsCombined(sink) {
			return m.setDefault(sink.Name)
		}
	}
	return nil
}

// setDefault makes name the default output and confirms the server took it.
//
// WirePlumber writes its own choice a moment after a sink disappears, so one write can be
// overwritten. The confirm loop keeps the user's routing from drifting away.
func (m *Manager) setDefault(name string) error {
	if err := m.PW.SetDefaultSink(name); err != nil {
		return err
	}
	for attempt := 0; attempt < 10; attempt++ {
		current, err := m.PW.DefaultSink()
		if err == nil && current == name {
			return nil
		}
		time.Sleep(50 * time.Millisecond)
		if err := m.PW.SetDefaultSink(name); err != nil {
			return err
		}
	}
	return nil
}

// resolveSinks turns each pattern into one distinct sink, in the order given.
func (m *Manager) resolveSinks(patterns []string, connect bool) ([]pipewire.Sink, error) {
	if len(patterns) == 0 {
		return nil, fmt.Errorf("name at least two outputs")
	}
	sinks, err := m.PW.Sinks()
	if err != nil {
		return nil, err
	}
	selected := make([]pipewire.Sink, 0, len(patterns))
	seen := map[string]bool{}
	var unconnected []string
	for _, pattern := range patterns {
		sink, err := resolveSink(pattern, sinks)
		if errors.Is(err, ErrNotFound) && connect {
			unconnected = append(unconnected, pattern)
			continue
		}
		if err != nil {
			return nil, err
		}
		if combine.IsCombined(sink) {
			return nil, fmt.Errorf("%q is a joined output; unlink it first", sink.Description)
		}
		if seen[sink.Name] {
			continue
		}
		seen[sink.Name] = true
		selected = append(selected, sink)
	}
	if len(unconnected) > 0 {
		results := m.Connect(unconnected)
		var failures []string
		for _, result := range results {
			if result.Err != nil {
				failures = append(failures, fmt.Sprintf("%s: %v", result.Device.Name, result.Err))
			}
		}
		if len(failures) > 0 {
			return nil, fmt.Errorf("could not connect: %s", strings.Join(failures, "; "))
		}
		sinks, err = m.PW.Sinks()
		if err != nil {
			return nil, err
		}
		for _, pattern := range unconnected {
			sink, err := resolveSink(pattern, sinks)
			if err != nil {
				return nil, err
			}
			if seen[sink.Name] {
				continue
			}
			seen[sink.Name] = true
			selected = append(selected, sink)
		}
	}
	if len(selected) < 2 {
		return nil, fmt.Errorf("a joined output needs at least two outputs, got %d", len(selected))
	}
	return selected, nil
}

// ResolveSinks turns patterns into sinks without joining them.
func (m *Manager) ResolveSinks(patterns []string) ([]pipewire.Sink, error) {
	sinks, err := m.PW.Sinks()
	if err != nil {
		return nil, err
	}
	selected := make([]pipewire.Sink, 0, len(patterns))
	for _, pattern := range patterns {
		sink, err := resolveSink(pattern, sinks)
		if err != nil {
			return nil, err
		}
		selected = append(selected, sink)
	}
	return selected, nil
}

// ResolveGroups turns patterns into joined outputs.
func (m *Manager) ResolveGroups(patterns []string) ([]combine.Group, error) {
	groups, err := m.Groups()
	if err != nil {
		return nil, err
	}
	if len(groups) == 0 {
		return nil, fmt.Errorf("no joined output exists")
	}
	selected := make([]combine.Group, 0, len(patterns))
	for _, pattern := range patterns {
		group, err := resolveGroup(pattern, groups)
		if err != nil {
			return nil, err
		}
		selected = append(selected, group)
	}
	return selected, nil
}

// Connected is the outcome of one connect attempt.
type Connected struct {
	Device bluetooth.Device
	Sink   string
	Err    error
}

// Connect brings paired Bluetooth audio devices online. An empty pattern list means every paired
// audio device that is currently off.
func (m *Manager) Connect(patterns []string) []Connected {
	devices, err := m.BT.Devices()
	if err != nil {
		return []Connected{{Err: err}}
	}
	offline := bluetooth.OfflineAudioDevices(devices)
	if len(offline) == 0 {
		return nil
	}
	selected := offline
	if len(patterns) > 0 {
		selected = nil
		for _, device := range offline {
			for _, pattern := range patterns {
				if matchDevice(device, pattern) {
					selected = append(selected, device)
					break
				}
			}
		}
		if len(selected) == 0 {
			return []Connected{{Err: fmt.Errorf("no paired audio device that is off matches %s", strings.Join(patterns, ", "))}}
		}
	}

	results := make([]Connected, 0, len(selected))
	for _, device := range selected {
		result := Connected{Device: device}
		m.logf("connecting %s (%s)", device.Name, device.MAC)
		if err := m.BT.Connect(device.MAC); err != nil {
			result.Err = err
			results = append(results, result)
			continue
		}
		sink, err := m.waitForBluetoothSink(device.MAC, 20*time.Second)
		if err != nil {
			result.Err = err
			results = append(results, result)
			continue
		}
		result.Sink = sink
		results = append(results, result)
	}
	return results
}

func matchDevice(device bluetooth.Device, pattern string) bool {
	pattern = strings.TrimSpace(pattern)
	if pattern == "" {
		return false
	}
	if pipewire.NormalizeMAC(pattern) == device.MAC {
		return true
	}
	return strings.Contains(strings.ToLower(device.Name), strings.ToLower(pattern))
}

func (m *Manager) waitForBluetoothSink(mac string, timeout time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)
	for {
		sinks, err := m.PW.Sinks()
		if err == nil {
			for _, sink := range sinks {
				if sink.MAC() == mac {
					return sink.Name, nil
				}
			}
		}
		if time.Now().After(deadline) {
			return "", fmt.Errorf("connected, but no output appeared within %s", timeout)
		}
		time.Sleep(250 * time.Millisecond)
	}
}

func (m *Manager) waitForSink(name string, timeout time.Duration) (pipewire.Sink, error) {
	deadline := time.Now().Add(timeout)
	for {
		sinks, err := m.PW.Sinks()
		if err == nil {
			for _, sink := range sinks {
				if sink.Name == name {
					return sink, nil
				}
			}
		}
		if time.Now().After(deadline) {
			return pipewire.Sink{}, fmt.Errorf("no sink named %q after %s", name, timeout)
		}
		time.Sleep(150 * time.Millisecond)
	}
}

func (m *Manager) waitForSinkGone(name string, timeout time.Duration) {
	deadline := time.Now().Add(timeout)
	for {
		sinks, err := m.PW.Sinks()
		if err == nil {
			found := false
			for _, sink := range sinks {
				if sink.Name == name {
					found = true
					break
				}
			}
			if !found {
				return
			}
		}
		if time.Now().After(deadline) {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
}

// resolveSink finds the one output a pattern names.
//
// The order is exact id, exact node name, exact description, Bluetooth address, then substring, so
// `Earmuffs` never loses to a longer device that also contains the word.
func resolveSink(pattern string, sinks []pipewire.Sink) (pipewire.Sink, error) {
	pattern = strings.TrimSpace(pattern)
	if pattern == "" {
		return pipewire.Sink{}, fmt.Errorf("empty output name")
	}
	lower := strings.ToLower(pattern)
	mac := pipewire.NormalizeMAC(pattern)
	stages := []func(pipewire.Sink) bool{
		func(s pipewire.Sink) bool { return strings.EqualFold(s.ID(), pattern) },
		func(s pipewire.Sink) bool { return strings.EqualFold(s.Name, pattern) },
		func(s pipewire.Sink) bool { return strings.EqualFold(s.Description, pattern) },
		func(s pipewire.Sink) bool { return mac != "" && s.MAC() == mac },
		func(s pipewire.Sink) bool { return strings.Contains(strings.ToLower(s.Name), lower) },
		func(s pipewire.Sink) bool { return strings.Contains(strings.ToLower(s.Description), lower) },
		func(s pipewire.Sink) bool { return strings.Contains(strings.ToLower(s.ID()), lower) },
	}
	for _, stage := range stages {
		var hits []pipewire.Sink
		for _, sink := range sinks {
			if stage(sink) {
				hits = append(hits, sink)
			}
		}
		switch len(hits) {
		case 0:
			continue
		case 1:
			return hits[0], nil
		default:
			return pipewire.Sink{}, fmt.Errorf("%q matches %d outputs: %s", pattern, len(hits), describeSinks(hits))
		}
	}
	return pipewire.Sink{}, fmt.Errorf("%w: %q; run `kdn-audio devices`", ErrNotFound, pattern)
}

func resolveGroup(pattern string, groups []combine.Group) (combine.Group, error) {
	pattern = strings.TrimSpace(pattern)
	if pattern == "" {
		return combine.Group{}, fmt.Errorf("empty joined-output name")
	}
	lower := strings.ToLower(pattern)
	for _, stage := range []func(combine.Group) bool{
		func(g combine.Group) bool { return strings.EqualFold(g.Title, pattern) },
		func(g combine.Group) bool { return strings.EqualFold(g.SinkName, pattern) },
		func(g combine.Group) bool { return strings.Contains(strings.ToLower(g.Title), lower) },
		func(g combine.Group) bool { return strings.Contains(strings.ToLower(g.SinkName), lower) },
	} {
		var hits []combine.Group
		for _, group := range groups {
			if stage(group) {
				hits = append(hits, group)
			}
		}
		switch len(hits) {
		case 0:
			continue
		case 1:
			return hits[0], nil
		default:
			titles := make([]string, 0, len(hits))
			for _, group := range hits {
				titles = append(titles, group.Title)
			}
			return combine.Group{}, fmt.Errorf("%q matches %d joined outputs: %s", pattern, len(hits), strings.Join(titles, ", "))
		}
	}
	titles := make([]string, 0, len(groups))
	for _, group := range groups {
		titles = append(titles, group.Title)
	}
	return combine.Group{}, fmt.Errorf("no joined output matches %q; joined outputs: %s", pattern, strings.Join(titles, ", "))
}

func describeSinks(sinks []pipewire.Sink) string {
	parts := make([]string, 0, len(sinks))
	for _, sink := range sinks {
		parts = append(parts, fmt.Sprintf("%s (%s)", sink.Description, sink.ID()))
	}
	return strings.Join(parts, ", ")
}

func memberTitles(members []pipewire.Sink) []string {
	titles := make([]string, 0, len(members))
	for _, member := range members {
		titles = append(titles, member.Description)
	}
	return titles
}

// Profiles reads the profiles from the profile directory.
func (m *Manager) Profiles() ([]profile.Profile, error) {
	return profile.Load(m.profileDir())
}

// ProfileDir returns the directory that holds the profiles.
func (m *Manager) ProfileDir() string { return m.profileDir() }

func (m *Manager) profileDir() string {
	if m.ProfilesDir != "" {
		return m.ProfilesDir
	}
	return pipewire.ConfigDir()
}

// ActiveProfile returns the joined output that a profile created, if any.
func (m *Manager) ActiveProfile() (combine.Group, bool, error) {
	groups, err := m.Groups()
	if err != nil {
		return combine.Group{}, false, err
	}
	for _, group := range groups {
		if group.Profile != "" {
			return group, true, nil
		}
	}
	return combine.Group{}, false, nil
}

// Match reports whether the profile applies to the current outputs, and returns the node names it
// names.
func (m *Manager) Match(p profile.Profile, sinks []pipewire.Sink) (bool, []string, error) {
	members := make([]string, 0, len(p.Outputs))
	for _, pattern := range p.Outputs {
		sink, err := resolveSink(pattern, sinks)
		if errors.Is(err, ErrNotFound) {
			return false, nil, nil
		}
		if err != nil {
			return false, nil, fmt.Errorf("profile %q: %w", p.Name, err)
		}
		if combine.IsCombined(sink) {
			return false, nil, fmt.Errorf("profile %q names the joined output %q; a profile cannot nest", p.Name, sink.Description)
		}
		members = append(members, sink.Name)
	}
	for _, pattern := range p.Absent {
		if _, err := resolveSink(pattern, sinks); err == nil {
			return false, nil, nil
		} else if !errors.Is(err, ErrNotFound) {
			return false, nil, fmt.Errorf("profile %q: %w", p.Name, err)
		}
	}
	return true, members, nil
}

// SelectProfile returns the first matching profile, which is the one with the highest priority.
func (m *Manager) SelectProfile(sinks []pipewire.Sink) (profile.Profile, []string, bool, error) {
	profiles, err := m.Profiles()
	if err != nil {
		return profile.Profile{}, nil, false, err
	}
	for _, candidate := range profiles {
		ok, members, err := m.Match(candidate, sinks)
		if err != nil {
			return profile.Profile{}, nil, false, err
		}
		if ok {
			return candidate, members, true, nil
		}
	}
	return profile.Profile{}, nil, false, nil
}

// ApplyProfile activates one profile by name, whatever else matches.
func (m *Manager) ApplyProfile(name string) (Created, error) {
	profiles, err := m.Profiles()
	if err != nil {
		return Created{}, err
	}
	chosen, ok := profile.Find(profiles, name)
	if !ok {
		return Created{}, fmt.Errorf("no profile named %q in %s", name, m.profileDir())
	}
	sinks, err := m.PW.Sinks()
	if err != nil {
		return Created{}, err
	}
	matches, members, err := m.Match(chosen, sinks)
	if err != nil {
		return Created{}, err
	}
	if !matches {
		return Created{}, fmt.Errorf("profile %q needs outputs that are not connected now", chosen.Name)
	}
	if err := m.unlinkProfiles(""); err != nil {
		return Created{}, err
	}
	return m.Create(CreateOptions{
		Title:       chosen.Title(),
		Members:     members,
		MakeDefault: chosen.Default,
		MoveStreams: chosen.MoveStreams,
		Profile:     chosen.Name,
	})
}

// Activation records what one automatic pass changed.
type Activation struct {
	Profile string
	Title   string
	Removed []string
	Created bool
	Skipped string
}

// AutoActivate applies the best matching profile and removes the profile joins that no longer
// apply. Joins that a person created by hand are never touched.
func (m *Manager) AutoActivate() (Activation, error) {
	sinks, err := m.PW.Sinks()
	if err != nil {
		return Activation{}, err
	}
	best, members, matched, err := m.SelectProfile(sinks)
	if err != nil {
		return Activation{}, err
	}
	groups, err := m.Groups()
	if err != nil {
		return Activation{}, err
	}
	var managed []combine.Group
	for _, group := range groups {
		if group.Profile != "" {
			managed = append(managed, group)
		}
	}

	if matched && len(managed) == 1 && managed[0].Profile == best.Name && sameMembers(managed[0].Members, members) {
		return Activation{Profile: best.Name, Skipped: "already active"}, nil
	}
	if !matched && len(managed) == 0 {
		return Activation{Skipped: "no profile matches"}, nil
	}

	var removed []string
	for _, group := range managed {
		if _, err := m.Unlink(group.SinkName); err != nil {
			return Activation{}, err
		}
		removed = append(removed, group.Title)
	}
	if !matched {
		return Activation{Removed: removed, Skipped: "no profile matches"}, nil
	}
	created, err := m.Create(CreateOptions{
		Title:       best.Title(),
		Members:     members,
		MakeDefault: best.Default,
		MoveStreams: best.MoveStreams,
		Profile:     best.Name,
	})
	if err != nil {
		return Activation{}, err
	}
	return Activation{Profile: best.Name, Title: created.Group.Title, Removed: removed, Created: true}, nil
}

// unlinkProfiles removes every profile-created join. An empty except keeps all of them.
func (m *Manager) unlinkProfiles(except string) error {
	groups, err := m.Groups()
	if err != nil {
		return err
	}
	for _, group := range groups {
		if group.Profile == "" || strings.EqualFold(group.Profile, except) {
			continue
		}
		if _, err := m.Unlink(group.SinkName); err != nil {
			return err
		}
	}
	return nil
}

// Daemon applies the profiles whenever the device mix changes.
func (m *Manager) Daemon(ctx context.Context, interval time.Duration) error {
	if interval <= 0 {
		interval = 2 * time.Second
	}
	m.logf("watching %d profile(s) every %s", len(m.mustProfiles()), interval)
	apply := func() {
		activation, err := m.AutoActivate()
		if err != nil {
			m.logf("error: %v", err)
			return
		}
		switch {
		case activation.Created:
			m.logf("activated profile %q as %q (removed %d old join(s))",
				activation.Profile, activation.Title, len(activation.Removed))
		case len(activation.Removed) > 0:
			m.logf("deactivated profile join(s) %v", activation.Removed)
		}
	}
	apply()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			apply()
		}
	}
}

func (m *Manager) mustProfiles() []profile.Profile {
	profiles, err := m.Profiles()
	if err != nil {
		return nil
	}
	return profiles
}

func sameMembers(current, wanted []string) bool {
	if len(current) != len(wanted) {
		return false
	}
	seen := map[string]bool{}
	for _, member := range current {
		seen[member] = true
	}
	for _, member := range wanted {
		if !seen[member] {
			return false
		}
	}
	return true
}
