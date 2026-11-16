// Package sessionid detects the running agent session and stores its local sidecar.
//
// The sidecar is the local source of truth for session identity. It lives next to the session's
// board and worklog under .cache/agents, so it is private and git-ignored. Nothing here needs
// jj, Atuin or a network.
package sessionid

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// SchemaVersion is the sidecar schema this build writes.
const SchemaVersion = 1

// Identity is the harness session the process runs inside.
type Identity struct {
	Harness string `json:"harness"`
	ID      string `json:"session_id"`
	Model   string `json:"model,omitempty"`
	// Source names the environment variable the ID came from, or "flag" for an override.
	Source string `json:"source,omitempty"`
}

type spec struct {
	harness   string
	idVars    []string
	modelVars []string
}

// specs is the detection table, in priority order. The table matches jj-meta's, so a session
// recorded here resolves to the same harness there.
var specs = []spec{
	{harness: "opencode", idVars: []string{"OPENCODE_SESSION_ID"}, modelVars: []string{"OPENCODE_MODEL"}},
	{harness: "pi", idVars: []string{"PI_SESSION_ID"}, modelVars: []string{"PI_MODEL"}},
	{harness: "claude", idVars: []string{"CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID"}, modelVars: []string{"CLAUDE_MODEL"}},
	{harness: "codex", idVars: []string{"CODEX_THREAD_ID", "CODEX_SESSION_ID"}, modelVars: []string{"CODEX_MODEL"}},
	{harness: "cursor", idVars: []string{"CURSOR_CONVERSATION_ID"}, modelVars: []string{"CURSOR_MODEL"}},
	{harness: "gemini", idVars: []string{"GEMINI_SESSION_ID"}, modelVars: []string{"GEMINI_MODEL"}},
	{harness: "copilot", idVars: []string{"COPILOT_SESSION_ID"}, modelVars: []string{"COPILOT_MODEL"}},
}

// Detect reads the environment through getenv. ok is false when no session ID is present.
func Detect(getenv func(string) string) (Identity, bool) {
	if getenv == nil {
		getenv = func(string) string { return "" }
	}
	for _, s := range specs {
		for _, v := range s.idVars {
			if id := strings.TrimSpace(getenv(v)); id != "" {
				return Identity{
					Harness: s.harness,
					ID:      id,
					Model:   firstEnv(getenv, append(s.modelVars, "AGENT_MODEL")),
					Source:  v,
				}, true
			}
		}
	}
	if id := strings.TrimSpace(getenv("AGENT_SESSION_ID")); id != "" {
		harness := firstEnv(getenv, []string{"AGENT_HARNESS", "AI_AGENT"})
		if harness == "" {
			harness = "agent"
		}
		return Identity{
			Harness: NormalizeHarness(harness),
			ID:      id,
			Model:   firstEnv(getenv, []string{"AGENT_MODEL"}),
			Source:  "AGENT_SESSION_ID",
		}, true
	}
	return Identity{Model: firstEnv(getenv, []string{"AGENT_MODEL"})}, false
}

// NormalizeHarness maps the names harnesses export for themselves to the short directory prefix.
// Claude Code exports AI_AGENT=claude-code_<version>, and Atuin calls the harness claude-code.
func NormalizeHarness(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	switch {
	case name == "":
		return ""
	case strings.HasPrefix(name, "claude-code"):
		return "claude"
	case strings.HasPrefix(name, "opencode"):
		return "opencode"
	case strings.HasPrefix(name, "copilot"):
		return "copilot"
	case strings.HasPrefix(name, "gemini"):
		return "gemini"
	case strings.HasPrefix(name, "cursor"):
		return "cursor"
	case strings.HasPrefix(name, "codex"):
		return "codex"
	case strings.HasPrefix(name, "pi"):
		return "pi"
	}
	return name
}

// JJ is the jj mapping recorded for one session.
type JJ struct {
	WorkingCopyChange string   `json:"working_copy_change,omitempty"`
	ChangeIDs         []string `json:"change_ids,omitempty"`
	Commits           []string `json:"commits,omitempty"`
}

// Atuin is the optional Atuin Threads link for one session.
type Atuin struct {
	ThreadID       string `json:"thread_id,omitempty"`
	AgentSessionID string `json:"agent_session_id,omitempty"`
	Model          string `json:"model,omitempty"`
	MessageCount   int    `json:"message_count,omitempty"`
	UpdatedAt      string `json:"updated_at,omitempty"`
}

// Sidecar is the session.json document.
type Sidecar struct {
	SchemaVersion int    `json:"schema_version"`
	Harness       string `json:"harness,omitempty"`
	SessionID     string `json:"session_id,omitempty"`
	StartedAt     string `json:"started_at,omitempty"`
	UpdatedAt     string `json:"updated_at,omitempty"`
	Cwd           string `json:"cwd,omitempty"`
	Task          string `json:"task,omitempty"`
	JJ            JJ     `json:"jj,omitempty"`
	Atuin         Atuin  `json:"atuin,omitempty"`

	// Extra holds keys this build does not know, so a rewrite never drops them.
	Extra map[string]json.RawMessage `json:"-"`
}

// knownKeys lists the top-level keys the struct owns.
var knownKeys = []string{
	"schema_version", "harness", "session_id", "started_at", "updated_at", "cwd", "task", "jj", "atuin",
}

// Load reads a sidecar. A missing file returns an error that satisfies errors.Is(err, os.ErrNotExist).
func Load(path string) (*Sidecar, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	sidecar := &Sidecar{}
	if err := json.Unmarshal(data, sidecar); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	var all map[string]json.RawMessage
	if err := json.Unmarshal(data, &all); err == nil {
		for _, key := range knownKeys {
			delete(all, key)
		}
		if len(all) > 0 {
			sidecar.Extra = all
		}
	}
	return sidecar, nil
}

// Save writes the sidecar atomically and refuses to replace a symlink.
func (s *Sidecar) Save(path string) error {
	if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("%s is a symlink; refusing to write the sidecar", path)
	}
	data, err := s.marshal()
	if err != nil {
		return err
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".session-*.json")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer func() {
		if tmpName != "" {
			_ = os.Remove(tmpName)
		}
	}()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmpName, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		return err
	}
	tmpName = ""
	return nil
}

func (s *Sidecar) marshal() ([]byte, error) {
	raw, err := json.Marshal(s)
	if err != nil {
		return nil, err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return nil, err
	}
	for key, value := range s.Extra {
		if _, exists := fields[key]; !exists {
			fields[key] = value
		}
	}
	out, err := json.MarshalIndent(fields, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(out, '\n'), nil
}

// AddChange records a jj change ID. It reports whether the ID was new.
func (s *Sidecar) AddChange(id string) bool {
	id = strings.TrimSpace(id)
	if id == "" {
		return false
	}
	for _, existing := range s.JJ.ChangeIDs {
		if existing == id {
			return false
		}
	}
	s.JJ.ChangeIDs = append(s.JJ.ChangeIDs, id)
	return true
}

// AddCommit records a jj commit ID. It reports whether the ID was new.
func (s *Sidecar) AddCommit(id string) bool {
	id = strings.TrimSpace(id)
	if id == "" {
		return false
	}
	for _, existing := range s.JJ.Commits {
		if existing == id {
			return false
		}
	}
	s.JJ.Commits = append(s.JJ.Commits, id)
	return true
}

// Touch sets updated_at.
func (s *Sidecar) Touch(now time.Time) {
	s.UpdatedAt = now.Format(time.RFC3339)
	if s.StartedAt == "" {
		s.StartedAt = s.UpdatedAt
	}
}

// DirName returns the session directory name for id at now.
func DirName(id Identity, now time.Time) string {
	return fmt.Sprintf("%s-%s-%s", id.Harness, now.Format("20060102"), sanitize(id.ID))
}

var dirNameRE = regexp.MustCompile(`^([a-z0-9]+)-(\d{8})-(.+)$`)

// FindOrCreate returns the session directory for id. An existing directory whose name carries the
// same session ID is reused, so a session that started yesterday keeps its directory. Otherwise
// the directory is created under root/.cache/agents.
func FindOrCreate(root string, id Identity, now time.Time) (string, error) {
	if id.ID == "" || id.Harness == "" {
		return "", errors.New("session identity needs a harness and a session ID")
	}
	dir, err := Find(root, id)
	if err == nil {
		return dir, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	dir = filepath.Join(root, ".cache", "agents", DirName(id, now))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

// Find returns the existing session directory for id. It reports os.ErrNotExist when no directory
// carries the session ID.
func Find(root string, id Identity) (string, error) {
	if id.ID == "" {
		return "", errors.New("session identity needs a session ID")
	}
	agentsDir := filepath.Join(root, ".cache", "agents")
	entries, err := os.ReadDir(agentsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return "", os.ErrNotExist
		}
		return "", err
	}
	suffix := "-" + sanitize(id.ID)
	var found []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !strings.HasSuffix(name, suffix) {
			continue
		}
		if dirNameRE.FindStringSubmatch(name) == nil {
			continue
		}
		found = append(found, filepath.Join(agentsDir, name))
	}
	if len(found) == 0 {
		return "", os.ErrNotExist
	}
	sort.Strings(found)
	return found[len(found)-1], nil
}

func sanitize(id string) string {
	return strings.NewReplacer("/", "-", "\\", "-", ":", "-", " ", "-").Replace(id)
}

func firstEnv(getenv func(string) string, names []string) string {
	for _, name := range names {
		if v := strings.TrimSpace(getenv(name)); v != "" {
			return v
		}
	}
	return ""
}
