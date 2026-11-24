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

// SlotLeaseTTL bounds a slot lease. It is longer than any plausible single generation (the
// gateway's provider idle timeout is 5 minutes) and much shorter than the drain: an orphaned slot
// then blocks a switch for minutes, not for the full 30-minute lease TTL.
const SlotLeaseTTL = 15 * time.Minute

// Priority classes, highest first. `primary` is the human's own turn; a delegated sub-agent is
// `normal` unless its caller says otherwise. Admission is strict priority, FIFO within a class:
// a running request is never preempted (a stream cannot be cancelled safely), so priority decides
// who takes the NEXT free slot.
const (
	PriorityLow     = 0
	PriorityNormal  = 1
	PriorityHigh    = 2
	PriorityPrimary = 3
)

// ParsePriority maps the request header/body value to a class. An unknown value is `normal`, so a
// typo cannot starve a request.
func ParsePriority(value string) int {
	switch value {
	case "primary":
		return PriorityPrimary
	case "high":
		return PriorityHigh
	case "low":
		return PriorityLow
	default:
		return PriorityNormal
	}
}

// PriorityName is the inverse of ParsePriority, for a response and the journal.
func PriorityName(priority int) string {
	switch priority {
	case PriorityPrimary:
		return "primary"
	case PriorityHigh:
		return "high"
	case PriorityLow:
		return "low"
	default:
		return "normal"
	}
}

type lease struct {
	started  time.Time
	deadline time.Time
	slot     bool
	priority int
}

type waiter struct {
	ch       chan int64 // buffered(1): a grant never blocks the releaser
	priority int
}

// Leases is the registry a switch drains. Every request in flight holds one, and a request that
// needs an engine slot holds one of the capacity-bounded `slot` leases.
//
// The rules this type exists to enforce:
//
//   - a fresh `drained` channel per drain, because a closed channel stays closed and reusing it
//     would make the next drain return instantly and cut a request that had just started;
//   - one mutex around "check the flag and insert" and "set the flag and read the set", so a
//     request cannot slip past a switch that has already begun stopping the engine;
//   - leases carry their start time, so a dead proxy's phantom lease expires instead of stalling
//     every future switch for the full ceiling;
//   - slot leases are bounded by the current profile's `parallel` and admitted by priority, so
//     several sessions share one pool instead of each assuming it owns the engine.
type Leases struct {
	mu       sync.Mutex
	next     int64
	open     map[int64]lease
	capacity int
	waiters  []*waiter
	drained  chan struct{}
	draining bool
	ttl      time.Duration
}

// NewLeases returns an empty registry. A zero ttl means DefaultLeaseTTL.
func NewLeases(ttl time.Duration) *Leases {
	if ttl <= 0 {
		ttl = DefaultLeaseTTL
	}
	return &Leases{open: map[int64]lease{}, ttl: ttl}
}

// Acquire grants a switch-participation lease, or reports that the engine is switching. It is the
// unlimited form used by `select`: it does not consume a slot. The caller must retry after a short
// wait when ok is false; it must never proceed without a lease.
func (l *Leases) Acquire() (id int64, ok bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.draining {
		return 0, false
	}
	return l.grantLocked(false, PriorityNormal), true
}

// AcquireSlot grants a slot lease if capacity allows, otherwise queues the caller by priority and
// waits until a slot frees, ctx expires, or the class is exhausted. A capacity of zero means
// "unknown" and grants immediately, so a manager without a profile table behaves as before.
func (l *Leases) AcquireSlot(ctx context.Context, priority int, wait time.Duration) (int64, bool) {
	l.mu.Lock()
	l.expireLocked(time.Now())
	if l.draining {
		l.mu.Unlock()
		return 0, false
	}
	if l.canGrantLocked(priority) {
		id := l.grantLocked(true, priority)
		l.mu.Unlock()
		return id, true
	}
	w := &waiter{ch: make(chan int64, 1), priority: priority}
	l.waiters = append(l.waiters, w)
	l.mu.Unlock()

	if wait <= 0 {
		l.abandon(w)
		return 0, false
	}
	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case id := <-w.ch:
		return id, true
	case <-ctx.Done():
		l.abandon(w)
		return 0, false
	case <-timer.C:
		l.abandon(w)
		return 0, false
	}
}

// abandon removes a waiter that gave up, and releases a slot that was granted in the same
// instant. The grant path sends into the waiter's buffered channel while holding the lock, so a
// grant and a timeout can cross: without this read the slot would stay open with no holder until
// the ttl, blocking a real request.
func (l *Leases) abandon(w *waiter) {
	l.forget(w)
	select {
	case id := <-w.ch:
		l.Release(id)
	default:
	}
}

// canGrantLocked is the admission rule: a free slot, and no queued waiter of a HIGHER class. A
// same-class arrival queues behind the queue, which is what makes it fair.
//
// Capacity has three states. Negative means "unknown" (no profile table, or a profile without a
// `parallel`) and admits without counting, which is the pre-pool behaviour. Zero means the pool is
// CLOSED — `select none` just stopped the engine — and admits nothing. A positive count is the
// profile's slot pool.
func (l *Leases) canGrantLocked(priority int) bool {
	if l.capacity < 0 {
		return true
	}
	if l.capacity == 0 {
		return false
	}
	if l.slotCountLocked() >= l.capacity {
		return false
	}
	for _, w := range l.waiters {
		if w.priority > priority {
			return false
		}
	}
	return true
}

func (l *Leases) grantLocked(slot bool, priority int) int64 {
	now := time.Now()
	deadline := now.Add(l.ttl)
	if slot {
		// A slot lease is short-lived by design: it is held for one model call. A client that
		// vanishes mid-lease must not block a switch for the full 30-minute drain.
		deadline = now.Add(SlotLeaseTTL)
	}
	l.next++
	l.open[l.next] = lease{started: now, deadline: deadline, slot: slot, priority: priority}
	return l.next
}

func (l *Leases) slotCountLocked() int {
	count := 0
	for _, held := range l.open {
		if held.slot {
			count++
		}
	}
	return count
}

func (l *Leases) forget(w *waiter) {
	l.mu.Lock()
	defer l.mu.Unlock()
	for i, queued := range l.waiters {
		if queued == w {
			l.waiters = append(l.waiters[:i], l.waiters[i+1:]...)
			return
		}
	}
}

// Release ends a lease. Releasing an unknown id is a no-op, which keeps a double release from a
// retrying proxy harmless. A freed slot goes to the highest-priority waiter.
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
	l.promoteLocked()
}

// promoteLocked hands free slots to queued waiters, highest class first, FIFO within a class.
func (l *Leases) promoteLocked() {
	if l.draining || l.capacity <= 0 {
		return
	}
	for len(l.waiters) > 0 && l.slotCountLocked() < l.capacity {
		best := 0
		for i := 1; i < len(l.waiters); i++ {
			if l.waiters[i].priority > l.waiters[best].priority {
				best = i
			}
		}
		w := l.waiters[best]
		l.waiters = append(l.waiters[:best], l.waiters[best+1:]...)
		w.ch <- l.grantLocked(true, w.priority)
	}
}

// SetCapacity changes the slot pool. The manager calls it at start and after every switch, because
// the count is a property of the profile that is now resident.
func (l *Leases) SetCapacity(capacity int) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.capacity = capacity
	l.promoteLocked()
}

// Capacity reports the current slot pool.
func (l *Leases) Capacity() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.capacity
}

// Position is how many waiters of the same or a higher class are ahead of a new arrival.
func (l *Leases) Position(priority int) int {
	l.mu.Lock()
	defer l.mu.Unlock()
	count := 0
	for _, w := range l.waiters {
		if w.priority >= priority {
			count++
		}
	}
	return count
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
	l.promoteLocked()
}

// expireLocked drops leases past their own deadline and returns how many went.
func (l *Leases) expireLocked(now time.Time) int {
	stale := 0
	for id, held := range l.open {
		if now.After(held.deadline) {
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
	if n > 0 {
		if len(l.open) == 0 && l.drained != nil {
			close(l.drained)
			l.drained = nil
		}
		l.promoteLocked()
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
