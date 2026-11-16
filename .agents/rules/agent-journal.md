---
type: Rule
description: "Every agent run keeps a session worklog and board, plus a task pair when a task exists: where the files live, how a parallel track appends safely, and how to turn the journals off."
timestamp: 2026-11-15T19:48:57+01:00
---

# Worklog and board

Every agent run in every harness keeps a **worklog** (append-only, dated) and a **board** (current
state). They are how the next harness, or the next session of the same harness, catches up without
replaying a transcript.

## Two levels, kept together

| Level   | Files                                                                | Purpose                                                             |
| ------- | -------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Session | `<repo>/.cache/agents/<harness>-<date>-<session>/{worklog,board}.md` | This run: what it did, the parallel tracks, the next action.        |
| Task    | `<task-dir>/.{worklog,board}.md`                                     | Durable history of the task, readable by whoever picks it up later. |

- **Always keep the session pair.** It exists even when the run touches several tasks or none.
- **Also keep the task pair** when the run works in a task directory under `docs/tasks/`. Write the
  task-level entry for task progress; keep run-level detail (tracks, retries, dead ends) in the
  session pair.

A session directory name has three parts, in this order:

- `<harness>` — the tool that runs the agent: `opencode`, `pi`, `claude`, `codex`.
- `<date>` — the run's start date, `YYYYMMDD`, no dashes. It makes the directory sort chronologically
  and tells you when the run happened without opening a file.
- `<session>` — the harness session id. **Always present, never a timestamp.**

```
.cache/agents/opencode-20261110-ses_e3c837bf2ffeKUFIukMf5s2OB2/worklog.md
.cache/agents/pi-20261110-01a193a9/worklog.md
```

Never substitute a timestamp for the session id: a run whose directory has no id cannot be resumed,
cannot be cross-referenced against the harness's own session store, and cannot be told apart from a
sibling run that started the same minute. When a harness exposes no id at all, mint one
(`local-<YYYYMMDD-HHMMSS>`) and reuse it for the whole run.

How to get the id:

| harness    | id                                                                                   |
| ---------- | ------------------------------------------------------------------------------------ |
| `opencode` | `$OPENCODE_SESSION_ID` (`ses_…`)                                                     |
| `pi`       | the UUID in the filename of the newest `~/.pi/agent/sessions/--<cwd-slug>--/*.jsonl` |

`kdn-journal session init` detects these and the rest of the harness matrix
(`CLAUDE_CODE_SESSION_ID`, `CODEX_THREAD_ID`, `CURSOR_CONVERSATION_ID`, `GEMINI_SESSION_ID`,
`COPILOT_SESSION_ID`, `AGENT_SESSION_ID`) and names the directory for you.

Write the directory **once**, at the start of the run, and keep using it. A second run of the same
session (a resume the next day) gets a new directory with the new date and the same session id.

Both locations are git-ignored: `.*.md` covers a file inside a task directory, and `/.cache/`
covers the session directory. Never add these files to a commit, and never move them into a
tracked path.

## Turning the journals off

The user can turn both journals off for a session. **A direct instruction in the session wins**:
"no worklog", "skip the board", "do not journal this" means write neither file for the rest of the
run. Say once that the journals are off, then stop mentioning it.

`KDN_AGENT_WORKLOG=skip` is the scriptable fallback for the same request. Use it when the user
cannot type the instruction, or when a wrapper must force it. Use neither switch for multi-step
work, for a fix that spans files, or for anything another agent may have to resume.

## One file per track

A run that splits into parallel tracks gives each track its own board at the session level:

```
worklog.md            shared, append-only
board.md              the run-level board
board-<track>.md      one board per track; that track owns it
worklog-<track>.md    optional: only when a track must keep its own log
```

A track edits only its own board. A track appends to the shared worklog and never edits it. This
keeps two agents from writing one file at the same time.

## Append-safe worklog

The worklog is append-only: one entry per event, one small append per entry.

```sh
cat > /tmp/agent-entry.md <<'EOF'
## 2026-11-10T04:56:00Z — opencode — session-id plugin verified
What changed, what proved it, and what is still open. One to five lines.
EOF
cat /tmp/agent-entry.md >> <dir>/worklog.md
rm /tmp/agent-entry.md
```

A single `cat ... >> file` is one append, and that order is safe for a small entry. Add `flock`
when the host has it, and fall back to the plain append when it does not:

```sh
if command -v flock >/dev/null 2>&1; then
  flock <dir>/.worklog.lock -c "cat /tmp/agent-entry.md >> <dir>/worklog.md"
else
  cat /tmp/agent-entry.md >> <dir>/worklog.md
fi
```

`flock` is util-linux; Linux hosts have it, macOS does not. Never require it. Write the entry to a
temporary file first: `flock -c` runs the string through `$SHELL`, and a heredoc inside it fails
under a non-POSIX shell such as fish.

Do not use an editor, `sed` or a rewrite on a shared worklog, and do not touch another track's
entries.

## What a board holds

- the problem in one or two lines;
- one row per open item with its state;
- the next action;
- the exact verification commands;
- the files in play.

Overwrite the board freely. It is a snapshot of the current state, not a history. The worklog is
the history.

Keep the tables readable in a terminal: run `hack/fmt-agent-docs.sh` after an edit. It formats every
file under `.cache/agents/` (a tree-wide `nix fmt` skips that git-ignored directory) and pads the
table cells so the pipes line up.

## Board shape

A board is an OKF file: Markdown with YAML frontmatter. This shape gives a reader the state without
a second look:

```markdown
---
type: Board
title: SSH CA follow-up
description: Where the host-key work stands.
updated: 2026-11-12T17:23:00+01:00
status: active # active | blocked | done
tags: [session, ssh-ca]
---

## Status

- [x] done item
- [ ] open item

## Next

- item

## Blocked

- item — what it waits for

## Done

- item
```

Frontmatter keys: `type: Board`, `title`, `description`, `updated`, `status`, `tags`. Headings:
`## Status`, `## Next`, `## Blocked`, `## Done`. Put free prose under `## Notes`.

The shape is **recommended, not required**. A free-form board keeps parsing: a date-headed section
and an `item | state` table also read as items, and a board with no known section still parses with
counts. Frontmatter is optional too; the file mtime stands in for `updated`, and the first H1 stands
in for `title`.

## Catch up with kdn-journal

`kdn-journal` reads these files and prints the state. Its only writes are the session sidecar
(`session.json`, next to the board) and `task set-status`.

```sh
kdn-journal summary --session "$OPENCODE_SESSION_ID" --json
kdn-journal summary --task <task-dir> --json
kdn-journal doctor --parse-only --json
```

**Record the session identity once, then every change you commit.**

```sh
kdn-journal session init --task <task-dir> --json
kdn-journal session record-change <change-id> --json
```

`session init` detects the harness and session from the environment and reuses the existing session
directory. `session record-change` stores the jj mapping in the sidecar and calls `kdn-jj-meta`, so the
change also gets its `Assisted-by` trailers. See [kdn-jj-meta.md](kdn-jj-meta.md). `session atuin` links the
Atuin Thread when the harness is captured; it is optional. `session backfill` attributes an existing
history from the sidecars and the Atuin intervals; run it once per repository, not per session.

Agents should use the JSON or JSONL path and never call `tui`. `--json` is the envelope with
`issues`; `--jsonl` is one object per line for `jq` and `fzf`. The machine-readable contract, the
JSON field table and the one safe write are in [kdn-journal.md](kdn-journal.md). The human command reference is
[docs/kdn-journal.md](../../docs/kdn-journal.md).
