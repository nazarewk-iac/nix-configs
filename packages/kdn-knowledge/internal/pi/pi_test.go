package pi

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"kdn-knowledge/internal/corpus"
)

func writeSession(t *testing.T, lines ...string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "session.jsonl")
	body := strings.Join(lines, "\n") + "\n"
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	return path
}

func header(id, timestamp, cwd string) string {
	return `{"type":"session","version":3,"id":"` + id + `","timestamp":"` + timestamp + `","cwd":"` + cwd + `"}`
}

func TestLoadKeepsDialogueAndToolCalls(t *testing.T) {
	t.Parallel()

	path := writeSession(t,
		header("01a1aaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "2026-11-02T13:55:59.516Z", "/repo"),
		`{"type":"model_change","timestamp":"2026-11-02T13:55:59.547Z","provider":"brys","modelId":"x"}`,
		`{"type":"message","timestamp":"2026-11-02T13:56:00.000Z","message":{"role":"system","content":"harness prompt must not appear"}}`,
		`{"type":"message","timestamp":"2026-11-02T13:56:01.000Z","message":{"role":"user","content":[{"type":"text","text":"How do I split a jj change?"}]}}`,
		`{"type":"message","timestamp":"2026-11-02T13:56:02.000Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"SECRET-THINKING"},{"type":"text","text":"Use jj split."},{"type":"toolCall","id":"1","name":"bash","arguments":{"command":"jj split -m x -- a b"}}]}}`,
		`not json at all`,
		`{"type":"message","timestamp":"2026-11-02T13:56:03.000Z","message":{"role":"toolResult","toolCallId":"1","toolName":"bash","content":[{"type":"text","text":"Done"}]}}`,
	)
	session, malformed, err := Load(path, 2000)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if malformed != 1 {
		t.Fatalf("malformed = %d, want 1", malformed)
	}
	if session.Source != Source {
		t.Fatalf("source = %q, want pi", session.Source)
	}
	if session.ID != "01a1aaaa-bbbb-cccc-dddd-eeeeeeeeeeee" {
		t.Fatalf("id = %q", session.ID)
	}
	if session.Directory != "/repo" {
		t.Fatalf("directory = %q, want the header cwd", session.Directory)
	}
	if !session.Started.Equal(mustParse("2026-11-02T13:55:59.516Z")) {
		t.Fatalf("started = %s", session.Started)
	}
	if session.Title != "How do I split a jj change?" {
		t.Fatalf("title = %q", session.Title)
	}
	for _, message := range session.Messages {
		if strings.Contains(message.Text, "harness prompt") || strings.Contains(message.Text, "SECRET-THINKING") {
			t.Fatalf("the harness prompt or a thinking part reached the corpus: %+v", message)
		}
	}
	if len(session.Messages) != 4 {
		t.Fatalf("messages = %d, want 4: %+v", len(session.Messages), session.Messages)
	}
	if session.Messages[1].Role != "assistant" || session.Messages[1].Text != "Use jj split." {
		t.Fatalf("assistant text = %+v", session.Messages[1])
	}
	if session.Messages[2].Role != "tool" || session.Messages[2].Name != "bash" {
		t.Fatalf("tool call = %+v", session.Messages[2])
	}
	if session.Messages[2].Command != "jj split -m x -- a b" {
		t.Fatalf("command = %q", session.Messages[2].Command)
	}
	if session.Messages[3].Text != "Done" {
		t.Fatalf("tool result = %+v", session.Messages[3])
	}
	if session.Hash == "" || !strings.HasPrefix(session.Hash, "sha256:") {
		t.Fatalf("hash = %q", session.Hash)
	}
	if session.Hash != corpus.Hash(session.Messages) {
		t.Fatal("the hash does not cover the messages")
	}
}

func TestLoadSkipsSessionsWithoutDialogue(t *testing.T) {
	t.Parallel()

	path := writeSession(t,
		header("01a1bbbb-bbbb-cccc-dddd-eeeeeeeeeeee", "2026-11-02T13:55:59.516Z", "/repo"),
		`{"type":"message","message":{"role":"system","content":"prompt"}}`,
		`{"type":"message","message":{"role":"toolResult","toolName":"bash","content":[{"type":"text","text":"output only"}]}}`,
	)
	session, _, err := Load(path, 2000)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if session.ID != "" || len(session.Messages) != 0 {
		t.Fatalf("Load returned %+v, want a silent skip", session)
	}
}

func TestLoadRejectsFilesWithoutHeader(t *testing.T) {
	t.Parallel()

	path := writeSession(t, `{"type":"message","message":{"role":"user","content":"hello"}}`)
	if _, _, err := Load(path, 2000); err == nil {
		t.Fatal("Load accepted a file without a session header")
	}
	if _, err := Index(path); err == nil {
		t.Fatal("Index accepted a file without a session header")
	}
}

func TestIndexAndIDs(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	for _, item := range []struct {
		name string
		body string
	}{
		{"a.jsonl", strings.Join([]string{
			header("id-a", "2026-11-01T10:00:00.000Z", "/repo"),
			`{"type":"message","timestamp":"2026-11-01T10:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"First task"}]}}`,
		}, "\n")},
		{"b.jsonl", strings.Join([]string{
			header("id-b", "2026-11-02T10:00:00.000Z", "/other"),
			`{"type":"message","timestamp":"2026-11-02T10:00:01.000Z","message":{"role":"user","content":"Second task"}}`,
		}, "\n")},
		{"ignore.txt", "not a session"},
	} {
		if err := os.WriteFile(filepath.Join(dir, item.name), []byte(item.body+"\n"), 0o644); err != nil {
			t.Fatalf("write fixture: %v", err)
		}
	}
	paths, err := Walk(dir)
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	if len(paths) != 2 {
		t.Fatalf("Walk returned %d paths, want 2", len(paths))
	}
	meta, err := Index(paths[0])
	if err != nil {
		t.Fatalf("Index: %v", err)
	}
	if meta.ID != "id-a" || meta.Cwd != "/repo" || meta.Title != "First task" {
		t.Fatalf("meta = %+v", meta)
	}
	ids, err := IDs(dir)
	if err != nil {
		t.Fatalf("IDs: %v", err)
	}
	if len(ids) != 2 {
		t.Fatalf("IDs = %v, want two ids", ids)
	}
	if _, ok := ids["id-b"]; !ok {
		t.Fatalf("IDs = %v, want id-b", ids)
	}
}

func TestWalkOnMissingRoot(t *testing.T) {
	t.Parallel()

	if _, err := Walk(filepath.Join(t.TempDir(), "absent")); err == nil {
		t.Fatal("Walk accepted a missing root")
	}
}

func mustParse(value string) time.Time {
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		panic(err)
	}
	return parsed.UTC()
}
