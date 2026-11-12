---
type: Task
description: Give agent journals a predictable shape and a script that prints where the work stands, so the owner reads one screen instead of four files.
status: open
authored_by: agent
timestamp: 2026-11-12T00:00:00+01:00
---

# Board summary: structured boards and a one-command status

## Context

[Worklog and Board](../../../.agents/rules/agent-journal.md) requires every run to keep a session
pair (`.cache/agents/<harness>-<date>-<session>/{worklog,board}.md`) and, when a run works in a
task, a task pair (`<task-dir>/.{worklog,board}.md`). A long run also grows **sub-boards**, one
per parallel track (`board-<track>.md` in the session directory).

Both files are free-form Markdown. Catching up today means opening the session board, then every
sub-board, then the task board, then the tail of the worklog, and reconstructing the state by hand.
The content is fine; the shape is not. Nothing tells the reader which section is current, and
nothing lets a script answer "what is in progress, what is blocked, what is next".

This session is the example: `.cache/agents/opencode-20261110-…/` holds `board.md` plus six
`board-*.md` files, and a new `board-ssh-ca.md` was added for one plan.

## Goal

One command prints where the work stands:

- the session (harness, date, id) and when it was last touched;
- **Now**, **Next**, **Blocked** items for the session and for each track;
- one line per sub-board, taken from its own summary section;
- the last few worklog entries, by heading only;
- optionally a task directory (`--task docs/tasks/…`), which adds that task's pair.

Target: one screen, under a second, no manual opening of files.

## Proposal

### 1. A predictable board shape

Keep Markdown and keep it readable by a human without the script. Add a small fixed skeleton:

```markdown
---
board: ssh-ca            # the track, or "session" for the main board
updated: 2026-11-12T17:23:00+01:00
status: active           # active | blocked | done
---

## Now
- [ ] short item, one line, with the file or command it concerns

## Next
- [ ] item

## Blocked

- item — what it waits for

## Notes
free prose, ignored by the script
```

Rules: `## Now`, `## Next`, `## Blocked` are the machine-read sections; `- [ ]` / `- [x]` are the
item markers; the frontmatter carries the track, the timestamp and a coarse status. Everything
else stays prose. A board without the skeleton must still parse — fall back to "no structured
items", never to an error.

### 2. The script

`hack/board-summary.py` (the repo already keeps Python helpers in `hack/`, e.g.
`align-md-tables.py`, `eval-profile-rank.py`):

- default: the newest `.cache/agents/*/` directory, or `--session <dir|id>`;
- `--track <name>`: one sub-board;
- `--task <dir>`: add a task pair;
- `--all`: every session directory, newest first;
- output: a compact block per board, then the worklog headings.

A `kdnctl` subcommand is the alternative. Python is the smaller step: no Go build, and the file
format is a script concern, not a fleet concern.

## Open questions

1. Does the skeleton belong in the rule (`.agents/rules/agent-journal.md`) so every harness writes
   it, or in this task's own convention first?
2. Should the frontmatter be required, or optional with the mtime as a fallback?
3. Do task `.board.md` files get the same skeleton, and does the script follow `parent:` links?
4. Where does the summary run: the owner's shell, or also a `kdnctl`/devenv command?
5. Do we want a `--json` mode for a future TUI or web view, or is text enough?

## Acceptance

- `hack/board-summary.py` prints the current session in one screen, and every existing free-form
  board in this repo parses without an error (degraded output is fine).
- With `--task docs/tasks/2026-11/agent-journal-summary`, it also shows that task's state.
- The output fits 40 lines for a session with three tracks.
- The script has a test with one structured and one unstructured board.

## Out of scope

- Changing where the journals live or what they contain.
- Parsing the transcript.
- A UI beyond the terminal.
