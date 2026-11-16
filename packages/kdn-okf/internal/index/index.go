// Package index walks an OKF bundle, parses every concept and keeps a cache outside the bundle.
package index

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"kdn-okf/internal/okf"
)

const cacheVersion = 1

// Options selects one indexing run.
type Options struct {
	Root     string
	CacheDir string
	NoCache  bool
	Rebuild  bool
	Now      time.Time
}

// CacheInfo describes the cache a run used.
type CacheInfo struct {
	Path     string `json:"path"`
	Warm     bool   `json:"warm"`
	Rebuilt  bool   `json:"rebuilt"`
	BuiltAt  string `json:"built_at,omitempty"`
	Concepts int    `json:"concepts"`
}

// Result is one indexed bundle.
type Result struct {
	Bundle *okf.Bundle
	Cache  CacheInfo
	Issues []okf.Issue
}

type cacheFile struct {
	Version  int              `json:"version"`
	Root     string           `json:"root"`
	BuiltAt  string           `json:"built_at"`
	Concepts []cachedConcept  `json:"concepts"`
	Reserved []cachedReserved `json:"reserved"`
}

type cachedConcept struct {
	Path    string       `json:"path"`
	ModTime int64        `json:"mtime"`
	Size    int64        `json:"size"`
	Body    string       `json:"body"`
	Concept *okf.Concept `json:"concept"`
}

type cachedReserved struct {
	Path    string `json:"path"`
	RelPath string `json:"relpath"`
	Kind    string `json:"kind"`
	Body    string `json:"body"`
}

// CachePath returns the cache file for a bundle root.
func CachePath(root, cacheDir string) string {
	if cacheDir == "" {
		base, err := os.UserCacheDir()
		if err != nil || base == "" {
			base = filepath.Join(os.TempDir(), "kdn-okf-cache")
		}
		cacheDir = filepath.Join(base, "kdn-okf")
	}
	sum := sha256.Sum256([]byte(root))
	return filepath.Join(cacheDir, hex.EncodeToString(sum[:])[:16], "index-v1.json")
}

// Load indexes the bundle at opts.Root. A missing or corrupt cache is a rebuild, never a failure.
func Load(opts Options) (*Result, error) {
	root, err := filepath.Abs(opts.Root)
	if err != nil {
		return nil, err
	}
	now := opts.Now
	if now.IsZero() {
		now = time.Now()
	}
	cachePath := CachePath(root, opts.CacheDir)
	previous := map[string]cachedConcept{}
	previousReserved := map[string]cachedReserved{}
	builtAt := ""
	warm := false
	if !opts.NoCache && !opts.Rebuild {
		if cached, err := readCache(cachePath); err == nil && cached.Version == cacheVersion && cached.Root == root {
			for _, record := range cached.Concepts {
				previous[record.Path] = record
			}
			for _, record := range cached.Reserved {
				previousReserved[record.Path] = record
			}
			builtAt = cached.BuiltAt
			warm = true
		}
	}

	ignore := loadIgnore(root)
	bundle := &okf.Bundle{Root: root, Name: filepath.Base(root)}
	var concepts []*okf.Concept
	var reserved []*okf.Reserved
	var issues []okf.Issue
	walkErr := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		if entry.IsDir() {
			if path != root {
				name := entry.Name()
				if strings.HasPrefix(name, ".") || name == "node_modules" || name == "vendor" {
					return fs.SkipDir
				}
			}
			return nil
		}
		if !strings.HasSuffix(strings.ToLower(entry.Name()), ".md") {
			return nil
		}
		// A dotfile such as `.board.md` or `.worklog.md` is an agent journal, not an OKF concept.
		if strings.HasPrefix(entry.Name(), ".") {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return nil
		}
		rel = filepath.ToSlash(rel)
		if ignored(ignore, rel) {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return nil
		}
		if record, ok := previous[path]; ok && record.ModTime == info.ModTime().UnixNano() && record.Size == info.Size() {
			concept := record.Concept
			if concept == nil {
				return nil
			}
			concept.Body = []byte(record.Body)
			concept.ModTime = info.ModTime()
			concept.Path = path
			concept.Bundle = root
			concept.Stale = computeStale(concept, now)
			concepts = append(concepts, concept)
			return nil
		}
		if record, ok := previousReserved[path]; ok && strings.TrimSuffix(filepath.Base(path), ".md") == record.Kind {
			// A reserved file can change; re-read it, it is cheap.
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		switch entry.Name() {
		case "index.md", "log.md":
			reserved = append(reserved, &okf.Reserved{
				Path:    path,
				RelPath: rel,
				Kind:    strings.TrimSuffix(entry.Name(), ".md"),
				Body:    data,
			})
			return nil
		}
		concepts = append(concepts, okf.ParseConcept(root, path, data, info.ModTime(), now))
		return nil
	})
	if walkErr != nil {
		return nil, walkErr
	}

	sort.SliceStable(concepts, func(i, j int) bool { return concepts[i].ID < concepts[j].ID })
	sort.SliceStable(reserved, func(i, j int) bool { return reserved[i].RelPath < reserved[j].RelPath })
	issues = append(issues, resolveLinks(concepts)...)
	for _, concept := range concepts {
		issues = append(issues, concept.Issues...)
	}
	bundle.Concepts = concepts
	bundle.Reserved = reserved
	bundle.Issues = issues

	info := CacheInfo{Path: cachePath, Warm: warm, Concepts: len(concepts), BuiltAt: builtAt}
	if !opts.NoCache {
		if err := writeCache(cachePath, root, concepts, reserved, now); err != nil {
			issues = append(issues, okf.Issue{Severity: okf.SeverityWarning, Code: "cache-write", Message: err.Error()})
		}
	}
	if !warm {
		info.Rebuilt = true
	}
	return &Result{Bundle: bundle, Cache: info, Issues: issues}, nil
}

// resolveLinks fills Link.Kind/Resolved/Missing and every concept's Backlinks.
func resolveLinks(concepts []*okf.Concept) []okf.Issue {
	byID := make(map[string]*okf.Concept, len(concepts))
	for _, concept := range concepts {
		byID[concept.ID] = concept
	}
	// Reset every backlink list first, then fill them. A single pass would wipe the backlinks
	// that earlier concepts added to a later concept.
	for _, concept := range concepts {
		concept.Backlinks = []okf.Link{}
	}
	var issues []okf.Issue
	for _, concept := range concepts {
		for i := range concept.Links {
			link := &concept.Links[i]
			kind, resolved := resolveTarget(concept, link.Target, byID)
			link.Kind = kind
			link.Resolved = resolved
			link.Missing = resolved == "" && kind != okf.LinkExternal && kind != okf.LinkFragment
			if link.Missing {
				issues = append(issues, okf.Issue{
					Severity: okf.SeverityWarning,
					Code:     "broken-link",
					Path:     concept.Path,
					Concept:  concept.ID,
					Line:     link.Line,
					Target:   link.Target,
					Message:  "link target does not exist",
				})
			}
			if resolved == "" {
				continue
			}
			if target := byID[resolved]; target != nil {
				target.Backlinks = append(target.Backlinks, okf.Link{
					Source:   concept.ID,
					Target:   link.Target,
					Resolved: resolved,
					Kind:     kind,
					Line:     link.Line,
				})
			}
		}
	}
	return issues
}

func resolveTarget(concept *okf.Concept, raw string, byID map[string]*okf.Concept) (string, string) {
	if strings.HasPrefix(raw, "#") {
		return okf.LinkFragment, concept.ID
	}
	if isExternal(raw) {
		return okf.LinkExternal, ""
	}
	cleaned := raw
	if idx := strings.IndexAny(cleaned, "#?"); idx >= 0 {
		cleaned = cleaned[:idx]
	}
	cleaned = strings.TrimSpace(cleaned)
	if cleaned == "" {
		return okf.LinkFragment, concept.ID
	}
	kind := okf.LinkRelative
	var rel string
	if strings.HasPrefix(cleaned, "/") {
		kind = okf.LinkBundleAbsolute
		rel = strings.TrimPrefix(cleaned, "/")
	} else {
		rel = filepath.ToSlash(filepath.Join(filepath.Dir(concept.RelPath), cleaned))
	}
	rel = filepath.ToSlash(filepath.Clean(rel))
	if rel == ".." || strings.HasPrefix(rel, "../") {
		return okf.LinkExternal, ""
	}
	id := strings.TrimSuffix(rel, ".md")
	if byID[id] != nil {
		return kind, id
	}
	return kind, ""
}

func isExternal(raw string) bool {
	lower := strings.ToLower(raw)
	return strings.Contains(lower, "://") || strings.HasPrefix(lower, "mailto:") || strings.HasPrefix(lower, "tel:")
}

func computeStale(concept *okf.Concept, now time.Time) bool {
	if concept.StaleAfter == "" {
		return false
	}
	at, ok := okf.ParseTime(concept.StaleAfter)
	if !ok {
		return false
	}
	return !now.Before(at)
}

func readCache(path string) (*cacheFile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cached cacheFile
	if err := json.Unmarshal(data, &cached); err != nil {
		return nil, err
	}
	return &cached, nil
}

func writeCache(path, root string, concepts []*okf.Concept, reserved []*okf.Reserved, now time.Time) error {
	cached := cacheFile{Version: cacheVersion, Root: root, BuiltAt: now.Format(time.RFC3339)}
	for _, concept := range concepts {
		cached.Concepts = append(cached.Concepts, cachedConcept{
			Path:    concept.Path,
			ModTime: concept.ModTime.UnixNano(),
			Size:    concept.Size,
			Body:    string(concept.Body),
			Concept: concept,
		})
	}
	for _, entry := range reserved {
		cached.Reserved = append(cached.Reserved, cachedReserved{
			Path:    entry.Path,
			RelPath: entry.RelPath,
			Kind:    entry.Kind,
			Body:    string(entry.Body),
		})
	}
	data, err := json.Marshal(cached)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".index-*.json")
	if err != nil {
		return err
	}
	name := tmp.Name()
	defer os.Remove(name)
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(name, 0o644); err != nil {
		return err
	}
	return os.Rename(name, path)
}

func loadIgnore(root string) []string {
	data, err := os.ReadFile(filepath.Join(root, ".okfignore"))
	if err != nil {
		return nil
	}
	var patterns []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		patterns = append(patterns, strings.TrimPrefix(line, "/"))
	}
	return patterns
}

func ignored(patterns []string, rel string) bool {
	for _, pattern := range patterns {
		if strings.HasSuffix(pattern, "/") {
			if strings.HasPrefix(rel, pattern) {
				return true
			}
			continue
		}
		if matched, _ := filepath.Match(pattern, rel); matched {
			return true
		}
		if matched, _ := filepath.Match(pattern, filepath.Base(rel)); matched {
			return true
		}
	}
	return false
}

// MissingBacklinks reports A -> B where B does not link back to A. It is a doctor warning, never a
// parse failure.
func MissingBacklinks(concepts []*okf.Concept) []okf.Issue {
	byID := make(map[string]*okf.Concept, len(concepts))
	for _, concept := range concepts {
		byID[concept.ID] = concept
	}
	var issues []okf.Issue
	for _, concept := range concepts {
		for _, link := range concept.Links {
			if link.Resolved == "" {
				continue
			}
			target := byID[link.Resolved]
			if target == nil {
				continue
			}
			hasBack := false
			for _, back := range target.Links {
				if back.Resolved == concept.ID {
					hasBack = true
					break
				}
			}
			if !hasBack {
				issues = append(issues, okf.Issue{
					Severity: okf.SeverityWarning,
					Code:     "missing-backlink",
					Path:     target.Path,
					Concept:  target.ID,
					Line:     link.Line,
					Target:   concept.ID,
					Message:  fmt.Sprintf("%s links here but this concept does not link back", concept.ID),
				})
			}
		}
	}
	return issues
}

// Orphans returns concepts with no incoming links.
func Orphans(concepts []*okf.Concept) []*okf.Concept {
	var out []*okf.Concept
	for _, concept := range concepts {
		if len(concept.Backlinks) == 0 {
			out = append(out, concept)
		}
	}
	return out
}

// RecursiveLinks follows resolved links breadth-first from start, up to maxDistance.
func RecursiveLinks(bundle *okf.Bundle, start *okf.Concept, maxDistance int) []okf.Link {
	seen := map[string]bool{start.ID: true}
	var out []okf.Link
	queue := []*okf.Concept{start}
	distance := 0
	for len(queue) > 0 && (maxDistance <= 0 || distance < maxDistance) {
		var next []*okf.Concept
		for _, concept := range queue {
			for _, link := range concept.Links {
				if link.Resolved == "" {
					continue
				}
				out = append(out, link)
				if seen[link.Resolved] {
					continue
				}
				seen[link.Resolved] = true
				if target := bundle.Find(link.Resolved); target != nil {
					next = append(next, target)
				}
			}
		}
		queue = next
		distance++
	}
	return out
}
