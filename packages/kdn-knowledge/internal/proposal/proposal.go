// Package proposal writes one reviewable directory: concept drafts, skill drafts, plan.json and
// report.md. Nothing here touches the memory bundle.
package proposal

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"kdn-knowledge/internal/dream"
	"kdn-knowledge/internal/okfkind"
	"kdn-knowledge/internal/store"
)

// GeneratedBy names the producer in every frontmatter block.
const GeneratedBy = "agent/kdn-knowledge"

// Result lists what a dream run wrote.
type Result struct {
	Dir        string   `json:"dir"`
	Concepts   []string `json:"concepts"`
	Skills     []string `json:"skills"`
	PlanPath   string   `json:"plan"`
	ReportPath string   `json:"report"`
}

// Write creates proposals/<UTC timestamp>/ and fills it. The timestamp comes from now, so two
// runs in the same second get distinct directories.
func Write(st *store.Store, plan *dream.Plan, now time.Time) (Result, error) {
	base := now.UTC().Format("20060102T150405Z")
	root := filepath.Join(st.ProposalsDir(), base)
	for suffix := 2; ; suffix++ {
		err := os.Mkdir(root, 0o755)
		if err == nil {
			break
		}
		if !os.IsExist(err) {
			return Result{}, err
		}
		root = filepath.Join(st.ProposalsDir(), fmt.Sprintf("%s-%d", base, suffix))
	}
	for _, dir := range []string{"concepts", "skills"} {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o755); err != nil {
			return Result{}, err
		}
	}

	result := Result{
		Dir:        root,
		Concepts:   []string{},
		Skills:     []string{},
		PlanPath:   filepath.Join(root, "plan.json"),
		ReportPath: filepath.Join(root, "report.md"),
	}

	for _, action := range plan.Actions {
		path := filepath.Join(root, filepath.FromSlash(action.Concept))
		if err := store.WriteAtomic(path, RenderConcept(action, now)); err != nil {
			return result, err
		}
		result.Concepts = append(result.Concepts, action.Concept)
	}
	for i := range plan.Skills {
		plan.Skills[i].Concept = "skills/" + plan.Skills[i].ID + ".md"
		path := filepath.Join(root, filepath.FromSlash(plan.Skills[i].Concept))
		if err := store.WriteAtomic(path, RenderSkill(plan.Skills[i], now)); err != nil {
			return result, err
		}
		result.Skills = append(result.Skills, plan.Skills[i].Concept)
	}

	if err := store.WriteJSON(result.PlanPath, plan); err != nil {
		return result, err
	}
	if err := store.WriteAtomic(result.ReportPath, RenderReport(plan, now)); err != nil {
		return result, err
	}
	return result, nil
}

// RenderConcept renders one OKF concept draft.
func RenderConcept(action dream.Action, now time.Time) []byte {
	var builder strings.Builder
	builder.WriteString("---\n")
	fmt.Fprintf(&builder, "type: %s\n", okfkind.TypeName(action.Kind))
	fmt.Fprintf(&builder, "title: %s\n", yamlString(action.Title))
	fmt.Fprintf(&builder, "description: %s\n", yamlString(describe(action.Statement)))
	fmt.Fprintf(&builder, "generated: { by: %s, at: %q }\n", GeneratedBy, now.UTC().Format(time.RFC3339))
	builder.WriteString("status: draft\n")
	fmt.Fprintf(&builder, "id: %s\n", yamlString(action.ID))
	if len(action.Tags) > 0 {
		fmt.Fprintf(&builder, "tags: [%s]\n", strings.Join(action.Tags, ", "))
	}
	builder.WriteString("links: []\n")
	builder.WriteString("---\n\n")
	fmt.Fprintf(&builder, "# %s\n\n", action.Title)
	builder.WriteString(action.Statement)
	builder.WriteString("\n")

	if action.Action == "conflict" {
		builder.WriteString("\n## Conflicts with\n\n")
		fmt.Fprintf(&builder, "The existing concept `%s` disagrees with this statement. "+
			"Resolve the two before `apply`.\n", action.Existing)
	}

	builder.WriteString("\n## Evidence\n\n")
	for _, evidence := range action.Evidence {
		line := "- `" + evidence.Session + "`"
		if evidence.Date != "" {
			line += " on " + evidence.Date
		}
		builder.WriteString(line + "\n")
	}
	if len(action.Tags) > 0 {
		builder.WriteString("\n## Tags\n\n")
		builder.WriteString("`" + strings.Join(action.Tags, "`, `") + "`\n")
	}
	builder.WriteString("\n> Draft from kdn-knowledge. A human reviews it before it joins the bundle.\n")
	return []byte(builder.String())
}

// RenderSkill renders one skill draft.
func RenderSkill(skill dream.SkillDraft, now time.Time) []byte {
	var builder strings.Builder
	builder.WriteString("---\n")
	builder.WriteString("type: Skill\n")
	fmt.Fprintf(&builder, "title: %s\n", yamlString(skill.Title))
	fmt.Fprintf(&builder, "description: %s\n", yamlString(skill.Description))
	fmt.Fprintf(&builder, "generated: { by: %s, at: %q }\n", GeneratedBy, now.UTC().Format(time.RFC3339))
	builder.WriteString("status: draft\n")
	fmt.Fprintf(&builder, "id: %s\n", yamlString(skill.ID))
	builder.WriteString("links: []\n")
	builder.WriteString("---\n\n")
	fmt.Fprintf(&builder, "# %s\n\n", skill.Title)
	builder.WriteString(skill.Description)
	builder.WriteString("\n\n## When to use\n\n")
	builder.WriteString(whenToUse(skill))
	builder.WriteString("\n\n## Steps\n\n")
	for i, command := range skill.Commands {
		fmt.Fprintf(&builder, "%d. `%s`\n", i+1, strings.ReplaceAll(command, "`", "'"))
	}
	builder.WriteString("\n## Evidence\n\n")
	for _, evidence := range skill.Evidence {
		line := "- `" + evidence.Session + "`"
		if evidence.Date != "" {
			line += " on " + evidence.Date
		}
		builder.WriteString(line + "\n")
	}
	builder.WriteString("\n> Draft from kdn-knowledge, from at least three sessions that followed this procedure.\n")
	return []byte(builder.String())
}

func whenToUse(skill dream.SkillDraft) string {
	if len(skill.Tags) == 0 {
		return "Use this when the same procedure appears again in a session."
	}
	return "Use this when a task matches: `" + strings.Join(skill.Tags, "`, `") + "`."
}

// RenderReport renders report.md: counts, the top ten clusters, every failure and the review
// order.
func RenderReport(plan *dream.Plan, now time.Time) []byte {
	var builder strings.Builder
	fmt.Fprintf(&builder, "# Knowledge proposal %s\n\n", now.UTC().Format(time.RFC3339))
	if plan.Model != "" {
		fmt.Fprintf(&builder, "Merge model: `%s`\n\n", plan.Model)
	}

	builder.WriteString("## What the run read\n\n")
	fmt.Fprintf(&builder, "- sessions with candidates: %d\n", len(plan.Sessions))
	fmt.Fprintf(&builder, "- items extracted: %d\n", plan.Items)
	fmt.Fprintf(&builder, "- clusters: %d (merged: %d, dropped as low confidence: %d)\n",
		plan.Clusters, plan.Merged, plan.Dropped)
	fmt.Fprintf(&builder, "- proposed: %d of %d clusters (over the cap: %d)\n",
		plan.Proposed, plan.Clusters, len(plan.NotProposed))
	if len(plan.Truncated) > 0 {
		fmt.Fprintf(&builder, "- sessions whose transcript was capped: %d (%s)\n",
			len(plan.Truncated), strings.Join(plan.Truncated, ", "))
	}

	builder.WriteString("\n## Actions\n\n")
	if len(plan.Actions) == 0 {
		builder.WriteString("None.\n")
	} else {
		builder.WriteString("| action | kind | id | items | evidence |\n")
		builder.WriteString("| --- | --- | --- | ---: | ---: |\n")
		for _, action := range plan.Actions {
			fmt.Fprintf(&builder, "| %s | %s | `%s` | %d | %d |\n",
				action.Action, action.Kind, action.ID, action.ClusterSize, len(action.Evidence))
		}
	}

	builder.WriteString("\n## Skills\n\n")
	if len(plan.Skills) == 0 {
		builder.WriteString("None: no runbook cluster reached the session and command minimums.\n")
	} else {
		for _, skill := range plan.Skills {
			fmt.Fprintf(&builder, "- `%s` — %s (%d sessions, %d commands)\n",
				skill.ID, skill.Title, len(skill.Sessions), len(skill.Commands))
		}
	}

	if len(plan.NotProposed) > 0 {
		builder.WriteString("\n## Not proposed (over the cap)\n\n")
		builder.WriteString("These clusters were read and merged, but the review budget left them out. " +
			"Nothing here is lost: raise `--max-concepts` to propose them.\n\n")
		for _, entry := range plan.NotProposed {
			fmt.Fprintf(&builder, "- **%s** %s — %d sessions, %d items\n",
				entry.Kind, entry.Statement, entry.Sessions, entry.Items)
		}
	}

	builder.WriteString("\n## Top ten clusters by evidence count\n\n")
	summaries := append([]dream.ClusterSummary{}, plan.Summaries...)
	sort.SliceStable(summaries, func(i, j int) bool {
		a, b := summaries[i], summaries[j]
		if a.Evidence != b.Evidence {
			return a.Evidence > b.Evidence
		}
		if a.Sessions != b.Sessions {
			return a.Sessions > b.Sessions
		}
		return a.Statement < b.Statement
	})
	if len(summaries) == 0 {
		builder.WriteString("None.\n")
	}
	for i, summary := range summaries {
		if i >= 10 {
			break
		}
		marks := make([]string, 0, 3)
		if summary.Merged {
			marks = append(marks, "merged")
		}
		if summary.Skill {
			marks = append(marks, "skill")
		}
		mark := ""
		if len(marks) > 0 {
			mark = " (" + strings.Join(marks, ", ") + ")"
		}
		fmt.Fprintf(&builder, "%d. **%s** %s — %d evidence, %d sessions, %d items%s\n",
			i+1, summary.Kind, summary.Statement, summary.Evidence, summary.Sessions, summary.Items, mark)
	}

	builder.WriteString("\n## Failed sessions\n\n")
	if len(plan.Failures) == 0 {
		builder.WriteString("None.\n")
	} else {
		failures := append([]dream.Failure{}, plan.Failures...)
		sort.SliceStable(failures, func(i, j int) bool { return failures[i].ID < failures[j].ID })
		for _, failure := range failures {
			fmt.Fprintf(&builder, "- `%s` — %s (%d attempts)\n", failure.ID, failure.Reason, failure.Attempts)
		}
	}

	builder.WriteString("\n## What to review first\n\n")
	review := reviewOrder(plan)
	if len(review) == 0 {
		builder.WriteString("Nothing: the proposal is empty.\n")
	}
	for i, line := range review {
		fmt.Fprintf(&builder, "%d. %s\n", i+1, line)
	}
	return []byte(builder.String())
}

// reviewOrder ranks the actions that most deserve a human eye: conflicts first, then clusters
// with many sessions, then skills, then updates.
func reviewOrder(plan *dream.Plan) []string {
	var conflicts, wide, updates, singles []string
	for _, action := range plan.Actions {
		switch action.Action {
		case "conflict":
			conflicts = append(conflicts,
				fmt.Sprintf("Resolve the conflict between `%s` and the existing `%s`.", action.ID, action.Existing))
		case "new":
			if len(action.Sessions) >= 2 {
				wide = append(wide,
					fmt.Sprintf("`%s` (%s) has %d sessions and %d items: check that it is one fact, not several.",
						action.ID, action.Kind, len(action.Sessions), action.ClusterSize))
			} else {
				singles = append(singles,
					fmt.Sprintf("`%s` (%s) comes from one session: confirm it is durable and not session chatter.",
						action.ID, action.Kind))
			}
		case "update":
			updates = append(updates,
				fmt.Sprintf("`%s` updates the existing `%s` at similarity %.2f.",
					action.ID, action.Existing, action.Similarity))
		}
	}
	skills := make([]string, 0, len(plan.Skills))
	for _, skill := range plan.Skills {
		skills = append(skills, fmt.Sprintf("Read the skill draft `%s` and check its steps.", skill.ID))
	}
	for _, group := range [][]string{conflicts, wide, skills, updates, singles} {
		sort.Strings(group)
	}
	out := make([]string, 0, 10)
	for _, group := range [][]string{conflicts, wide, skills, updates, singles} {
		for _, line := range group {
			if len(out) >= 10 {
				return out
			}
			out = append(out, line)
		}
	}
	return out
}

// yamlString quotes a value when YAML would otherwise misread it. A double-quoted value with Go
// escaping is valid YAML.
func yamlString(value string) string {
	value = strings.Join(strings.Fields(value), " ")
	if value == "" {
		return `""`
	}
	if strings.ContainsAny(value, `:#{}[],&*?|!%@`+"`"+`"'`) || strings.HasPrefix(value, "-") {
		return strconv.Quote(value)
	}
	return value
}

func describe(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	if len(text) <= 180 {
		return text
	}
	runes := []rune(text)
	return string(runes[:177]) + "…"
}
