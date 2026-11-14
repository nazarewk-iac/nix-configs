---
type: Research
description: Harness session environment variables, jj change-ID semantics, and the Atuin Threads capture/search/resume surface that a journal session identity can use.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T08:30:00+01:00
---

# Research: session identity, jj changes and Atuin Threads

## 1. Harness session environment

The shell tool of each harness exposes a different session identifier. The table below is the
support matrix to implement; verify the variable names against the installed harness version.

| Harness     | Session variable                   | Other markers                                | Notes                                                                        |
| ----------- | ---------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------------- |
| opencode    | `OPENCODE_SESSION_ID`              | `OPENCODE=1`, `AGENT=1`, `AI_AGENT=opencode` | v2 shell tool sets the session ID; v1 used `OPENCODE_RUN_ID` in some builds. |
| pi          | `PI_SESSION_ID`, `PI_SESSION_FILE` | `PI_CODING_AGENT=true`, `AI_AGENT=pi`        | Pi injects these into commands its `bash`/`powershell` tools run.            |
| Claude Code | `CLAUDE_CODE_SESSION_ID`           | `CLAUDECODE=1`, `AI_AGENT=claude-code_*`     | `CLAUDE_CODE_SESSION_ID` is present in tool commands and hooks.              |
| Codex       | `CODEX_THREAD_ID`                  | `CODEX_CI=1`, `CODEX_SESSION_ID` fallback    | `CODEX_THREAD_ID` is the resumable thread id.                                |
| Cursor      | `CURSOR_CONVERSATION_ID`           | `CURSOR_AGENT=1`                             | Not an Atuin Threads harness.                                                |
| Gemini CLI  | `GEMINI_SESSION_ID`                | —                                            | Not an Atuin Threads harness.                                                |
| Copilot     | `COPILOT_SESSION_ID`               | —                                            | Atuin Threads supports Copilot.                                              |
| generic     | `AGENT_SESSION_ID`                 | —                                            | Lowest-priority fallback.                                                    |

`kdn-journal` currently checks only `OPENCODE_SESSION_ID`; the directory convention itself accepts
any `[a-z0-9]+` harness name.

## 2. Jujutsu change IDs

- A jj **change ID** identifies a mutable change; a **commit ID** identifies one snapshot. The
  change ID survives rewrites, the commit ID does not.
- In this repository, parallel agent sessions share the same working-copy commit `@`. A change ID
  recorded at session start is a pointer to the shared working copy, not proof that one session owns
  the change.
- A session that creates commits can record each change ID. A commit can be split, squashed or
  rewritten; the change ID of the new commit may differ.
- A `Session-Id:` trailer in the commit description travels with the commit and can be scanned with
  `jj log`, but it publishes the session ID and can be lost or duplicated by a split/squash. A
  local sidecar is private and easier to maintain.
- `jj log -r @ -T 'change_id.short()'` gives the current working-copy change; `jj log -r <id> -T
'...'` resolves a recorded change.

## 3. Atuin Threads

Atuin 18.24+ captures AI coding-agent sessions as **threads**. The installed version is 18.24.5.

- Enable: `atuin threads enable` (or `atuin config enable threads`).
- Import: `atuin threads import [--harness <name>]`.
- List/show/search: `atuin threads list|show|search --style json|ndjson|plain|pretty`.
- Resume: `atuin resume` or `atuin threads resume`; `atuin resume <id> --in <harness>`.
- MCP: `atuin mcp` exposes thread search/read to agents.
- Supported harnesses: Claude Code, Codex, Copilot, Grok, Kiro, opencode, Pi, Omp, Amp.
- Each thread has a stable Atuin UUIDv7, the same on every machine, plus the agent's own session ID.
- Capture keeps the conversation and tool calls (input/output, file reads/writes, edit diffs),
  with secrets redacted and per-call output clipped to 64 KiB. Search covers conversation, tool
  input and changed file names; output is not searchable.
- `atuin threads show` accepts an Atuin id, a unique harness-id prefix, or `latest`.
- Atuin history also records `ATUIN_HISTORY_AUTHOR`, `ATUIN_HISTORY_AUTHOR_KIND` (`user`/`agent`)
  and `ATUIN_HISTORY_INTENT`; `$all-agent`/`$all-user` are search filters. This is the shell-history
  channel, secondary to Threads for agent tool calls.

## 4. Matching a journal session to an Atuin thread

1. **Native ID** (best): the journal session id equals the Atuin thread's agent session id.
2. **Harness + cwd + start time**: when the native ID is missing, match the same harness and cwd
   within a small window around the session start.
3. **Atuin UUID**: once matched, store it in the sidecar so later lookups do not need heuristics.
4. **No match**: leave `atuin` empty and report a warning; never fail the journal.

## 5. Commit trailers and transparency

The Nixpkgs automation/AI policy requires an `Assisted-by:` Git commit trailer for LLM-assisted
contributions. The trailer must name at least the tool and the primary model name and version.
`Co-authored-by:` explicitly does **not** satisfy the policy; it is optional attribution, not the
disclosure. Source:
<https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md#transparency>.

Git trailers are the last `Key: value` lines of a commit message. Jujutsu stores the commit
description as the message, so trailers work with `jj describe -m` and `jj commit -m`. A practical
shape:

```
feat(journal): add the session sidecar

Assisted-by: opencode (DeepSeek V4.1 Flash 1017)
Co-authored-by: Krzysztof Nazarewski <gpg@kdn.im>
Session-Id: ses_e1f8bbd08ffep6essAsRoa3wna
```

`Session-Id:` is a local extension, not a Nixpkgs requirement. It publishes the session ID, so make
it opt-in or keep it in the local sidecar instead.

Jujutsu has no arbitrary per-change metadata key/value store. `jj metaedit` can change the
description, author, committer, timestamps and change ID, but not a custom field. The operation log
has operation descriptions and user/host/timestamp metadata, but no public command to attach a
session ID to a specific change, and operations are repo-global rather than per-change. A commit
trailer is the supported, portable channel today. Enforcement is also not native: jj has no
commit-msg hook, so a helper command or a CI/doctor gate must add or check the trailer.

## 6. Lessons from `kdn-journal`

- The directory convention is already harness-agnostic; only the env detection is narrow.
- The session pair is local and git-ignored; a `session.json` sidecar fits the same lifecycle.
- `task set-status` shows the safe-write pattern: temp file, rename, preserve everything else.
- `doctor --parse-only` is the model for an optional integration: a clean local path that does not
  require jj or Atuin.
- The TUI already uses `bubbles/list`, `bubbles/viewport`, `glamour` and `lipgloss`; adding an
  Atuin line to the session detail does not need a new UI component.

## 7. Sources

- Pi environment variables: <https://pi.dev/docs/latest/environment-variables>
- Harness environment detection (Codex, Claude Code, Cursor, OpenCode, Pi):
  <https://harnessnotes.com/environment-detection>
- Atuin Threads: <https://docs.atuin.sh/main/ai/threads/>
- Atuin agent sessions (older name): <https://docs.atuin.sh/main/ai/sessions/>
- Atuin shell integration and author/intent variables:
  <https://docs.atuin.sh/main/guide/shell-integration/>
- Atuin Threads announcement:
  <https://blog.atuin.sh/threads-agent-sessions/>
- jj change IDs and working copy:
  <https://jj-vcs.github.io/jj/latest/working-copy/>
- This repository's jj rules: [../../.agents/rules/jujutsu-vcs.md](../../../.agents/rules/jujutsu-vcs.md)
