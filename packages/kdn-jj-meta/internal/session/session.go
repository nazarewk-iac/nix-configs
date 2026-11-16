// Package session detects the harness, session ID and model of the agent that runs the command.
//
// Detection reads only the environment. It never inspects a transcript and never calls another
// tool, so it works offline and inside a sandbox.
package session

import "strings"

// Session identifies one agent session.
type Session struct {
	Harness string `json:"harness,omitempty"`
	ID      string `json:"session_id,omitempty"`
	Model   string `json:"model,omitempty"`
	// Source names the environment variable the session ID came from, or "flag" for an
	// explicit override. It is diagnostic only.
	Source string `json:"source,omitempty"`
}

type spec struct {
	harness   string
	idVars    []string
	modelVars []string
}

// specs is the detection table, in priority order. The first non-empty session ID wins. The
// table matches the harness matrix in docs/tasks/2026-11/journal-session-identity/, so a session
// recorded in the journal resolves to the same harness here.
var specs = []spec{
	{harness: "opencode", idVars: []string{"OPENCODE_SESSION_ID"}, modelVars: []string{"OPENCODE_MODEL"}},
	{harness: "pi", idVars: []string{"PI_SESSION_ID"}, modelVars: []string{"PI_MODEL"}},
	{harness: "claude", idVars: []string{"CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID"}, modelVars: []string{"CLAUDE_MODEL"}},
	{harness: "codex", idVars: []string{"CODEX_THREAD_ID", "CODEX_SESSION_ID"}, modelVars: []string{"CODEX_MODEL"}},
	{harness: "cursor", idVars: []string{"CURSOR_CONVERSATION_ID"}, modelVars: []string{"CURSOR_MODEL"}},
	{harness: "gemini", idVars: []string{"GEMINI_SESSION_ID"}, modelVars: []string{"GEMINI_MODEL"}},
	{harness: "copilot", idVars: []string{"COPILOT_SESSION_ID"}, modelVars: []string{"COPILOT_MODEL"}},
}

// Detect reads the environment through getenv and returns the session it describes.
//
// A harness without a session ID is still reported when AI_AGENT or AGENT_HARNESS names one, so
// the Harness trailer is available even when the harness exports no ID. The model is empty when
// nothing exports it; the caller warns and writes a model-less Assisted-by.
func Detect(getenv func(string) string) Session {
	if getenv == nil {
		getenv = func(string) string { return "" }
	}
	for _, s := range specs {
		for _, v := range s.idVars {
			if id := strings.TrimSpace(getenv(v)); id != "" {
				return Session{
					Harness: s.harness,
					ID:      id,
					Model:   firstEnv(getenv, append(s.modelVars, "AGENT_MODEL", "KDN_JJ_META_MODEL")),
					Source:  v,
				}
			}
		}
	}
	if id := strings.TrimSpace(getenv("AGENT_SESSION_ID")); id != "" {
		harness := firstEnv(getenv, []string{"AGENT_HARNESS", "AI_AGENT"})
		if harness == "" {
			harness = "agent"
		}
		return Session{
			Harness: NormalizeHarness(harness),
			ID:      id,
			Model:   firstEnv(getenv, []string{"AGENT_MODEL", "KDN_JJ_META_MODEL"}),
			Source:  "AGENT_SESSION_ID",
		}
	}
	if agent := firstEnv(getenv, []string{"AI_AGENT", "AGENT_HARNESS"}); agent != "" {
		return Session{
			Harness: NormalizeHarness(agent),
			Model:   firstEnv(getenv, []string{"AGENT_MODEL", "KDN_JJ_META_MODEL"}),
			Source:  "AI_AGENT",
		}
	}
	return Session{Model: firstEnv(getenv, []string{"AGENT_MODEL", "KDN_JJ_META_MODEL"}), Source: "none"}
}

// NormalizeHarness maps the values harnesses export for themselves to the short names the table
// uses. Claude Code exports AI_AGENT=claude-code_<version>, for example.
func NormalizeHarness(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	switch {
	case name == "":
		return ""
	case strings.HasPrefix(name, "claude-code"):
		return "claude"
	case strings.HasPrefix(name, "opencode"):
		return "opencode"
	case strings.HasPrefix(name, "copilot"):
		return "copilot"
	case strings.HasPrefix(name, "gemini"):
		return "gemini"
	case strings.HasPrefix(name, "cursor"):
		return "cursor"
	case strings.HasPrefix(name, "codex"):
		return "codex"
	case strings.HasPrefix(name, "pi"):
		return "pi"
	}
	return name
}

// Apply returns s with the non-empty explicit overrides applied. An override also marks the
// session as flag-sourced.
func (s Session) Apply(harness, id, model string) Session {
	if v := strings.TrimSpace(harness); v != "" {
		s.Harness = NormalizeHarness(v)
		s.Source = "flag"
	}
	if v := strings.TrimSpace(id); v != "" {
		s.ID = v
		s.Source = "flag"
	}
	if v := strings.TrimSpace(model); v != "" {
		s.Model = v
		s.Source = "flag"
	}
	return s
}

func firstEnv(getenv func(string) string, names []string) string {
	for _, name := range names {
		if v := strings.TrimSpace(getenv(name)); v != "" {
			return v
		}
	}
	return ""
}
