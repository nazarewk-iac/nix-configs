// Package cmd holds the cobra command tree of kdn-okf.
package cmd

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/x/ansi"
	"github.com/spf13/cobra"
	"golang.org/x/term"

	"kdn-okf/internal/index"
	"kdn-okf/internal/okf"
)

// App is the shared state of one CLI run.
type App struct {
	Bundle    string
	JSON      bool
	JSONL     bool
	NoColor   bool
	Width     int
	Quiet     bool
	Now       time.Time
	nowRaw    string
	CacheDir  string
	NoCache   bool
	Rebuild   bool
	Prefix    bool
	PrintPath bool
	Version   string
	Skill     string
	Out       io.Writer
	Err       io.Writer
}

// ExitError carries an explicit process exit code.
type ExitError struct {
	Code int
	Err  error
}

func (e *ExitError) Error() string {
	if e.Err != nil {
		return e.Err.Error()
	}
	return fmt.Sprintf("exit %d", e.Code)
}

func (e *ExitError) Unwrap() error { return e.Err }

// AsExitError reports the explicit exit code of err, if any.
func AsExitError(err error) (*ExitError, bool) {
	var target *ExitError
	if errors.As(err, &target) {
		return target, true
	}
	return nil, false
}

// NewRoot builds the root command with the real output streams.
func NewRoot(version, skill string) *cobra.Command {
	app := &App{Version: version, Skill: skill, Out: os.Stdout, Err: os.Stderr, Width: 100}
	root := &cobra.Command{
		Use:   "kdn-okf",
		Short: "Index, search and browse Open Knowledge Format v0.2 bundles",
		Long: "kdn-okf walks an OKF v0.2 bundle, indexes every concept, and exposes the knowledge\n" +
			"graph, trust and freshness as a CLI and a TUI. Every read command has --json.",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	flags := root.PersistentFlags()
	flags.StringVar(&app.Bundle, "bundle", "", "bundle root (default: walk up to a directory with index.md or a .md file)")
	flags.BoolVar(&app.JSON, "json", false, "print machine-readable JSON")
	flags.BoolVar(&app.JSONL, "jsonl", false, "print one JSON object per line")
	flags.BoolVar(&app.NoColor, "no-color", false, "disable color")
	flags.IntVar(&app.Width, "width", 100, "output width in columns")
	flags.StringVar(&app.CacheDir, "cache-dir", "", "cache directory (default: $XDG_CACHE_HOME/kdn-okf)")
	flags.BoolVar(&app.NoCache, "no-cache", false, "ignore and do not write the cache")
	flags.BoolVar(&app.Rebuild, "rebuild", false, "ignore the cache and rebuild it")
	flags.BoolVar(&app.Quiet, "quiet", false, "suppress the index summary on stderr")
	flags.StringVar(&app.nowRaw, "now", "", "RFC 3339 instant used for staleness (default: now)")
	flags.BoolVar(&app.Prefix, "prefix", false, "accept a unique concept ID or title prefix")
	flags.BoolVar(&app.PrintPath, "print-path", false, "print the resolved file path and nothing else")
	root.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
		switch cmd.Name() {
		case "version", "skill", "completion", "help":
			return nil
		}
		if raw := strings.TrimSpace(app.nowRaw); raw != "" {
			parsed, ok := okf.ParseTime(raw)
			if !ok {
				return fmt.Errorf("--now %q is not a timestamp", raw)
			}
			app.Now = parsed
		}
		return app.resolveBundle()
	}
	root.AddCommand(
		newListCmd(app),
		newShowCmd(app),
		newSearchCmd(app),
		newOutlineCmd(app),
		newSectionCmd(app),
		newContextCmd(app),
		newTypesCmd(app),
		newTagsCmd(app),
		newStatusesCmd(app),
		newTrustCmd(app),
		newLinksCmd(app),
		newBacklinksCmd(app),
		newOrphansCmd(app),
		newBrokenCmd(app),
		newStaleCmd(app),
		newUnverifiedCmd(app),
		newDoctorCmd(app),
		newGraphCmd(app),
		newIndexCmd(app),
		newGenerateIndexCmd(app),
		newOpenCmd(app),
		newTUICmd(app),
		newSkillCmd(app),
		newVersionCmd(app),
	)
	return root
}

func (a *App) resolveBundle() error {
	if a.Bundle != "" {
		abs, err := filepath.Abs(a.Bundle)
		if err != nil {
			return err
		}
		info, err := os.Stat(abs)
		if err != nil || !info.IsDir() {
			return fmt.Errorf("--bundle %q is not a directory", a.Bundle)
		}
		a.Bundle = abs
		return nil
	}
	cwd, err := os.Getwd()
	if err != nil {
		return err
	}
	dir := cwd
	var mdCandidate string
	for {
		if fileExists(filepath.Join(dir, "index.md")) {
			a.Bundle = dir
			return nil
		}
		if mdCandidate == "" && hasMarkdown(dir) {
			mdCandidate = dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	if mdCandidate != "" {
		a.Bundle = mdCandidate
		return nil
	}
	return fmt.Errorf("no OKF bundle found from %s; pass --bundle", cwd)
}

func (a *App) load() (*index.Result, error) {
	result, err := index.Load(index.Options{
		Root:     a.Bundle,
		CacheDir: a.CacheDir,
		NoCache:  a.NoCache,
		Rebuild:  a.Rebuild,
		Now:      a.Now,
	})
	if err != nil {
		return nil, err
	}
	if !a.Quiet && !a.JSON {
		state := "cold"
		if result.Cache.Warm {
			state = "warm"
		}
		fmt.Fprintf(a.Err, "kdn-okf: %s index: %d concepts\n", state, result.Cache.Concepts)
	}
	return result, nil
}

type envelope struct {
	SchemaVersion int         `json:"schema_version"`
	Command       string      `json:"command"`
	Bundle        string      `json:"bundle"`
	GeneratedAt   string      `json:"generated_at"`
	Data          any         `json:"data"`
	Issues        []okf.Issue `json:"issues"`
}

func (a *App) writeJSONL(items []any) error {
	enc := json.NewEncoder(a.Out)
	for _, item := range items {
		if err := enc.Encode(item); err != nil {
			return err
		}
	}
	return nil
}

func (a *App) writeJSON(command string, data any, issues []okf.Issue) error {
	if data == nil {
		data = map[string]any{}
	}
	if issues == nil {
		issues = []okf.Issue{}
	}
	now := a.Now
	if now.IsZero() {
		now = time.Now()
	}
	enc := json.NewEncoder(a.Out)
	enc.SetIndent("", "  ")
	return enc.Encode(envelope{
		SchemaVersion: 1,
		Command:       command,
		Bundle:        a.Bundle,
		GeneratedAt:   now.Format(time.RFC3339),
		Data:          data,
		Issues:        issues,
	})
}

// resolve finds one concept. Exact matches win; a prefix needs --prefix.
func (a *App) resolve(bundle *okf.Bundle, selector string) (*okf.Concept, error) {
	selector = strings.TrimSpace(selector)
	if selector == "" {
		return nil, &ExitError{Code: 2, Err: errors.New("empty concept selector")}
	}
	id := strings.TrimSuffix(strings.TrimPrefix(selector, "/"), ".md")
	if concept := bundle.Find(id); concept != nil {
		return concept, nil
	}
	for _, concept := range bundle.Concepts {
		if concept.RelPath == selector || concept.Path == selector {
			return concept, nil
		}
	}
	var titles []*okf.Concept
	for _, concept := range bundle.Concepts {
		if strings.EqualFold(concept.Title, selector) {
			titles = append(titles, concept)
		}
	}
	if len(titles) == 1 {
		return titles[0], nil
	}
	if len(titles) > 1 {
		return nil, a.ambiguous(selector, titles)
	}
	if a.Prefix {
		var matches []*okf.Concept
		lower := strings.ToLower(id)
		for _, concept := range bundle.Concepts {
			if strings.HasPrefix(strings.ToLower(concept.ID), lower) ||
				strings.HasPrefix(strings.ToLower(concept.Title), strings.ToLower(selector)) {
				matches = append(matches, concept)
			}
		}
		if len(matches) == 1 {
			return matches[0], nil
		}
		if len(matches) > 1 {
			return nil, a.ambiguous(selector, matches)
		}
	}
	return nil, &ExitError{Code: 2, Err: fmt.Errorf("concept %q not found", selector)}
}

func (a *App) ambiguous(selector string, matches []*okf.Concept) error {
	names := make([]string, 0, len(matches))
	for _, concept := range matches {
		names = append(names, concept.ID)
	}
	sort.Strings(names)
	fmt.Fprintf(a.Err, "kdn-okf: selector %q is ambiguous:\n", selector)
	for _, name := range names {
		fmt.Fprintf(a.Err, "  %s\n", name)
	}
	return &ExitError{Code: 2, Err: fmt.Errorf("selector %q matches %d concepts", selector, len(matches))}
}

type conceptSummary struct {
	ID          string   `json:"id"`
	Path        string   `json:"path"`
	RelPath     string   `json:"rel_path"`
	Type        string   `json:"type"`
	Title       string   `json:"title"`
	Description string   `json:"description,omitempty"`
	Tags        []string `json:"tags"`
	Status      string   `json:"status"`
	Trust       string   `json:"trust"`
	Stale       bool     `json:"stale"`
	StaleAfter  string   `json:"stale_after,omitempty"`
	Modified    string   `json:"modified,omitempty"`
	Size        int64    `json:"size"`
}

func summarize(concept *okf.Concept) conceptSummary {
	modified := ""
	if !concept.ModTime.IsZero() {
		modified = concept.ModTime.Format(time.RFC3339)
	}
	return conceptSummary{
		ID:          concept.ID,
		Path:        concept.Path,
		RelPath:     concept.RelPath,
		Type:        concept.Type,
		Title:       concept.Title,
		Description: concept.Description,
		Tags:        nonNil(concept.Tags),
		Status:      concept.Status,
		Trust:       concept.Trust.String(),
		Stale:       concept.Stale,
		StaleAfter:  concept.StaleAfter,
		Modified:    modified,
		Size:        concept.Size,
	}
}

func summarizeAll(concepts []*okf.Concept) []conceptSummary {
	out := make([]conceptSummary, 0, len(concepts))
	for _, concept := range concepts {
		out = append(out, summarize(concept))
	}
	return out
}

type filterOptions struct {
	Type       string
	Tag        string
	Status     string
	Trust      string
	Stale      bool
	Orphan     bool
	Broken     bool
	Unverified bool
}

func applyFilters(concepts []*okf.Concept, opts filterOptions) []*okf.Concept {
	out := make([]*okf.Concept, 0, len(concepts))
	for _, concept := range concepts {
		if opts.Type != "" && !strings.EqualFold(concept.Type, opts.Type) {
			continue
		}
		if opts.Tag != "" && !hasTag(concept.Tags, opts.Tag) {
			continue
		}
		if opts.Status != "" && !strings.EqualFold(concept.Status, opts.Status) {
			continue
		}
		if opts.Trust != "" && !strings.EqualFold(concept.Trust.String(), opts.Trust) {
			continue
		}
		if opts.Stale && !concept.Stale {
			continue
		}
		if opts.Orphan && len(concept.Backlinks) > 0 {
			continue
		}
		if opts.Broken && !hasMissingLink(concept) {
			continue
		}
		if opts.Unverified && concept.Trust != okf.TrustUnverified {
			continue
		}
		out = append(out, concept)
	}
	return out
}

func hasTag(tags []string, want string) bool {
	for _, tag := range tags {
		if strings.EqualFold(tag, want) {
			return true
		}
	}
	return false
}

func hasMissingLink(concept *okf.Concept) bool {
	for _, link := range concept.Links {
		if link.Missing {
			return true
		}
	}
	return false
}

func sortConcepts(concepts []*okf.Concept, mode string) {
	switch mode {
	case "title":
		sort.SliceStable(concepts, func(i, j int) bool {
			if strings.EqualFold(concepts[i].Title, concepts[j].Title) {
				return concepts[i].ID < concepts[j].ID
			}
			return strings.ToLower(concepts[i].Title) < strings.ToLower(concepts[j].Title)
		})
	case "modified":
		sort.SliceStable(concepts, func(i, j int) bool {
			return concepts[i].ModTime.After(concepts[j].ModTime)
		})
	case "type":
		sort.SliceStable(concepts, func(i, j int) bool {
			if concepts[i].Type != concepts[j].Type {
				return concepts[i].Type < concepts[j].Type
			}
			return concepts[i].ID < concepts[j].ID
		})
	case "status":
		sort.SliceStable(concepts, func(i, j int) bool {
			if concepts[i].Status != concepts[j].Status {
				return concepts[i].Status < concepts[j].Status
			}
			return concepts[i].ID < concepts[j].ID
		})
	case "trust":
		sort.SliceStable(concepts, func(i, j int) bool {
			if concepts[i].Trust != concepts[j].Trust {
				return concepts[i].Trust > concepts[j].Trust
			}
			return concepts[i].ID < concepts[j].ID
		})
	case "stale":
		sort.SliceStable(concepts, func(i, j int) bool {
			if concepts[i].Stale != concepts[j].Stale {
				return concepts[i].Stale
			}
			return concepts[i].ID < concepts[j].ID
		})
	default:
		sort.SliceStable(concepts, func(i, j int) bool { return concepts[i].ID < concepts[j].ID })
	}
}

func limitConcepts(concepts []*okf.Concept, limit int, all bool) []*okf.Concept {
	if all || limit <= 0 || limit >= len(concepts) {
		return concepts
	}
	return concepts[:limit]
}

func (a *App) color() bool {
	if a.NoColor || a.JSON || os.Getenv("NO_COLOR") != "" || os.Getenv("TERM") == "dumb" {
		return false
	}
	file, ok := a.Out.(*os.File)
	return ok && term.IsTerminal(int(file.Fd()))
}

func (a *App) truncate(value string, width int) string {
	if width <= 0 || ansi.StringWidth(value) <= width {
		return value
	}
	return ansi.Truncate(value, width, "…")
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func hasMarkdown(dir string) bool {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(strings.ToLower(entry.Name()), ".md") {
			return true
		}
	}
	return false
}

func nonNil(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}
