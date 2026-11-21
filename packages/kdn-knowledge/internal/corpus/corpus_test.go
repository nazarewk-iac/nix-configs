package corpus

import (
	"context"
	"strings"
	"testing"
	"time"

	"kdn-knowledge/internal/testsupport"
)

func TestBuildDropsReasoningAndTruncatesTools(t *testing.T) {
	t.Parallel()

	long := strings.Repeat("x", 5000)
	db := testsupport.NewDB(t,
		testsupport.Session{
			ID: "ses_one", Title: "One", Directory: "/repo", CreatedMS: 1700000000000, UpdatedMS: 1700000001000,
			Messages: []testsupport.Message{
				testsupport.User("How do I split a change?"),
				testsupport.Assistant(
					testsupport.Reasoning("SECRET-REASONING-MUST-NOT-APPEAR"),
					testsupport.Text("Use jj split."),
					testsupport.Tool("shell", map[string]any{"command": "jj split -m x -- a b"}, long),
				),
			},
		},
		testsupport.Session{
			ID: "ses_two", Title: "Two", Directory: "/repo/sub", CreatedMS: 1700000002000, UpdatedMS: 1700000003000,
			Messages: []testsupport.Message{
				testsupport.User("Second session"),
				testsupport.Assistant(testsupport.Reasoning("SECRET-REASONING-MUST-NOT-APPEAR")),
			},
		},
	)
	rows, err := Sessions(context.Background(), db, Query{Project: "/repo"})
	if err != nil {
		t.Fatalf("Sessions: %v", err)
	}
	if len(rows) != 2 {
		t.Fatalf("Sessions returned %d rows, want 2", len(rows))
	}
	raw, err := Messages(context.Background(), db, "ses_one")
	if err != nil {
		t.Fatalf("Messages: %v", err)
	}
	session := Build(rows[1], raw, 0)
	if session.ID != "ses_one" {
		t.Fatalf("built session %s, want ses_one", session.ID)
	}
	if len(session.Messages) != 3 {
		t.Fatalf("got %d messages, want 3: %+v", len(session.Messages), session.Messages)
	}
	for _, message := range session.Messages {
		if strings.Contains(message.Text, "SECRET-REASONING") {
			t.Fatalf("reasoning part leaked into the corpus: %+v", message)
		}
	}
	tool := session.Messages[2]
	if tool.Role != "tool" || tool.Name != "shell" {
		t.Fatalf("third message = %+v, want a shell tool message", tool)
	}
	if tool.Command != "jj split -m x -- a b" {
		t.Fatalf("command = %q", tool.Command)
	}
	if !strings.Contains(tool.Text, "… [truncated]") {
		t.Fatalf("tool text was not truncated: %q", tool.Text[:40])
	}
	if len([]rune(tool.Text)) > ToolChars {
		t.Fatalf("tool text has %d runes, want at most %d", len([]rune(tool.Text)), ToolChars)
	}
	if session.Hash == "" || !strings.HasPrefix(session.Hash, "sha256:") {
		t.Fatalf("hash = %q, want a sha256 prefix", session.Hash)
	}

	second, err := Messages(context.Background(), db, "ses_two")
	if err != nil {
		t.Fatalf("Messages: %v", err)
	}
	secondSession := Build(rows[0], second, 0)
	if len(secondSession.Messages) != 1 {
		t.Fatalf("second session has %d messages, want only the user message", len(secondSession.Messages))
	}

	changed := Build(rows[1], second, 0)
	if changed.Hash == session.Hash {
		t.Fatalf("two different sessions share the hash %q", session.Hash)
	}
}

func mustTime(milliseconds int64) time.Time {
	return time.UnixMilli(milliseconds).UTC()
}

func TestSessionsFilters(t *testing.T) {
	t.Parallel()

	db := testsupport.NewDB(t,
		testsupport.Session{
			ID: "ses_idle", Title: "Idle", Directory: "/repo", CreatedMS: 1700000000000, UpdatedMS: 1700000001000,
			Messages: []testsupport.Message{testsupport.User("hello")},
		},
		testsupport.Session{
			ID: "ses_live", Title: "Live", Directory: "/repo", CreatedMS: 1700000002000, UpdatedMS: 1700000003000,
			Live:     true,
			Messages: []testsupport.Message{testsupport.User("still running")},
		},
		testsupport.Session{
			ID: "ses_other", Title: "Other", Directory: "/repo2", CreatedMS: 1700000004000, UpdatedMS: 1700000005000,
			Messages: []testsupport.Message{testsupport.User("elsewhere")},
		},
	)

	cases := []struct {
		name  string
		query Query
		want  []string
	}{
		{
			name:  "project and idle",
			query: Query{Project: "/repo"},
			want:  []string{"ses_idle"},
		},
		{
			name:  "the prefix does not match another repository",
			query: Query{Project: "/repo2"},
			want:  []string{"ses_other"},
		},
		{
			name:  "live sessions are included on request",
			query: Query{Project: "/repo", IncludeLive: true},
			want:  []string{"ses_live", "ses_idle"},
		},
		{
			name:  "since filter",
			query: Query{Project: "/repo", IncludeLive: true, Since: mustTime(1700000001500)},
			want:  []string{"ses_live"},
		},
		{
			name:  "limit",
			query: Query{Project: "/repo", IncludeLive: true, Limit: 1},
			want:  []string{"ses_live"},
		},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			rows, err := Sessions(context.Background(), db, test.query)
			if err != nil {
				t.Fatalf("Sessions: %v", err)
			}
			got := make([]string, 0, len(rows))
			for _, row := range rows {
				got = append(got, row.ID)
			}
			if strings.Join(got, ",") != strings.Join(test.want, ",") {
				t.Fatalf("got %v, want %v", got, test.want)
			}
		})
	}

	ids, err := AllIDs(context.Background(), db)
	if err != nil {
		t.Fatalf("AllIDs: %v", err)
	}
	if len(ids) != 3 {
		t.Fatalf("AllIDs returned %d ids, want 3", len(ids))
	}
}

func TestMessagesRejectsUnsafeID(t *testing.T) {
	t.Parallel()

	db := testsupport.NewDB(t)
	if _, err := Messages(context.Background(), db, "ses_x'; DROP TABLE session_v2; --"); err == nil {
		t.Fatal("Messages accepted an unsafe session id")
	}
}
