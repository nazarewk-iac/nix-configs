package profile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSaveAndLoad(t *testing.T) {
	dir := t.TempDir()
	saved, err := Profile{
		Name:        "Both Ears",
		Description: "headphones and earbuds",
		Priority:    10,
		Outputs:     []string{"bt:60:AB:D2:77:07:56", "bt:38:D5:18:B6:64:93"},
		Default:     true,
		MoveStreams: true,
	}.Save(dir)
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	if filepath.Dir(saved) != dir {
		t.Errorf("path = %q", saved)
	}
	data, err := os.ReadFile(saved)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if len(data) == 0 || data[0] != '#' {
		t.Errorf("the file does not start with the comment header:\n%s", data)
	}

	profiles, err := Load(dir)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(profiles) != 1 {
		t.Fatalf("profiles = %d, want 1", len(profiles))
	}
	loaded := profiles[0]
	if loaded.Name != "Both Ears" || loaded.Priority != 10 || len(loaded.Outputs) != 2 {
		t.Errorf("loaded = %+v", loaded)
	}
	if !loaded.Default || !loaded.MoveStreams {
		t.Errorf("flags lost: %+v", loaded)
	}
	if loaded.Path != saved {
		t.Errorf("path = %q, want %q", loaded.Path, saved)
	}
}

func TestLoadDefaultsTheNameFromTheFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "desk-pair.yaml")
	if err := os.WriteFile(path, []byte("outputs:\n  - a\n  - b\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	profiles, err := Load(dir)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(profiles) != 1 || profiles[0].Name != "desk-pair" {
		t.Fatalf("profiles = %+v", profiles)
	}
}

func TestLoadSortsByPriority(t *testing.T) {
	dir := t.TempDir()
	for _, p := range []Profile{
		{Name: "low", Priority: 1, Outputs: []string{"a", "b"}},
		{Name: "high", Priority: 9, Outputs: []string{"a", "b"}},
		{Name: "medium", Priority: 5, Outputs: []string{"a", "b"}},
	} {
		if _, err := p.Save(dir); err != nil {
			t.Fatal(err)
		}
	}
	profiles, err := Load(dir)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	names := []string{profiles[0].Name, profiles[1].Name, profiles[2].Name}
	if names[0] != "high" || names[1] != "medium" || names[2] != "low" {
		t.Errorf("order = %v", names)
	}
}

func TestLoadRejectsABrokenProfile(t *testing.T) {
	dir := t.TempDir()
	if _, err := (Profile{Name: "one", Outputs: []string{"a"}}).Save(dir); err == nil {
		t.Fatal("Save accepted a profile with one output")
	}
	if _, err := os.Stat(filepath.Join(dir, "one.yaml")); !os.IsNotExist(err) {
		t.Error("a broken profile was written")
	}
}

func TestMissingDirectoryIsEmpty(t *testing.T) {
	profiles, err := Load(filepath.Join(t.TempDir(), "absent"))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(profiles) != 0 {
		t.Errorf("profiles = %v", profiles)
	}
}

func TestFind(t *testing.T) {
	profiles := []Profile{{Name: "Both Ears"}}
	if _, ok := Find(profiles, "both ears"); !ok {
		t.Error("Find missed an exact name")
	}
	if _, ok := Find(profiles, "both_ears"); !ok {
		t.Error("Find missed the slug")
	}
	if _, ok := Find(profiles, "nothing"); ok {
		t.Error("Find invented a profile")
	}
}
