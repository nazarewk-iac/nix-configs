---
type: Task
description: Give agent journals a predictable shape and a Go CLI plus TUI that prints where the work stands and browses repository tasks, session journals and task boards.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-11-12T00:00:00+01:00
---

# Agent journal CLI: structured boards and a one-command status

> ✅ **Done** — see the solution in [done.md](done.md).

> Owner decision 2026-11-15: implement this as a Go CLI (with a TUI) under `packages/`, not as
> `hack/board-summary.py`. The Python proposal below is kept only as history; the design document
> and the acceptance criteria are the current contract.

## Context

[Worklog and Board](../../../.agents/rules/agent-journal.md) requires every run to keep a session
pair (`.cache/agents/<harness>-<date>-<session>/{worklog,board}.md`) and, when a run works in a
task, a task pair (`<task-dir>/.{worklog,board}.md`). A long run also grows **sub-boards**, one
per parallel track (`board-<track>.md` in the session directory).

Both files are free-form Markdown. Catching up today means opening the session board, then every
sub-board, then the task board, then the tail of the worklog, and reconstructing the state by hand.
The content is fine; the shape is not. Nothing tells the reader which section is current, and
nothing lets a script answer "what is in progress, what is blocked, what is next".

This session is the example: `.cache/agents/opencode-20261110-…/` holds `board.md` plus seven
`board-*.md` files, and a new `board-ssh-ca.md` was added for one plan.

## Goal

One command prints where the work stands:

- the session (harness, date, id) and when it was last touched;
- **Now**, **Next**, **Blocked** items for the session and for each track;
- one line per sub-board, taken from its own summary section;
- the last few worklog entries, by heading only;
- optionally a task directory (`--task docs/tasks/…`), which adds that task's pair.

A second surface browses the same data interactively: repository tasks, their definitions, boards
and worklogs, and every session journal.

Target: one screen, under a second, no manual opening of files.

## Proposal

### 1. A predictable board shape, in OKF

Follow [Open Knowledge Format v0.2](https://github.com/GoogleCloudPlatform/open-knowledge-format):
Markdown with YAML frontmatter, `type` required, unknown keys allowed. A board is one concept file
in the session bundle, not a private format:

```markdown
---
type: Board
title: SSH CA follow-up
description: Where the host-key work stands.
updated: 2026-11-12T17:23:00+01:00
status: active # active | blocked | done (an extension key, OKF allows it)
tags: [session, ssh-ca]
---

## Status

- [x] done item
- [ ] open item

## Next

- item

## Blocked

- item — what it waits for

## Notes

free prose
```

Parsing uses **headings**, not new keywords: the CLI reads `## Status` / `## Now` / `## Next` /
`## Blocked` / `## Done` and treats `- [ ]` / `- [x]` as item markers. Everything else is prose.
OKF's conventional headings are a superset of this, so a future consumer can read the bundle
without our tool.

A board without the skeleton must still parse: its date-headed sections and `item | state` tables
become items, and a board with no recognized section still reports counts instead of failing. The
session directory can carry an OKF `index.md` listing its boards; the CLI accepts one but does not
require it.

### 2. The CLI

`packages/kdn-journal`, binary `kdn-journal`:

- `summary`: the newest session (or `$OPENCODE_SESSION_ID` when it names one), or `--session`;
- `summary --track <name>`: one sub-board in full;
- `summary --task <dir|slug>`: add a task pair;
- `summary --all`: every session, newest first;
- `sessions`: list sessions with board counts and last activity;
- `tasks`: list repository tasks with status, activity and open items;
- `task <dir|slug>`: one task, its files, board, worklog and sub-tasks;
- `task set-status <dir|slug> <open|in-progress|done>`: update the frontmatter status safely;
- `board <path>` / `worklog <path>`: parse one file or a directory's pair;
- `doctor`: validate the task tree and journals, exit non-zero on errors;
- `tui`: a bubbletea browser over the same models;
- every read command accepts `--json`.

The output is compact by default (three items per section, five worklog headings, a 24-line cap,
the requested `--width`) and `--full` removes the limits.

### 3. Why Go

The owner prefers a compiled CLI under `packages/`. The repo already builds Go packages with
`buildGoModule` (`kdn-certs`, `kdn-ssh-access`, `kdnctl`) and uses cobra plus the charmbracelet
stack. A Go binary gives one artifact, a real TUI, JSON output, and a test suite that runs without
Python or a devenv shell.

## Decisions (answers to the earlier open questions)

1. The skeleton is **recommended** in `.agents/rules/agent-journal.md`, not required. Existing
   free-form boards must keep parsing; the CLI degrades instead of failing.
2. Frontmatter is **optional**. The `updated` key falls back to `timestamp`, then to the file
   mtime; the first H1 is the fallback for `title`.
3. Task `.board.md` files use the **same** skeleton and parser. The CLI shows the task pair when
   `--task` is given, and follows sub-task directories for the task browser.
4. The summary runs from the owner's shell and from the devenv shell; the package is exposed in
   `devenv.nix`. No `kdnctl` subcommand.
5. `--json` is part of the first version. The TUI consumes the same Go models, not the JSON.

## Acceptance

- `kdn-journal summary` prints the current session in one screen, and every existing free-form
  board in this repo parses without an error (degraded output is fine).
- `kdn-journal summary --task docs/tasks/2026-11/agent-journal-summary` also shows that task's
  state.
- The output fits 24 lines for the eight-board session that motivated the task, and every line
  fits the requested width.
- The test suite has one structured and one unstructured board, and covers the summary line count.
- `kdn-journal tasks`, `kdn-journal task <slug>`, `kdn-journal sessions`, `kdn-journal doctor` and
  `kdn-journal tui` work against this repository.
- `nix build .#kdn-journal` succeeds, and `go test ./...` passes inside and outside the Nix build.

## Out of scope

- Changing where the journals live or what they contain.
- Parsing the transcript.
- A web UI.
- Automatically editing a board from the TUI; the TUI opens the file in `$EDITOR` instead.
