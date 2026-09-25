package iso8601

import (
	"testing"
	"time"
)

func TestParseForms(t *testing.T) {
	cases := []struct {
		in   string
		want time.Time
	}{
		{"2026", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)},
		{"2026-09", time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)},
		{"2026-09-01", time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)},
		{"2026-09-01T12:30", time.Date(2026, 9, 1, 12, 30, 0, 0, time.UTC)},
		{"2026-09-01T12:30:45", time.Date(2026, 9, 1, 12, 30, 45, 0, time.UTC)},
		{"2026-09-01T12:30:45Z", time.Date(2026, 9, 1, 12, 30, 45, 0, time.UTC)},
		{"2026Z", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)},
		{"2026-09Z", time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)},
	}
	for _, tc := range cases {
		got, err := Parse(tc.in)
		if err != nil {
			t.Fatalf("Parse(%q): %v", tc.in, err)
		}
		if !got.Equal(tc.want) {
			t.Errorf("Parse(%q) = %v, want %v", tc.in, got, tc.want)
		}
	}
}

func TestParseLowestValue(t *testing.T) {
	// A missing component takes its lowest value.
	got, err := Parse("2026")
	if err != nil {
		t.Fatal(err)
	}
	if got.Month() != time.January || got.Day() != 1 || got.Hour() != 0 || got.Minute() != 0 {
		t.Errorf("Parse(2026) = %v, want 2026-01-01T00:00:00Z", got)
	}
}

func TestParseRejectsGarbage(t *testing.T) {
	if _, err := Parse("not-a-date"); err == nil {
		t.Error("Parse(not-a-date) succeeded, want error")
	}
	if _, err := Parse(""); err == nil {
		t.Error("Parse(\"\") succeeded, want error")
	}
}

func TestBefore(t *testing.T) {
	notBefore := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)

	// A null minimum never triggers.
	stale, err := Before(notBefore, nil)
	if err != nil || stale {
		t.Errorf("Before(nil) = %v, %v; want false, nil", stale, err)
	}

	// An older minimum does not trigger.
	older := "2026"
	stale, err = Before(notBefore, &older)
	if err != nil || stale {
		t.Errorf("Before(2026) = %v, %v; want false, nil", stale, err)
	}

	// A newer minimum triggers.
	newer := "2026-09-01"
	stale, err = Before(notBefore, &newer)
	if err != nil || !stale {
		t.Errorf("Before(2026-09-01) = %v, %v; want true, nil", stale, err)
	}
}
