---
type: Rule
description: "Agent-facing use of kdn-journal: JSON reads, explicit session and root, doctor --parse-only as the gate, and the one safe write."
timestamp: 2026-11-15T21:45:00+01:00
---

# kdn-journal for agents

`kdn-journal` reads repository tasks and agent journals. Use the machine-readable path; the text
output is for people.

## Read with JSON

- Use `--json` on every read. Parse `data`; read `issues` for findings.
- Pass `--session <id>` explicitly. `$OPENCODE_SESSION_ID` is an OpenCode fallback only.
- Pass `--root <repo>` when the working directory is not the repository root.
- Use `--print-path` to resolve a task, board or worklog before you edit it.
- Do **not** call `kdn-journal tui` from an agent; it is interactive and needs a terminal.

```sh
kdn-journal summary --session "$OPENCODE_SESSION_ID" --json
kdn-journal tasks --status in-progress --json
kdn-journal task "$TASK" --json
kdn-journal board "$TASK_DIR" --json
kdn-journal worklog "$TASK_DIR" --json
```

## Gate edits

`doctor --parse-only` exits 0 when every task, board and worklog parses. Run it before and after an
edit. Plain `doctor` exits 1 on pre-existing findings; use `--ignore <code>` for known codes, or
accept the exit code and read `issues`.

```sh
kdn-journal doctor --parse-only --json
```

## The one write

`task set-status` rewrites only the `status:` and, for `done`, `solution:` lines. It refuses `done`
without an existing `done.md`, refuses `done` while `status.md` remains, and exits 2 on a refusal
without changing the file.

```sh
kdn-journal task set-status "$TASK" in-progress --json
```

The CLI never writes a journal. Keep writing the session and task boards and worklogs yourself.

## Contract

- The envelope is `schema_version`, `command`, `root`, `generated_at`, `data`, `issues`.
- `issues` is always an array. Optional times are omitted, never `0001-01-01`.
- Do not diff `root` or `generated_at`; they change per run.
- Text output is truncated to `--width`; JSON ignores width and color.

Full reference, including the JSON field table and `jq` examples:
[docs/kdn-journal.md](../../docs/kdn-journal.md#for-agents).
