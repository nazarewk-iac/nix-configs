// Package extract turns one normalised session into candidate knowledge items.
//
// The extraction prompt is fixed text in this file. The reply must be a JSON array; one repair
// attempt is allowed, then the session fails and the run continues.
package extract

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"kdn-knowledge/internal/corpus"
	"kdn-knowledge/internal/llm"
	"kdn-knowledge/internal/store"
	"kdn-knowledge/internal/textsim"
)

// SystemPrompt is the fixed instruction of every extraction call.
//
// The wording follows the design. One line names the five kinds: without it the model labels
// every item "fact", and a runbook can never be distilled into a skill.
const SystemPrompt = `You extract durable engineering knowledge from an agent session. Reply with a JSON array only.
Each item is {"kind","statement","tags","confidence","evidence"}. "kind" is one of: decision,
runbook, pitfall, preference, fact. Keep an item only if it
would still be true and useful in a different session next month. Drop chatter, plans, status
reports, restatements of the user's request, and anything that names a temporary path, port or
commit id. Prefer five good items over thirty weak ones. If the session carries nothing
durable, reply with [].`

// DefaultChunkChars is the split size that --chunk-chars uses when a caller names it without a
// value. Chunking is off by default: the frontier window holds a whole session.
const DefaultChunkChars = 24000

// MaxPromptChars is the fail-fast limit of one call. The frontier has a 512k token window; at
// about four characters per token this keeps a wide margin for the reply.
const MaxPromptChars = 1500000

// DedupeThreshold merges items that two chunks of the same session both produced. A one-word
// difference still merges: eight words in common out of nine score 0.86.
const DedupeThreshold = 0.8

// Kinds is the closed vocabulary of an item.
var Kinds = []string{"decision", "runbook", "pitfall", "preference", "fact"}

// Item is one extracted knowledge item.
type Item struct {
	Session    string   `json:"session"`
	Kind       string   `json:"kind"`
	Statement  string   `json:"statement"`
	Tags       []string `json:"tags"`
	Confidence string   `json:"confidence"`
	Evidence   []string `json:"evidence"`
}

// File is candidates/<session>.json.
type File struct {
	Session     string `json:"session"`
	Model       string `json:"model"`
	ExtractedAt string `json:"extracted_at"`
	Truncated   bool   `json:"truncated,omitempty"`
	Items       []Item `json:"items"`
}

// Options tunes one session extraction.
type Options struct {
	// ChunkChars splits the transcript at this many characters, on message boundaries, with one
	// message of overlap. Zero sends the whole session in one call.
	ChunkChars int
	// MaxChunks caps the calls of one session. Zero means no cap.
	MaxChunks int
}

// Chunk is one model call worth of transcript.
type Chunk struct {
	Index    int
	Total    int
	Messages int
	Text     string
}

// Result is the outcome of one session extraction.
type Result struct {
	Items     []Item
	Chunks    int
	Calls     int
	Truncated bool
	Duration  time.Duration
}

// Chunks renders the transcript and splits it only when ChunkChars asks for a split.
func Chunks(session corpus.Session, opts Options) ([]Chunk, bool, error) {
	messages := session.Messages
	if len(messages) == 0 {
		return nil, false, fmt.Errorf("session %s has no messages", session.ID)
	}
	header := fmt.Sprintf("Title: %s\nDate: %s\n\n", session.Title, session.Started.UTC().Format(time.RFC3339))

	lines := make([]string, 0, len(messages))
	for _, message := range messages {
		lines = append(lines, renderMessage(message))
	}

	if opts.ChunkChars <= 0 {
		var builder strings.Builder
		builder.WriteString(header)
		for _, line := range lines {
			builder.WriteString(line)
			builder.WriteString("\n")
		}
		text := builder.String()
		if len(text) > MaxPromptChars {
			return nil, false, fmt.Errorf(
				"the transcript of %s is %d characters, over the model window; "+
					"pass --chunk-chars %d", session.ID, len(text), DefaultChunkChars)
		}
		return []Chunk{{Index: 1, Total: 1, Messages: len(messages), Text: text}}, false, nil
	}

	budget := opts.ChunkChars
	var chunks []Chunk
	current := make([]string, 0, 16)
	size := 0
	flush := func() {
		if len(current) == 0 {
			return
		}
		var builder strings.Builder
		builder.WriteString(header)
		for _, line := range current {
			builder.WriteString(line)
			builder.WriteString("\n")
		}
		chunks = append(chunks, Chunk{Messages: len(current), Text: builder.String()})
	}
	for _, line := range lines {
		if len(line) > budget {
			line = truncateRunes(line, budget)
		}
		length := len(line) + 1
		if len(current) > 0 && size+length > budget {
			overlap := current[len(current)-1]
			flush()
			current = []string{overlap}
			size = len(overlap) + 1
		}
		current = append(current, line)
		size += length
	}
	flush()

	truncated := false
	if opts.MaxChunks > 0 && len(chunks) > opts.MaxChunks {
		chunks = chunks[:opts.MaxChunks]
		truncated = true
	}
	for i := range chunks {
		chunks[i].Index = i + 1
		chunks[i].Total = len(chunks)
	}
	return chunks, truncated, nil
}

// ExtractSession runs every chunk of one session and returns the deduplicated items.
func ExtractSession(ctx context.Context, client *llm.Client, session corpus.Session, opts Options) (*Result, error) {
	started := time.Now()
	chunks, truncated, err := Chunks(session, opts)
	if err != nil {
		return nil, err
	}
	result := &Result{Chunks: len(chunks), Truncated: truncated}
	items := make([]Item, 0, len(chunks)*3)
	for _, chunk := range chunks {
		result.Calls++
		reply, err := client.Chat(ctx, SystemPrompt, chunk.Text)
		if err != nil {
			return nil, err
		}
		parsed, parseErr := ParseItems(reply.Content)
		if parseErr != nil {
			repair := chunk.Text + "\n\nYour previous reply was rejected: " + parseErr.Error() +
				"\nReply with the JSON array only."
			result.Calls++
			reply, err = client.Chat(ctx, SystemPrompt, repair)
			if err != nil {
				return nil, err
			}
			parsed, parseErr = ParseItems(reply.Content)
			if parseErr != nil {
				return nil, fmt.Errorf("invalid JSON after one repair: %w", parseErr)
			}
		}
		items = append(items, normalize(parsed, session)...)
	}
	result.Items = Dedupe(items, DedupeThreshold)
	result.Duration = time.Since(started)
	return result, nil
}

// ParseItems decodes the model reply. It tolerates a Markdown fence and prose around the array,
// and it coerces the field types that a small model drifts on: a numeric confidence, a single
// string instead of an evidence array, and an unknown kind.
func ParseItems(reply string) ([]Item, error) {
	text := strings.TrimSpace(reply)
	if strings.HasPrefix(text, "```") {
		if index := strings.Index(text, "\n"); index >= 0 {
			text = text[index+1:]
		}
		text = strings.TrimSuffix(strings.TrimSpace(text), "```")
		text = strings.TrimSpace(text)
	}
	start := strings.Index(text, "[")
	if start < 0 {
		return nil, fmt.Errorf("reply has no JSON array")
	}
	end := strings.LastIndex(text, "]")
	if end < start {
		return nil, fmt.Errorf("reply has an unterminated JSON array")
	}
	var raw []struct {
		Kind       json.RawMessage `json:"kind"`
		Statement  json.RawMessage `json:"statement"`
		Tags       json.RawMessage `json:"tags"`
		Confidence json.RawMessage `json:"confidence"`
		Evidence   json.RawMessage `json:"evidence"`
	}
	if err := json.Unmarshal([]byte(text[start:end+1]), &raw); err != nil {
		return nil, fmt.Errorf("reply is not a JSON array of items: %w", err)
	}
	items := make([]Item, 0, len(raw))
	for _, entry := range raw {
		statement := collapse(asString(entry.Statement))
		if statement == "" {
			continue
		}
		items = append(items, Item{
			Kind:       normalizeKind(asString(entry.Kind)),
			Statement:  statement,
			Tags:       asTags(entry.Tags),
			Confidence: asConfidence(entry.Confidence),
			Evidence:   asEvidence(entry.Evidence),
		})
	}
	return items, nil
}

// Dedupe drops items whose statement is near-identical to one already kept.
func Dedupe(items []Item, threshold float64) []Item {
	kept := make([]Item, 0, len(items))
	for _, item := range items {
		duplicate := false
		for i := range kept {
			if textsim.SimilarityWithTags(item.Statement, kept[i].Statement, item.Tags, kept[i].Tags) >= threshold {
				kept[i].Tags = textsim.NormalizeTags(append(kept[i].Tags, item.Tags...))
				kept[i].Evidence = mergeSorted(kept[i].Evidence, item.Evidence)
				duplicate = true
				break
			}
		}
		if !duplicate {
			kept = append(kept, item)
		}
	}
	return kept
}

// LoadFiles reads every candidates file of a directory, sorted by session id.
func LoadFiles(dir string) ([]File, error) {
	ids, err := store.ListJSON(dir)
	if err != nil {
		return nil, err
	}
	files := make([]File, 0, len(ids))
	for _, id := range ids {
		var file File
		if err := store.ReadJSON(filepath.Join(dir, id+".json"), &file); err != nil {
			return nil, err
		}
		if file.Session == "" {
			file.Session = id
		}
		sort.SliceStable(file.Items, func(i, j int) bool {
			return file.Items[i].Statement < file.Items[j].Statement
		})
		files = append(files, file)
	}
	return files, nil
}

var datePattern = regexp.MustCompile(`\d{4}-\d{2}-\d{2}(?:T[0-9:+.\-Z]+)?`)

func normalize(items []Item, session corpus.Session) []Item {
	evidence := []string{session.Started.UTC().Format(time.RFC3339)}
	out := make([]Item, 0, len(items))
	for _, item := range items {
		item.Session = session.ID
		item.Kind = normalizeKind(item.Kind)
		item.Confidence = normalizeConfidence(item.Confidence)
		item.Tags = textsim.NormalizeTags(item.Tags)
		item.Evidence = cleanEvidence(item.Evidence)
		if len(item.Evidence) == 0 {
			item.Evidence = evidence
		}
		item.Statement = collapse(item.Statement)
		if item.Statement == "" {
			continue
		}
		out = append(out, item)
	}
	return out
}

func normalizeKind(value string) string {
	kind := strings.ToLower(strings.TrimSpace(value))
	for _, known := range Kinds {
		if kind == known {
			return kind
		}
	}
	return "fact"
}

func normalizeConfidence(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "high":
		return "high"
	case "low":
		return "low"
	default:
		return "medium"
	}
}

func asString(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return text
	}
	return ""
}

func asTags(raw json.RawMessage) []string {
	if len(raw) == 0 {
		return nil
	}
	var list []string
	if err := json.Unmarshal(raw, &list); err == nil {
		return textsim.NormalizeTags(list)
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return textsim.NormalizeTags(strings.FieldsFunc(text, func(r rune) bool {
			return r == ',' || r == ';' || r == '\n'
		}))
	}
	return nil
}

func asConfidence(raw json.RawMessage) string {
	if len(raw) == 0 {
		return "medium"
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		clean := strings.TrimSpace(text)
		if level, ok := levelOfNumber(clean); ok {
			return level
		}
		return normalizeConfidence(clean)
	}
	var number float64
	if err := json.Unmarshal(raw, &number); err == nil {
		switch {
		case number >= 0.8:
			return "high"
		case number >= 0.5:
			return "medium"
		default:
			return "low"
		}
	}
	return "medium"
}

// levelOfNumber accepts a confidence that the model wrote as a numeric string, "0.95".
func levelOfNumber(value string) (string, bool) {
	number, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return "", false
	}
	switch {
	case number >= 0.8:
		return "high", true
	case number >= 0.5:
		return "medium", true
	default:
		return "low", true
	}
}

// asEvidence accepts a list of dates, one date, or prose that carries dates.
func asEvidence(raw json.RawMessage) []string {
	if len(raw) == 0 {
		return nil
	}
	var list []string
	if err := json.Unmarshal(raw, &list); err == nil {
		return cleanEvidence(list)
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		matches := datePattern.FindAllString(text, -1)
		cleaned := make([]string, 0, len(matches))
		for _, match := range matches {
			cleaned = append(cleaned, strings.TrimRight(match, ".,;"))
		}
		return cleanEvidence(cleaned)
	}
	return nil
}

func cleanEvidence(values []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(values))
	for _, value := range values {
		clean := strings.TrimSpace(value)
		if clean == "" {
			continue
		}
		if _, ok := seen[clean]; ok {
			continue
		}
		seen[clean] = struct{}{}
		out = append(out, clean)
	}
	sort.Strings(out)
	return out
}

func mergeSorted(a, b []string) []string {
	return cleanEvidence(append(append([]string{}, a...), b...))
}

func renderMessage(message corpus.Message) string {
	switch message.Role {
	case "user":
		return "user: " + message.Text
	case "assistant":
		return "assistant: " + message.Text
	case "tool":
		if message.Name != "" {
			return "tool(" + message.Name + "): " + message.Text
		}
		return "tool: " + message.Text
	default:
		return message.Role + ": " + message.Text
	}
}

func truncateRunes(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	return string(runes[:limit]) + "\n… [truncated]"
}

func collapse(text string) string {
	return strings.Join(strings.Fields(text), " ")
}
