---
type: Design
description: Local session sidecar plus optional jj trailers and Atuin Threads JSON, with harness env detection and graceful fallbacks.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T08:30:00+01:00
---

# Design: journal session identity

## 1. Decisions

| Question          | Decision                                                                     | Reason                                                                                              |
| ----------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Source of truth   | `.cache/agents/<session>/session.json`, local and git-ignored                | Private, easy to write, survives a checkout, no public session IDs.                                 |
| jj mapping        | Record change IDs in the sidecar; optional `Session-Id:` commit trailer      | Sidecar is private and works with shared `@`; the trailer is opt-in for durable public correlation. |
| `@` change ID     | Record as `working_copy_change`; label it "shared working copy"              | Parallel sessions share `@`; it is a pointer, not ownership.                                        |
| Atuin             | Shell out to `atuin threads ... --style json`; store the UUID in the sidecar | No new dependency, no direct DB coupling, uses Atuin's public CLI.                                  |
| Harness detection | Env-var table, explicit `--session` wins, newest session fallback            | Makes `summary` work for every supported harness.                                                   |
| Missing jj/Atuin  | Warning in `issues`, exit 0 for reads                                        | Integrations are optional; the journal must still work.                                             |
| Transcripts       | Link to Atuin, do not copy them                                              | Atuin already stores, encrypts and syncs them.                                                      |

## 2. Sidecar

Path: `.cache/agents/<harness>-<date>-<session>/session.json`.

```json
{
  "schema_version": 1,
  "harness": "opencode",
  "session_id": "ses_e1f8bbd08ffep6essAsRoa3wna",
  "started_at": "2026-11-16T08:30:00+01:00",
  "updated_at": "2026-11-16T10:00:00+01:00",
  "cwd": "/home/kdn/dev/github.com/nazarewk-iac/nix-configs",
  "task": "docs/tasks/2026-11/agent-journal-summary",
  "jj": {
    "working_copy_change": "yoorvlzmnpxs",
    "change_ids": ["yoorvlzmnpxs"],
    "commits": ["c8090f46"]
  },
  "atuin": {
    "thread_id": "019a...",
    "agent_session_id": "ses_e1f8bbd08ffep6essAsRoa3wna"
  }
}
```

Rules:

- Write atomically (temp file + rename), like `task set-status`.
- Never commit the file; `.cache/` is already git-ignored.
- A missing or corrupt sidecar is a warning, not an error; the session directory still works.
- Unknown keys are preserved when the CLI rewrites the file.
- `schema_version` gates a future migration.

## 3. Harness detection

```go
type HarnessSession struct {
    Harness string
    ID      string
    Source  string // env variable or "newest"
}

func DetectHarnessSession() (HarnessSession, bool)
```

Order:

1. `OPENCODE_SESSION_ID` -> `opencode`
2. `PI_SESSION_ID` -> `pi`
3. `CLAUDE_CODE_SESSION_ID` -> `claude`
4. `CODEX_THREAD_ID`, then `CODEX_SESSION_ID` -> `codex`
5. `CURSOR_CONVERSATION_ID` -> `cursor`
6. `GEMINI_SESSION_ID` -> `gemini`
7. `COPILOT_SESSION_ID` -> `copilot`
8. `AGENT_SESSION_ID` -> `agent`

`kdn-journal summary` uses the detected pair when it matches a session directory, otherwise the
newest session. `--session` always wins. The directory prefix is normalized: `claude-code` ->
`claude`, `opencode` -> `opencode`, and an unknown harness keeps its own name.

## 4. jj integration

### 4.1 Runner

```go
type JJRunner interface {
    ChangeID(ctx context.Context, rev string) (string, error)
    Change(ctx context.Context, rev string) (Change, error)
    LogSession(ctx context.Context, sessionID string) ([]Change, error)
}

type Change struct {
    ChangeID    string
    CommitID    string
    Description string
    Author      string
    Timestamp   time.Time
    Files       []string
}
```

The real runner shells out to `jj` with `--no-pager` and a template; tests inject a fake. If `jj`
is absent, `exec.LookPath` fails and the integration reports `jj-unavailable`.

### 4.2 Recording

- `session init`: read `jj log -r @ -T 'change_id.short()'` and store it as
  `working_copy_change`; do not claim ownership.
- `session record-change <id>`: append to `jj.change_ids`, deduplicated.
- `session record-commit <id>`: append to `jj.commits`.
- `session changes`: resolve every recorded ID with `jj log -r <id> -T ...`; print change ID,
  commit ID, description, author, timestamp and changed files. A missing ID is a warning.

### 4.3 Commit attribution

Commit trailers are owned by the separate **`jj-meta`** tool (see
[docs/tasks/2026-11/jj-meta](../jj-meta/design.md)):

- `jj-meta` owns the profile set (`portable`, `github`, `asf`, `full`), the mutable-only check, the
  deduplication and the `Assisted-by`/`Co-authored-by`/`Generated-by` policy.
- `kdn-journal` records the sidecar mapping and calls
  `jj-meta attribute <change-id> --session <id> --harness <harness> --model <model>` when a change
  is recorded. It never edits a commit description itself.
- `kdn-journal changes` reads `jj-meta show --json` when it needs to display attribution.
- If `jj-meta` is absent, the sidecar still records the mapping and the journal reports a warning.

This keeps the trailer policy in one place and lets `kdn-journal` work without jj or Atuin.

## 5. Atuin integration

### 5.1 Runner

```go
type AtuinRunner interface {
    List(ctx context.Context) ([]Thread, error)
    Show(ctx context.Context, id string) (Thread, error)
    Search(ctx context.Context, query string, harness string, limit int) ([]Thread, error)
}

type Thread struct {
    AtuinID        string
    Harness        string
    AgentSessionID string
    Cwd            string
    Title          string
    StartedAt      time.Time
    UpdatedAt      time.Time
    MessageCount   int
    ToolCalls      int
}
```

The real runner executes:

```
atuin threads list --style json
atuin threads show <id> --style json
atuin threads search <query> --harness <name> --limit <n> --style json
```

and decodes the JSON. `list --style json` is an array of objects with `atuin_id`, `harness`,
`session_id`, `cwd`, `model`, `started_at`, `updated_at`, `message_count`, `title`, `preview`,
`last_reply`, `children_atuin_ids` and token counts. The adapter pins those names and covers them
with a fixture; a future Atuin schema change is isolated there.

The repo config sets `[threads] capture = true` in both Atuin modules. The daemon is already
enabled. Existing sessions are imported once with `atuin threads import`; on `oams` this imported
766 threads (2026-11-16), including the current session. Capture then records new sessions as the
agents run.

If Atuin is absent, the daemon is down, or capture is off (`atuin threads list` returns `[]` with a
warning), the integration reports `atuin-unavailable` or `atuin-empty` and continues.

### 5.2 Matching

1. Exact `agent_session_id` match, if Atuin exposes it.
2. Same harness and cwd, within a configurable window around `started_at` (default 10 minutes).
3. If several candidates remain, leave the link empty and report `atuin-ambiguous`.
4. Once matched, write `atuin.thread_id` to the sidecar.

### 5.3 Commands

- `kdn-journal atuin list [--harness] [--json]`: list threads.
- `kdn-journal atuin show <id> [--json]`: show one thread; `--pretty` shells out to Atuin's own
  renderer.
- `kdn-journal atuin search <query> [--harness] [--json]`.
- `kdn-journal session atuin [--session] [--json]`: the thread for one journal session.
- `kdn-journal summary --atuin`: add one line per session with Atuin UUID, message count and last
  active.
- TUI session detail: `Atuin  <uuid> · N messages · last active ...`; a key opens
  `atuin threads show --style pretty` in the pager.

Atuin's `atuin mcp` remains the agent-facing transcript tool; `kdn-journal` links to it rather than
duplicating it.

## 6. Shell history (secondary)

Atuin history records commands with `ATUIN_HISTORY_AUTHOR`, `ATUIN_HISTORY_AUTHOR_KIND` and
`ATUIN_HISTORY_INTENT`; `$all-agent` filters agent-run commands. The journal can show a
`session history` view later, but Threads already captures the agent tool calls, so shell history is
not part of v1.

## 7. CLI and JSON

New commands are additive; existing commands keep their flags and envelope. New `--json` payloads:

```json
{
  "schema_version": 1,
  "command": "session changes",
  "root": "/repo",
  "generated_at": "...",
  "data": {
    "session": "opencode-20261116-ses_...",
    "working_copy_change": "yoorvlzmnpxs",
    "changes": [{ "change_id": "...", "commit_id": "...", "description": "...", "files": ["..."] }],
    "atuin": { "thread_id": "...", "messages": 42 }
  },
  "issues": []
}
```

`issues` carries `jj-unavailable`, `atuin-unavailable`, `atuin-empty`, `atuin-ambiguous`,
`sidecar-corrupt`, `change-missing` as warnings. A corrupt sidecar never fails a read.

## 8. TUI

The session list already has `bubbles/list` and the detail uses `glamour`. Add:

- A sidecar line in the session detail: harness, native ID, task, jj working-copy change.
- An Atuin line when linked: UUID, message count, last active.
- `c` opens the jj changes view (a Markdown list in the viewport).
- `a` opens the Atuin thread summary in the viewport; `A` shells out to
  `atuin threads show --style pretty` in `$PAGER`.
- Missing integrations show a one-line hint, not an error.

No new UI component is needed; this is more content in the existing viewport.

## 9. Privacy and safety

- The sidecar is local-only and git-ignored. Session IDs are not committed by default.
- The optional commit trailer is explicit; `kdn-journal` never adds it automatically.
- Atuin data stays in Atuin's encrypted store; the journal stores only the thread UUID and counts.
- Do not read Atuin's SQLite database directly; use the CLI.
- Do not run `atuin resume` from the TUI; resuming changes the running agent session.
- All new writes are atomic and refuse a symlink target.

## 10. Tests

- Harness detection: every env var, precedence, unknown harness, explicit `--session`.
- Sidecar: round-trip, unknown keys preserved, corrupt file, atomic write, symlink refusal.
- jj fake: `@` change, recorded change, missing change, trailer scan, `jj` unavailable.
- Atuin fake: list/show/search JSON, native-ID match, cwd/time fallback, ambiguous, capture off,
  missing binary.
- Summary: `--atuin` line, missing integration warning.
- TUI: session detail contains sidecar/Atuin lines; `c`/`a` views; no-op when absent.
- Integration: real repo without jj/Atuin (skip gracefully), then with fakes.

## 11. Migration

- Existing session directories without `session.json` keep working; the sidecar is optional.
- `kdn-journal summary` gains harness detection; the previous OpenCode fallback is a subset.
- No existing JSON field is renamed; new fields are additive.
- The journal rule gets a short "record the session identity" step; the CLI command is optional.
- A later task can add the commit trailer and Atuin MCP guidance if the sidecar proves insufficient.

## 12. Open questions

1. Does Atuin's thread JSON expose the agent session ID under a stable key in 18.24.x and later?
2. Should `session init` be mandatory in the journal rule, or only recommended?
3. Should the sidecar be synced across machines, or is Atuin's UUID enough?
4. Is a commit trailer worth the public session ID, or should the sidecar stay the only mapping?
5. Should the TUI show a compact transcript preview, or only link to Atuin?
