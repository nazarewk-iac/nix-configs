package extract

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"kdn-knowledge/internal/corpus"
	"kdn-knowledge/internal/llm"
)

// fakeServer answers with a script of replies and records every request.
type fakeServer struct {
	calls   atomic.Int32
	bodies  []string
	auth    []string
	server  *httptest.Server
	handler func(call int, body string, w http.ResponseWriter)
}

func newFakeServer(t *testing.T, handler func(call int, body string, w http.ResponseWriter)) *fakeServer {
	t.Helper()
	fake := &fakeServer{handler: handler}
	fake.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		call := int(fake.calls.Add(1))
		fake.bodies = append(fake.bodies, string(body))
		fake.auth = append(fake.auth, r.Header.Get("Authorization"))
		fake.handler(call, string(body), w)
	}))
	t.Cleanup(fake.server.Close)
	return fake
}

func reply(content string) func(int, string, http.ResponseWriter) {
	return func(_ int, _ string, w http.ResponseWriter) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"model": "test-model",
			"choices": []any{
				map[string]any{"message": map[string]any{"role": "assistant", "content": content}},
			},
			"usage": map[string]any{"prompt_tokens": 10, "completion_tokens": 20},
		})
	}
}

func newClient(server *httptest.Server, timeout time.Duration) *llm.Client {
	return llm.New(server.URL, "test-model", "test-key", timeout)
}

func testSession() corpus.Session {
	return corpus.Session{
		ID:        "ses_test",
		Title:     "Test session",
		Directory: "/repo",
		Started:   time.Date(2026, 11, 21, 20, 0, 0, 0, time.UTC),
		Messages: []corpus.Message{
			{Role: "user", Text: "How do I split a jj change?"},
			{Role: "assistant", Text: "Use jj split with a path list."},
		},
	}
}

func TestExtractSessionValidJSON(t *testing.T) {
	t.Parallel()

	fake := newFakeServer(t, reply(`[{"kind":"runbook","statement":"Split a jj change with jj split and explicit paths.","tags":["JJ","nix","jj"],"confidence":"high","evidence":["2026-11-21"]}]`))
	result, err := ExtractSession(context.Background(), newClient(fake.server, 5*time.Second), testSession(), Options{})
	if err != nil {
		t.Fatalf("ExtractSession: %v", err)
	}
	if fake.calls.Load() != 1 {
		t.Fatalf("calls = %d, want 1", fake.calls.Load())
	}
	if len(result.Items) != 1 {
		t.Fatalf("items = %d, want 1", len(result.Items))
	}
	item := result.Items[0]
	if item.Session != "ses_test" || item.Kind != "runbook" || item.Confidence != "high" {
		t.Fatalf("item = %+v", item)
	}
	if strings.Join(item.Tags, ",") != "jj,nix" {
		t.Fatalf("tags = %v, want sorted deduplicated [jj nix]", item.Tags)
	}
	request := fake.bodies[0]
	if !strings.Contains(request, "How do I split a jj change?") {
		t.Fatalf("the user message did not reach the model: %s", request)
	}
	if !strings.Contains(request, `"system"`) {
		t.Fatalf("the system prompt is missing: %s", request)
	}
	if !strings.Contains(request, `"enable_thinking":false`) {
		t.Fatalf("the request does not disable thinking: %s", request)
	}
	if !strings.Contains(request, `"temperature":0`) {
		t.Fatalf("the request is not deterministic: %s", request)
	}
	if !strings.Contains(request, `"max_tokens":2048`) {
		t.Fatalf("the request does not use the default token budget: %s", request)
	}
	if fake.auth[0] != "Bearer test-key" {
		t.Fatalf("Authorization = %q, want a bearer key", fake.auth[0])
	}
}

func TestExtractSessionRepairsInvalidJSON(t *testing.T) {
	t.Parallel()

	fake := newFakeServer(t, func(call int, _ string, w http.ResponseWriter) {
		if call == 1 {
			reply("I cannot answer that.")(call, "", w)
			return
		}
		reply(`[{"kind":"fact","statement":"The pipeline reads SQLite through the sqlite3 CLI.","tags":["sqlite","go"],"confidence":"medium","evidence":[]}]`)(call, "", w)
	})
	result, err := ExtractSession(context.Background(), newClient(fake.server, 5*time.Second), testSession(), Options{})
	if err != nil {
		t.Fatalf("ExtractSession: %v", err)
	}
	if fake.calls.Load() != 2 {
		t.Fatalf("calls = %d, want 2 (one repair attempt)", fake.calls.Load())
	}
	if !strings.Contains(fake.bodies[1], "Your previous reply was rejected") {
		t.Fatalf("the repair request does not carry the parser error: %s", fake.bodies[1])
	}
	if len(result.Items) != 1 || result.Items[0].Kind != "fact" {
		t.Fatalf("items = %+v", result.Items)
	}
	if len(result.Items[0].Evidence) == 0 {
		t.Fatal("the item has no evidence; the pipeline fills in the session date")
	}
}

func TestExtractSessionFailsAfterTwoInvalidReplies(t *testing.T) {
	t.Parallel()

	fake := newFakeServer(t, func(call int, _ string, w http.ResponseWriter) {
		reply("still not JSON")(call, "", w)
	})
	_, err := ExtractSession(context.Background(), newClient(fake.server, 5*time.Second), testSession(), Options{})
	if err == nil {
		t.Fatal("ExtractSession accepted two invalid replies")
	}
	if fake.calls.Load() != 2 {
		t.Fatalf("calls = %d, want exactly 2 (one repair, then fail)", fake.calls.Load())
	}
	if !strings.Contains(err.Error(), "invalid JSON after one repair") {
		t.Fatalf("error = %v, want it to name the repair failure", err)
	}
}

func TestExtractSessionHTTPError(t *testing.T) {
	t.Parallel()

	fake := newFakeServer(t, func(_ int, _ string, w http.ResponseWriter) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":{"message":"upstream command exited prematurely"}}`))
	})
	_, err := ExtractSession(context.Background(), newClient(fake.server, 5*time.Second), testSession(), Options{})
	if err == nil {
		t.Fatal("ExtractSession ignored HTTP 500")
	}
	if fake.calls.Load() != 1 {
		t.Fatalf("calls = %d, want 1: a transport error is not repaired", fake.calls.Load())
	}
	if !strings.Contains(err.Error(), "500") {
		t.Fatalf("error = %v, want the status code", err)
	}
	if !strings.Contains(err.Error(), "resting profile") {
		t.Fatalf("error = %v, want the qfn/placement hint", err)
	}
}

func TestExtractSessionTimeout(t *testing.T) {
	t.Parallel()

	fake := newFakeServer(t, func(_ int, _ string, w http.ResponseWriter) {
		time.Sleep(300 * time.Millisecond)
		reply("[]")(0, "", w)
	})
	started := time.Now()
	_, err := ExtractSession(context.Background(), newClient(fake.server, 50*time.Millisecond), testSession(), Options{})
	if err == nil {
		t.Fatal("ExtractSession ignored the timeout")
	}
	if time.Since(started) > 2*time.Second {
		t.Fatalf("the timeout did not fire: %s", time.Since(started))
	}
	if fake.calls.Load() != 1 {
		t.Fatalf("calls = %d, want 1", fake.calls.Load())
	}
}

func TestParseItemsNormalizes(t *testing.T) {
	t.Parallel()

	items, err := ParseItems("Here you go:\n```json\n" +
		`[{"kind":"weird","statement":"  Use   jj absorb. ","tags":["Nix","nix",""],"confidence":"certain"},{"statement":""}]` +
		"\n```")
	if err != nil {
		t.Fatalf("ParseItems: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("items = %d, want 1: %+v", len(items), items)
	}
	item := items[0]
	if item.Kind != "fact" {
		t.Fatalf("kind = %q, want fact", item.Kind)
	}
	if item.Confidence != "medium" {
		t.Fatalf("confidence = %q, want medium", item.Confidence)
	}
	if item.Statement != "Use jj absorb." {
		t.Fatalf("statement = %q", item.Statement)
	}
	if strings.Join(item.Tags, ",") != "nix" {
		t.Fatalf("tags = %v", item.Tags)
	}
}

// TestParseItemsRealModelDrift covers the reply that the frontier actually produced: a numeric
// confidence and a prose evidence string.
func TestParseItemsRealModelDrift(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		reply      string
		confidence string
		evidence   []string
	}{
		{
			name:       "numeric confidence and prose evidence",
			reply:      `[{"kind":"fact","statement":"SQLite has no Go driver in the standard library.","tags":["sqlite","go"],"confidence":0.95,"evidence":"Verified schema on 2026-11-21T22:00:00Z."}]`,
			confidence: "high",
			evidence:   []string{"2026-11-21T22:00:00Z"},
		},
		{
			name:       "numeric string confidence and evidence array",
			reply:      `[{"kind":"Pitfall","statement":"The chat-dumb-fast alias answers no router.","tags":"alias, model","confidence":"0.6","evidence":["2026-11-21","2026-11-21"]}]`,
			confidence: "medium",
			evidence:   []string{"2026-11-21"},
		},
		{
			name:       "low numeric confidence",
			reply:      `[{"kind":"preference","statement":"Prefer explicit paths in jj commands.","confidence":0.2,"evidence":[]}]`,
			confidence: "low",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			items, err := ParseItems(test.reply)
			if err != nil {
				t.Fatalf("ParseItems: %v", err)
			}
			if len(items) != 1 {
				t.Fatalf("items = %d, want 1", len(items))
			}
			if items[0].Confidence != test.confidence {
				t.Fatalf("confidence = %q, want %q", items[0].Confidence, test.confidence)
			}
			if strings.Join(items[0].Evidence, ",") != strings.Join(test.evidence, ",") {
				t.Fatalf("evidence = %v, want %v", items[0].Evidence, test.evidence)
			}
		})
	}
}

func TestChunksSplitOnRequest(t *testing.T) {
	t.Parallel()

	session := corpus.Session{
		ID:      "ses_long",
		Title:   "Long",
		Started: time.Date(2026, 11, 21, 0, 0, 0, 0, time.UTC),
	}
	for i := 0; i < 4; i++ {
		session.Messages = append(session.Messages, corpus.Message{
			Role: "assistant",
			Text: strings.Repeat(string(rune('a'+i)), 10000),
		})
	}

	whole, truncated, err := Chunks(session, Options{})
	if err != nil {
		t.Fatalf("Chunks: %v", err)
	}
	if truncated {
		t.Fatal("Chunks reported truncation without MaxChunks")
	}
	if len(whole) != 1 {
		t.Fatalf("got %d chunks by default, want 1", len(whole))
	}
	if whole[0].Messages != 4 {
		t.Fatalf("default chunk has %d messages, want 4", whole[0].Messages)
	}

	split, _, err := Chunks(session, Options{ChunkChars: 24000})
	if err != nil {
		t.Fatalf("Chunks with ChunkChars: %v", err)
	}
	if len(split) < 2 {
		t.Fatalf("got %d chunks with ChunkChars, want at least 2", len(split))
	}
	for _, chunk := range split {
		if len(chunk.Text) > 24000+8192 {
			t.Fatalf("chunk %d is %d characters, over the budget", chunk.Index, len(chunk.Text))
		}
	}
	if !strings.Contains(split[1].Text, strings.Repeat("b", 10000)) ||
		!strings.Contains(split[1].Text, strings.Repeat("c", 10000)) {
		t.Fatal("the second chunk does not carry the overlapping message and the next one")
	}

	capped, truncated, err := Chunks(session, Options{ChunkChars: 24000, MaxChunks: 1})
	if err != nil {
		t.Fatalf("Chunks with MaxChunks: %v", err)
	}
	if !truncated || len(capped) != 1 {
		t.Fatalf("MaxChunks did not cap: %d chunks, truncated=%v", len(capped), truncated)
	}
}

func TestChunksFailsFastOverTheWindow(t *testing.T) {
	t.Parallel()

	session := corpus.Session{
		ID:      "ses_huge",
		Title:   "Huge",
		Started: time.Date(2026, 11, 21, 0, 0, 0, 0, time.UTC),
		Messages: []corpus.Message{
			{Role: "assistant", Text: strings.Repeat("x", MaxPromptChars+10)},
		},
	}
	_, _, err := Chunks(session, Options{})
	if err == nil {
		t.Fatal("Chunks accepted a transcript over the window")
	}
	if !strings.Contains(err.Error(), "--chunk-chars") {
		t.Fatalf("error = %v, want it to name --chunk-chars", err)
	}
	if _, _, err := Chunks(session, Options{ChunkChars: 24000}); err != nil {
		t.Fatalf("Chunks with ChunkChars: %v", err)
	}
}

func TestDedupe(t *testing.T) {
	t.Parallel()

	items := []Item{
		{Session: "a", Kind: "fact", Statement: "The pipeline reads SQLite through the sqlite3 CLI.", Tags: []string{"sqlite"}, Confidence: "high", Evidence: []string{"2026-11-21"}},
		{Session: "b", Kind: "fact", Statement: "The pipeline reads SQLite through the sqlite3 CLI today.", Tags: []string{"go"}, Confidence: "medium", Evidence: []string{"2026-11-22"}},
		{Session: "c", Kind: "fact", Statement: "Clustering uses word trigrams, not a model.", Tags: []string{"dream"}, Confidence: "high", Evidence: []string{"2026-11-23"}},
	}
	kept := Dedupe(items, DedupeThreshold)
	if len(kept) != 2 {
		t.Fatalf("kept %d items, want 2: %+v", len(kept), kept)
	}
	if strings.Join(kept[0].Tags, ",") != "go,sqlite" {
		t.Fatalf("merged tags = %v", kept[0].Tags)
	}
	if len(kept[0].Evidence) != 2 {
		t.Fatalf("merged evidence = %v", kept[0].Evidence)
	}
}
