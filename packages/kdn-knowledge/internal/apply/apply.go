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

// Result is the outcome of one apply run.
type Result struct {
	Writer     string   `json:"writer"`
	Written    []string `json:"written"`
	Skipped    []Skip   `json:"skipped"`
	Validation string   `json:"validation,omitempty"`
	RolledBack bool     `json:"rolled_back"`
	Warning    string   `json:"warning,omitempty"`
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
	result := Result{Written: []string{}, Skipped: []Skip{}}
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

	validation, err := validate(root, result.Writer)
	result.Validation = validation
	if err != nil {
		rollback()
		result.RolledBack = len(changes) > 0 || len(snapshots) > 0
		return result, fmt.Errorf("the bundle failed validation; %d copies rolled back: %w: %s",
			len(changes), err, validation)
	}
	return result, nil
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

// validate runs the bundle gate. okflint is the strict gate; kdn-okf is the fallback.
func validate(root, writer string) (string, error) {
	manifest := filepath.Join(root, "okf-base.yaml")
	if binary, err := exec.LookPath("okflint"); err == nil {
		if _, err := os.Stat(manifest); err == nil {
			command := exec.Command(binary, "validate", "--manifest", manifest, root)
			output, err := command.CombinedOutput()
			text := strings.TrimSpace(string(output))
			if err != nil {
				return text, err
			}
			return text, nil
		}
	}
	if binary, err := exec.LookPath("kdn-okf"); err == nil {
		command := exec.Command(binary, "doctor", "--parse-only", "--bundle", root)
		output, err := command.CombinedOutput()
		text := strings.TrimSpace(string(output))
		if err != nil {
			return text, err
		}
		return text, nil
	}
	if writer == "files" {
		return "no validator on PATH: okflint and kdn-okf are both absent", nil
	}
	return "", nil
}
