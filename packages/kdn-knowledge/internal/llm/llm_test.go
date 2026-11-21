package llm

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestReadKey(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	valid := filepath.Join(dir, "key")
	if err := os.WriteFile(valid, []byte("  abc123def  \nsecond line\n"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	key, err := ReadKey(valid)
	if err != nil {
		t.Fatalf("ReadKey: %v", err)
	}
	if key != "abc123def" {
		t.Fatalf("key = %q, want the trimmed first line", key)
	}

	noNewline := filepath.Join(dir, "one")
	if err := os.WriteFile(noNewline, []byte("abc123def"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if key, err := ReadKey(noNewline); err != nil || key != "abc123def" {
		t.Fatalf("ReadKey = %q, %v", key, err)
	}

	empty := filepath.Join(dir, "empty")
	if err := os.WriteFile(empty, []byte("   \n"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if _, err := ReadKey(empty); err == nil || !strings.Contains(err.Error(), "--key-file") {
		t.Fatalf("empty key error = %v, want it to name --key-file", err)
	}

	if _, err := ReadKey(filepath.Join(dir, "absent")); err == nil || !strings.Contains(err.Error(), "--key-file") {
		t.Fatalf("missing key error = %v, want it to name --key-file", err)
	}
	if key, err := ReadKey(""); err != nil || key != "" {
		t.Fatalf("empty path = %q, %v", key, err)
	}
}

func TestChatSendsTheContract(t *testing.T) {
	t.Parallel()

	var gotAuth, gotBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		gotBody = string(body)
		gotAuth = r.Header.Get("Authorization")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"model":"qfn","choices":[{"message":{"content":"[]"}}],"usage":{"prompt_tokens":7,"completion_tokens":1}}`))
	}))
	t.Cleanup(server.Close)

	client := New(server.URL+"/", "qfn", "secret", 5*time.Second)
	result, err := client.Chat(context.Background(), "system text", "user text")
	if err != nil {
		t.Fatalf("Chat: %v", err)
	}
	if result.Content != "[]" || result.CompletionTokens != 1 || result.PromptTokens != 7 {
		t.Fatalf("result = %+v", result)
	}
	if gotAuth != "Bearer secret" {
		t.Fatalf("Authorization = %q", gotAuth)
	}
	for _, want := range []string{
		`"model":"qfn"`,
		`"temperature":0`,
		`"max_tokens":2048`,
		`"enable_thinking":false`,
		`"role":"system"`,
	} {
		if !strings.Contains(gotBody, want) {
			t.Fatalf("request does not contain %q: %s", want, gotBody)
		}
	}
}

func TestChatReportsReasoningOnlyReply(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"","reasoning_content":"long thoughts"}}]}`))
	}))
	t.Cleanup(server.Close)

	client := New(server.URL, "qfn", "", 5*time.Second)
	_, err := client.Chat(context.Background(), "s", "u")
	if err == nil {
		t.Fatal("Chat accepted a reasoning-only reply")
	}
	if !strings.Contains(err.Error(), "enable_thinking") {
		t.Fatalf("error = %v, want the thinking hint", err)
	}
}

func TestChatErrorHints(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		status int
		body   string
		want   string
	}{
		{
			name:   "unauthorized",
			status: http.StatusUnauthorized,
			body:   `{"error":{"message":"Invalid API Key"}}`,
			want:   "--key-file",
		},
		{
			name:   "dead alias",
			status: http.StatusNotFound,
			body:   `{"error":{"message":"no router for requested model"}}`,
			want:   "base model id",
		},
		{
			name:   "engine refused",
			status: http.StatusInternalServerError,
			body:   `{"error":{"message":"upstream command exited prematurely"}}`,
			want:   "resting profile",
		},
		{
			name:   "context overflow",
			status: http.StatusBadRequest,
			body:   `{"error":{"message":"the prompt exceeds the context window"}}`,
			want:   "--chunk-chars",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(test.status)
				_, _ = w.Write([]byte(test.body))
			}))
			t.Cleanup(server.Close)

			client := New(server.URL, "qfn", "", 2*time.Second)
			_, err := client.Chat(context.Background(), "s", "u")
			if err == nil {
				t.Fatal("Chat accepted an error response")
			}
			if !strings.Contains(err.Error(), test.want) {
				t.Fatalf("error = %v, want %q", err, test.want)
			}
		})
	}
}

func TestDecide(t *testing.T) {
	t.Parallel()

	var gotBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		gotBody = string(body)
		if r.URL.Path != "/decide" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_, _ = w.Write([]byte(`{"verdict":"refuse","why":[{"node":"root.0.0","type":"check","verb":"model-unknown","result":"failure","facts":{"model":"gemma-4-e4b"}},{"node":"root","type":"sequence","result":"failure"}]}`))
	}))
	t.Cleanup(server.Close)

	verdict, err := Decide(context.Background(), server.URL, "gemma-4-e4b")
	if err != nil {
		t.Fatalf("Decide: %v", err)
	}
	if !strings.Contains(gotBody, `"model":"gemma-4-e4b"`) {
		t.Fatalf("request body = %s", gotBody)
	}
	if verdict.Admits() {
		t.Fatal("Admits reported true for a refusal")
	}
	if verdict.Summary() != "refuse: model-unknown" {
		t.Fatalf("summary = %q", verdict.Summary())
	}
	trace := verdict.Trace(2)
	if len(trace) != 1 || !strings.Contains(trace[0], "model-unknown") {
		t.Fatalf("trace = %v", trace)
	}
	if !strings.Contains(trace[0], "gemma-4-e4b") {
		t.Fatalf("trace does not carry the facts: %v", trace)
	}
}

func TestDecideCooldown(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte(`a switch just happened; retry shortly`))
	}))
	t.Cleanup(server.Close)

	_, err := Decide(context.Background(), server.URL, "qfn")
	if err == nil {
		t.Fatal("Decide accepted a 429")
	}
	cooldown, ok := err.(*CooldownError)
	if !ok {
		t.Fatalf("error = %T, want *CooldownError", err)
	}
	if !strings.Contains(cooldown.Error(), "cooldown") || !strings.Contains(cooldown.Error(), "retry shortly") {
		t.Fatalf("error = %v", cooldown)
	}
}

func TestDecideUnreachable(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	url := server.URL
	server.Close()

	if _, err := Decide(context.Background(), url, "qfn"); err == nil {
		t.Fatal("Decide reported a verdict for a dead manager")
	}
}
