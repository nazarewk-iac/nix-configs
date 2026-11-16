---
type: Reference
description: The kdn-journal Go CLI and TUI: how it reads repository tasks and session journals, its command surface, the board format it accepts, JSON output, exit codes and editor integration.
timestamp: 2026-11-15T19:48:57+01:00
---

# `kdn-journal`

`kdn-journal` reads the two journal trees of this repository and prints where the work stands. It
also validates the trees and browses them in a TUI. It is a Go binary under
[`packages/kdn-journal/`](../packages/kdn-journal/).

## Why

Every agent run keeps a session pair and, when it works in a task, a task pair. The full contract is
in [agent-journal.md](../.agents/rules/agent-journal.md), and the task layout is in
[tasks/README.md](tasks/README.md). A long run also grows one sub-board per parallel track.

The files are free-form Markdown. To catch up by hand you open the session board, then every
sub-board, then the task board, then the tail of the worklog, and rebuild the state in your head.
`kdn-journal` does that in one command: one screen, no manual opening of files.

The tool reads two trees:

| Tree               | Path                                            | Files                                                                                       |
| ------------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Repository tasks   | `docs/tasks/<YYYY-MM>/<slug>/`                  | `definition.md`, `design.md`, `status.md`, `done.md`, `.board.md`, `.worklog.md`, sub-tasks |
| Agent session logs | `.cache/agents/<harness>-<YYYYMMDD>-<session>/` | `board.md`, `board-<track>.md`, `worklog.md`, `worklog-<track>.md`, optional `index.md`     |

It never writes a journal. The only writes are `task set-status` (frontmatter), the session sidecar
(`session.json`, local and git-ignored), and the TUI hand-off to `$EDITOR`. It never parses a
harness transcript.

The parser is tolerant by design. Bad YAML frontmatter falls back to a line-based reader. A board
with no known section still parses and still reports counts. A missing frontmatter is not an error.
This keeps the existing free-form boards readable.

## Commands

```
kdn-journal summary [--session <dir|id|id@date>] [--task <dir|slug>] [--all]
                    [--track <name>] [--tail N] [--full]
kdn-journal sessions [--harness <name>] [--limit N] [--all] [--json]
kdn-journal tasks [--status <value>|all] [--month YYYY-MM] [--tree]
                  [--limit N] [--all] [--json]
kdn-journal task <dir|slug> [--json] [--print-path]
kdn-journal task set-status <dir|slug> <open|in-progress|done|not-scheduled|blocked>
kdn-journal board <path> [--track <name>] [--raw] [--json] [--print-path]
kdn-journal worklog <path> [--track <name>] [--tail N] [--raw] [--json] [--print-path]
kdn-journal doctor [--parse-only] [--ignore <code>] [--json]
kdn-journal session init [--task <dir|slug>]
kdn-journal session record-change <change-id>
kdn-journal session record-commit <commit-id>
kdn-journal session changes
kdn-journal session atuin
kdn-journal atuin list [--harness <name>]
kdn-journal atuin show <thread-id>
kdn-journal atuin search <query...> [--harness <name>] [--limit N]
kdn-journal tui
kdn-journal completion <shell>
kdn-journal version
```

Global flags: `--root <path>`, `--json`, `--no-color`, `--width <n>`.

`--root` defaults to a walk up from the current directory until it finds `docs/tasks`, or
`flake.nix` with `.jj` or `.git`. There is no `KDN_ROOT` environment variable.

Text is the default output. `--json` selects the envelope in [JSON envelope](#json-envelope). Text
lines truncate to the width (100 by default, set by `--width`) with a tail ellipsis.
Color is used only on a TTY, without `--no-color`, and with `NO_COLOR` unset.

### `summary`

Prints one session: the header, the main board, one line per track board, the last worklog
headings, and the task pair when `--task` is given.

- `--session <dir|id|id@date>` selects the session. Without it the tool uses
  `$OPENCODE_SESSION_ID` when a matching directory exists, then the newest session by last-touched
  time.
- A selector accepts a directory, a relative path, an exact id, an id prefix, or `id@YYYYMMDD`.
  When several runs share an id, the newest is used and the header says `1 of N runs`. A prefix
  that matches several distinct ids is ambiguous and exits 2.
- `--task <dir|slug>` adds that task's board and worklog.
- `--track <name>` prints that board in full.
- `--tail N` sets the worklog heading count.
- `--all` prints one compact line per session, newest first, limited to 20.
- `--full` removes the item and worklog limits.

Default limits: 3 items per section, 5 worklog headings, 24 lines for one session.

### `sessions`

Lists sessions, newest first. One line per session: date, harness, id, last touched, board count,
worklog count, task references.

- `--harness <name>` filters by harness.
- `--limit N` caps the list, and `--all` removes the cap.

### `tasks`

Lists repository tasks, newest activity first. The default limit is 20, and `--all` removes it.

- `--status <value>|all` filters by frontmatter status. Any value present in the tree is accepted;
  an unknown value is a usage error.
- `--month YYYY-MM` filters by month directory.
- `--tree` indents a sub-task under its parent with two spaces per depth.

Last activity comes from a task board frontmatter `updated`/`timestamp`, then the definition
`timestamp`, then the newest file mtime. This survives a checkout that resets every mtime.

### `task`

Shows one task: the definition, the files, the board sections, the worklog headings and the
sub-tasks.

`<dir|slug>` accepts an absolute path, a repo-relative path, a slug, or an unambiguous slug prefix.
An ambiguous selector prints every candidate. `--print-path` prints the resolved `definition.md` and
exits.

`task set-status <dir|slug> <value>` rewrites the `status:` line of `definition.md`. It writes
through a temporary file and a rename, so a reader sees either the old file or the new file. It
refuses `done` without an existing `done.md`, and it refuses `done` while a `status.md` remains.

### `board` and `worklog`

Print one board or worklog file. `<path>` accepts a file, a session directory, or a task directory.

A directory resolves in this order: an explicit file name, `board.md` (`worklog.md`), `.board.md`
(`.worklog.md`), then an error that lists the candidates. `--track <name>` picks
`board-<name>.md` or `worklog-<name>.md`. `--raw` prints the file unchanged. `--print-path` prints
the resolved file. `--tail N` limits the worklog headings.

### `doctor`

Validates the task tree and the journals. It is read-only.

- `--parse-only` checks only that every task definition, board and worklog parses. It is the gate
  for the Nix check and exits 0 on a clean tree.
- `--ignore <code>` suppresses one issue code.

`doctor` exits 1 when any error remains, and 0 otherwise. Warnings do not fail. Each issue prints
with a stable code, for example `status-missing` or `done-without-solution`.

### `tui`

A bubbletea browser over the same models. The list uses `bubbles/list` (filtering, pagination,
status bar), the detail uses `bubbles/viewport` and `glamour`, and the footer uses `bubbles/help`.
Two tabs: **Tasks** and **Sessions**.

| Key           | Action                                                  |
| ------------- | ------------------------------------------------------- |
| `j` / `k`     | Move the cursor.                                        |
| `enter`       | Open the detail view of the selected item.              |
| `esc`         | Return to the list.                                     |
| `tab`         | Switch tab.                                             |
| `1` / `2`     | Switch to Tasks or Sessions.                            |
| `/`           | Enter filter mode. `enter` applies, `esc` cancels.      |
| `e`           | Open the primary file in `$EDITOR` and refresh on exit. |
| `r`           | Reload from disk.                                       |
| `g` / `G`     | Jump to the first or last item or line.                 |
| `pgup`/`pgdn` | Scroll the detail view.                                 |
| `q`           | Quit.                                                   |

The TUI needs a TTY. A non-TTY invocation exits 2 with a clear error.

`e` opens the task `definition.md` or the session `board.md`. It is a no-op with a status-line
message when the file is absent.

### `session` and `atuin`

`session` writes the local sidecar that ties a harness session to jj changes and to an Atuin
Thread. The sidecar is `.cache/agents/<session>/session.json`, which is git-ignored. Nothing here
publishes a session ID, and nothing needs jj or Atuin to read a journal.

```
kdn-journal session init [--task <dir|slug>]
kdn-journal session record-change <change-id>
kdn-journal session record-commit <commit-id>
kdn-journal session changes
kdn-journal session atuin
kdn-journal atuin list|show|search
```

`--session`, `--harness` and `--model` override the environment on every `session` subcommand.
Detection reads the same table as `jj-meta`: `OPENCODE_SESSION_ID`, `PI_SESSION_ID`,
`CLAUDE_CODE_SESSION_ID`, `CODEX_THREAD_ID`, `CURSOR_CONVERSATION_ID`, `GEMINI_SESSION_ID`,
`COPILOT_SESSION_ID`, then `AGENT_SESSION_ID`.

`session init` finds the session directory by its ID, so a session that started yesterday keeps its
directory, and creates `.cache/agents/<harness>-<YYYYMMDD>-<id>/` when none exists. It records the
working-copy change as `jj.working_copy_change`. That is a pointer to the shared working copy, not
proof of ownership.

`session record-change` appends the change ID to `jj.change_ids` and calls
`jj-meta attribute <change-id> --session ... --harness ... --model ...`. The trailer policy lives in
[jj-meta](jj-meta.md); `kdn-journal` never edits a commit description. A missing `jj-meta` is a
`jj-meta-unavailable` warning and the mapping is still recorded. When the harness exports no model,
the model Atuin recorded for the thread is the fallback.

`session changes` resolves every recorded ID through jj and prints the description, the author, the
timestamp and the changed files. A missing change is a `change-missing` warning.

`session atuin` links the session to its Atuin Thread. It matches the exact agent session ID first,
then the same harness and cwd within 10 minutes of `started_at`. An ambiguous match is not linked.
The sidecar stores the thread UUID, the model, the message count and the last update; the
transcript stays in Atuin's encrypted store. The thread's real start time replaces a later
`started_at` when the sidecar was created after the session began.

Atuin is optional. Without the binary, with capture off, or with an empty store, the command prints
`atuin-unavailable` or `atuin-empty` and exits 0. `atuin list|show|search` read the same CLI.

The sidecar:

```json
{
  "schema_version": 1,
  "harness": "opencode",
  "session_id": "ses_e1f8bbd08ffep6essAsRoa3wna",
  "started_at": "2026-11-15T18:24:38+01:00",
  "updated_at": "2026-11-16T10:00:00+01:00",
  "cwd": "/home/kdn/dev/github.com/nazarewk-iac/nix-configs",
  "task": "docs/tasks/2026-11/jj-meta",
  "jj": {
    "working_copy_change": "slrttxqzkkzn",
    "change_ids": ["sqzunxvvtlzy"],
    "commits": ["4ecd546084b3"]
  },
  "atuin": {
    "thread_id": "01a1e074430c7a9190885ff832b21db2",
    "agent_session_id": "ses_e1f8bbd08ffep6essAsRoa3wna",
    "model": "deepseek-v4.1-flash-1017",
    "message_count": 728
  }
}
```

Rules: the write is atomic (temp file plus rename), a symlink target is refused, unknown keys
survive a rewrite, a corrupt file is a `sidecar-corrupt` warning, and `schema_version` gates a
migration.

## Board format

A board is an OKF file: Markdown with YAML frontmatter. The shape is **recommended, not required**.

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

Frontmatter keys: `type: Board`, `title`, `description`, `updated`, `status`, `tags`. Frontmatter is
optional. A missing `updated` falls back to the `timestamp` key, then to the file mtime, and a
missing `title` falls back to the first H1, then to the file name.

Recommended headings: `## Status`, `## Next`, `## Blocked`, `## Done`. `## Notes` holds free prose.

The parser maps a heading to one kind by words, in order: `not blocker` makes "next"; `blocked`,
`waiting`, `on hold`, `gated` make "blocked"; `done`, `completed`, `shipped` make "done"; `now`,
`current`, `in progress`, `status`, `items`, `tracks` make "now"; `next`, `todo`, `remaining`,
`follow up` make "next"; `notes`, `context`, `plan`, `risks`, `evidence` make "notes"; a heading
that contains a date (`## 2026-11-13`) makes "now"; anything else is "other". A notes/other section
with an `item | state` table and an open row is promoted to "now". A subsection inherits the kind
of its parent.

An item is a bullet, a checkbox (`- [ ]`, `- [x]`), an ordered line (`1.`), or a table row in a
table that has both an item-like column and a state-like column. A bullet can also carry its state
in the text, for example `- 005 ssh-ca — **blocked**: waits for reboot`.

State words are read case-insensitively: `done`, `complete`, `shipped`, `verified`, `pass` are done;
`blocked`, `waiting`, `on hold` are blocked; `dropped`, `cancelled`, `n/a` are dropped; everything
else is open.

Board status is the frontmatter `status` (`in-progress` and `open` count as `active`). Without it,
the tool infers the status from the items: any blocked item makes the board `blocked`, any open item
makes it `active`, and only done items with no open, blocked or dropped item make it `done`.

A board with no recognized section still parses and still reports counts from its tables and
state-bearing bullets. The tool degrades, it never fails on a free-form board.

A session directory can carry an optional `index.md`. When present, its links order the boards.
Without it the order is `board.md`, then `board-*.md` sorted by name.

## JSON envelope

Every read command supports `--json` and emits one envelope:

```json
{
  "schema_version": 1,
  "command": "summary",
  "root": "/path/to/repo",
  "generated_at": "2026-11-15T20:00:00+01:00",
  "data": {},
  "issues": []
}
```

`data` is the payload of the command: `session` and optional `task` for `summary`; `sessions` for
`sessions`; `tasks` for `tasks`; `task` for `task`; `board` for `board`; `worklog` for `worklog`;
`errors` and `warnings` for `doctor`. `summary --all` uses the `sessions` payload.

Optional times are omitted, never a zero time. Internal fields such as line numbers and raw
frontmatter maps stay out of the output. JSON ignores `--width` and color.

## For agents

The CLI works without a TTY. Use `--json`, never `tui`, and treat the exit code as the result.

### Golden rules

- **Never call `kdn-journal tui` from an agent.** It is interactive and needs a terminal.
- **Use `--json` for every read.** The text output is for people; the JSON is the contract.
- **Pass `--session` explicitly when detection could be wrong.** The CLI detects eight harnesses
  from the environment (`OPENCODE_SESSION_ID`, `PI_SESSION_ID`, `CLAUDE_CODE_SESSION_ID`,
  `CODEX_THREAD_ID`, `CURSOR_CONVERSATION_ID`, `GEMINI_SESSION_ID`, `COPILOT_SESSION_ID`,
  `AGENT_SESSION_ID`). Without a match it uses the newest session.
- **Pass `--root` when the working directory is not the repository root**, for example in a jj
  workspace or a script started from `/tmp`.
- **Do not parse the human text.** Read `data`; read `issues` for findings.
- **Gate edits with `doctor --parse-only`.** It exits 0 when every task, board and worklog parses.
- **`doctor` without `--parse-only` can exit 1 on pre-existing findings.** Use `--parse-only`,
  `--ignore <code>` for known codes, or accept the exit code and read `issues`.
- **Do not mark a task done until `done.md` exists.** `task set-status` enforces this, and it
  refuses `done` while `status.md` remains.
- **The only journal writes are `task set-status` and the `session` sidecar.** Agents still write
  boards and worklogs themselves.
- **Record your session identity and every change you commit.** `session init` once, then
  `session record-change <change-id>` after each commit. It calls `jj-meta`, so the change gets the
  `Assisted-by` trailers and the sidecar gets the mapping. Neither step is required to read the
  journal.

### Recommended loop

```sh
# 1. Where does this run stand?
kdn-journal summary --session "$OPENCODE_SESSION_ID" --json

# 2. Record the session identity once. It finds the directory by the session ID.
kdn-journal session init --task "$TASK" --json

# 3. What is the task state?
kdn-journal task "$TASK" --json

# 4. Check the tree before and after an edit.
kdn-journal doctor --parse-only --json

# 5. Read one board or worklog when the summary is not enough.
kdn-journal board "$TASK_DIR" --json
kdn-journal worklog "$TASK_DIR" --json

# 6. After a commit, map the change and attribute it through jj-meta.
kdn-journal session record-change "$CHANGE_ID" --json

# 7. Update the status only after the lifecycle files are in place.
kdn-journal task set-status "$TASK" in-progress --json
```

### JSON field reference

Every command emits the same envelope:

| Field            | Type   | Meaning                                                                                                                  |
| ---------------- | ------ | ------------------------------------------------------------------------------------------------------------------------ |
| `schema_version` | number | `1`; a breaking change bumps it.                                                                                         |
| `command`        | string | `summary`, `sessions`, `session <sub>`, `tasks`, `task`, `board`, `worklog`, `doctor`, `atuin <sub>`, `task set-status`. |
| `root`           | string | Absolute repository root. Do not diff it.                                                                                |
| `generated_at`   | string | RFC 3339. Do not diff it.                                                                                                |
| `data`           | object | Command payload.                                                                                                         |
| `issues`         | array  | Machine-readable findings; an empty array, never `null`.                                                                 |

Payloads:

| Command                 | `data`                                                              |
| ----------------------- | ------------------------------------------------------------------- |
| `summary`               | `session`, optional `task`; with `--all`, `sessions`.               |
| `sessions`              | `sessions[]`.                                                       |
| `tasks`                 | `tasks[]`.                                                          |
| `task`                  | `task`.                                                             |
| `board`                 | `board`.                                                            |
| `worklog`               | `worklog`.                                                          |
| `doctor`                | `errors`, `warnings` (counts); the issue objects are in `issues`.   |
| `task set-status`       | `task` (repo-relative path), `status`.                              |
| `session init`          | `session` (the sidecar), `dir`, `sidecar`.                          |
| `session record-change` | `session`, `sidecar`, `change_id`, `recorded`, `attributed`.        |
| `session record-commit` | `session`, `sidecar`, `commit_id`, `recorded`.                      |
| `session changes`       | `session`, `changes[]`.                                             |
| `session atuin`         | `session`, `match` (`session-id`, `cwd-time`, `none`, `ambiguous`). |
| `atuin list`            | `threads[]`.                                                        |
| `atuin show`            | `thread`.                                                           |
| `atuin search`          | `query`, `threads[]`.                                               |

Key model fields:

| Model   | Fields                                                                                                                                                                                                                                                                                                                    |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| session | `dir`, `rel_dir`, `name`, `harness`, `date`, `id`, `last_touched`, `boards[]`, `worklog`, `track_worklogs[]`, `task_refs[]`, `sidecar`, `issues[]`                                                                                                                                                                        |
| board   | `path`, `title`, `description`, `status`, `updated`, `tags[]`, `sections[]`, `has_frontmatter`                                                                                                                                                                                                                            |
| section | `title`, `level`, `kind` (`now`, `next`, `blocked`, `done`, `notes`, `other`), `items[]`                                                                                                                                                                                                                                  |
| item    | `text`, `state`, `extra[]`, `done`, `blocked`, `dropped`, `checkbox`, `depth`, `section`                                                                                                                                                                                                                                  |
| task    | `dir`, `rel_dir`, `month`, `slug`, `depth`, `parent_dir`, `definition_path`, `title`, `description`, `status`, `solution`, `authored_by`, `timestamp`, `files[]`, `has_board`, `has_worklog`, `board`, `worklog`, `subtasks[]`, `last_activity`, `open_items`, `done_items`, `blocked_items`, `dropped_items`, `issues[]` |
| worklog | `path`, `entries[]`; an entry has `heading`, `timestamp` (omitted when absent), `has_timestamp`, `precise`, `body`                                                                                                                                                                                                        |
| sidecar | `schema_version`, `harness`, `session_id`, `started_at`, `updated_at`, `cwd`, `task`, `jj` (`working_copy_change`, `change_ids[]`, `commits[]`), `atuin` (`thread_id`, `agent_session_id`, `model`, `message_count`, `updated_at`)                                                                                        |
| thread  | `atuin_id`, `harness`, `session_id`, `cwd`, `model`, `title`, `started_at`, `updated_at`, `message_count`                                                                                                                                                                                                                 |
| issue   | `severity`, `code`, `path`, `message`                                                                                                                                                                                                                                                                                     |

### Stability and pitfalls

- `schema_version` is the contract. New fields can appear; do not reject unknown fields.
- `root` and `generated_at` change per run. Never use them as cache keys or golden output.
- Optional times are omitted. A missing `timestamp` means "undated", not `0001-01-01`.
- `issues` is always an array. `doctor` puts the full issue objects there and the counts in `data`.
- Text output is truncated to `--width`; JSON ignores width and color.
- `summary` is capped at 24 lines by default; `--full` removes the cap. Agents should read JSON, not
  count text lines.
- `summary` picks `$OPENCODE_SESSION_ID` when it matches, otherwise the newest session. A prefix
  that matches distinct ids is ambiguous and exits 2.
- `tasks --status` accepts only a value present in the tree, or `all`; anything else exits 2.
- `task set-status` exits 2 on a refusal and leaves the file unchanged.
- The `session` commands degrade to warnings, not errors: `jj-unavailable`, `jj-working-copy`,
  `jj-meta-unavailable`, `jj-meta-failed`, `atuin-unavailable`, `atuin-empty`, `atuin-no-match`,
  `atuin-ambiguous`, `sidecar-corrupt` and `change-missing` all keep exit 0.
- `session record-change` records the mapping even when `jj-meta` is missing or refuses the change.
  The sidecar is the local source of truth; the trailer is the public, optional one.

### `jq` examples

```sh
# The current task's status and open items.
kdn-journal task "$TASK" --json | jq '{status: .data.task.status, open: .data.task.open_items}'

# Every in-progress task, newest first.
kdn-journal tasks --status in-progress --json | jq -r '.data.tasks[] | [.slug, .last_activity] | @tsv'

# The issue codes that make doctor fail.
kdn-journal doctor --json | jq -r '.issues[] | select(.severity=="error") | .code' | sort -u

# The main board's blocked items.
kdn-journal board "$TASK_DIR" --json | jq -r '.data.board.sections[] | select(.kind=="blocked") | .items[].text'
```

## Exit codes

| Code | Meaning                                                   |
| ---- | --------------------------------------------------------- |
| `0`  | Success.                                                  |
| `1`  | Findings or errors. For example, `doctor` found an error. |
| `2`  | Usage error, or a selector that is unknown or ambiguous.  |

A selector that matches nothing and a selector that matches several items both exit 2.

## Editor integration

`--print-path` prints the resolved file and exits. This turns any editor into a journal opener:

```sh
$EDITOR "$(kdn-journal task agent-journal-summary --print-path)"
$EDITOR "$(kdn-journal board --print-path .cache/agents/opencode-20261115-ses_abc)"
```

The TUI does the same with `e`, and refreshes when the editor exits. There is no `edit` subcommand.

`kdn-journal completion <shell>` prints completions for bash, fish and zsh.

## Examples

```sh
# Where does the current session stand?
kdn-journal summary

# Add one task's pair to the summary.
kdn-journal summary --task docs/tasks/2026-11/agent-journal-summary

# One track board in full.
kdn-journal summary --track ssh-ca

# Every session, one line each.
kdn-journal summary --all

# What is in progress in this month?
kdn-journal tasks --status in-progress --month 2026-11

# One task with its sub-tasks.
kdn-journal task agent-journal-summary --print-path

# Flip a task to in-progress.
kdn-journal task set-status agent-journal-summary in-progress

# Validate the tree, then the full tree.
kdn-journal doctor --parse-only
kdn-journal doctor

# Browse.
kdn-journal tui
```

## See also

- [agent-journal.md](../.agents/rules/agent-journal.md) — the worklog and board contract.
- [tasks/README.md](tasks/README.md) — the task directory convention.
- [../packages/kdn-journal/](../packages/kdn-journal/) — the source.
