package dream

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"

	"kdn-knowledge/internal/textsim"

	"kdn-knowledge/internal/bundle"
	"kdn-knowledge/internal/extract"
)

type fakeMerger struct {
	statement  string
	tags       []string
	err        error
	contradict bool
	merges     int
	compares   int
}

func (f *fakeMerger) Merge(context.Context, []string, []string) (string, []string, error) {
	f.merges++
	return f.statement, f.tags, f.err
}

func (f *fakeMerger) Contradicts(context.Context, string, string) (bool, error) {
	f.compares++
	return f.contradict, nil
}

func fixedNow() time.Time {
	return time.Date(2026, 11, 22, 0, 0, 0, 0, time.UTC)
}

func decisionItems() []extract.Item {
	return []extract.Item{
		{
			Session: "ses_a", Kind: "decision",
			Statement: "Always scope every jj command to the paths the session owns.",
			Tags:      []string{"jj"}, Confidence: "high", Evidence: []string{"2026-11-21T10:00:00Z"},
		},
		{
			Session: "ses_b", Kind: "decision",
			Statement: "Scope every jj command to the paths the session owns.",
			Tags:      []string{"jj"}, Confidence: "medium", Evidence: []string{"2026-11-22T10:00:00Z"},
		},
		{
			Session: "ses_a", Kind: "fact",
			Statement: "The endpoint guard refuses api.openai.com.",
			Tags:      []string{"guard"}, Confidence: "high", Evidence: []string{"2026-11-21T10:00:00Z"},
		},
		{
			Session: "ses_c", Kind: "pitfall",
			Statement: "Avoid running nix fmt on the whole tree.",
			Tags:      []string{"nix"}, Confidence: "low", Evidence: []string{"2026-11-23T10:00:00Z"},
		},
	}
}

func TestBuildClustersNearDuplicates(t *testing.T) {
	t.Parallel()

	plan, err := Build(context.Background(), Input{Items: decisionItems()}, Options{Now: fixedNow})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if plan.Clusters != 3 {
		t.Fatalf("clusters = %d, want 3 (one merged pair, one fact, one dropped)", plan.Clusters)
	}
	if plan.Dropped != 1 {
		t.Fatalf("dropped = %d, want the low-confidence singleton", plan.Dropped)
	}
	if len(plan.Actions) != 2 {
		t.Fatalf("actions = %d, want 2: %+v", len(plan.Actions), plan.Actions)
	}
	var decision Action
	for _, action := range plan.Actions {
		if action.Kind == "decision" {
			decision = action
		}
	}
	if decision.ClusterSize != 2 || len(decision.Sessions) != 2 || len(decision.Evidence) != 2 {
		t.Fatalf("decision action = %+v, want two items from two sessions", decision)
	}
	if decision.Confidence != "high" {
		t.Fatalf("confidence = %q, want the highest of the cluster", decision.Confidence)
	}
	if decision.Action != "new" || decision.ID == "" || decision.Concept == "" {
		t.Fatalf("action = %+v, want a new concept with an id", decision)
	}
}

func TestBuildIsDeterministic(t *testing.T) {
	t.Parallel()

	first, err := Build(context.Background(), Input{Items: decisionItems()}, Options{Now: fixedNow})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	second, err := Build(context.Background(), Input{Items: decisionItems()}, Options{Now: fixedNow})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("two builds differ:\n%+v\n%+v", first, second)
	}

	// The input order must not change the result.
	shuffled := decisionItems()
	for i, j := 0, len(shuffled)-1; i < j; i, j = i+1, j-1 {
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	}
	third, err := Build(context.Background(), Input{Items: shuffled}, Options{Now: fixedNow})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if !reflect.DeepEqual(first, third) {
		t.Fatalf("a shuffled input changed the plan:\n%+v\n%+v", first, third)
	}

	// A JSON round trip must also be stable, which proves sorted map keys reach the output.
	firstJSON, err := json.Marshal(first)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	secondJSON, err := json.Marshal(second)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(firstJSON) != string(secondJSON) {
		t.Fatal("the JSON of two identical builds differs")
	}
}

func TestBuildMergesWithTheModel(t *testing.T) {
	t.Parallel()

	merger := &fakeMerger{
		statement: "Scope every jj command to the paths the session owns.",
		tags:      []string{"jj", "commands"},
	}
	plan, err := Build(context.Background(), Input{Items: decisionItems()}, Options{Now: fixedNow, Merger: merger})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if merger.merges != 1 {
		t.Fatalf("merge calls = %d, want 1", merger.merges)
	}
	if plan.Merged != 1 {
		t.Fatalf("merged = %d, want 1", plan.Merged)
	}
	var decision Action
	for _, action := range plan.Actions {
		if action.Kind == "decision" {
			decision = action
		}
	}
	if decision.Statement != merger.statement {
		t.Fatalf("statement = %q, want the merged one", decision.Statement)
	}
	if len(decision.Evidence) != 2 {
		t.Fatalf("evidence = %+v, want the union", decision.Evidence)
	}
	if decision.MergeError != "" {
		t.Fatalf("merge error = %q", decision.MergeError)
	}
	if len(decision.Tags) != 2 {
		t.Fatalf("tags = %v, want the union of the cluster and the model", decision.Tags)
	}
}

func TestBuildKeepsTheRepresentativeOnMergeError(t *testing.T) {
	t.Parallel()

	merger := &fakeMerger{err: context.DeadlineExceeded}
	plan, err := Build(context.Background(), Input{Items: decisionItems()}, Options{Now: fixedNow, Merger: merger})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	var decision Action
	for _, action := range plan.Actions {
		if action.Kind == "decision" {
			decision = action
		}
	}
	if decision.Statement == "" {
		t.Fatal("a failed merge left an empty statement")
	}
	if decision.MergeError == "" {
		t.Fatal("a failed merge is not recorded")
	}
}

func TestBuildComparesWithTheBundle(t *testing.T) {
	t.Parallel()

	statement := "Always scope every jj command to the paths the session owns."
	concepts := []bundle.Concept{
		{
			ID:          "path-scoped-jj",
			Kind:        "decision",
			Type:        "Decision",
			Title:       "Scope every jj command to the paths the session owns.",
			Description: statement,
			Statement:   statement,
			RelPath:     "decisions/path-scoped-jj.md",
			Status:      "stable",
		},
	}
	merger := &fakeMerger{statement: statement}
	plan, err := Build(context.Background(), Input{Items: decisionItems(), Concepts: concepts},
		Options{Now: fixedNow, Merger: merger})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	var decision Action
	for _, action := range plan.Actions {
		if action.Kind == "decision" {
			decision = action
		}
	}
	if decision.Action != "update" {
		t.Fatalf("action = %q, want update", decision.Action)
	}
	if decision.Existing != "path-scoped-jj" || decision.Target != "decisions/path-scoped-jj.md" {
		t.Fatalf("action = %+v", decision)
	}
	if decision.Similarity < UpdateThreshold {
		t.Fatalf("similarity = %f", decision.Similarity)
	}

	merger.contradict = true
	conflict, err := Build(context.Background(), Input{Items: decisionItems(), Concepts: concepts},
		Options{Now: fixedNow, Merger: merger})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	for _, action := range conflict.Actions {
		if action.Kind == "decision" {
			if action.Action != "conflict" || action.Target != "" {
				t.Fatalf("action = %+v, want a conflict with no target", action)
			}
		}
	}
}

func TestBuildDraftsSkills(t *testing.T) {
	t.Parallel()

	items := []extract.Item{
		{Session: "ses_1", Kind: "runbook", Statement: "Rebuild the host with nixos-rebuild switch.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T10:00:00Z"}},
		{Session: "ses_2", Kind: "runbook", Statement: "Rebuild the host with nixos-rebuild switch.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T11:00:00Z"}},
		{Session: "ses_3", Kind: "runbook", Statement: "Rebuild the host with nixos-rebuild switch.", Tags: []string{"nix"}, Confidence: "medium", Evidence: []string{"2026-11-21T12:00:00Z"}},
	}
	commands := map[string][]string{
		"ses_1": {"nix build .#host", "nixos-rebuild switch --flake .#host"},
		"ses_2": {"nix build .#host", "nixos-rebuild switch --flake .#host", "systemctl status"},
		"ses_3": {"nixos-rebuild switch --flake .#host"},
	}
	plan, err := Build(context.Background(), Input{Items: items, Commands: commands},
		Options{Now: fixedNow, MinSessions: 3})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if len(plan.Skills) != 1 {
		t.Fatalf("skills = %d, want 1: %+v", len(plan.Skills), plan.Skills)
	}
	skill := plan.Skills[0]
	if len(skill.Sessions) != 3 {
		t.Fatalf("sessions = %v", skill.Sessions)
	}
	wantCommands := []string{"nix build .#host", "nixos-rebuild switch --flake .#host", "systemctl status"}
	if !reflect.DeepEqual(skill.Commands, wantCommands) {
		t.Fatalf("commands = %v, want the ordered union %v", skill.Commands, wantCommands)
	}
	if skill.Title == "" || skill.Description == "" || skill.ID == "" {
		t.Fatalf("skill = %+v", skill)
	}
	if len(skill.Evidence) != 3 {
		t.Fatalf("evidence = %+v, want three sessions", skill.Evidence)
	}

	// Two sessions are not enough.
	few, err := Build(context.Background(), Input{Items: items, Commands: commands},
		Options{Now: fixedNow, MinSessions: 4})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if len(few.Skills) != 0 {
		t.Fatalf("skills = %d, want none below the session minimum", len(few.Skills))
	}
}

func TestBuildWithNoCandidates(t *testing.T) {
	t.Parallel()

	plan, err := Build(context.Background(), Input{}, Options{Now: fixedNow})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if plan.Items != 0 || len(plan.Actions) != 0 || len(plan.Summaries) != 0 {
		t.Fatalf("plan = %+v, want an empty plan", plan)
	}
	if plan.GeneratedAt == "" {
		t.Fatal("the plan has no timestamp")
	}
}

func TestTitleIsAPhrase(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		statement string
		wantLen   int
		wantNoEnd string
	}{
		{
			name:      "cuts at a word boundary with an unbalanced backtick",
			statement: "The Strata frontier profile configuration on host `brys` is derived from `data/llm.nix` in the repository.",
			wantLen:   0,
			wantNoEnd: " ",
		},
		{
			name:      "takes only the first sentence",
			statement: "First sentence here. Second sentence must not appear.",
			wantLen:   19,
			wantNoEnd: " ",
		},
		{
			name:      "drops a trailing connector",
			statement: "The configuration is derived from the model file and",
			wantLen:   0,
			wantNoEnd: "and",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			title := Title(test.statement)
			if title == "" {
				t.Fatal("Title returned an empty string")
			}
			if len([]rune(title)) > TitleMaxRunes {
				t.Fatalf("title has %d runes, want at most %d: %q", len([]rune(title)), TitleMaxRunes, title)
			}
			if test.wantLen > 0 && len([]rune(title)) != test.wantLen {
				t.Fatalf("title = %q (%d runes), want %d", title, len([]rune(title)), test.wantLen)
			}
			if strings.Contains(title, "Second sentence") {
				t.Fatalf("the title crossed the sentence boundary: %q", title)
			}
			if strings.HasSuffix(title, " ") || strings.HasSuffix(title, ",") ||
				strings.HasSuffix(title, ";") || strings.HasSuffix(title, ":") {
				t.Fatalf("the title ends on a cut: %q", title)
			}
			if test.wantNoEnd != "" && strings.HasSuffix(strings.ToLower(title), " "+test.wantNoEnd) {
				t.Fatalf("the title keeps the trailing connector: %q", title)
			}
			if strings.Count(title, "`")%2 == 1 {
				t.Fatalf("the title has an unmatched backtick: %q", title)
			}
		})
	}

	long := "The Strata frontier profile configuration on host `brys` is derived from `data/llm.nix` in the repository."
	action := Action{Statement: long}
	action.Title = Title(action.Statement)
	action.ID = "placeholder"
	if !strings.Contains(action.Title, "Strata") {
		t.Fatalf("title = %q", action.Title)
	}
}

func TestTitleDropsATrailingCompoundModifier(t *testing.T) {
	t.Parallel()

	title := Title("In the nix-configs repo, agent sessions must maintain a session-level worklog and board in the cache directory.")
	if strings.HasSuffix(title, "session-level") {
		t.Fatalf("title = %q, a cut compound modifier survived", title)
	}
	if !strings.HasPrefix(title, "In the nix-configs repo, agent sessions must maintain") {
		t.Fatalf("title = %q", title)
	}
}

func TestSkillKeepsTheSharedStepsFirst(t *testing.T) {
	t.Parallel()

	items := []extract.Item{
		{Session: "s1", Kind: "runbook", Statement: "Deploy the host with the release script safely.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T10:00:00Z"}},
		{Session: "s2", Kind: "runbook", Statement: "Deploy the host with the release script safely.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T11:00:00Z"}},
		{Session: "s3", Kind: "runbook", Statement: "Deploy the host with the release script safely.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T12:00:00Z"}},
	}
	commands := map[string][]string{
		"s1": {"nix build .#host", "nixos-rebuild switch", "systemctl status", "noise a1", "noise a2", "noise a3", "noise a4", "noise a5", "noise a6", "noise a7", "noise a8", "noise a9", "noise a10", "noise a11"},
		"s2": {"nix build .#host", "nixos-rebuild switch", "systemctl status", "noise b1", "noise b2", "noise b3", "noise b4"},
		"s3": {"nix build .#host", "nixos-rebuild switch", "systemctl status", "noise c1"},
	}
	plan, err := Build(context.Background(), Input{Items: items, Commands: commands},
		Options{Now: fixedNow, MinSessions: 3})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if len(plan.Skills) != 1 {
		t.Fatalf("skills = %d, want 1", len(plan.Skills))
	}
	steps := plan.Skills[0].Commands
	if len(steps) > MaxSteps {
		t.Fatalf("steps = %d, want at most %d", len(steps), MaxSteps)
	}
	want := []string{"nix build .#host", "nixos-rebuild switch", "systemctl status"}
	if !reflect.DeepEqual(steps[:3], want) {
		t.Fatalf("the shared steps do not lead: %v", steps)
	}
}

func TestJoinPairTagRule(t *testing.T) {
	t.Parallel()

	// a and b share two of nine trigrams: raw Jaccard 0.222, between the tag pair threshold
	// (0.22) and the default threshold (0.35).
	a := map[string]struct{}{"a": {}, "b": {}, "c": {}, "d": {}}
	b := map[string]struct{}{"a": {}, "b": {}, "e": {}, "f": {}, "g": {}, "h": {}, "i": {}}
	if got := textsim.Jaccard(a, b); got < TagPairThreshold || got >= DefaultThreshold {
		t.Fatalf("the fixture scores %f, outside [%f, %f)", got, TagPairThreshold, DefaultThreshold)
	}
	leadA, leadB := a, b

	tests := []struct {
		name         string
		tagsA, tagsB []string
		want         bool
	}{
		{name: "two shared tags join", tagsA: []string{"nix", "brys"}, tagsB: []string{"brys", "nix"}, want: true},
		{name: "one shared tag does not", tagsA: []string{"nix"}, tagsB: []string{"nix"}, want: false},
		{name: "no shared tag does not", tagsA: []string{"nix"}, tagsB: []string{"brys"}, want: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if got := joinPair(a, leadA, b, leadB, test.tagsA, test.tagsB, DefaultThreshold); got != test.want {
				t.Fatalf("joinPair = %v, want %v", got, test.want)
			}
		})
	}

	// A raw score under 0.22 is too weak even with two shared tags.
	weakA := map[string]struct{}{"a": {}, "b": {}, "c": {}, "d": {}}
	weakB := map[string]struct{}{"a": {}, "e": {}, "f": {}, "g": {}, "h": {}, "i": {}, "j": {}, "k": {}, "l": {}}
	if raw := textsim.Jaccard(weakA, weakB); raw >= TagPairThreshold {
		t.Fatalf("the weak fixture scores %f, want under %f", raw, TagPairThreshold)
	}
	if joinPair(weakA, weakA, weakB, weakB, []string{"nix", "brys"}, []string{"nix", "brys"}, DefaultThreshold) {
		t.Fatal("joinPair joined a pair below the tag pair threshold")
	}

	// A long trailing detail can dilute the statement score; the lead sentence still joins.
	longA := map[string]struct{}{"lead1": {}, "lead2": {}, "lead3": {}, "det1": {}, "det2": {}, "det3": {}, "det4": {}, "det5": {}, "det6": {}, "det7": {}, "det8": {}, "det9": {}}
	longB := map[string]struct{}{"lead1": {}, "lead2": {}, "lead3": {}, "other1": {}, "other2": {}, "other3": {}, "other4": {}, "other5": {}, "other6": {}, "other7": {}, "other8": {}, "other9": {}}
	if raw := textsim.Jaccard(longA, longB); raw >= TagPairThreshold {
		t.Fatalf("the long fixture scores %f, want under %f", raw, TagPairThreshold)
	}
	if !joinPair(longA, map[string]struct{}{"lead1": {}, "lead2": {}, "lead3": {}},
		longB, map[string]struct{}{"lead1": {}, "lead2": {}, "lead3": {}},
		[]string{"nix", "brys"}, []string{"nix", "brys"}, DefaultThreshold) {
		t.Fatal("joinPair ignored two shared tags and a matching lead sentence")
	}
}

func TestBuildTagAwareMerge(t *testing.T) {
	t.Parallel()

	pair := func(tagsA, tagsB []string) []extract.Item {
		return []extract.Item{
			{Session: "ses_a", Kind: "preference", Statement: "Scope jj commands to the paths the session owns, always.", Tags: tagsA, Confidence: "high", Evidence: []string{"2026-11-21"}},
			{Session: "ses_b", Kind: "preference", Statement: "Scope jj commands to the paths that a session owns.", Tags: tagsB, Confidence: "high", Evidence: []string{"2026-11-22"}},
		}
	}
	raw := textsim.Similarity("Scope jj commands to the paths the session owns, always.",
		"Scope jj commands to the paths that a session owns.")
	if raw >= DefaultThreshold {
		t.Fatalf("the fixture scores %f, want under the default threshold", raw)
	}

	tagged, err := Build(context.Background(), Input{Items: pair([]string{"jj", "paths"}, []string{"jj", "paths"})},
		Options{Now: fixedNow})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if tagged.Clusters != 1 {
		t.Fatalf("clusters = %d, want 1 with two shared tags (raw %f)", tagged.Clusters, raw)
	}

	// The same text with disjoint tags keeps the plain threshold, which this pair misses.
	untagged, err := Build(context.Background(), Input{Items: pair([]string{"jj"}, []string{"paths"})},
		Options{Now: fixedNow})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if untagged.Clusters != 2 {
		t.Fatalf("clusters = %d, want 2 without a shared tag (raw %f)", untagged.Clusters, raw)
	}
}

func TestBuildCapsTheProposal(t *testing.T) {
	t.Parallel()

	items := []extract.Item{
		// Runbook pair across two sessions: rank 1.
		{Session: "ses_1", Kind: "runbook", Statement: "Deploy the host with the release script.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T10:00:00Z"}},
		{Session: "ses_2", Kind: "runbook", Statement: "Deploy the host with the release script.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T11:00:00Z"}},
		// One session, three items: rank 2.
		{Session: "ses_3", Kind: "fact", Statement: "The sqlite3 CLI carries no driver.", Tags: []string{"sqlite"}, Confidence: "high", Evidence: []string{"2026-11-21T12:00:00Z"}},
		{Session: "ses_3", Kind: "fact", Statement: "The sqlite3 CLI carries no driver.", Tags: []string{"sqlite"}, Confidence: "high", Evidence: []string{"2026-11-21T12:00:00Z"}},
		{Session: "ses_3", Kind: "fact", Statement: "The sqlite3 CLI carries no driver.", Tags: []string{"sqlite"}, Confidence: "high", Evidence: []string{"2026-11-21T12:00:00Z"}},
		// Singletons, one session each: kind priority decides between them.
		{Session: "ses_4", Kind: "decision", Statement: "Prefer explicit paths over prefixes.", Tags: []string{"jj"}, Confidence: "high", Evidence: []string{"2026-11-21T13:00:00Z"}},
		{Session: "ses_4", Kind: "pitfall", Statement: "Never run a bare nix flake check.", Tags: []string{"nix"}, Confidence: "high", Evidence: []string{"2026-11-21T14:00:00Z"}},
	}

	plan, err := Build(context.Background(), Input{Items: items}, Options{Now: fixedNow, MaxConcepts: 2})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if plan.Clusters != 4 || plan.Proposed != 2 || len(plan.Actions) != 2 {
		t.Fatalf("clusters %d, proposed %d, actions %d; want 4, 2, 2", plan.Clusters, plan.Proposed, len(plan.Actions))
	}
	if len(plan.NotProposed) != 2 {
		t.Fatalf("not proposed = %d, want 2", len(plan.NotProposed))
	}
	if plan.Actions[0].Kind != "fact" || plan.Actions[1].Kind != "runbook" {
		t.Fatalf("proposed kinds = %s, %s, want the widest and largest clusters",
			plan.Actions[0].Kind, plan.Actions[1].Kind)
	}
	if plan.NotProposed[0].Kind != "pitfall" || plan.NotProposed[1].Kind != "decision" {
		t.Fatalf("over-cap order = %s, %s, want pitfall before decision",
			plan.NotProposed[0].Kind, plan.NotProposed[1].Kind)
	}

	uncapped, err := Build(context.Background(), Input{Items: items}, Options{Now: fixedNow, MaxConcepts: 0})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if uncapped.Proposed != 4 || len(uncapped.NotProposed) != 0 {
		t.Fatalf("uncapped proposed %d, not proposed %d, want 4 and 0", uncapped.Proposed, len(uncapped.NotProposed))
	}
}
