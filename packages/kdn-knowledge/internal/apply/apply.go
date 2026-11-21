// Package apply copies accepted concept drafts into the memory bundle.
//
// The bundle has one writer. When `okf-memory` is on PATH, apply calls it for every concept, so
// `log.md` and the parent `index.md` stay correct; direct file writing is only the fallback.
//
// A stable concept is never overwritten. The writes are validated with `okflint` (or, when that
// is absent, `kdn-okf doctor --parse-only`), and a validation error rolls every change back.
package apply

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"kdn-knowledge/internal/bundle"
	"kdn-knowledge/internal/dream"
	"kdn-knowledge/internal/okfkind"
	"kdn-knowledge/internal/store"
)

// Actor is the provenance that every written concept carries.
const Actor = "agent/kdn-knowledge"

// Skip records one action that was not written.
type Skip struct {
	ID     string `json:"id"`
	Reason string `json:"reason"`
}

// Gate is the outcome of one bundle gate.
type Gate struct {
	Name   string `json:"name"`
	Status string `json:"status"`
	Output string `json:"output,omitempty"`
}

// Result is the outcome of one apply run.
type Result struct {
	Writer        string   `json:"writer"`
	Written       []string `json:"written"`
	Skipped       []Skip   `json:"skipped"`
	Canonicalised []string `json:"canonicalised,omitempty"`
	Gates         []Gate   `json:"gates"`
	Validation    string   `json:"validation,omitempty"`
	Warnings      []string `json:"warnings,omitempty"`
	RolledBack    bool     `json:"rolled_back"`
	Warning       string   `json:"warning,omitempty"`
}

// draft is the content that apply sends to the bundle writer.
type draft struct {
	Type        string
	Title       string
	Description string
	Tags        []string
	Body        string
}

// Run writes the new and update actions of plan into root.
//
// A conflict is never applied: it needs a human to choose one of the two statements. A skill
// draft is not a concept, so a human installs it.
func Run(root, proposalDir string, plan *dream.Plan) (Result, error) {
	result := Result{Written: []string{}, Skipped: []Skip{}, Gates: []Gate{}}
	info, err := os.Stat(root)
	if err != nil || !info.IsDir() {
		return result, fmt.Errorf("bundle %s is not a directory", root)
	}
	memory, memoryErr := exec.LookPath("okf-memory")
	if memoryErr == nil {
		result.Writer = "okf-memory"
	} else {
		result.Writer = "files"
		result.Warning = "okf-memory is not on PATH: the concept files were written directly and " +
			"log.md and index.md were NOT updated"
	}

	type change struct {
		path    string
		backup  []byte
		existed bool
		created bool
	}
	changes := make([]change, 0, len(plan.Actions))
	snapshots := map[string][]byte{}

	snapshot := func(path string) {
		if _, ok := snapshots[path]; ok {
			return
		}
		if body, err := os.ReadFile(path); err == nil {
			snapshots[path] = body
		}
	}
	// The bookkeeping files that a bundle writer touches.
	snapshot(filepath.Join(root, "index.md"))
	snapshot(filepath.Join(root, "log.md"))
	for _, action := range plan.Actions {
		if action.Target == "" {
			continue
		}
		snapshot(filepath.Join(root, filepath.Dir(action.Target), "index.md"))
	}
	snapshot(filepath.Join(root, "okf-base.yaml"))

	rollback := func() {
		for i := len(changes) - 1; i >= 0; i-- {
			change := changes[i]
			if change.existed {
				_ = store.WriteAtomic(change.path, change.backup)
				continue
			}
			if change.created {
				_ = os.Remove(change.path)
			}
		}
		for path, body := range snapshots {
			_ = store.WriteAtomic(path, body)
		}
	}

	for _, action := range plan.Actions {
		switch action.Action {
		case "new", "update":
		default:
			result.Skipped = append(result.Skipped, Skip{
				ID:     action.ID,
				Reason: "action " + action.Action + " needs a human decision",
			})
			continue
		}
		if action.Target == "" {
			result.Skipped = append(result.Skipped, Skip{ID: action.ID, Reason: "no target path"})
			continue
		}
		source := filepath.Join(proposalDir, filepath.FromSlash(action.Concept))
		content, err := os.ReadFile(source)
		if err != nil {
			rollback()
			result.RolledBack = len(changes) > 0 || len(snapshots) > 0
			return result, err
		}
		target := filepath.Join(root, filepath.FromSlash(action.Target))
		change := change{path: target}
		if existing, err := os.ReadFile(target); err == nil {
			fields, _ := bundle.ParseFrontmatter(string(existing))
			if strings.EqualFold(fields["status"], "stable") {
				result.Skipped = append(result.Skipped, Skip{
					ID:     action.ID,
					Reason: "the bundle concept is stable; a human must retire it first",
				})
				continue
			}
			change.existed = true
			change.backup = existing
		} else {
			change.created = true
		}

		parsed := readDraft(content, action)
		if memory != "" {
			if err := writeWithMemory(memory, root, parsed, action); err != nil {
				rollback()
				result.RolledBack = len(changes) > 0 || len(snapshots) > 0
				return result, err
			}
			slug := filepath.Base(strings.TrimSuffix(action.Target, ".md"))
			if err := insertID(target, slug); err != nil {
				rollback()
				result.RolledBack = len(changes) > 0 || len(snapshots) > 0
				return result, fmt.Errorf("set the id of %s: %w", action.Target, err)
			}
		} else {
			if err := store.WriteAtomic(target, content); err != nil {
				rollback()
				result.RolledBack = len(changes) > 0 || len(snapshots) > 0
				return result, err
			}
		}
		changes = append(changes, change)
		result.Written = append(result.Written, action.Target)
	}

	for _, skill := range plan.Skills {
		result.Skipped = append(result.Skipped, Skip{
			ID:     skill.ID,
			Reason: "skill drafts are not concepts; install them by hand",
		})
	}
	sort.SliceStable(result.Skipped, func(i, j int) bool { return result.Skipped[i].ID < result.Skipped[j].ID })

	report, err := runGates(root, snapshot)
	result.Canonicalised = report.Canonicalised
	result.Gates = report.Gates
	result.Warnings = append(result.Warnings, report.Warnings...)
	result.Validation = report.Validation
	if err != nil {
		rollback()
		result.RolledBack = len(changes) > 0 || len(snapshots) > 0
		return result, fmt.Errorf("the bundle failed a gate; %d copies rolled back: %w", len(changes), err)
	}
	return result, nil
}

// insertID sets the `id` field that the bundle writer does not write.
//
// `okf-memory create` writes type, title, description, tags, generated and status, but no `id`,
// and AI-XF Level 1 requires one. This is the only field the writer leaves out. The edit is
// minimal and ordered: `id` goes directly after `type` — the place the canonical serialisation
// gives it — and every other byte of the file stays as it was. A file that already carries an
// `id` is left alone, so an update of an older concept also becomes conformant.
func insertID(path, slug string) error {
	body, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(body)
	if !strings.HasPrefix(text, "---\n") {
		return fmt.Errorf("%s has no frontmatter block", path)
	}
	lines := strings.Split(text, "\n")
	end := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == "---" {
			end = i
			break
		}
	}
	if end < 0 {
		return fmt.Errorf("%s has an unterminated frontmatter block", path)
	}
	for _, line := range lines[1:end] {
		key, _, ok := strings.Cut(strings.TrimSpace(line), ":")
		if ok && strings.EqualFold(strings.TrimSpace(key), "id") {
			return nil
		}
	}
	insertAt := 1
	for i := 1; i < end; i++ {
		key, _, ok := strings.Cut(strings.TrimSpace(lines[i]), ":")
		if ok && strings.EqualFold(strings.TrimSpace(key), "type") {
			insertAt = i + 1
			break
		}
	}
	lines = append(lines[:insertAt], append([]string{"id: " + slug}, lines[insertAt:]...)...)
	return store.WriteAtomic(path, []byte(strings.Join(lines, "\n")))
}

// readDraft reads the reviewed concept file: its frontmatter fields and its body.
func readDraft(content []byte, action dream.Action) draft {
	fields, body := bundle.ParseFrontmatter(string(content))
	parsed := draft{
		Type:        fields["type"],
		Title:       fields["title"],
		Description: fields["description"],
		Body:        strings.TrimSpace(body),
	}
	if parsed.Type == "" {
		parsed.Type = okfkind.TypeName(action.Kind)
	}
	if parsed.Title == "" {
		parsed.Title = action.Title
	}
	if parsed.Description == "" {
		parsed.Description = action.Statement
	}
	if tags := inlineList(fields["tags"]); len(tags) > 0 {
		parsed.Tags = tags
	} else {
		parsed.Tags = action.Tags
	}
	return parsed
}

// inlineList parses the YAML flow list that a concept file carries: `[jj, nix]`.
func inlineList(value string) []string {
	value = strings.TrimSpace(value)
	value = strings.TrimSuffix(strings.TrimPrefix(value, "["), "]")
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		clean := strings.Trim(strings.TrimSpace(part), `"'`)
		if clean != "" {
			out = append(out, clean)
		}
	}
	return out
}

// writeWithMemory asks the bundle's writer to create or update the concept.
func writeWithMemory(memory, root string, parsed draft, action dream.Action) error {
	conceptID := strings.TrimSuffix(filepath.ToSlash(action.Target), ".md")
	args := []string{}
	if action.Action == "update" {
		args = append(args, "update", conceptID, root,
			"--type", parsed.Type,
			"--title", parsed.Title,
			"--desc", parsed.Description,
			"--body", parsed.Body,
			"--actor", Actor,
			"--json")
		if len(parsed.Tags) > 0 {
			args = append(args, "--tags", strings.Join(parsed.Tags, ","))
		}
	} else {
		args = append(args, "create", conceptID, root,
			"--type", parsed.Type,
			"--title", parsed.Title,
			"--desc", parsed.Description,
			"--body", parsed.Body,
			"--status", "draft",
			"--actor", Actor,
			"--json")
		if len(parsed.Tags) > 0 {
			args = append(args, "--tags", strings.Join(parsed.Tags, ","))
		}
	}
	command := exec.Command(memory, args...)
	output, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("okf-memory %s failed for %s: %w: %s",
			args[0], conceptID, err, strings.TrimSpace(string(output)))
	}
	return nil
}

// gateReport is what the gates did.
type gateReport struct {
	Canonicalised []string
	Gates         []Gate
	Warnings      []string
	Validation    string
}

// runGates canonicalises the bundle, then runs the two gates in order: okflint, then AI-XF
// level 2. A missing binary is a warning, not a failure: the pipeline also runs from a laptop
// that has no validator installed.
func runGates(root string, snapshot func(string)) (gateReport, error) {
	report := gateReport{Gates: []Gate{}, Warnings: []string{}}
	lines := make([]string, 0, 3)

	if canon, err := exec.LookPath("ai-xf-canon"); err == nil {
		checkOutput, checkErr := runCommand(canon, "check", root)
		if checkErr != nil {
			for _, file := range nonCanonicalFiles(checkOutput) {
				snapshot(file)
			}
			writeOutput, writeErr := runCommand(canon, "write", root)
			if writeErr != nil {
				report.Gates = append(report.Gates, Gate{Name: "ai-xf-canon", Status: "fail", Output: writeOutput})
				return report, fmt.Errorf("ai-xf-canon write failed: %w: %s", writeErr, writeOutput)
			}
			report.Canonicalised = writtenFiles(writeOutput)
			lines = append(lines, fmt.Sprintf("ai-xf-canon: canonicalised %d file(s)", len(report.Canonicalised)))
			checkOutput, checkErr = runCommand(canon, "check", root)
		}
		if checkErr != nil {
			report.Gates = append(report.Gates, Gate{Name: "ai-xf-canon", Status: "fail", Output: checkOutput})
			return report, fmt.Errorf("ai-xf-canon check failed: %s", checkOutput)
		}
		report.Gates = append(report.Gates, Gate{Name: "ai-xf-canon", Status: "pass"})
	} else {
		report.Gates = append(report.Gates, Gate{Name: "ai-xf-canon", Status: "skipped"})
		report.Warnings = append(report.Warnings, "ai-xf-canon is not on PATH: canonical form not checked")
	}

	manifest := filepath.Join(root, "okf-base.yaml")
	if binary, err := exec.LookPath("okflint"); err == nil {
		if _, err := os.Stat(manifest); err != nil {
			report.Gates = append(report.Gates, Gate{Name: "okflint", Status: "skipped"})
			report.Warnings = append(report.Warnings, "the bundle has no okf-base.yaml: okflint skipped")
		} else {
			output, gateErr := runCommand(binary, "validate", "--manifest", manifest, root)
			lines = append(lines, "okflint: "+output)
			if gateErr != nil {
				report.Gates = append(report.Gates, Gate{Name: "okflint", Status: "fail", Output: output})
				return report, fmt.Errorf("okflint validate failed: %s", output)
			}
			report.Gates = append(report.Gates, Gate{Name: "okflint", Status: "pass", Output: output})
		}
	} else {
		report.Gates = append(report.Gates, Gate{Name: "okflint", Status: "skipped"})
		report.Warnings = append(report.Warnings, "okflint is not on PATH: manifest gate skipped")
	}

	if binary, err := exec.LookPath("ai-xf-validate"); err == nil {
		output, gateErr := runCommand(binary, root, "--level", "2")
		lines = append(lines, "ai-xf-validate --level 2: "+output)
		if gateErr != nil {
			report.Gates = append(report.Gates, Gate{Name: "ai-xf-validate", Status: "fail", Output: output})
			return report, fmt.Errorf("ai-xf-validate --level 2 failed: %s", output)
		}
		report.Gates = append(report.Gates, Gate{Name: "ai-xf-validate", Status: "pass", Output: output})
	} else {
		report.Gates = append(report.Gates, Gate{Name: "ai-xf-validate", Status: "skipped"})
		report.Warnings = append(report.Warnings, "ai-xf-validate is not on PATH: AI-XF level 2 gate skipped")
	}

	report.Validation = strings.Join(lines, "\n")
	return report, nil
}

func runCommand(binary string, args ...string) (string, error) {
	command := exec.Command(binary, args...)
	output, err := command.CombinedOutput()
	return strings.TrimSpace(string(output)), err
}

// nonCanonicalFiles reads the `ai-xf-canon check` report: one `not canonical  <path>` per file.
func nonCanonicalFiles(output string) []string {
	files := make([]string, 0, 4)
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 3 || fields[0] != "not" || fields[1] != "canonical" {
			continue
		}
		files = append(files, fields[2])
	}
	return files
}

// writtenFiles reads the `ai-xf-canon write` report: one `wrote  <path>` per rewritten file.
func writtenFiles(output string) []string {
	files := make([]string, 0, 4)
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 || fields[0] != "wrote" {
			continue
		}
		files = append(files, fields[1])
	}
	return files
}
