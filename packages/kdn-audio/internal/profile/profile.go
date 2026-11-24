// Package profile stores joined-output presets on disk.
//
// A profile is one YAML file in the profile directory. It names the outputs it needs by stable
// device id, so the same file keeps working when PipeWire renumbers its nodes. The daemon applies
// the highest-priority profile whose outputs are all present, which is the audio counterpart of a
// kanshi profile for displays.
package profile

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"kdn-audio/internal/combine"
)

// Profile is one named joined output and the device mix that turns it on.
type Profile struct {
	// Name is the title of the joined output and the node description.
	Name string `yaml:"name"`
	// Description is free text for humans.
	Description string `yaml:"description,omitempty"`
	// Priority breaks ties: the highest matching profile wins.
	Priority int `yaml:"priority,omitempty"`
	// Outputs are device ids, names, or any unambiguous part of one. All must be present.
	Outputs []string `yaml:"outputs"`
	// Absent lists devices whose presence blocks the profile.
	Absent []string `yaml:"absent,omitempty"`
	// Default makes the joined output the default output when activated.
	Default bool `yaml:"default,omitempty"`
	// MoveStreams moves the streams that play now when activated.
	MoveStreams bool `yaml:"move-streams,omitempty"`
	// Path is where the profile came from. It is not stored in the file.
	Path string `yaml:"-"`
}

// Load reads every profile in dir, highest priority first.
//
// A missing directory is not an error: a host with no profiles is a host with no automatic
// joins.
func Load(dir string) ([]Profile, error) {
	entries, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	profiles := []Profile{}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		extension := strings.ToLower(filepath.Ext(entry.Name()))
		if extension != ".yaml" && extension != ".yml" {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		var loaded Profile
		if err := yaml.Unmarshal(data, &loaded); err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		if loaded.Name == "" {
			loaded.Name = strings.TrimSuffix(entry.Name(), filepath.Ext(entry.Name()))
		}
		loaded.Path = path
		if err := loaded.Validate(); err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		profiles = append(profiles, loaded)
	}
	sort.SliceStable(profiles, func(i, j int) bool {
		if profiles[i].Priority != profiles[j].Priority {
			return profiles[i].Priority > profiles[j].Priority
		}
		return strings.ToLower(profiles[i].Name) < strings.ToLower(profiles[j].Name)
	})
	return profiles, nil
}

// Find returns the profile with the given name.
func Find(profiles []Profile, name string) (Profile, bool) {
	for _, loaded := range profiles {
		if strings.EqualFold(loaded.Name, name) || loaded.DisplayKey() == strings.ToLower(name) {
			return loaded, true
		}
	}
	return Profile{}, false
}

// DisplayKey is the lower-case slug of the profile name.
func (p Profile) DisplayKey() string {
	return combine.Slug(p.Name)
}

// Validate rejects a profile that cannot be applied.
func (p Profile) Validate() error {
	if strings.TrimSpace(p.Name) == "" {
		return fmt.Errorf("the profile needs a name")
	}
	if err := combine.ValidateTitle(p.Name); err != nil {
		return fmt.Errorf("name: %w", err)
	}
	if len(p.Outputs) < 2 {
		return fmt.Errorf("a profile joins at least two outputs, got %d", len(p.Outputs))
	}
	for _, output := range p.Outputs {
		if strings.TrimSpace(output) == "" {
			return fmt.Errorf("outputs must not contain an empty entry")
		}
	}
	return nil
}

// PathFor returns the file that holds the profile with the given name.
func PathFor(dir, name string) string {
	return filepath.Join(dir, combine.Slug(name)+".yaml")
}

// Save writes the profile to dir and returns the path.
func (p Profile) Save(dir string) (string, error) {
	if err := p.Validate(); err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	path := PathFor(dir, p.Name)
	data, err := yaml.Marshal(p)
	if err != nil {
		return "", err
	}
	header := "# kdn-audio profile. Devices are named by id; `kdn-audio devices` maps ids to names.\n"
	if err := os.WriteFile(path, append([]byte(header), data...), 0o644); err != nil {
		return "", err
	}
	return path, nil
}

// Title is the name of the joined output that the profile creates.
func (p Profile) Title() string {
	return p.Name
}
