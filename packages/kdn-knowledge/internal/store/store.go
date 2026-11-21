// Package store owns the on-disk layout of the pipeline. Every write goes through a temporary
// file and a rename, so an interrupted run leaves the previous file intact.
package store

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Store is the data directory of the pipeline.
type Store struct {
	Root string
}

// Open returns a Store rooted at dir and creates the subdirectories.
func Open(dir string) (*Store, error) {
	if strings.TrimSpace(dir) == "" {
		return nil, fmt.Errorf("empty data directory")
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	store := &Store{Root: abs}
	for _, path := range []string{
		store.CorpusDir(),
		store.CandidatesDir(),
		store.ProposalsDir(),
		store.RunsDir(),
	} {
		if err := os.MkdirAll(path, 0o755); err != nil {
			return nil, err
		}
	}
	return store, nil
}

// CorpusDir holds one normalised session per file.
func (s *Store) CorpusDir() string { return filepath.Join(s.Root, "corpus") }

// CandidatesDir holds the extracted items per session.
func (s *Store) CandidatesDir() string { return filepath.Join(s.Root, "candidates") }

// ProposalsDir holds one directory per dream run.
func (s *Store) ProposalsDir() string { return filepath.Join(s.Root, "proposals") }

// RunsDir holds the stderr log of every run.
func (s *Store) RunsDir() string { return filepath.Join(s.Root, "runs") }

// StatePath is the session state file.
func (s *Store) StatePath() string { return filepath.Join(s.Root, "state.json") }

// CorpusPath is the corpus file of one session.
func (s *Store) CorpusPath(id string) string { return filepath.Join(s.CorpusDir(), id+".json") }

// CandidatesPath is the candidates file of one session.
func (s *Store) CandidatesPath(id string) string { return filepath.Join(s.CandidatesDir(), id+".json") }

// ListJSON returns the sorted session ids that have a file in dir.
func (s *Store) ListJSON(dir string) ([]string, error) { return ListJSON(dir) }

// ListJSON returns the sorted session ids that have a JSON file in dir.
func ListJSON(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	ids := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		ids = append(ids, strings.TrimSuffix(entry.Name(), ".json"))
	}
	sort.Strings(ids)
	return ids, nil
}

// WriteJSON writes v as indented JSON with a trailing newline, atomically.
func WriteJSON(path string, v any) error {
	body, err := MarshalJSON(v)
	if err != nil {
		return err
	}
	return WriteAtomic(path, body)
}

// MarshalJSON renders v as indented JSON with a trailing newline.
func MarshalJSON(v any) ([]byte, error) {
	body, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(body, '\n'), nil
}

// WriteAtomic writes body to path through a temporary file in the same directory.
func WriteAtomic(path string, body []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	temp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp*")
	if err != nil {
		return err
	}
	name := temp.Name()
	defer func() {
		_ = os.Remove(name)
	}()
	if _, err := temp.Write(body); err != nil {
		_ = temp.Close()
		return err
	}
	if err := temp.Sync(); err != nil {
		_ = temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(name, 0o644); err != nil {
		return err
	}
	return os.Rename(name, path)
}

// ReadJSON decodes one JSON file into v.
func ReadJSON(path string, v any) error {
	body, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(body, v); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}
