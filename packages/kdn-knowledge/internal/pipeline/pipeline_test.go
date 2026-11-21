package pipeline

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"kdn-knowledge/internal/corpus"
	"kdn-knowledge/internal/llm"
	"kdn-knowledge/internal/state"
	"kdn-knowledge/internal/store"
)

func newStore(t *testing.T) (*store.Store, *state.State) {
	t.Helper()
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	ledger, err := state.Load(st.StatePath())
	if err != nil {
		t.Fatalf("state.Load: %v", err)
	}
	return st, ledger
}

func writeCorpus(t *testing.T, st *store.Store, id string, started time.Time) corpus.Session {
	t.Helper()
	session := corpus.Session{
		ID:        id,
		Source:    "opencode",
		Title:     "Title of " + id,
		Directory: "/repo",
		Started:   started,
		Messages: []corpus.Message{
			{Role: "user", Text: "Do the thing."},
			{Role: "assistant", Text: "The thing is done."},
		},
		Hash: "sha256:" + id,
	}
	if err := store.WriteJSON(st.CorpusPath(id), session); err != nil {
		t.Fatalf("write corpus: %v", err)
	}
	return session
}

func fakeEndpoint(t *testing.T, status int, body string) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(server.Close)
	return server
}

func TestExtractOneMarksFailed(t *testing.T) {
	t.Parallel()

	st, ledger := newStore(t)
	session := writeCorpus(t, st, "ses_fail", time.Date(2026, 11, 21, 20, 0, 0, 0, time.UTC))
	ledger.Put("ses_fail", state.Entry{Hash: session.Hash, Status: state.StatusNew})
	if err := ledger.Save(); err != nil {
		t.Fatalf("Save: %v", err)
	}

	server := fakeEndpoint(t, http.StatusInternalServerError,
		`{"error":{"message":"upstream command exited prematurely"}}`)
	client := llm.New(server.URL, "qfn", "key", 2*time.Second)
	outcome := ExtractOne(context.Background(), client, st, ledger, session, ExtractOptions{})
	if outcome.Err == nil {
		t.Fatal("ExtractOne reported success on HTTP 500")
	}
	entry, _ := ledger.Get("ses_fail")
	if entry.Status != state.StatusFailed || entry.Attempts != 1 {
		t.Fatalf("entry = %+v, want failed with one attempt", entry)
	}
	if !strings.Contains(entry.Reason, "500") {
		t.Fatalf("reason = %q, want the status code", entry.Reason)
	}
	if _, err := st.ListJSON(st.CandidatesDir()); err != nil {
		t.Fatalf("ListJSON: %v", err)
	}
	if ids, _ := st.ListJSON(st.CandidatesDir()); len(ids) != 0 {
		t.Fatalf("a failed session wrote candidates: %v", ids)
	}

	// A second run increments the attempt count and keeps the session retryable.
	outcome = ExtractOne(context.Background(), client, st, ledger, session, ExtractOptions{})
	if outcome.Err == nil {
		t.Fatal("ExtractOne reported success on the second HTTP 500")
	}
	if entry, _ := ledger.Get("ses_fail"); entry.Attempts != 2 {
		t.Fatalf("attempts = %d, want 2", entry.Attempts)
	}
	if candidates := Candidates(ledger, false, 0); len(candidates) != 1 || candidates[0] != "ses_fail" {
		t.Fatalf("Candidates = %v, want the failed session", candidates)
	}
}

func TestExtractOneWritesCandidatesAndDone(t *testing.T) {
	t.Parallel()

	st, ledger := newStore(t)
	started := time.Date(2026, 11, 21, 20, 0, 0, 0, time.UTC)
	session := writeCorpus(t, st, "ses_ok", started)
	ledger.Put("ses_ok", state.Entry{Hash: session.Hash, Status: state.StatusNew, Started: started.Format(time.RFC3339)})
	if err := ledger.Save(); err != nil {
		t.Fatalf("Save: %v", err)
	}

	reply := `{"model":"qfn","choices":[{"message":{"content":"[{\"kind\":\"fact\",\"statement\":\"Use jj split.\",\"tags\":[\"jj\"],\"confidence\":\"high\",\"evidence\":[]}]"}}],"usage":{"prompt_tokens":10,"completion_tokens":5}}`
	server := fakeEndpoint(t, http.StatusOK, reply)
	client := llm.New(server.URL, "qfn", "key", 2*time.Second)
	outcome := ExtractOne(context.Background(), client, st, ledger, session, ExtractOptions{})
	if outcome.Err != nil {
		t.Fatalf("ExtractOne: %v", outcome.Err)
	}
	if outcome.Items != 1 || outcome.Calls != 1 {
		t.Fatalf("outcome = %+v, want 1 item and 1 call", outcome)
	}
	entry, _ := ledger.Get("ses_ok")
	if entry.Status != state.StatusDone || entry.Attempts != 0 || entry.Seconds <= 0 {
		t.Fatalf("entry = %+v, want done with a measured duration", entry)
	}
	var file struct {
		Session string `json:"session"`
		Model   string `json:"model"`
		Items   []struct {
			Statement string `json:"statement"`
		} `json:"items"`
	}
	if err := store.ReadJSON(st.CandidatesPath("ses_ok"), &file); err != nil {
		t.Fatalf("read candidates: %v", err)
	}
	if file.Session != "ses_ok" || file.Model != "qfn" || len(file.Items) != 1 {
		t.Fatalf("candidates = %+v", file)
	}
	if candidates := Candidates(ledger, false, 0); len(candidates) != 0 {
		t.Fatalf("Candidates = %v after success, want none", candidates)
	}
	if candidates := Candidates(ledger, true, 0); len(candidates) != 1 {
		t.Fatalf("Candidates(force) = %v, want the done session", candidates)
	}
}

func TestCandidatesOrderAndLimits(t *testing.T) {
	t.Parallel()

	_, ledger := newStore(t)
	ledger.Put("ses_old", state.Entry{Status: state.StatusNew, Started: "2026-11-19T10:00:00Z"})
	ledger.Put("ses_new", state.Entry{Status: state.StatusFailed, Started: "2026-11-21T10:00:00Z"})
	ledger.Put("ses_mid", state.Entry{Status: state.StatusNew, Started: "2026-11-20T10:00:00Z"})
	ledger.Put("ses_done", state.Entry{Status: state.StatusDone, Started: "2026-11-22T10:00:00Z"})
	ledger.Put("ses_gone", state.Entry{Status: state.StatusOrphaned, Started: "2026-11-18T10:00:00Z"})

	got := Candidates(ledger, false, 0)
	want := []string{"ses_new", "ses_mid", "ses_old"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("Candidates = %v, want %v (newest first, done and orphaned skipped)", got, want)
	}
	if limited := Candidates(ledger, false, 2); len(limited) != 2 || limited[0] != "ses_new" {
		t.Fatalf("limited = %v", limited)
	}
	if forced := Candidates(ledger, true, 0); len(forced) != 4 || forced[0] != "ses_done" {
		t.Fatalf("forced = %v, want the done session first", forced)
	}
}

func TestStateResumeUnchangedAndChangedHash(t *testing.T) {
	t.Parallel()

	_, ledger := newStore(t)
	ledger.Put("ses_a", state.Entry{Hash: "sha256:a", Status: state.StatusDone, Started: "2026-11-21T10:00:00Z"})
	ledger.Put("ses_b", state.Entry{Hash: "sha256:b", Status: state.StatusDone, Started: "2026-11-21T11:00:00Z"})
	if err := ledger.Save(); err != nil {
		t.Fatalf("Save: %v", err)
	}

	// Reload the file, as a new process would.
	reloaded, err := state.Load(ledger.Path())
	if err != nil {
		t.Fatalf("state.Load: %v", err)
	}
	if candidates := Candidates(reloaded, false, 0); len(candidates) != 0 {
		t.Fatalf("Candidates after reload = %v, want none", candidates)
	}
	entry, _ := reloaded.Get("ses_b")
	entry.Hash = "sha256:changed"
	entry.Status = state.StatusNew
	reloaded.Put("ses_b", entry)
	if err := reloaded.Save(); err != nil {
		t.Fatalf("Save: %v", err)
	}
	again, err := state.Load(ledger.Path())
	if err != nil {
		t.Fatalf("state.Load: %v", err)
	}
	candidates := Candidates(again, false, 0)
	if len(candidates) != 1 || candidates[0] != "ses_b" {
		t.Fatalf("Candidates = %v, want only the changed session", candidates)
	}
	if value, _ := again.Get("ses_a"); value.Hash != "sha256:a" || value.Status != state.StatusDone {
		t.Fatalf("unchanged entry = %+v", value)
	}
	if _, err := json.Marshal(again); err != nil {
		t.Fatalf("marshal state: %v", err)
	}
}
