package atuin

import (
	"testing"
	"time"
)

func TestFind(t *testing.T) {
	started := time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC)
	threads := []Thread{
		{AtuinID: "a", Harness: "opencode", SessionID: "ses_1", Cwd: "/repo", StartedAt: "2026-11-16T09:01:00Z"},
		{AtuinID: "b", Harness: "claude-code", SessionID: "c_1", Cwd: "/repo", StartedAt: "2026-11-16T09:02:00Z"},
		{AtuinID: "c", Harness: "opencode", SessionID: "ses_2", Cwd: "/other", StartedAt: "2026-11-16T09:03:00Z"},
	}
	cases := []struct {
		name      string
		sessionID string
		harness   string
		cwd       string
		started   time.Time
		window    time.Duration
		want      string
		how       string
	}{
		{name: "exact session id", sessionID: "ses_1", harness: "opencode", cwd: "/repo", started: started, want: "a", how: MatchSessionID},
		{name: "claude-code normalizes", harness: "claude", cwd: "/repo", started: started, window: 10 * time.Minute, want: "b", how: MatchCwdTime},
		{name: "cwd filters", harness: "opencode", cwd: "/other", started: started, window: 10 * time.Minute, want: "c", how: MatchCwdTime},
		{name: "window filters", harness: "opencode", cwd: "/repo", started: started.Add(time.Hour), window: 10 * time.Minute, how: MatchNone},
		{name: "ambiguous", harness: "opencode", cwd: "", started: started, window: 10 * time.Minute, how: MatchAmbiguous},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			match := Find(threads, tc.sessionID, tc.harness, tc.cwd, tc.started, tc.window)
			if match.How != tc.how || match.Thread.AtuinID != tc.want {
				t.Fatalf("Find() = %#v", match)
			}
		})
	}
}

func TestParseTime(t *testing.T) {
	for _, value := range []string{
		"2026-11-15T18:24:38.156+00:00",
		"2026-11-15T18:24:38Z",
		"2026-11-15T18:24:38.156+01:00",
	} {
		if _, err := ParseTime(value); err != nil {
			t.Fatalf("ParseTime(%q) error = %v", value, err)
		}
	}
	if _, err := ParseTime(""); err == nil {
		t.Fatal("ParseTime accepted an empty value")
	}
}

func TestDecodeThreads(t *testing.T) {
	threads, err := decodeThreads(`[{"atuin_id":"a","harness":"opencode","session_id":"ses_1","message_count":3}]`)
	if err != nil {
		t.Fatal(err)
	}
	if len(threads) != 1 || threads[0].AtuinID != "a" || threads[0].MessageCount != 3 {
		t.Fatalf("threads = %#v", threads)
	}
	for _, empty := range []string{"", "null", "[]"} {
		if got, err := decodeThreads(empty); err != nil || len(got) != 0 {
			t.Fatalf("decodeThreads(%q) = %#v, %v", empty, got, err)
		}
	}
	if _, err := decodeThreads("{not json"); err == nil {
		t.Fatal("decodeThreads accepted invalid JSON")
	}
}

func TestFindAt(t *testing.T) {
	threads := []Thread{
		{AtuinID: "early", Harness: "opencode", SessionID: "ses_early", Cwd: "/repo", StartedAt: "2026-11-16T09:00:00Z", UpdatedAt: "2026-11-16T12:00:00Z"},
		{AtuinID: "late", Harness: "pi", SessionID: "ses_late", Cwd: "/repo", StartedAt: "2026-11-16T10:00:00Z", UpdatedAt: "2026-11-16T11:00:00Z"},
		{AtuinID: "elsewhere", Harness: "opencode", SessionID: "ses_other", Cwd: "/other", StartedAt: "2026-11-16T09:00:00Z", UpdatedAt: "2026-11-16T12:00:00Z"},
	}
	at := func(value string) time.Time {
		parsed, err := ParseTime(value)
		if err != nil {
			t.Fatal(err)
		}
		return parsed
	}
	if match := FindAt(threads, "/repo", at("2026-11-16T09:30:00Z")); match.How != MatchTime || match.Thread.AtuinID != "early" {
		t.Fatalf("FindAt(09:30) = %#v", match)
	}
	if match := FindAt(threads, "/repo", at("2026-11-16T10:30:00Z")); match.How != MatchTime || match.Thread.AtuinID != "late" {
		t.Fatalf("FindAt(10:30) = %#v, want the latest start", match)
	}
	if match := FindAt(threads, "/repo", at("2026-11-16T13:00:00Z")); match.How != MatchNone {
		t.Fatalf("FindAt(13:00) = %#v", match)
	}
	if match := FindAt(threads, "/other", at("2026-11-16T10:30:00Z")); match.How != MatchTime || match.Thread.AtuinID != "elsewhere" {
		t.Fatalf("FindAt(/other) = %#v", match)
	}
	tie := append([]Thread{}, threads...)
	tie[1].StartedAt = "2026-11-16T09:00:00Z"
	if match := FindAt(tie, "/repo", at("2026-11-16T10:30:00Z")); match.How != MatchAmbiguous {
		t.Fatalf("FindAt(tie) = %#v", match)
	}
}
