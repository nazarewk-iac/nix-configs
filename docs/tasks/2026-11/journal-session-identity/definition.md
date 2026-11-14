---
type: Task
description: Tie harness sessions to jujutsu change IDs and Atuin Threads, and broaden kdn-journal's harness detection beyond OpenCode.
status: open
authored_by: agent
timestamp: 2026-11-16T08:30:00+01:00
---

# Journal session identity: jj changes, harnesses and Atuin Threads

## Context

`kdn-journal` reads a session directory named
`.cache/agents/<harness>-<YYYYMMDD>-<session>/`, plus the task pair. The directory convention is
harness-agnostic, but the tool's automatic session selection knows only
`$OPENCODE_SESSION_ID`. The documented harnesses are `opencode`, `pi`, `claude` and `codex`; the
actual environment variables differ per harness, and the current journal has no durable link to the
VCS changes a session produced or to the transcript that Atuin now captures.

Atuin 18.24+ added **Threads**: it captures AI coding-agent sessions (Claude Code, Codex, Copilot,
Grok, Kiro, opencode, Pi, Omp, Amp) into an encrypted record store, gives each a stable UUIDv7, and
exposes `atuin threads list|show|search --style json` plus an MCP server. That is the transcript and
tool-call layer the journal has been missing.

Jujutsu change IDs are stable identifiers for changes, but the main checkout shares one `@` between
parallel sessions. A change ID can be recorded, but it does not by itself prove which session owns
the change.

## Goal

Give every journal session a durable identity record that answers:

- which harness and native session ID this directory belongs to;
- which task it works on and where it runs;
- which jj changes and commits it recorded or produced;
- which Atuin thread holds its transcript and tool calls;
- which other sessions are in the same checkout or task.

Make `kdn-journal summary` auto-select the current session for every supported harness, not only
OpenCode, and add commands to record and inspect the links.

## Scope

### 1. Harness support matrix

| Harness     | Session env var                                | Process marker                           | Atuin Threads   |
| ----------- | ---------------------------------------------- | ---------------------------------------- | --------------- |
| opencode    | `OPENCODE_SESSION_ID` (v2 shell tool)          | `OPENCODE=1`, `AGENT=1`                  | yes             |
| pi          | `PI_SESSION_ID`, `PI_SESSION_FILE`             | `PI_CODING_AGENT=true`, `AI_AGENT=pi`    | yes             |
| Claude Code | `CLAUDE_CODE_SESSION_ID`                       | `CLAUDECODE=1`, `AI_AGENT=claude-code_*` | yes             |
| Codex       | `CODEX_THREAD_ID`, `CODEX_SESSION_ID` fallback | `CODEX_CI=1`                             | yes             |
| Cursor      | `CURSOR_CONVERSATION_ID`                       | `CURSOR_AGENT=1`                         | no (Atuin list) |
| Gemini CLI  | `GEMINI_SESSION_ID`                            | —                                        | no (Atuin list) |
| Copilot     | `COPILOT_SESSION_ID`                           | —                                        | yes             |
| generic     | `AGENT_SESSION_ID`                             | —                                        | —               |

- Detect the harness and session ID from the environment in priority order; `--session` always
  wins.
- Map harness names to the journal directory prefix (`claude-code` -> `claude`).
- Fall back to the newest session when no environment variable matches.
- Document that env vars are version-specific and that the directory convention accepts any
  `[a-z0-9]+` harness even when the detector does not know it.

### 2. Session metadata sidecar

Add `.cache/agents/<session>/session.json` (git-ignored) with:

```json
{
  "version": 1,
  "harness": "opencode",
  "session_id": "ses_e1f8...",
  "started_at": "2026-11-16T08:30:00+01:00",
  "cwd": "/home/kdn/dev/github.com/nazarewk-iac/nix-configs",
  "task": "docs/tasks/2026-11/agent-journal-summary",
  "jj": {
    "working_copy_change": "yoorvlzm...",
    "change_ids": ["..."],
    "commits": ["..."]
  },
  "atuin": {
    "thread_id": "019a...",
    "agent_session_id": "ses_e1f8..."
  }
}
```

- `kdn-journal session init` writes it from the environment, cwd, task and
  `jj log -r @ -T change_id` (when jj is available).
- `kdn-journal session record-change <change-id>` appends a change; `session record-commit <id>`
  appends a commit.
- `kdn-journal session changes` resolves the recorded change/commit IDs through jj and prints the
  descriptions, authors, timestamps and files.
- The sidecar is local-only by default. It must not be committed.

### 3. jj change mapping

- Record `working_copy_change` at session start/end as a **pointer to the shared working copy**, not
  as proof of ownership.
- Record explicit change IDs when the session creates or splits commits.
- Optional VCS-native alternative: a `Session-Id:` and `Harness:` trailer in commit descriptions,
  scanned by `kdn-journal changes --session <id>`. This is opt-in because it publishes session IDs
  and can be lost or duplicated by split/squash.
- Never claim that a change ID uniquely belongs to one session when `@` is shared.
- Degrade gracefully when jj is absent or the repo is not a jj repo.

### 4. Atuin Threads integration

- Match a journal session to an Atuin thread by the agent's native session ID (preferred), then by
  harness + cwd + start-time window as a fallback.
- Store the Atuin UUID in `session.json` once matched.
- Add `kdn-journal session atuin [--session <id>]` and `kdn-journal atuin list|show|search` that
  shell out to `atuin threads list|show|search --style json` and merge the result with the local
  session model.
- `kdn-journal summary --atuin` adds one line per session: Atuin thread UUID, harness, message count,
  last active.
- The TUI session detail shows the Atuin thread ID and a message/tool-call count; a key opens
  `atuin threads show --style pretty` in the pager.
- If Atuin is absent, capture is off, or the daemon is down, the command reports a warning and the
  journal still works.
- Atuin's `ATUIN_HISTORY_AUTHOR`, `ATUIN_HISTORY_AUTHOR_KIND` and `ATUIN_HISTORY_INTENT` can mark
  agent-run shell commands; `$all-agent` filters them. Treat shell history as secondary evidence,
  because Threads already captures tool calls.

### 5. Commands

```
kdn-journal session init [--task <dir|slug>] [--json]
kdn-journal session record-change <change-id> [--json]
kdn-journal session record-commit <commit-id> [--json]
kdn-journal session changes [--session <id>] [--json]
kdn-journal session atuin [--session <id>] [--json]
kdn-journal atuin list|show|search [--json]
kdn-journal summary --atuin
kdn-journal tui   # session detail shows the Atuin link
```

## Non-goals

- Replacing Atuin Threads or duplicating its transcript store.
- Requiring Atuin or jj; both integrations are optional and degrade.
- Automatically publishing session IDs in commits by default.
- Parsing harness transcripts directly.
- Merging or resuming sessions; `atuin resume` owns that.

## Acceptance

- `kdn-journal summary` auto-selects the current session for opencode, pi, Claude Code and Codex
  when the matching env var is present; `--session` still wins.
- `session init` writes a valid sidecar; `session changes` resolves a recorded change through jj and
  prints its description and files.
- A fixture proves the shared-`@` caveat is labelled, not hidden.
- A fixture with `atuin threads list --style json` output maps a session by native ID and by the
  cwd/time fallback; missing Atuin or capture-off produces a warning, not an error.
- `summary --atuin` and the TUI session detail show the Atuin UUID and message count.
- No sidecar or session ID is committed by default.
- Tests cover env detection, sidecar round-trip, jj template parsing with a fake runner, Atuin JSON
  parsing with a fake runner, and the no-tool fallbacks.
- `go test ./...`, `nix build .#kdn-journal`, and the package check pass.

## Open questions

1. Is the sidecar enough, or should the repo also standardize a `Session-Id:` commit trailer?
2. Should `session init` be called by the agent rule automatically, or only by the CLI/TUI?
3. How should two sessions in the same cwd be disambiguated when Atuin has no native-ID match?
4. Does Atuin's thread JSON expose the agent session ID under a stable key across versions?
5. Should the TUI show the transcript summary inline or only launch `atuin threads show`?
6. Do we want an `atuin mcp` bridge in the agent rule, or leave MCP to the agent's own config?
