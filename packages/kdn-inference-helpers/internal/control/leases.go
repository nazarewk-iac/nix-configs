// Package control is the HTTP control plane: the profile switch, the lease registry that makes a
// switch wait for in-flight work, the status and the statistics.
package control

import (
	"context"
	"sync"
	"time"
)

// DefaultLeaseTTL is how long a lease is trusted. A proxy killed with SIGKILL cannot release, and a
// phantom lease would burn the drain ceiling on every later switch. A 1M-token prefill is about ten
// minutes on this host, so 30 minutes never cuts a real request.
const DefaultLeaseTTL = 30 * time.Minute

// Leases is the registry a switch drains. Every request in flight holds one.
//
// The three rules this type exists to enforce:
//
//   - a fresh `drained` channel per drain, because a closed channel stays closed and reusing it
//     would make the next drain return instantly and cut a request that had just started;
//   - one mutex around "check the flag and insert" and "set the flag and read the set", so a
//     request cannot slip past a switch that has already begun stopping the engine;
//   - leases carry their start time, so a dead proxy's phantom lease expires instead of stalling
//     every future switch for the full ceiling.
type Leases struct {
	mu       sync.Mutex
	next     int64
	open     map[int64]time.Time
	drained  chan struct{}
	draining bool
	ttl      time.Duration
}

// NewLeases returns an empty registry. A zero ttl means DefaultLeaseTTL.
func NewLeases(ttl time.Duration) *Leases {
	if ttl <= 0 {
		ttl = DefaultLeaseTTL
	}
	return &Leases{open: map[int64]time.Time{}, ttl: ttl}
}

// Acquire grants a lease, or reports that the engine is switching. The caller must retry after a
// short wait when ok is false; it must never proceed without a lease.
func (l *Leases) Acquire() (id int64, ok bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.draining {
		return 0, false
	}
	l.next++
	l.open[l.next] = time.Now()
	return l.next, true
}

// Release ends a lease. Releasing an unknown id is a no-op, which keeps a double release from a
// retrying proxy harmless.
func (l *Leases) Release(id int64) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.releaseLocked(id)
}

func (l *Leases) releaseLocked(id int64) {
	if _, ok := l.open[id]; !ok {
		return
	}
	delete(l.open, id)
	if len(l.open) == 0 && l.drained != nil {
		close(l.drained)
		l.drained = nil
	}
}

// BeginDrain refuses new leases and waits for the live ones to be released. It returns how long it
// waited and whether the set actually emptied before ctx expired. On ctx expiry the caller proceeds
// with the switch and the registry stays in the draining state until EndDrain.
func (l *Leases) BeginDrain(ctx context.Context) (waited time.Duration, clean bool) {
	start := time.Now()
	l.mu.Lock()
	l.draining = true
	l.expireLocked(time.Now())
	if len(l.open) == 0 {
		l.mu.Unlock()
		return 0, true
	}
	// A fresh channel for this drain. Never reuse one: closing is permanent.
	l.drained = make(chan struct{})
	ch := l.drained
	l.mu.Unlock()

	select {
	case <-ch:
		return time.Since(start), true
	case <-ctx.Done():
		return time.Since(start), false
	}
}

// EndDrain accepts new leases again.
func (l *Leases) EndDrain() {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.draining = false
	l.drained = nil
}

// expireLocked drops leases past their ttl and returns how many went.
func (l *Leases) expireLocked(now time.Time) int {
	stale := 0
	for id, started := range l.open {
		if now.Sub(started) > l.ttl {
			delete(l.open, id)
			stale++
		}
	}
	return stale
}

// ExpireStale drops leases older than the ttl and reports how many were dropped. The manager calls
// it before a drain so the count reaches the journal.
func (l *Leases) ExpireStale() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	n := l.expireLocked(time.Now())
	if n > 0 && len(l.open) == 0 && l.drained != nil {
		close(l.drained)
		l.drained = nil
	}
	return n
}

// InFlight is how many requests hold a lease right now.
func (l *Leases) InFlight() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.open)
}

// Draining reports whether a switch is in progress.
func (l *Leases) Draining() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.draining
}
