package control

import (
	"context"
	"sync"
	"testing"
	"time"
)

func TestAcquireReleaseCounts(t *testing.T) {
	l := NewLeases(time.Minute)
	if l.InFlight() != 0 {
		t.Fatalf("fresh registry reports %d in flight", l.InFlight())
	}
	id1, ok1 := l.Acquire()
	id2, ok2 := l.Acquire()
	if !ok1 || !ok2 || id1 == id2 {
		t.Fatalf("two acquires: ok=(%v,%v) ids=(%d,%d)", ok1, ok2, id1, id2)
	}
	if got := l.InFlight(); got != 2 {
		t.Fatalf("in flight = %d, want 2", got)
	}
	l.Release(id1)
	l.Release(id1)  // double release must be harmless
	l.Release(9999) // unknown id must be harmless
	if got := l.InFlight(); got != 1 {
		t.Fatalf("in flight = %d, want 1 after one release", got)
	}
	l.Release(id2)
	if got := l.InFlight(); got != 0 {
		t.Fatalf("in flight = %d, want 0", got)
	}
}

func TestDrainWaitsForLease(t *testing.T) {
	l := NewLeases(time.Minute)
	id, _ := l.Acquire()

	done := make(chan time.Duration, 1)
	go func() {
		waited, clean := l.BeginDrain(context.Background())
		if !clean {
			t.Errorf("drain reported unclean")
		}
		done <- waited
	}()

	// The drain must not finish while the lease is held.
	select {
	case d := <-done:
		t.Fatalf("drain returned after %v with a lease still open", d)
	case <-time.After(100 * time.Millisecond):
	}

	l.Release(id)
	select {
	case waited := <-done:
		if waited < 90*time.Millisecond {
			t.Fatalf("drain waited %v, expected to wait for the release", waited)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("drain never returned after the lease was released")
	}
}

func TestTwoConsecutiveDrainsDoNotReuseAClosedChannel(t *testing.T) {
	l := NewLeases(time.Minute)

	// First drain over an empty set: returns immediately.
	if _, clean := l.BeginDrain(context.Background()); !clean {
		t.Fatal("first drain over an empty set was not clean")
	}
	l.EndDrain()

	// Second drain with a lease open must wait. If the channel were reused, this would return
	// instantly and cut the request — the regression the review caught.
	id, _ := l.Acquire()
	waited := make(chan bool, 1)
	go func() {
		_, clean := l.BeginDrain(context.Background())
		waited <- clean
	}()
	select {
	case <-waited:
		t.Fatal("second drain returned while a lease was open")
	case <-time.After(100 * time.Millisecond):
	}
	l.Release(id)
	select {
	case clean := <-waited:
		if !clean {
			t.Fatal("second drain ended unclean")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("second drain never returned")
	}
}

func TestAcquireRefusedWhileDraining(t *testing.T) {
	l := NewLeases(time.Minute)
	l.EndDrain()
	l.mu.Lock()
	l.draining = true
	l.mu.Unlock()
	if _, ok := l.Acquire(); ok {
		t.Fatal("acquire succeeded while draining")
	}
	l.EndDrain()
	if _, ok := l.Acquire(); !ok {
		t.Fatal("acquire refused after the drain ended")
	}
}

func TestDrainTimeoutReportsUnclean(t *testing.T) {
	l := NewLeases(time.Minute)
	id, _ := l.Acquire()
	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
	defer cancel()
	waited, clean := l.BeginDrain(ctx)
	if clean {
		t.Fatal("drain reported clean although a lease was still open")
	}
	if waited < 70*time.Millisecond {
		t.Fatalf("drain waited %v, expected about the context deadline", waited)
	}
	l.Release(id)
	l.EndDrain()
}

func TestStaleLeaseExpires(t *testing.T) {
	l := NewLeases(50 * time.Millisecond)
	id, _ := l.Acquire()
	time.Sleep(80 * time.Millisecond)
	if n := l.ExpireStale(); n != 1 {
		t.Fatalf("expired %d leases, want 1", n)
	}
	if l.InFlight() != 0 {
		t.Fatalf("in flight = %d after expiry", l.InFlight())
	}
	l.Release(id) // releasing an expired lease is harmless
}

func TestConcurrentAcquireAndDrainDoNotLoseTheFlag(t *testing.T) {
	// The hazard: Acquire checks draining, BeginDrain sets it. With one mutex, either the acquire
	// happens first (and the drain waits for it) or the drain happens first (and the acquire is
	// refused). It must never return a lease that the drain does not see.
	l := NewLeases(time.Minute)
	var wg sync.WaitGroup
	var mu sync.Mutex
	var granted []int64

	for i := 0; i < 32; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if id, ok := l.Acquire(); ok {
				mu.Lock()
				granted = append(granted, id)
				mu.Unlock()
			}
		}()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_, clean := l.BeginDrain(ctx)
	wg.Wait()

	mu.Lock()
	ids := append([]int64(nil), granted...)
	mu.Unlock()

	// Everything granted before the drain began must still be held by the drain's bookkeeping.
	if clean && l.InFlight() != len(ids) {
		t.Fatalf("drain saw a clean set but %d leases were granted and not yet released", len(ids))
	}
	for _, id := range ids {
		l.Release(id)
	}
	l.EndDrain()
	if got := l.InFlight(); got != 0 {
		t.Fatalf("in flight = %d after releasing everything", got)
	}
	if len(ids) == 0 {
		t.Log("no lease was granted before the drain; the race window was not exercised")
	}
}
