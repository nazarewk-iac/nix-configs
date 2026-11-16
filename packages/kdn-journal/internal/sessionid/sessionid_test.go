package sessionid

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func env(pairs map[string]string) func(string) string {
	return func(key string) string { return pairs[key] }
}

func TestDetect(t *testing.T) {
	cases := []struct {
		name string
		env  map[string]string
		want Identity
		ok   bool
	}{
		{
			name: "opencode",
			env:  map[string]string{"OPENCODE_SESSION_ID": "ses_1", "OPENCODE_MODEL": "m"},
			want: Identity{Harness: "opencode", ID: "ses_1", Model: "m", Source: "OPENCODE_SESSION_ID"},
			ok:   true,
		},
		{
			name: "claude code",
			env:  map[string]string{"CLAUDE_CODE_SESSION_ID": "c_1"},
			want: Identity{Harness: "claude", ID: "c_1", Source: "CLAUDE_CODE_SESSION_ID"},
			ok:   true,
		},
		{
			name: "codex thread id",
			env:  map[string]string{"CODEX_THREAD_ID": "t_1"},
			want: Identity{Harness: "codex", ID: "t_1", Source: "CODEX_THREAD_ID"},
			ok:   true,
		},
		{
			name: "generic",
			env:  map[string]string{"AGENT_SESSION_ID": "a_1", "AI_AGENT": "claude-code_2"},
			want: Identity{Harness: "claude", ID: "a_1", Source: "AGENT_SESSION_ID"},
			ok:   true,
		},
		{
			name: "nothing",
			env:  map[string]string{},
			want: Identity{},
			ok:   false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := Detect(env(tc.env))
			if ok != tc.ok || got != tc.want {
				t.Fatalf("Detect() = %#v, %v; want %#v, %v", got, ok, tc.want, tc.ok)
			}
		})
	}
}

func TestSidecarRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "session.json")
	if err := os.WriteFile(path, []byte(`{"schema_version":1,"harness":"opencode","future_key":{"a":1}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	sidecar, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if sidecar.Harness != "opencode" {
		t.Fatalf("Harness = %q", sidecar.Harness)
	}
	if _, ok := sidecar.Extra["future_key"]; !ok {
		t.Fatalf("Extra = %#v", sidecar.Extra)
	}
	sidecar.AddChange("aaaa")
	sidecar.Touch(time.Date(2026, 11, 16, 10, 0, 0, 0, time.UTC))
	if err := sidecar.Save(path); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err := json.Unmarshal(data, &fields); err != nil {
		t.Fatalf("invalid JSON: %v\n%s", err, data)
	}
	if _, ok := fields["future_key"]; !ok {
		t.Fatalf("unknown key was dropped:\n%s", data)
	}
	if fields["session_id"] != nil {
		t.Fatalf("session_id should be omitted when empty:\n%s", data)
	}
	reloaded, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(reloaded.JJ.ChangeIDs) != 1 || reloaded.JJ.ChangeIDs[0] != "aaaa" {
		t.Fatalf("JJ = %#v", reloaded.JJ)
	}
}

func TestSidecarRefusesSymlink(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "target.json")
	if err := os.WriteFile(target, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "session.json")
	if err := os.Symlink(target, link); err != nil {
		t.Skip("symlinks are unavailable")
	}
	sidecar := &Sidecar{SchemaVersion: 1}
	if err := sidecar.Save(link); err == nil {
		t.Fatal("Save replaced a symlink")
	}
}

func TestFindOrCreate(t *testing.T) {
	root := t.TempDir()
	existing := filepath.Join(root, ".cache", "agents", "opencode-20261110-ses_1")
	if err := os.MkdirAll(existing, 0o755); err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 11, 16, 10, 0, 0, 0, time.UTC)
	id := Identity{Harness: "opencode", ID: "ses_1"}
	dir, err := FindOrCreate(root, id, now)
	if err != nil {
		t.Fatal(err)
	}
	if dir != existing {
		t.Fatalf("FindOrCreate() = %q, want the existing %q", dir, existing)
	}
	fresh := Identity{Harness: "pi", ID: "pi_1"}
	dir, err = FindOrCreate(root, fresh, now)
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(root, ".cache", "agents", "pi-20261116-pi_1"); dir != want {
		t.Fatalf("FindOrCreate() = %q, want %q", dir, want)
	}
	if _, err := Find(root, Identity{Harness: "pi", ID: "nope"}); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("Find() error = %v", err)
	}
}

func TestSidecarAddIsDeduplicated(t *testing.T) {
	sidecar := &Sidecar{}
	if !sidecar.AddChange("aaaa") || sidecar.AddChange("aaaa") {
		t.Fatal("AddChange did not deduplicate")
	}
	if !sidecar.AddCommit("1111") || sidecar.AddCommit("1111") {
		t.Fatal("AddCommit did not deduplicate")
	}
	if sidecar.AddChange("") || sidecar.AddCommit("") {
		t.Fatal("an empty ID was recorded")
	}
}

func TestLoadAllAndMatchesChange(t *testing.T) {
	root := t.TempDir()
	good := filepath.Join(root, ".cache", "agents", "opencode-20261116-ses_1")
	if err := os.MkdirAll(good, 0o755); err != nil {
		t.Fatal(err)
	}
	sidecar := &Sidecar{SchemaVersion: 1, Harness: "opencode", SessionID: "ses_1"}
	sidecar.AddChange("abcdef123456")
	if err := sidecar.Save(filepath.Join(good, "session.json")); err != nil {
		t.Fatal(err)
	}
	// A directory without a sidecar is not an entry.
	if err := os.MkdirAll(filepath.Join(root, ".cache", "agents", "pi-20261116-ses_2"), 0o755); err != nil {
		t.Fatal(err)
	}
	corrupt := filepath.Join(root, ".cache", "agents", "claude-20261116-ses_3")
	if err := os.MkdirAll(corrupt, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(corrupt, "session.json"), []byte("{broken"), 0o644); err != nil {
		t.Fatal(err)
	}
	entries, err := LoadAll(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("LoadAll() returned %d entries: %#v", len(entries), entries)
	}
	var loaded *Sidecar
	for _, entry := range entries {
		if entry.Sidecar != nil {
			loaded = entry.Sidecar
		} else if entry.Err == nil {
			t.Fatalf("corrupt sidecar lost its error: %#v", entry)
		}
	}
	if loaded == nil || !loaded.MatchesChange("abcdef123456") {
		t.Fatalf("loaded = %#v", loaded)
	}
	if !loaded.MatchesChange("abcdef123456") {
		t.Fatal("MatchesChange rejected the full change ID")
	}
	if loaded.MatchesChange("zzzzzz") {
		t.Fatal("MatchesChange accepted an unknown ID")
	}
}
