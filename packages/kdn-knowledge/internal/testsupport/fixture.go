// Package testsupport builds the SQLite fixture that the harvest and pipeline tests read.
//
// It shells out to the sqlite3 CLI, like the tool itself, and skips the test when that binary is
// absent.
package testsupport

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

// TB is the part of testing.T that this package needs.
type TB interface {
	Helper()
	TempDir() string
	Fatalf(format string, args ...any)
	Skipf(format string, args ...any)
}

// Message is one session_message row.
type Message struct {
	Type string
	Data string
}

// Session is one session_v2 row with its messages.
type Session struct {
	ID        string
	Title     string
	Directory string
	CreatedMS int64
	UpdatedMS int64
	Live      bool
	Messages  []Message
}

// User builds a user message row.
func User(text string) Message {
	payload := map[string]any{"time": map[string]any{"created": 0}, "text": text, "files": []any{}, "agents": []any{}}
	return Message{Type: "user", Data: mustJSON(payload)}
}

// Assistant builds an assistant row from content parts.
func Assistant(parts ...map[string]any) Message {
	payload := map[string]any{
		"time":    map[string]any{"created": 0, "completed": 1},
		"agent":   "build",
		"model":   map[string]any{"id": "test", "providerID": "local"},
		"content": parts,
	}
	return Message{Type: "assistant", Data: mustJSON(payload)}
}

// Text is a text content part.
func Text(text string) map[string]any {
	return map[string]any{"type": "text", "text": text}
}

// Reasoning is a reasoning content part.
func Reasoning(text string) map[string]any {
	return map[string]any{"type": "reasoning", "text": text}
}

// Tool is a tool content part. The real database carries input and content, and sometimes a
// plain output field; both are supported.
func Tool(name string, input map[string]any, output string) map[string]any {
	return map[string]any{
		"type": "tool",
		"id":   "tool-" + name,
		"name": name,
		"state": map[string]any{
			"status":  "completed",
			"input":   input,
			"output":  output,
			"content": []any{map[string]any{"type": "text", "text": output}},
		},
	}
}

// NewDB creates a SQLite database with the columns that the pipeline reads.
func NewDB(t TB, sessions ...Session) string {
	t.Helper()
	binary, err := exec.LookPath("sqlite3")
	if err != nil {
		t.Skipf("sqlite3 is not on PATH: %v", err)
	}
	path := filepath.Join(t.TempDir(), "fixture.db")
	schema := `
CREATE TABLE session_v2 (
  id text PRIMARY KEY,
  title text,
  directory text NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  time_idle integer
);
CREATE TABLE session_message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  type text NOT NULL,
  seq integer NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
`
	if out, err := run(binary, path, schema); err != nil {
		t.Fatalf("create fixture schema: %v: %s", err, out)
	}
	for _, session := range sessions {
		live := "NULL"
		if !session.Live {
			live = fmt.Sprintf("%d", session.UpdatedMS)
		}
		insert := fmt.Sprintf(
			"INSERT INTO session_v2 (id, title, directory, time_created, time_updated, time_idle)"+
				" VALUES (%s, %s, %s, %d, %d, %s);",
			quote(session.ID), quote(session.Title), quote(session.Directory),
			session.CreatedMS, session.UpdatedMS, live)
		if out, err := run(binary, path, insert); err != nil {
			t.Fatalf("insert session %s: %v: %s", session.ID, err, out)
		}
		for index, message := range session.Messages {
			statement := fmt.Sprintf(
				"INSERT INTO session_message (id, session_id, type, seq, time_created, time_updated, data)"+
					" VALUES (%s, %s, %s, %d, %d, %d, %s);",
				quote(fmt.Sprintf("%s-%d", session.ID, index)), quote(session.ID), quote(message.Type),
				index, session.CreatedMS, session.CreatedMS, quote(message.Data))
			if out, err := run(binary, path, statement); err != nil {
				t.Fatalf("insert message of %s: %v: %s", session.ID, err, out)
			}
		}
	}
	return path
}

// Exec runs one SQL statement against a fixture database.
func Exec(t TB, path, statement string) {
	t.Helper()
	binary, err := exec.LookPath("sqlite3")
	if err != nil {
		t.Skipf("sqlite3 is not on PATH: %v", err)
	}
	if out, err := run(binary, path, statement); err != nil {
		t.Fatalf("exec %q: %v: %s", statement, err, out)
	}
}

func run(binary, path, sql string) (string, error) {
	command := exec.Command(binary, path)
	command.Stdin = strings.NewReader(sql)
	output, err := command.CombinedOutput()
	return string(output), err
}

func quote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

func mustJSON(value any) string {
	body, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return string(body)
}
