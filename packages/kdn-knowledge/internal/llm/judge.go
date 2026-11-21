package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// MergeSystem is the prompt that collapses a cluster of near-duplicate statements.
const MergeSystem = `You merge near-duplicate engineering notes into one. Reply with JSON only, ` +
	`shaped {"statement": "...", "tags": ["..."]}. The statement is at most two sentences and keeps ` +
	`every distinct fact of the inputs. Tags are lowercase topic words. Do not add facts that the ` +
	`inputs do not contain.`

// JudgeSystem compares a new note with an existing one.
const JudgeSystem = `You compare two engineering notes. Reply with JSON only, shaped ` +
	`{"relation": "contradicts" | "agrees" | "unrelated"}. Answer "contradicts" only when the two ` +
	`statements cannot both be true.`

// Judge turns the chat client into the merge and contradiction calls of the dream stage.
type Judge struct {
	Client *Client
}

// SetMaxTokens lowers the reply budget for the short merge and compare answers.
func (j *Judge) SetMaxTokens(tokens int) {
	if j != nil && j.Client != nil && tokens > 0 {
		j.Client.MaxTokens = tokens
	}
}

// Merge collapses the statements of one cluster, in the order given.
func (j *Judge) Merge(ctx context.Context, statements []string, tags []string) (string, []string, error) {
	if j == nil || j.Client == nil {
		return "", nil, fmt.Errorf("no merge model configured")
	}
	var builder strings.Builder
	builder.WriteString("Tags: " + strings.Join(tags, ", ") + "\n\nNotes:\n")
	for i, statement := range statements {
		fmt.Fprintf(&builder, "%d. %s\n", i+1, statement)
	}
	result, err := j.Client.Chat(ctx, MergeSystem, builder.String())
	if err != nil {
		return "", nil, err
	}
	var parsed struct {
		Statement string   `json:"statement"`
		Tags      []string `json:"tags"`
	}
	text := extractJSONObject(result.Content)
	if text == "" {
		return "", nil, fmt.Errorf("merge reply is not a JSON object")
	}
	if err := json.Unmarshal([]byte(text), &parsed); err != nil {
		return "", nil, fmt.Errorf("merge reply is not a JSON object: %w", err)
	}
	statement := strings.TrimSpace(parsed.Statement)
	if statement == "" {
		return "", nil, fmt.Errorf("merge reply has an empty statement")
	}
	return statement, parsed.Tags, nil
}

// Contradicts asks whether the new statement and the old statement cannot both be true.
func (j *Judge) Contradicts(ctx context.Context, newStatement, oldStatement string) (bool, error) {
	if j == nil || j.Client == nil {
		return false, fmt.Errorf("no merge model configured")
	}
	user := "New: " + newStatement + "\nExisting: " + oldStatement
	result, err := j.Client.Chat(ctx, JudgeSystem, user)
	if err != nil {
		return false, err
	}
	var parsed struct {
		Relation string `json:"relation"`
	}
	text := extractJSONObject(result.Content)
	if text == "" {
		return false, fmt.Errorf("compare reply is not a JSON object")
	}
	if err := json.Unmarshal([]byte(text), &parsed); err != nil {
		return false, fmt.Errorf("compare reply is not a JSON object: %w", err)
	}
	return strings.EqualFold(strings.TrimSpace(parsed.Relation), "contradicts"), nil
}

// extractJSONObject returns the first balanced JSON object of a reply, or "".
func extractJSONObject(reply string) string {
	start := strings.Index(reply, "{")
	if start < 0 {
		return ""
	}
	depth := 0
	inString := false
	escaped := false
	for i := start; i < len(reply); i++ {
		char := reply[i]
		if inString {
			switch {
			case escaped:
				escaped = false
			case char == '\\':
				escaped = true
			case char == '"':
				inString = false
			}
			continue
		}
		switch char {
		case '"':
			inString = true
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return reply[start : i+1]
			}
		}
	}
	return ""
}
