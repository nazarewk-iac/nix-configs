package session

import "testing"

func env(pairs map[string]string) func(string) string {
	return func(key string) string { return pairs[key] }
}

func TestDetect(t *testing.T) {
	cases := []struct {
		name string
		env  map[string]string
		want Session
	}{
		{
			name: "opencode",
			env:  map[string]string{"OPENCODE_SESSION_ID": "ses_1", "OPENCODE_MODEL": "deepseek"},
			want: Session{Harness: "opencode", ID: "ses_1", Model: "deepseek", Source: "OPENCODE_SESSION_ID"},
		},
		{
			name: "pi wins over claude when both are set",
			env:  map[string]string{"PI_SESSION_ID": "pi_1", "PI_MODEL": "m", "CLAUDE_CODE_SESSION_ID": "claude_1"},
			want: Session{Harness: "pi", ID: "pi_1", Model: "m", Source: "PI_SESSION_ID"},
		},
		{
			name: "claude",
			env:  map[string]string{"CLAUDE_CODE_SESSION_ID": "c_1"},
			want: Session{Harness: "claude", ID: "c_1", Source: "CLAUDE_CODE_SESSION_ID"},
		},
		{
			name: "codex thread id",
			env:  map[string]string{"CODEX_THREAD_ID": "t_1"},
			want: Session{Harness: "codex", ID: "t_1", Source: "CODEX_THREAD_ID"},
		},
		{
			name: "codex session id fallback",
			env:  map[string]string{"CODEX_SESSION_ID": "s_1"},
			want: Session{Harness: "codex", ID: "s_1", Source: "CODEX_SESSION_ID"},
		},
		{
			name: "agent model fallback",
			env:  map[string]string{"OPENCODE_SESSION_ID": "ses_1", "AGENT_MODEL": "fallback"},
			want: Session{Harness: "opencode", ID: "ses_1", Model: "fallback", Source: "OPENCODE_SESSION_ID"},
		},
		{
			name: "generic session",
			env:  map[string]string{"AGENT_SESSION_ID": "a_1", "AGENT_MODEL": "m"},
			want: Session{Harness: "agent", ID: "a_1", Model: "m", Source: "AGENT_SESSION_ID"},
		},
		{
			name: "generic session with harness",
			env:  map[string]string{"AGENT_SESSION_ID": "a_1", "AGENT_HARNESS": "my-agent"},
			want: Session{Harness: "my-agent", ID: "a_1", Source: "AGENT_SESSION_ID"},
		},
		{
			name: "harness without a session id",
			env:  map[string]string{"AI_AGENT": "claude-code_2.1", "AGENT_MODEL": "opus"},
			want: Session{Harness: "claude", Model: "opus", Source: "AI_AGENT"},
		},
		{
			name: "nothing",
			env:  map[string]string{},
			want: Session{Source: "none"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Detect(env(tc.env)); got != tc.want {
				t.Fatalf("Detect() = %#v, want %#v", got, tc.want)
			}
		})
	}
}

func TestApply(t *testing.T) {
	base := Session{Harness: "opencode", ID: "ses_1", Model: "m", Source: "OPENCODE_SESSION_ID"}
	got := base.Apply("", "ses_2", "")
	if got.ID != "ses_2" || got.Source != "flag" || got.Harness != "opencode" {
		t.Fatalf("Apply() = %#v", got)
	}
	got = base.Apply("Claude-Code", "", "")
	if got.Harness != "claude" {
		t.Fatalf("Apply() harness = %q", got.Harness)
	}
	if got = base.Apply("", "", ""); got != base {
		t.Fatalf("empty overrides changed the session: %#v", got)
	}
}

func TestNormalizeHarness(t *testing.T) {
	cases := map[string]string{
		"":                "",
		"opencode":        "opencode",
		"claude-code_2.0": "claude",
		"Codex":           "codex",
		"pi-coding-agent": "pi",
		"custom-agent":    "custom-agent",
	}
	for input, want := range cases {
		if got := NormalizeHarness(input); got != want {
			t.Fatalf("NormalizeHarness(%q) = %q, want %q", input, got, want)
		}
	}
}
