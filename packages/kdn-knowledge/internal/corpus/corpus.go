// Package corpus reads the OpenCode SQLite database and normalises one session into the record
// that the rest of the pipeline consumes.
//
// The database is read through the sqlite3 CLI: the Go standard library has no SQLite driver,
// and linking one would add a third-party dependency to a tool that must run from a laptop.
package corpus

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// ToolChars is the cap on one tool part: the design drops the long tail of command output.
const ToolChars = 2000

// Message is one line of the normalised transcript.
//
// Command is set for a tool part that carries a shell command. Skill distillation reads it to
// find the ordered procedure of a runbook cluster.
type Message struct {
	Role    string `json:"role"`
	Name    string `json:"name,omitempty"`
	Command string `json:"command,omitempty"`
	Text    string `json:"text"`
}

// Session is the corpus record of one session.
type Session struct {
	ID        string    `json:"id"`
	Source    string    `json:"source"`
	Title     string    `json:"title"`
	Directory string    `json:"directory"`
	Started   time.Time `json:"started"`
	Messages  []Message `json:"messages"`
	Hash      string    `json:"hash"`
}

// RawMessage is one row of session_message.
type RawMessage struct {
	Type string
	Data string
}

// Row is one selected session of session_v2.
type Row struct {
	ID        string
	Title     string
	Directory string
	Created   time.Time
	Updated   time.Time
}

// Query selects the sessions of one project.
type Query struct {
	Project     string
	Since       time.Time
	Limit       int
	IncludeLive bool
}

// Sessions runs the selection query. A session counts as live while time_idle is null; the
// default skips it, because a running session is not finished and its transcript still grows.
func Sessions(ctx context.Context, db string, query Query) ([]Row, error) {
	var conditions []string
	if strings.TrimSpace(query.Project) != "" {
		project := quote(query.Project)
		conditions = append(conditions, fmt.Sprintf(
			"(s.directory = %s OR (instr(s.directory, %s) = 1 AND substr(s.directory, length(%s) + 1, 1) = '/'))",
			project, project, project))
	}
	if !query.Since.IsZero() {
		conditions = append(conditions, fmt.Sprintf("s.time_created >= %d", query.Since.UTC().UnixMilli()))
	}
	if !query.IncludeLive {
		conditions = append(conditions, "s.time_idle IS NOT NULL")
	}
	where := ""
	if len(conditions) > 0 {
		where = " WHERE " + strings.Join(conditions, " AND ")
	}
	limit := ""
	if query.Limit > 0 {
		limit = " LIMIT " + strconv.Itoa(query.Limit)
	}
	sql := "SELECT s.id AS id, coalesce(s.title, '') AS title, s.directory AS directory," +
		" s.time_created AS created, s.time_updated AS updated" +
		" FROM session_v2 s" + where + " ORDER BY s.time_updated DESC" + limit

	rows, err := queryJSON[struct {
		ID        string `json:"id"`
		Title     string `json:"title"`
		Directory string `json:"directory"`
		Created   int64  `json:"created"`
		Updated   int64  `json:"updated"`
	}](ctx, db, sql)
	if err != nil {
		return nil, err
	}
	out := make([]Row, 0, len(rows))
	for _, row := range rows {
		out = append(out, Row{
			ID:        row.ID,
			Title:     row.Title,
			Directory: row.Directory,
			Created:   time.UnixMilli(row.Created).UTC(),
			Updated:   time.UnixMilli(row.Updated).UTC(),
		})
	}
	return out, nil
}

// AllIDs returns every session id in the database, whatever its project or state.
func AllIDs(ctx context.Context, db string) (map[string]struct{}, error) {
	rows, err := queryJSON[struct {
		ID string `json:"id"`
	}](ctx, db, "SELECT id FROM session_v2")
	if err != nil {
		return nil, err
	}
	ids := make(map[string]struct{}, len(rows))
	for _, row := range rows {
		ids[row.ID] = struct{}{}
	}
	return ids, nil
}

// Messages returns the user and assistant rows of one session in sequence order.
func Messages(ctx context.Context, db string, sessionID string) ([]RawMessage, error) {
	if !validID(sessionID) {
		return nil, fmt.Errorf("session id %q is not a safe SQLite key", sessionID)
	}
	rows, err := queryJSON[struct {
		Type string `json:"type"`
		Data string `json:"data"`
	}](ctx, db, fmt.Sprintf(
		"SELECT type AS type, data AS data FROM session_message"+
			" WHERE session_id = '%s' AND type IN ('user', 'assistant') ORDER BY seq", sessionID))
	if err != nil {
		return nil, err
	}
	out := make([]RawMessage, 0, len(rows))
	for _, row := range rows {
		out = append(out, RawMessage{Type: row.Type, Data: row.Data})
	}
	return out, nil
}

// Build normalises the rows of one session. Reasoning parts are dropped: they are long and they
// carry no durable knowledge.
func Build(row Row, raw []RawMessage, toolChars int) Session {
	if toolChars <= 0 {
		toolChars = ToolChars
	}
	session := Session{
		ID:        row.ID,
		Source:    "opencode",
		Title:     strings.TrimSpace(row.Title),
		Directory: row.Directory,
		Started:   row.Created.UTC(),
	}
	for _, message := range raw {
		switch message.Type {
		case "user":
			if text := userText(message.Data); text != "" {
				session.Messages = append(session.Messages, Message{Role: "user", Text: text})
			}
		case "assistant":
			session.Messages = append(session.Messages, assistantMessages(message.Data, toolChars)...)
		}
	}
	session.Hash = Hash(session.Messages)
	return session
}

// Hash covers the role, name, command and text of every message. An edited session changes its
// hash and is extracted again; an unchanged one is skipped.
func Hash(messages []Message) string {
	digest := sha256.New()
	for _, message := range messages {
		fmt.Fprintf(digest, "%s\x00%s\x00%s\x00%s\x00", message.Role, message.Name, message.Command, message.Text)
	}
	return "sha256:" + hex.EncodeToString(digest.Sum(nil))
}

func userText(data string) string {
	var parsed struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal([]byte(data), &parsed); err != nil {
		return ""
	}
	return strings.TrimSpace(parsed.Text)
}

func assistantMessages(data string, toolChars int) []Message {
	var parsed struct {
		Content []struct {
			Type  string          `json:"type"`
			Text  string          `json:"text"`
			Name  string          `json:"name"`
			State json.RawMessage `json:"state"`
		} `json:"content"`
	}
	if err := json.Unmarshal([]byte(data), &parsed); err != nil {
		return nil
	}
	messages := make([]Message, 0, len(parsed.Content))
	var texts []string
	flush := func() {
		text := strings.TrimSpace(strings.Join(texts, "\n"))
		texts = texts[:0]
		if text == "" {
			return
		}
		messages = append(messages, Message{Role: "assistant", Text: text})
	}
	for _, part := range parsed.Content {
		switch part.Type {
		case "reasoning":
			// Dropped on purpose.
		case "text":
			if strings.TrimSpace(part.Text) != "" {
				texts = append(texts, strings.TrimSpace(part.Text))
			}
		case "tool":
			flush()
			if message, ok := toolMessage(part.Name, part.State, toolChars); ok {
				messages = append(messages, message)
			}
		}
	}
	flush()
	return messages
}

func toolMessage(name string, rawState json.RawMessage, toolChars int) (Message, bool) {
	if len(rawState) == 0 {
		return Message{}, false
	}
	var state struct {
		Status  string          `json:"status"`
		Input   json.RawMessage `json:"input"`
		Output  string          `json:"output"`
		Error   string          `json:"error"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(rawState, &state); err != nil {
		return Message{}, false
	}
	command := commandOf(state.Input)
	input := compactJSON(state.Input)
	output := state.Output
	if strings.TrimSpace(output) == "" && state.Error != "" {
		output = state.Error
	}
	if strings.TrimSpace(output) == "" {
		var parts []string
		for _, part := range state.Content {
			if part.Type == "text" && strings.TrimSpace(part.Text) != "" {
				parts = append(parts, strings.TrimSpace(part.Text))
			}
		}
		output = strings.Join(parts, "\n")
	}
	text := strings.TrimSpace(strings.Join([]string{input, output}, "\n"))
	if text == "" {
		return Message{}, false
	}
	return Message{
		Role:    "tool",
		Name:    strings.TrimSpace(name),
		Command: command,
		Text:    truncate(text, toolChars),
	}, true
}

func commandOf(input json.RawMessage) string {
	if len(input) == 0 {
		return ""
	}
	var parsed map[string]any
	if err := json.Unmarshal(input, &parsed); err != nil {
		return ""
	}
	value, ok := parsed["command"]
	if !ok {
		return ""
	}
	command, ok := value.(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(command)
}

func compactJSON(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var buffer bytes.Buffer
	if err := json.Compact(&buffer, raw); err != nil {
		return strings.TrimSpace(string(raw))
	}
	return buffer.String()
}

func truncate(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	marker := []rune("\n… [truncated]")
	keep := limit - len(marker)
	if keep < 0 {
		keep = limit
		marker = nil
	}
	return string(runes[:keep]) + string(marker)
}

func validID(id string) bool {
	if id == "" || len(id) > 128 {
		return false
	}
	for _, char := range id {
		switch {
		case char >= 'a' && char <= 'z':
		case char >= 'A' && char <= 'Z':
		case char >= '0' && char <= '9':
		case char == '_' || char == '-':
		default:
			return false
		}
	}
	return true
}

func quote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

// queryJSON runs one query with the sqlite3 CLI and decodes its JSON output.
func queryJSON[T any](ctx context.Context, db string, sql string) ([]T, error) {
	if _, err := os.Stat(db); err != nil {
		return nil, fmt.Errorf("session database %s: %w", db, err)
	}
	binary, err := exec.LookPath("sqlite3")
	if err != nil {
		return nil, fmt.Errorf("the sqlite3 CLI is required but not on PATH: %w", err)
	}
	command := exec.CommandContext(ctx, binary, "-json", "-readonly", db, sql)
	var stdout, stderr strings.Builder
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		return nil, fmt.Errorf("sqlite3 query failed: %w: %s", err, strings.TrimSpace(stderr.String()))
	}
	body := strings.TrimSpace(stdout.String())
	if body == "" {
		return nil, nil
	}
	var rows []T
	if err := json.Unmarshal([]byte(body), &rows); err != nil {
		return nil, fmt.Errorf("sqlite3 returned invalid JSON: %w", err)
	}
	return rows, nil
}
