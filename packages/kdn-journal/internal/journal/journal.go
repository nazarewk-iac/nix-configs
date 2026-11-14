// Package journal discovers agent session directories under .cache/agents.
package journal

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"kdn-journal/internal/board"
	"kdn-journal/internal/task"
	"kdn-journal/internal/worklog"
)

// Session is one agent session directory.
type Session struct {
	Dir           string             `json:"dir"`
	RelDir        string             `json:"rel_dir"`
	Name          string             `json:"name"`
	Harness       string             `json:"harness"`
	Date          string             `json:"date"`
	DateParsed    time.Time          `json:"date_parsed,omitempty"`
	ID            string             `json:"id"`
	LastTouched   time.Time          `json:"last_touched"`
	Boards        []*board.Board     `json:"boards"`
	Worklog       *worklog.Worklog   `json:"worklog,omitempty"`
	TrackWorklogs []*worklog.Worklog `json:"track_worklogs,omitempty"`
	TaskRefs      []string           `json:"task_refs,omitempty"`
	Issues        []task.Issue       `json:"issues,omitempty"`
}

// Store is the loaded set of sessions, newest first.
type Store struct {
	Root     string     `json:"root"`
	Sessions []*Session `json:"sessions"`
}

// MarshalJSON omits a missing date or touch time instead of emitting the zero time.
func (s Session) MarshalJSON() ([]byte, error) {
	type alias Session
	data, err := json.Marshal(alias(s))
	if err != nil {
		return nil, err
	}
	var fields map[string]any
	if err := json.Unmarshal(data, &fields); err != nil {
		return nil, err
	}
	if s.DateParsed.IsZero() {
		delete(fields, "date_parsed")
	}
	if s.LastTouched.IsZero() {
		delete(fields, "last_touched")
	}
	return json.Marshal(fields)
}

var (
	sessionNameRE = regexp.MustCompile(`^([a-z0-9]+)-(\d{8})-(.+)$`)
	taskRefRE     = regexp.MustCompile(`docs/tasks/[0-9]{4}-[0-9]{2}/[A-Za-z0-9._/{},-]+`)
	lineSuffixRE  = regexp.MustCompile(`:[0-9]+(?:-[0-9]+)?$`)
	monthRE       = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}$`)
	slugRE        = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)
	linkRE        = regexp.MustCompile(`\[[^\]]*\]\(([^)]+)\)`)
)

// Load reads root/.cache/agents. A missing directory is an empty store, not an error.
func Load(root string) (*Store, error) {
	store := &Store{Root: root}
	agentsDir := filepath.Join(root, ".cache", "agents")
	entries, err := os.ReadDir(agentsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return store, nil
		}
		return nil, err
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		session, err := loadSession(root, filepath.Join(agentsDir, entry.Name()))
		if err != nil {
			continue
		}
		store.Sessions = append(store.Sessions, session)
	}
	sort.SliceStable(store.Sessions, func(i, j int) bool {
		if store.Sessions[i].LastTouched.Equal(store.Sessions[j].LastTouched) {
			return store.Sessions[i].Name > store.Sessions[j].Name
		}
		return store.Sessions[i].LastTouched.After(store.Sessions[j].LastTouched)
	})
	return store, nil
}

func loadSession(root, dir string) (*Session, error) {
	name := filepath.Base(dir)
	rel, _ := filepath.Rel(root, dir)
	session := &Session{
		Dir:    dir,
		RelDir: filepath.ToSlash(rel),
		Name:   name,
	}
	if m := sessionNameRE.FindStringSubmatch(name); m != nil {
		session.Harness = m[1]
		session.Date = m[2]
		session.ID = m[3]
		if t, err := time.ParseInLocation("20060102", session.Date, time.Local); err == nil {
			session.DateParsed = t
		}
	} else {
		session.ID = name
		session.Issues = append(session.Issues, task.Issue{
			Severity: "warning",
			Code:     "session-name",
			Path:     dir,
			Message:  "directory name is not <harness>-<YYYYMMDD>-<session>",
		})
	}
	session.LastTouched = lastTouched(dir)
	session.Boards = loadBoards(dir)
	if path := filepath.Join(dir, "worklog.md"); fileExists(path) {
		if w, err := worklog.ParseFile(path); err == nil {
			session.Worklog = w
		}
	}
	trackPaths, _ := filepath.Glob(filepath.Join(dir, "worklog-*.md"))
	sort.Strings(trackPaths)
	for _, path := range trackPaths {
		if w, err := worklog.ParseFile(path); err == nil {
			session.TrackWorklogs = append(session.TrackWorklogs, w)
		}
	}
	session.TaskRefs = extractTaskRefs(root, dir)
	return session, nil
}

func loadBoards(dir string) []*board.Board {
	var out []*board.Board
	seen := map[string]bool{}
	add := func(path string) {
		if path == "" || seen[path] {
			return
		}
		seen[path] = true
		if b, err := board.ParseFile(path); err == nil {
			out = append(out, b)
		}
	}
	// An optional index.md lists the boards in the intended order.
	if data, err := os.ReadFile(filepath.Join(dir, "index.md")); err == nil {
		for _, match := range linkRE.FindAllStringSubmatch(string(data), -1) {
			target := strings.TrimSpace(match[1])
			target = strings.TrimPrefix(target, "./")
			if strings.Contains(target, "://") || strings.HasPrefix(target, "/") {
				continue
			}
			base := filepath.Base(target)
			if strings.HasPrefix(base, "board") && strings.HasSuffix(base, ".md") {
				add(filepath.Join(dir, base))
			}
		}
	}
	add(filepath.Join(dir, "board.md"))
	tracks, _ := filepath.Glob(filepath.Join(dir, "board-*.md"))
	sort.Strings(tracks)
	for _, path := range tracks {
		add(path)
	}
	return out
}

func lastTouched(dir string) time.Time {
	var newest time.Time
	entries, err := os.ReadDir(dir)
	if err != nil {
		return newest
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !(strings.HasPrefix(name, "board") || strings.HasPrefix(name, "worklog") || name == "index.md") {
			continue
		}
		if info, err := entry.Info(); err == nil && info.ModTime().After(newest) {
			newest = info.ModTime()
		}
	}
	if newest.IsZero() {
		if info, err := os.Stat(dir); err == nil {
			newest = info.ModTime()
		}
	}
	return newest
}

func extractTaskRefs(root, dir string) []string {
	texts := make([]string, 0)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !(strings.HasPrefix(name, "board") || strings.HasPrefix(name, "worklog") || name == "index.md") {
			continue
		}
		if data, err := os.ReadFile(filepath.Join(dir, name)); err == nil {
			texts = append(texts, string(data))
		}
	}
	seen := map[string]bool{}
	var refs []string
	for _, text := range texts {
		for _, match := range taskRefRE.FindAllString(text, -1) {
			ref := normalizeTaskRef(root, match)
			if ref != "" && !seen[ref] {
				seen[ref] = true
				refs = append(refs, ref)
			}
		}
	}
	sort.Strings(refs)
	return refs
}

func normalizeTaskRef(root, match string) string {
	ref := strings.TrimSpace(match)
	if idx := strings.IndexByte(ref, '#'); idx >= 0 {
		ref = ref[:idx]
	}
	ref = lineSuffixRE.ReplaceAllString(ref, "")
	if idx := strings.IndexByte(ref, '{'); idx >= 0 {
		ref = ref[:idx]
	}
	ref = strings.TrimSuffix(ref, ".md")
	ref = strings.TrimSuffix(ref, "/")
	parts := strings.Split(ref, "/")
	if len(parts) < 4 || parts[0] != "docs" || parts[1] != "tasks" {
		return ""
	}
	// Try the longest existing directory prefix. This maps a sub-task file reference to the
	// sub-task directory, not its parent.
	for end := len(parts); end >= 4; end-- {
		candidate := strings.Join(parts[:end], "/")
		if len(parts) >= 3 && !monthRE.MatchString(parts[2]) {
			return ""
		}
		if !slugRE.MatchString(parts[3]) {
			return ""
		}
		if info, err := os.Stat(filepath.Join(root, candidate)); err == nil && info.IsDir() {
			if def, err := os.Stat(filepath.Join(root, candidate, "definition.md")); err == nil && !def.IsDir() {
				return candidate
			}
		}
	}
	return ""
}

// Newest returns the newest session, or nil when there is none.
func (s *Store) Newest() *Session {
	if len(s.Sessions) == 0 {
		return nil
	}
	return s.Sessions[0]
}

// Find resolves a directory, an id, an id prefix, or id@YYYYMMDD. When several runs share an id,
// it returns the newest and the complete match list.
func (s *Store) Find(selector string) (*Session, []*Session, error) {
	matches, err := s.Matches(selector)
	if err != nil {
		return nil, nil, err
	}
	if len(matches) == 0 {
		return nil, nil, fmt.Errorf("session %q not found", selector)
	}
	return matches[0], matches, nil
}

// Matches returns every session that matches selector, newest first.
func (s *Store) Matches(selector string) ([]*Session, error) {
	selector = strings.TrimSpace(selector)
	if selector == "" {
		return nil, fmt.Errorf("empty session selector")
	}
	if strings.ContainsAny(selector, "/\\") || strings.HasPrefix(selector, ".") {
		clean := filepath.Clean(selector)
		abs := clean
		if !filepath.IsAbs(abs) {
			abs = filepath.Join(s.Root, clean)
		}
		var out []*Session
		for _, session := range s.Sessions {
			if session.Dir == abs || session.Dir == clean || session.RelDir == filepath.ToSlash(clean) {
				out = append(out, session)
			}
		}
		return out, nil
	}
	id := selector
	date := ""
	if idx := strings.LastIndexByte(selector, '@'); idx > 0 {
		id = selector[:idx]
		date = selector[idx+1:]
	}
	var exact []*Session
	var prefix []*Session
	for _, session := range s.Sessions {
		if date != "" && session.Date != date {
			continue
		}
		if session.ID == id || session.Name == id {
			exact = append(exact, session)
		} else if strings.HasPrefix(session.ID, id) || strings.HasPrefix(session.Name, id) {
			prefix = append(prefix, session)
		}
	}
	if len(exact) > 0 {
		return exact, nil
	}
	if len(prefix) > 0 {
		if ids := uniqueIDs(prefix); len(ids) > 1 {
			names := make([]string, len(prefix))
			for i, session := range prefix {
				names[i] = session.Name
			}
			return nil, fmt.Errorf("session %q is ambiguous: %s", selector, strings.Join(names, ", "))
		}
	}
	return prefix, nil
}

func uniqueIDs(sessions []*Session) []string {
	seen := map[string]bool{}
	var ids []string
	for _, session := range sessions {
		if !seen[session.ID] {
			seen[session.ID] = true
			ids = append(ids, session.ID)
		}
	}
	return ids
}

// ForTask returns the sessions that reference a task, newest first.
func (s *Store) ForTask(t *task.Task) []*Session {
	var out []*Session
	for _, session := range s.Sessions {
		for _, ref := range session.TaskRefs {
			if ref == t.RelDir {
				out = append(out, session)
				break
			}
		}
		if len(out) > 0 && out[len(out)-1] == session {
			continue
		}
		// A board may name only the session id, not the task path.
		if session.ID != "" && session.ID != session.Name && taskMentionsID(t, session.ID) {
			out = append(out, session)
		}
	}
	return out
}

func taskMentionsID(t *task.Task, id string) bool {
	paths := []string{filepath.Join(t.Dir, ".board.md"), filepath.Join(t.Dir, "board.md"), filepath.Join(t.Dir, ".worklog.md"), filepath.Join(t.Dir, "worklog.md")}
	for _, path := range paths {
		if data, err := os.ReadFile(path); err == nil && strings.Contains(string(data), id) {
			return true
		}
	}
	return false
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
