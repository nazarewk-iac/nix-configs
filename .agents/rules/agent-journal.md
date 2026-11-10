---
type: Rule
description: "Every agent run keeps a session worklog and board, plus a task pair when a task exists: where the files live, how a parallel track appends safely, and how to turn the journals off."
timestamp: 2026-11-10T05:05:00+01:00
---

# Worklog and board

Every agent run in every harness keeps a **worklog** (append-only, dated) and a **board** (current
state). They are how the next harness, or the next session of the same harness, catches up without
replaying a transcript.

## Two levels, kept together

| Level   | Files                                                         | Purpose                                                             |
| ------- | ------------------------------------------------------------- | ------------------------------------------------------------------- |
| Session | `<repo>/.cache/agents/<harness>-<session>/{worklog,board}.md` | This run: what it did, the parallel tracks, the next action.        |
| Task    | `<task-dir>/.{worklog,board}.md`                              | Durable history of the task, readable by whoever picks it up later. |

- **Always keep the session pair.** It exists even when the run touches several tasks or none.
- **Also keep the task pair** when the run works in a task directory under `docs/tasks/`. Write the
  task-level entry for task progress; keep run-level detail (tracks, retries, dead ends) in the
  session pair.

`<harness>` is the tool that runs the agent, for example `opencode`, `claude`, `pi` or `codex`.
`<session>` is the harness session id when the harness has one, else `<YYYYMMDD-HHMMSS>`. Example:

```
.cache/agents/opencode-ses_e3c837bf2ffeKUFIukMf5s2OB2/worklog.md
.cache/agents/opencode-ses_e3c837bf2ffeKUFIukMf5s2OB2/board.md
```

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
