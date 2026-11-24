package journal

import (
	"os"
	"path/filepath"
	"testing"
)

func write(t *testing.T, j *Journal, rec map[string]any) {
	t.Helper()
	if err := j.Append(rec); err != nil {
		t.Fatalf("append: %v", err)
	}
}

func TestAppendStampsTimeAndEventSurvivesARoundTrip(t *testing.T) {
	j := New(filepath.Join(t.TempDir(), "events.jsonl"))
	write(t, j, map[string]any{"event": EventSwitch, "from": "omni-fast", "to": "max",
		"seconds": 67.0, "ok": true, "cause": "select"})

	events := j.Events(0)
	if len(events) != 1 {
		t.Fatalf("read %d events, want 1", len(events))
	}
	if _, ok := events[0]["ts"].(float64); !ok {
		t.Fatalf("ts is %T, want a number", events[0]["ts"])
	}
	if events[0]["event"] != EventSwitch || events[0]["to"] != "max" {
		t.Fatalf("round trip lost fields: %#v", events[0])
	}
}

func TestLastSwitchIgnoresLaterEvents(t *testing.T) {
	j := New(filepath.Join(t.TempDir(), "events.jsonl"))
	write(t, j, map[string]any{"event": EventSwitch, "from": "max", "to": "omni-fast", "seconds": 50.0})
	write(t, j, map[string]any{"event": EventRequest, "seconds": 6.2})
	write(t, j, map[string]any{"event": EventCompanionUp, "model": "qwen3-omni", "seconds": 90.0})

	last, ok := j.LastSwitch()
	if !ok {
		t.Fatal("no switch found")
	}
	if last["to"] != "omni-fast" {
		t.Fatalf("last switch to = %v", last["to"])
	}
}

func TestStatsAggregatesAndToleratesUnknownEventsAndMissingDurations(t *testing.T) {
	j := New(filepath.Join(t.TempDir(), "events.jsonl"))
	write(t, j, map[string]any{"event": EventSwitch, "from": "max", "to": "omni-fast", "seconds": 50.0})
	write(t, j, map[string]any{"event": EventSwitch, "from": "omni-fast", "to": "max", "seconds": 70.0})
	write(t, j, map[string]any{"event": EventSwitch, "from": "max", "to": "omni-fast", "seconds": 60.0})
	// A companion unload records how long it was loaded, not a duration: it must not create a bucket.
	write(t, j, map[string]any{"event": EventCompanionDown, "model": "qwen3-omni", "loaded_for": 36.0})
	// An event name a future version invented must be aggregated, not rejected.
	write(t, j, map[string]any{"event": "future_thing", "seconds": 3.0})

	stats := j.Stats()
	if stats.Events != 5 {
		t.Fatalf("events = %d, want 5", stats.Events)
	}
	if got := stats.ByEvent[EventCompanionDown]; got.N != 0 {
		t.Fatalf("companion_down produced a duration bucket: %#v", got)
	}
	switchBucket := stats.ByEvent[EventSwitch]
	if switchBucket.N != 3 || switchBucket.Max != 70 {
		t.Fatalf("switch bucket = %#v, want n=3 max=70", switchBucket)
	}
	// Two values: round(0.5) is 0 in both Python and Go, so the median is the lower element.
	if got := stats.ByTransition["max->omni-fast"]; got.N != 2 || got.Median != 50 {
		t.Fatalf("transition bucket = %#v, want n=2 median=50", got)
	}
	if got := stats.ByEvent["future_thing"]; got.N != 1 {
		t.Fatalf("unknown event was dropped: %#v", got)
	}
}

func TestPercentileUsesRoundHalfToEvenLikePython(t *testing.T) {
	// Python's round() is banker's rounding: n=6 -> index 2 (not 3), n=11 -> index 5.
	n6 := []float64{1, 2, 3, 4, 5, 6}
	if got := percentile(n6, 50); got != 3 {
		t.Fatalf("median of 6 = %v, want 3", got)
	}
	n11 := []float64{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
	if got := percentile(n11, 50); got != 6 {
		t.Fatalf("median of 11 = %v, want 6", got)
	}
}

func TestPartialLineIsSkippedNotFatal(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	j := New(path)
	write(t, j, map[string]any{"event": EventRequest, "seconds": 1.0})
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	f.WriteString(`{"event": "switch", "sec`) // a torn write
	f.Close()

	events := j.Events(0)
	if len(events) != 1 {
		t.Fatalf("read %d events, want the one intact line", len(events))
	}
}

func TestLimitReturnsTheNewest(t *testing.T) {
	j := New(filepath.Join(t.TempDir(), "events.jsonl"))
	for i := 0; i < 5; i++ {
		write(t, j, map[string]any{"event": EventRequest, "seconds": float64(i)})
	}
	events := j.Events(2)
	if len(events) != 2 || events[1]["seconds"] != 4.0 {
		t.Fatalf("limit=2 returned %#v", events)
	}
}

func TestSeqIsMonotonicAndSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	j := New(path)
	write(t, j, map[string]any{"event": EventSwitch, "to": "max"})
	write(t, j, map[string]any{"event": EventEngineLoad, "model": "qfn"})

	events := j.Events(0)
	if seqOf(events[0]) != 1 || seqOf(events[1]) != 2 {
		t.Fatalf("seq = %d,%d, want 1,2", seqOf(events[0]), seqOf(events[1]))
	}

	// A restarted manager continues the sequence and replays the ring from the file.
	restarted := New(path)
	write(t, restarted, map[string]any{"event": EventEngineStop})
	events = restarted.Events(0)
	if seqOf(events[2]) != 3 {
		t.Fatalf("seq after restart = %d, want 3", seqOf(events[2]))
	}
}

func TestSubscribeReplaysThenStreamsLive(t *testing.T) {
	j := New(filepath.Join(t.TempDir(), "events.jsonl"))
	write(t, j, map[string]any{"event": EventSwitch, "to": "a"})
	write(t, j, map[string]any{"event": EventSwitch, "to": "b"})
	write(t, j, map[string]any{"event": EventSwitch, "to": "c"})

	ch, cancel := j.Subscribe(1) // everything after seq 1
	defer cancel()

	got := []string{}
	for i := 0; i < 2; i++ {
		select {
		case rec := <-ch:
			got = append(got, rec["to"].(string))
		default:
			t.Fatalf("replay delivered %d of 2 records: %v", i, got)
		}
	}
	if got[0] != "b" || got[1] != "c" {
		t.Fatalf("replay = %v, want [b c]", got)
	}

	write(t, j, map[string]any{"event": EventSwitch, "to": "d"})
	select {
	case rec := <-ch:
		if rec["to"] != "d" {
			t.Fatalf("live record = %v, want d", rec["to"])
		}
	default:
		t.Fatal("no live record after append")
	}
}

func TestSubscribeCancelClosesTheChannel(t *testing.T) {
	j := New(filepath.Join(t.TempDir(), "events.jsonl"))
	ch, cancel := j.Subscribe(0)
	cancel()
	cancel() // a double cancel must not panic on a closed channel

	if _, open := <-ch; open {
		t.Fatal("channel is still open after cancel")
	}
}
