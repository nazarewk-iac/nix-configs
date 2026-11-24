package control

import (
	"bufio"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"kdn-inference-helpers/internal/journal"
)

// readEvents opens the stream, reads up to want `data:` payloads, and closes the connection.
func readEvents(t *testing.T, url string, want int) []string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("GET %s: %v", url, err)
	}
	defer response.Body.Close()
	if got := response.Header.Get("Content-Type"); !strings.HasPrefix(got, "text/event-stream") {
		t.Fatalf("content type = %q, want text/event-stream", got)
	}

	var events []string
	scanner := bufio.NewScanner(response.Body)
	for scanner.Scan() && len(events) < want {
		line := scanner.Text()
		if payload, ok := strings.CutPrefix(line, "data: "); ok {
			events = append(events, payload)
		}
	}
	return events
}

func TestEventsStreamReplaysFromSince(t *testing.T) {
	m, events := newTestManager(t, nil)
	server := httptest.NewServer(m.Handler())
	defer server.Close()

	_ = events.Append(map[string]any{"event": journal.EventSwitch, "from": "", "to": "max"})
	_ = events.Append(map[string]any{"event": journal.EventEngineLoad, "model": "qfn"})

	got := readEvents(t, server.URL+"/events/stream?since=1", 1)
	if len(got) != 1 || !strings.Contains(got[0], "\"seq\":2") {
		t.Fatalf("since=1 replayed %v, want record seq 2 only", got)
	}
}

func TestEventsStreamFiltersByModelAndAlwaysKeepsSwitches(t *testing.T) {
	m, events := newTestManager(t, nil)
	server := httptest.NewServer(m.Handler())
	defer server.Close()

	_ = events.Append(map[string]any{"event": journal.EventSwitch, "from": "", "to": "max"})
	_ = events.Append(map[string]any{"event": journal.EventEngineLoad, "model": "qfn"})
	_ = events.Append(map[string]any{"event": journal.EventEngineLoad, "model": "other"})

	got := readEvents(t, server.URL+"/events/stream?model=qfn", 2)
	if len(got) != 2 {
		t.Fatalf("filtered stream returned %v, want the switch and the qfn load", got)
	}
	if strings.Contains(strings.Join(got, " "), "\"model\":\"other\"") {
		t.Fatalf("filter leaked another model: %v", got)
	}
}
