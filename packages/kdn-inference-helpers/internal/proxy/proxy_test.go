package proxy

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// fakeLeaser records leases and can refuse a fixed number of acquires first, which is how a switch
// under load looks to the proxy.
type fakeLeaser struct {
	mu       sync.Mutex
	next     int64
	open     map[int64]bool
	refusals int
	acquired int
	released int
}

func newLeaser() *fakeLeaser { return &fakeLeaser{open: map[int64]bool{}} }

func (f *fakeLeaser) Acquire(ctx context.Context) (int64, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.refusals > 0 {
		f.refusals--
		return 0, false
	}
	f.next++
	f.open[f.next] = true
	f.acquired++
	return f.next, true
}

func (f *fakeLeaser) Release(id int64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.open, id)
	f.released++
}

func (f *fakeLeaser) idle() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.open) == 0
}

func targetOf(t *testing.T, srv *httptest.Server) *url.URL {
	t.Helper()
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	return u
}

func newHandler(t *testing.T, upstream *httptest.Server, leaser Leaser) *httptest.Server {
	t.Helper()
	h := New(targetOf(t, upstream), leaser, func() bool { return false })
	return httptest.NewServer(h)
}

func TestStreamingChunksArriveAsTheyAreProduced(t *testing.T) {
	// The upstream writes five chunks with a pause between them, like a model emitting tokens.
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		flusher, _ := w.(http.Flusher)
		for i := 0; i < 5; i++ {
			io.WriteString(w, "data: chunk\n\n")
			flusher.Flush()
			time.Sleep(60 * time.Millisecond)
		}
	}))
	defer upstream.Close()

	front := newHandler(t, upstream, newLeaser())
	defer front.Close()

	resp, err := http.Get(front.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		t.Fatalf("content type = %q", ct)
	}

	start := time.Now()
	scanner := bufio.NewScanner(resp.Body)
	var firstAt, lastAt time.Duration
	n := 0
	for scanner.Scan() {
		if !strings.HasPrefix(scanner.Text(), "data: ") {
			continue
		}
		n++
		if n == 1 {
			firstAt = time.Since(start)
		}
		lastAt = time.Since(start)
	}
	if n != 5 {
		t.Fatalf("received %d chunks, want 5", n)
	}
	// The point of FlushInterval=-1: the first chunk must arrive long before the last one, not be
	// buffered to the end. Without it firstAt would be approximately lastAt.
	if firstAt > 150*time.Millisecond {
		t.Fatalf("first chunk arrived at %v; the stream was buffered", firstAt)
	}
	// Five chunks with four 60 ms pauses between them: the last one cannot arrive before ~240 ms.
	if lastAt < 180*time.Millisecond {
		t.Fatalf("last chunk arrived at %v, expected the upstream pauses to be visible", lastAt)
	}
}

func TestChunkedRequestBodyPassesThrough(t *testing.T) {
	const payload = "the quick brown fox jumps over the lazy dog, repeated for length"
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if string(body) != payload {
			http.Error(w, "body mismatch: "+string(body), http.StatusBadRequest)
			return
		}
		io.WriteString(w, "ok")
	}))
	defer upstream.Close()

	front := newHandler(t, upstream, newLeaser())
	defer front.Close()

	// A body with unknown length makes the Go client use chunked transfer encoding.
	req, err := http.NewRequest(http.MethodPost, front.URL, io.NopCloser(strings.NewReader(payload)))
	if err != nil {
		t.Fatal(err)
	}
	req.ContentLength = -1
	req.Header.Set("Content-Type", "text/plain")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK || string(body) != "ok" {
		t.Fatalf("status %d body %q", resp.StatusCode, body)
	}
}

func TestKeepAliveReuseServesSeveralRequests(t *testing.T) {
	var requests atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		io.WriteString(w, "ok")
	}))
	defer upstream.Close()

	front := newHandler(t, upstream, newLeaser())
	defer front.Close()

	// One client, one transport: the second request reuses the connection unless the proxy breaks it.
	client := &http.Client{}
	for i := 0; i < 3; i++ {
		resp, err := client.Get(front.URL)
		if err != nil {
			t.Fatalf("request %d: %v", i, err)
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("request %d: status %d", i, resp.StatusCode)
		}
	}
	if requests.Load() != 3 {
		t.Fatalf("upstream saw %d requests", requests.Load())
	}
}

func TestExpect100ContinueIsHonoured(t *testing.T) {
	const payload = `{"model":"qfn","messages":[]}`
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if string(body) != payload {
			http.Error(w, "short body", http.StatusBadRequest)
			return
		}
		io.WriteString(w, "ok")
	}))
	defer upstream.Close()

	front := newHandler(t, upstream, newLeaser())
	defer front.Close()

	req, err := http.NewRequest(http.MethodPost, front.URL, strings.NewReader(payload))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Expect", "100-continue")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestLeaseIsHeldForTheWholeRequestAndReleasedAfterwards(t *testing.T) {
	release := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-release
		io.WriteString(w, "ok")
	}))
	defer upstream.Close()

	leaser := newLeaser()
	front := newHandler(t, upstream, leaser)
	defer front.Close()

	done := make(chan struct{})
	go func() {
		resp, err := http.Get(front.URL)
		if err == nil {
			io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
		}
		close(done)
	}()

	time.Sleep(100 * time.Millisecond)
	if leaser.idle() {
		t.Fatal("the lease was released while the request was still in flight")
	}
	close(release)
	<-done
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && !leaser.idle() {
		time.Sleep(10 * time.Millisecond)
	}
	if !leaser.idle() {
		t.Fatal("the lease was not released after the response finished")
	}
}

func TestRequestWaitsWhileTheEngineIsSwitching(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "ok")
	}))
	defer upstream.Close()

	leaser := newLeaser()
	leaser.refusals = 4 // as a drain would: the manager says "wait" a few times
	h := New(targetOf(t, upstream), leaser, func() bool { return false })
	h.PollInterval = 20 * time.Millisecond
	front := httptest.NewServer(h)
	defer front.Close()

	start := time.Now()
	resp, err := http.Get(front.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if time.Since(start) < 60*time.Millisecond {
		t.Fatal("the request did not wait for the switch")
	}
	if leaser.acquired != 1 {
		t.Fatalf("acquired %d leases, want 1", leaser.acquired)
	}
}

func TestHealthIsAnsweredLocallyWhileDraining(t *testing.T) {
	var upstreamHits atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamHits.Add(1)
		io.WriteString(w, "upstream")
	}))
	defer upstream.Close()

	draining := atomic.Bool{}
	draining.Store(true)
	h := New(targetOf(t, upstream), newLeaser(), func() bool { return draining.Load() })
	front := httptest.NewServer(h)
	defer front.Close()

	resp, err := http.Get(front.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if !strings.Contains(string(body), "switching") {
		t.Fatalf("body = %q", body)
	}
	if upstreamHits.Load() != 0 {
		t.Fatal("the health check reached the engine while draining")
	}

	// When not draining the check is proxied, so a genuinely dead engine is still reported.
	draining.Store(false)
	resp, err = http.Get(front.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	body, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	if upstreamHits.Load() != 1 || string(body) != "upstream" {
		t.Fatalf("health was not proxied when idle: hits=%d body=%q", upstreamHits.Load(), body)
	}
}

func TestUpstreamDownIsAJSON502(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	dead := targetOf(t, upstream)
	upstream.Close()

	h := New(dead, newLeaser(), func() bool { return false })
	front := httptest.NewServer(h)
	defer front.Close()

	resp, err := http.Get(front.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("status %d, want 502", resp.StatusCode)
	}
	var payload map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		t.Fatalf("502 body is not JSON: %v", err)
	}
	if _, ok := payload["error"]; !ok {
		t.Fatalf("502 body = %#v", payload)
	}
}

func TestClientDisconnectReleasesTheLease(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		flusher, _ := w.(http.Flusher)
		for i := 0; i < 100; i++ {
			io.WriteString(w, "data: tick\n\n")
			flusher.Flush()
			time.Sleep(20 * time.Millisecond)
		}
	}))
	defer upstream.Close()

	leaser := newLeaser()
	front := newHandler(t, upstream, leaser)
	defer front.Close()

	ctx, cancel := context.WithCancel(context.Background())
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, front.URL, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 32)
	resp.Body.Read(buf)
	cancel()
	resp.Body.Close()

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) && !leaser.idle() {
		time.Sleep(20 * time.Millisecond)
	}
	if !leaser.idle() {
		t.Fatal("the lease survived a client disconnect; the next switch would wait for it")
	}
}
