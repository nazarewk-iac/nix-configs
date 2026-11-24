// Package proxy is the per-entry HTTP listener llama-swap spawns: one lease per request, a wait
// while the engine switches profiles, and a local health answer so llama-swap never kills the
// process that is holding delayed requests.
//
// The HTTP itself is the standard library's reverse proxy. That is the whole reason this package is
// short: chunked bodies, keep-alive, 100-continue, trailers and streaming flushes are not our code.
package proxy

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httputil"
	"net/url"
	"sync/atomic"
	"time"
)

// Leaser is the lease registry, either in-process (the manager) or over HTTP (a `select` process).
type Leaser interface {
	Acquire(ctx context.Context) (id string, ok bool)
	Release(id string)
}

// Handler proxies to one engine and holds one lease per request.
type Handler struct {
	Target *url.URL
	Leaser Leaser
	// Draining reports whether a switch is in progress, so `/health` can be answered locally.
	Draining func() bool
	// Transport is optional; the default disables compression and HTTP/2, because the engine speaks
	// plain HTTP/1.1 and a compressed stream would corrupt SSE boundaries.
	Transport http.RoundTripper
	// WaitTimeout bounds how long a request may wait for a switching engine (900 s on brys).
	WaitTimeout time.Duration
	// PollInterval is how often a waiting request re-asks for a lease.
	PollInterval time.Duration
	// Identity is stamped onto every response. A model name is not a model: `qfn` is `max` before a
	// swap and `omni-fast` after it, and only the server knows which one answered. The client reads
	// these headers and can record what actually served the request it just made.
	Identity map[string]string
	// Profile answers "which profile is serving right now" for each request. It has to be asked per
	// request: `auto` (the profile-neutral frontier name) deliberately outlives a switch, so a value
	// captured when this listener started would be a stale claim about the present.
	Profile func(ctx context.Context) string

	proxy *httputil.ReverseProxy
	// inFlight counts requests between the lease and the response.
	inFlight atomic.Int64
}

// New builds the handler. It is a constructor rather than a literal so the reverse proxy is always
// configured the same way: a handler built by hand would silently lose `FlushInterval`.
func New(target *url.URL, leaser Leaser, draining func() bool) *Handler {
	h := &Handler{Target: target, Leaser: leaser, Draining: draining,
		WaitTimeout: 900 * time.Second, PollInterval: 500 * time.Millisecond}
	h.proxy = h.build()
	return h
}

func (h *Handler) build() *httputil.ReverseProxy {
	transport := h.Transport
	if transport == nil {
		transport = &http.Transport{
			// No Accept-Encoding added: the engine's bytes must reach the client untouched.
			DisableCompression: true,
			// The engine is HTTP/1.1; h2 would change the streaming semantics for nothing.
			ForceAttemptHTTP2:   false,
			MaxIdleConnsPerHost: 8,
			IdleConnTimeout:     90 * time.Second,
		}
	}
	return &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(h.Target)
			// The engine is local and does not consume forwarding headers; sending them only invites
			// downstream confusion.
			r.Out.Header.Del("X-Forwarded-For")
			r.Out.Header.Del("X-Forwarded-Host")
			r.Out.Header.Del("X-Forwarded-Proto")
		},
		Transport: transport,
		// -1 flushes after every write: this is what makes a streamed token reach the client while
		// the model is still generating.
		FlushInterval: -1,
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			// A JSON 502 instead of a bare EOF: the Python proxy closed the socket, and the client
			// saw an unexplained failure.
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadGateway)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"error": "the engine did not answer: " + err.Error(),
			})
		},
	}
}

// ServeHTTP takes a lease, waits out a switch, and relays.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Before anything else, so a health answer, a 503 and a streamed token all carry it.
	for key, value := range h.Identity {
		if value != "" {
			w.Header().Set(key, value)
		}
	}
	if h.Profile != nil {
		if profile := h.Profile(r.Context()); profile != "" {
			w.Header().Set("X-KDN-Profile", profile)
		}
	}
	// llama-swap health-checks this port. During a switch the engine is gone but this process is
	// alive and holding requests, so answering 200 locally is the difference between "delayed" and
	// "killed".
	if r.Method == http.MethodGet && r.URL.Path == "/health" && h.isDraining() {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"switching"}`))
		return
	}

	h.inFlight.Add(1)
	defer h.inFlight.Add(-1)
	lease, ok := h.acquire(r.Context())
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"error": "the engine did not come back from a profile switch in time",
		})
		return
	}
	defer h.Leaser.Release(lease)

	h.proxy.ServeHTTP(w, r)
}

// InFlight is how many requests this listener is serving right now. A listener that leaves with a
// lease cuts the response it was started for, so the watcher waits for this to reach zero.
func (h *Handler) InFlight() int64 { return h.inFlight.Load() }

// acquire retries until a lease is granted, the wait times out, or the client goes away. An
// unreachable manager is not an error: the caller's Leaser decides that, and a manager restart is
// shorter than a failed request.
func (h *Handler) acquire(ctx context.Context) (string, bool) {
	timeout := h.WaitTimeout
	if timeout <= 0 {
		timeout = 900 * time.Second
	}
	poll := h.PollInterval
	if poll <= 0 {
		poll = 500 * time.Millisecond
	}
	deadline := time.Now().Add(timeout)
	for {
		if id, ok := h.Leaser.Acquire(ctx); ok {
			return id, true
		}
		if time.Now().After(deadline) {
			return "", false
		}
		select {
		case <-ctx.Done():
			return "", false
		case <-time.After(poll):
		}
	}
}

func (h *Handler) isDraining() bool {
	return h.Draining != nil && h.Draining()
}
