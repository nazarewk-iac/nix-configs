// Package dream merges the candidate items into clusters, distils skills, compares the result
// with the existing bundle, and returns a plan.
//
// Every step is deterministic: items are sorted, unions are sorted, and clusters are ordered by
// size and by statement. The same candidates therefore give the same plan.
package dream

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"kdn-knowledge/internal/bundle"
	"kdn-knowledge/internal/extract"
	"kdn-knowledge/internal/okfkind"
	"kdn-knowledge/internal/textsim"
)

// Constants of the design.
const (
	// DefaultThreshold is the similarity at which two items join a cluster.
	DefaultThreshold = 0.35
	// DefaultMinSessions is the number of sessions that makes a runbook a skill.
	DefaultMinSessions = 3
	// UpdateThreshold is the similarity at which an item updates an existing concept.
	UpdateThreshold = 0.7
	// MinCommands is the number of ordered commands that a skill needs.
	MinCommands = 3
	// MaxSteps caps a skill draft, so a long session cannot turn it into a transcript.
	MaxSteps = 12
	// DefaultMaxConcepts caps a proposal. Zero means no cap.
	DefaultMaxConcepts = 60
	// SharedTagsForMerge is the number of shared tags that lets two items of one kind join on
	// weaker trigram evidence.
	SharedTagsForMerge = 2
	// TagPairThreshold is that weaker trigram similarity.
	TagPairThreshold = 0.22
)

// kindPriority ranks the kinds when clusters tie on sessions and items.
var kindPriority = map[string]int{
	"runbook":    1,
	"pitfall":    2,
	"decision":   3,
	"preference": 4,
	"fact":       5,
}

// Merger collapses a cluster and answers the contradiction question. A nil merger keeps the
// representative statement and never reports a conflict.
type Merger interface {
	Merge(ctx context.Context, statements []string, tags []string) (string, []string, error)
	Contradicts(ctx context.Context, newStatement, oldStatement string) (bool, error)
}

// Failure is one session that extraction could not finish.
type Failure struct {
	ID       string `json:"id"`
	Reason   string `json:"reason"`
	Attempts int    `json:"attempts"`
}

// Input is everything that one dream run reads.
type Input struct {
	Items    []extract.Item
	Commands map[string][]string
	Concepts []bundle.Concept
	Failures []Failure
}

// Options tune the clustering.
type Options struct {
	Threshold   float64
	MinSessions int
	// MaxConcepts caps the proposal. Zero means no cap; the rest goes to the report.
	MaxConcepts int
	Merger      Merger
	Now         func() time.Time
	Model       string
}

// Evidence is one session and the date that it contributes to a cluster.
type Evidence struct {
	Session string `json:"session"`
	Date    string `json:"date"`
}

// Action is one proposed change to the bundle.
type Action struct {
	Action      string     `json:"action"`
	Kind        string     `json:"kind"`
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Statement   string     `json:"statement"`
	Tags        []string   `json:"tags"`
	Confidence  string     `json:"confidence"`
	Evidence    []Evidence `json:"evidence"`
	Sessions    []string   `json:"sessions"`
	Concept     string     `json:"concept"`
	Target      string     `json:"target,omitempty"`
	Existing    string     `json:"existing,omitempty"`
	Similarity  float64    `json:"similarity,omitempty"`
	ClusterSize int        `json:"cluster_size"`
	MergeError  string     `json:"merge_error,omitempty"`
}

// SkillDraft is one proposed skill.
type SkillDraft struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Statement   string     `json:"statement"`
	Tags        []string   `json:"tags"`
	Sessions    []string   `json:"sessions"`
	Commands    []string   `json:"commands"`
	Evidence    []Evidence `json:"evidence"`
	Concept     string     `json:"concept"`
}

// ClusterSummary is one row of the report.
type ClusterSummary struct {
	Kind      string `json:"kind"`
	Statement string `json:"statement"`
	Items     int    `json:"items"`
	Evidence  int    `json:"evidence"`
	Sessions  int    `json:"sessions"`
	Merged    bool   `json:"merged"`
	Skill     bool   `json:"skill"`
}

// Plan is proposals/<timestamp>/plan.json.
type Plan struct {
	GeneratedAt string           `json:"generated_at"`
	Model       string           `json:"model,omitempty"`
	Items       int              `json:"items"`
	Sessions    []string         `json:"sessions"`
	Clusters    int              `json:"clusters"`
	Proposed    int              `json:"proposed"`
	Merged      int              `json:"merged"`
	Dropped     int              `json:"dropped"`
	NotProposed []ClusterSummary `json:"not_proposed"`
	Truncated   []string         `json:"truncated_sessions,omitempty"`
	Actions     []Action         `json:"actions"`
	Skills      []SkillDraft     `json:"skills"`
	Summaries   []ClusterSummary `json:"cluster_summaries"`
	Failures    []Failure        `json:"failures"`
}

// cluster is the internal form before the plan is built.
type cluster struct {
	kind       string
	items      []extract.Item
	statement  string
	tags       []string
	confidence string
	evidence   []Evidence
	sessions   []string
	mergeError string
	merged     bool
	skill      bool
}

// Build turns candidates into a plan. It calls the merger only for clusters of two or more
// items and for concepts that are similar enough to compare.
func Build(ctx context.Context, input Input, opts Options) (*Plan, error) {
	if opts.Threshold <= 0 {
		opts.Threshold = DefaultThreshold
	}
	if opts.MinSessions <= 0 {
		opts.MinSessions = DefaultMinSessions
	}
	now := time.Now
	if opts.Now != nil {
		now = opts.Now
	}

	items := append([]extract.Item{}, input.Items...)
	sortItems(items)

	clusters := clusterItems(items, opts.Threshold)
	plan := &Plan{
		GeneratedAt: now().UTC().Format(time.RFC3339),
		Model:       opts.Model,
		Items:       len(items),
		Sessions:    uniqueSessions(items),
		Clusters:    len(clusters),
		Actions:     []Action{},
		Skills:      []SkillDraft{},
		Summaries:   []ClusterSummary{},
		Failures:    append([]Failure{}, input.Failures...),
	}

	kept := make([]*cluster, 0, len(clusters))
	for _, candidate := range clusters {
		if len(candidate.items) == 1 && candidate.confidence == "low" {
			plan.Dropped++
			continue
		}
		kept = append(kept, candidate)
	}
	rankClusters(kept)

	proposed := kept
	over := []*cluster{}
	if opts.MaxConcepts > 0 && len(kept) > opts.MaxConcepts {
		proposed = kept[:opts.MaxConcepts]
		over = kept[opts.MaxConcepts:]
	}
	plan.Proposed = len(proposed)
	for _, candidate := range over {
		plane := ClusterSummary{
			Kind:      candidate.kind,
			Statement: candidate.statement,
			Items:     len(candidate.items),
			Evidence:  len(candidate.evidence),
			Sessions:  len(candidate.sessions),
		}
		plan.NotProposed = append(plan.NotProposed, plane)
	}

	// Merge only what the proposal keeps: the cap is a review budget, and a model call for a
	// cluster that no human will see is wasted.
	for _, candidate := range proposed {
		if len(candidate.items) > 1 {
			plan.Merged++
		}
		if err := mergeCluster(ctx, candidate, opts.Merger); err != nil {
			candidate.mergeError = err.Error()
		}
		candidate.statement = strings.TrimSpace(candidate.statement)
		if candidate.statement == "" {
			candidate.statement = candidate.items[0].Statement
		}
	}

	used := map[string]bool{}
	for _, candidate := range proposed {
		action := propose(ctx, candidate, input.Concepts, opts, used)
		plan.Actions = append(plan.Actions, action)
		if skill, ok := draftSkill(candidate, input.Commands, opts.MinSessions, used); ok {
			plan.Skills = append(plan.Skills, skill)
			candidate.skill = true
		}
	}

	sort.SliceStable(plan.Actions, func(i, j int) bool {
		if plan.Actions[i].Kind != plan.Actions[j].Kind {
			return plan.Actions[i].Kind < plan.Actions[j].Kind
		}
		if plan.Actions[i].ID != plan.Actions[j].ID {
			return plan.Actions[i].ID < plan.Actions[j].ID
		}
		return plan.Actions[i].Statement < plan.Actions[j].Statement
	})
	sort.SliceStable(plan.Skills, func(i, j int) bool { return plan.Skills[i].ID < plan.Skills[j].ID })

	for _, candidate := range kept {
		summary := ClusterSummary{
			Kind:      candidate.kind,
			Statement: candidate.statement,
			Items:     len(candidate.items),
			Evidence:  len(candidate.evidence),
			Sessions:  len(candidate.sessions),
			Merged:    candidate.merged,
			Skill:     candidate.skill,
		}
		plan.Summaries = append(plan.Summaries, summary)
	}
	sort.SliceStable(plan.Summaries, func(i, j int) bool {
		a, b := plan.Summaries[i], plan.Summaries[j]
		if a.Evidence != b.Evidence {
			return a.Evidence > b.Evidence
		}
		if a.Sessions != b.Sessions {
			return a.Sessions > b.Sessions
		}
		if a.Statement != b.Statement {
			return a.Statement < b.Statement
		}
		return a.Kind < b.Kind
	})
	return plan, nil
}

// clusterItems groups by kind, then by transitive similarity inside each kind.
func clusterItems(items []extract.Item, threshold float64) []*cluster {
	byKind := map[string][]extract.Item{}
	for _, item := range items {
		byKind[item.Kind] = append(byKind[item.Kind], item)
	}
	kinds := make([]string, 0, len(byKind))
	for kind := range byKind {
		kinds = append(kinds, kind)
	}
	sort.Strings(kinds)

	clusters := make([]*cluster, 0, len(items))
	for _, kind := range kinds {
		group := byKind[kind]
		grams := make([]map[string]struct{}, len(group))
		leads := make([]map[string]struct{}, len(group))
		for i, item := range group {
			grams[i] = textsim.Trigrams(item.Statement)
			leads[i] = textsim.Trigrams(FirstSentence(item.Statement))
		}
		parent := make([]int, len(group))
		for i := range parent {
			parent[i] = i
		}
		var find func(int) int
		find = func(i int) int {
			for parent[i] != i {
				parent[i] = parent[parent[i]]
				i = parent[i]
			}
			return i
		}
		union := func(a, b int) {
			ra, rb := find(a), find(b)
			if ra != rb {
				parent[ra] = rb
			}
		}
		for i := 0; i < len(group); i++ {
			for j := i + 1; j < len(group); j++ {
				if joinPair(grams[i], leads[i], grams[j], leads[j], group[i].Tags, group[j].Tags, threshold) {
					union(i, j)
				}
			}
		}
		components := map[int][]extract.Item{}
		for i := range group {
			root := find(i)
			components[root] = append(components[root], group[i])
		}
		roots := make([]int, 0, len(components))
		for root := range components {
			roots = append(roots, root)
		}
		sort.Ints(roots)
		for _, root := range roots {
			members := components[root]
			sortItems(members)
			clusters = append(clusters, &cluster{
				kind:       kind,
				items:      members,
				statement:  members[0].Statement,
				tags:       unionTags(members),
				confidence: bestConfidence(members),
				evidence:   clusterEvidence(members),
				sessions:   clusterSessions(members),
			})
		}
	}
	sort.SliceStable(clusters, func(i, j int) bool {
		if len(clusters[i].items) != len(clusters[j].items) {
			return len(clusters[i].items) > len(clusters[j].items)
		}
		if clusters[i].kind != clusters[j].kind {
			return clusters[i].kind < clusters[j].kind
		}
		return clusters[i].statement < clusters[j].statement
	})
	return clusters
}

// joinPair reports whether two items of one kind belong to one cluster.
//
// The trigram score gets the tag bonus first. A weaker score is enough when the two items share
// at least two tags: a paraphrase of one fact usually keeps the topic tags but changes many
// words, and that is how a flood of near-identical facts becomes one concept.
//
// The weaker score is measured on the whole statement or on its first sentence. A long statement
// carries its detail into the trigram union and dilutes a shared phrase; the first sentence is
// the part that states the fact.
func joinPair(a, leadA, b, leadB map[string]struct{}, tagsA, tagsB []string, threshold float64) bool {
	raw := textsim.Jaccard(a, b)
	if raw == 0 && len(leadA) == 0 {
		return false
	}
	score := raw
	if textsim.TagsIntersect(tagsA, tagsB) {
		score += textsim.TagBonus
		if score > 1 {
			score = 1
		}
	}
	if score >= threshold {
		return true
	}
	if sharedTagCount(tagsA, tagsB) < SharedTagsForMerge {
		return false
	}
	if raw >= TagPairThreshold {
		return true
	}
	return textsim.Jaccard(leadA, leadB) >= TagPairThreshold
}

// sharedTagCount counts the lowercased tags that two lists share.
func sharedTagCount(a, b []string) int {
	seen := make(map[string]struct{}, len(a))
	for _, tag := range a {
		seen[strings.ToLower(strings.TrimSpace(tag))] = struct{}{}
	}
	count := 0
	for _, tag := range b {
		if _, ok := seen[strings.ToLower(strings.TrimSpace(tag))]; ok {
			count++
		}
	}
	return count
}

// rankClusters orders the clusters that a proposal would keep: the widest evidence first, then
// the largest cluster, then the kind that a human should read first.
func rankClusters(clusters []*cluster) {
	sort.SliceStable(clusters, func(i, j int) bool {
		a, b := clusters[i], clusters[j]
		if len(a.sessions) != len(b.sessions) {
			return len(a.sessions) > len(b.sessions)
		}
		if len(a.items) != len(b.items) {
			return len(a.items) > len(b.items)
		}
		if kindPriority[a.kind] != kindPriority[b.kind] {
			return kindPriority[a.kind] < kindPriority[b.kind]
		}
		if a.kind != b.kind {
			return a.kind < b.kind
		}
		return a.statement < b.statement
	})
}

func mergeCluster(ctx context.Context, candidate *cluster, merger Merger) error {
	if len(candidate.items) < 2 || merger == nil {
		return nil
	}
	statements := make([]string, 0, len(candidate.items))
	for _, item := range candidate.items {
		statements = append(statements, item.Statement)
	}
	statement, tags, err := merger.Merge(ctx, statements, candidate.tags)
	if err != nil {
		return err
	}
	candidate.merged = true
	candidate.statement = statement
	candidate.tags = textsim.NormalizeTags(append(candidate.tags, tags...))
	return nil
}

func propose(ctx context.Context, candidate *cluster, concepts []bundle.Concept, opts Options, used map[string]bool) Action {
	action := Action{
		Kind:        candidate.kind,
		Title:       Title(candidate.statement),
		Statement:   candidate.statement,
		Tags:        candidate.tags,
		Confidence:  candidate.confidence,
		Evidence:    candidate.evidence,
		Sessions:    candidate.sessions,
		ClusterSize: len(candidate.items),
		MergeError:  candidate.mergeError,
	}
	match, score := bestConcept(candidate, concepts)
	if match != nil && score >= UpdateThreshold {
		action.Action = "update"
		action.Existing = match.ID
		action.ID = match.ID
		action.Similarity = round(score)
		action.Target = match.RelPath
		if opts.Merger != nil {
			contradicts, err := opts.Merger.Contradicts(ctx, candidate.statement, match.Statement)
			if err == nil && contradicts {
				action.Action = "conflict"
				action.Target = ""
			}
		}
	} else {
		action.Action = "new"
		action.ID = uniqueID(textsim.Slug(FirstSentence(candidate.statement), 8), candidate.kind, used)
		action.Target = okfkind.Dir(candidate.kind) + "/" + action.ID + ".md"
	}
	action.Concept = "concepts/" + action.ID + ".md"
	return action
}

func bestConcept(candidate *cluster, concepts []bundle.Concept) (*bundle.Concept, float64) {
	var best *bundle.Concept
	bestScore := 0.0
	for i := range concepts {
		concept := &concepts[i]
		if concept.Kind != candidate.kind {
			continue
		}
		score := textsim.SimilarityWithTags(candidate.statement, concept.Label(), candidate.tags, nil)
		if score > bestScore || (score == bestScore && best != nil && concept.ID < best.ID) {
			best = concept
			bestScore = score
		}
	}
	return best, bestScore
}

func draftSkill(candidate *cluster, commands map[string][]string, minSessions int, used map[string]bool) (SkillDraft, bool) {
	if candidate.kind != "runbook" || len(candidate.sessions) < minSessions {
		return SkillDraft{}, false
	}
	// A skill is the part of the procedure that repeats. Count the sessions of each command,
	// keep the shared ones first in first-seen order, and cap the list so a long session cannot
	// turn a skill into a transcript.
	shared := make([]string, 0, 8)
	firstSeen := make([]string, 0, 32)
	counts := map[string]int{}
	seen := map[string]struct{}{}
	for _, session := range candidate.sessions {
		perSession := map[string]struct{}{}
		for _, command := range commands[session] {
			clean := strings.TrimSpace(command)
			if clean == "" {
				continue
			}
			if index := strings.IndexAny(clean, "\n"); index >= 0 {
				clean = strings.TrimSpace(clean[:index])
			}
			if len(clean) > 200 {
				clean = clean[:200]
			}
			if _, ok := perSession[clean]; ok {
				continue
			}
			perSession[clean] = struct{}{}
			if _, ok := seen[clean]; !ok {
				seen[clean] = struct{}{}
				firstSeen = append(firstSeen, clean)
			}
			counts[clean]++
		}
	}
	for _, command := range firstSeen {
		if counts[command] >= 2 {
			shared = append(shared, command)
		}
	}
	ordered := shared
	if len(ordered) < MinCommands {
		for _, command := range firstSeen {
			if counts[command] >= 2 {
				continue
			}
			ordered = append(ordered, command)
			if len(ordered) >= MinCommands {
				break
			}
		}
	}
	if len(ordered) > MaxSteps {
		ordered = ordered[:MaxSteps]
	}
	if len(ordered) < MinCommands {
		return SkillDraft{}, false
	}
	title := Title(candidate.statement)
	slug := textsim.Slug(strings.Join(candidate.tags, " "), 3)
	if slug == "" {
		slug = textsim.Slug(FirstSentence(candidate.statement), 8)
	}
	return SkillDraft{
		ID:          uniqueID(slug, "skill", used),
		Title:       title,
		Description: describe(candidate.statement),
		Statement:   candidate.statement,
		Tags:        candidate.tags,
		Sessions:    candidate.sessions,
		Commands:    ordered,
		Evidence:    candidate.evidence,
		Concept:     "",
	}, true
}

func uniqueID(slug, kind string, used map[string]bool) string {
	if slug == "" {
		slug = kind
	}
	candidate := slug
	for suffix := 2; used[candidate]; suffix++ {
		candidate = fmt.Sprintf("%s-%d", slug, suffix)
	}
	used[candidate] = true
	return candidate
}

func sortItems(items []extract.Item) {
	sort.SliceStable(items, func(i, j int) bool {
		a, b := items[i], items[j]
		if a.Session != b.Session {
			return a.Session < b.Session
		}
		if a.Statement != b.Statement {
			return a.Statement < b.Statement
		}
		if a.Kind != b.Kind {
			return a.Kind < b.Kind
		}
		return a.Confidence < b.Confidence
	})
}

func unionTags(items []extract.Item) []string {
	tags := make([]string, 0, len(items))
	for _, item := range items {
		tags = append(tags, item.Tags...)
	}
	return textsim.NormalizeTags(tags)
}

func bestConfidence(items []extract.Item) string {
	best := "low"
	for _, item := range items {
		if rank(item.Confidence) > rank(best) {
			best = item.Confidence
		}
	}
	return best
}

func rank(confidence string) int {
	switch confidence {
	case "high":
		return 3
	case "medium":
		return 2
	default:
		return 1
	}
}

func clusterEvidence(items []extract.Item) []Evidence {
	evidence := make([]Evidence, 0, len(items))
	for _, item := range items {
		date := ""
		if len(item.Evidence) > 0 {
			date = item.Evidence[0]
		}
		evidence = append(evidence, Evidence{Session: item.Session, Date: date})
	}
	sort.SliceStable(evidence, func(i, j int) bool {
		if evidence[i].Session != evidence[j].Session {
			return evidence[i].Session < evidence[j].Session
		}
		return evidence[i].Date < evidence[j].Date
	})
	out := evidence[:0]
	for _, value := range evidence {
		if len(out) > 0 && out[len(out)-1] == value {
			continue
		}
		out = append(out, value)
	}
	return out
}

func clusterSessions(items []extract.Item) []string {
	set := map[string]struct{}{}
	for _, item := range items {
		set[item.Session] = struct{}{}
	}
	out := make([]string, 0, len(set))
	for session := range set {
		out = append(out, session)
	}
	sort.Strings(out)
	return out
}

func uniqueSessions(items []extract.Item) []string { return clusterSessions(items) }

// FirstSentence returns the first sentence of text, without its final punctuation. A statement
// with no sentence break counts as one sentence.
func FirstSentence(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	for i := 0; i+1 < len(text); i++ {
		if (text[i] == '.' || text[i] == '!' || text[i] == '?') && text[i+1] == ' ' {
			return strings.TrimSpace(text[:i])
		}
	}
	return text
}

// TitleMaxRunes is the cap of a concept title.
const TitleMaxRunes = 72

// Title turns a statement into a phrase: the first sentence, cut at a word boundary, without
// dangling punctuation, an unmatched backtick, or a trailing connector.
func Title(text string) string {
	sentence := FirstSentence(text)
	title := sentence
	runes := []rune(title)
	if len(runes) > TitleMaxRunes {
		// Reserve one rune for the ellipsis: a cut title must look cut, not finished.
		title = string(runes[:TitleMaxRunes-1])
		if index := strings.LastIndex(title, " "); index > 0 {
			title = title[:index]
		}
	}
	title = strings.TrimRight(title, " ,;:.")
	if strings.Count(title, "`")%2 == 1 {
		title = strings.TrimSuffix(title, "`")
		title = strings.TrimSpace(title)
	}
	// A trailing hyphenated word is usually a compound modifier whose noun the cut removed:
	// "maintain a session-level" reads as a cut, "must maintain" reads as a phrase.
	if index := strings.LastIndex(title, " "); index > 0 {
		last := title[index+1:]
		if strings.Contains(last, "-") && !strings.ContainsAny(last, "`/.") {
			title = strings.TrimRight(title[:index], " ,;:.")
		}
	}
	for {
		lowered := strings.ToLower(title)
		trimmed := false
		for _, word := range []string{
			" the", " and", " or", " of", " to", " with", " from", " on", " in", " for",
			" is", " are", " was", " were", " a", " an",
		} {
			if strings.HasSuffix(lowered, word) {
				title = strings.TrimRight(title[:len(title)-len(word)], " ,;:.")
				trimmed = true
				break
			}
		}
		if !trimmed {
			break
		}
	}
	title = strings.TrimSpace(title)
	if title == "" {
		return describe(text)
	}
	if len([]rune(sentence)) > len([]rune(title)) && !strings.HasSuffix(title, "…") {
		title += "…"
	}
	return title
}

func describe(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	if len(text) <= 180 {
		return text
	}
	runes := []rune(text)
	return string(runes[:177]) + "…"
}

func round(value float64) float64 {
	return float64(int(value*100+0.5)) / 100
}
