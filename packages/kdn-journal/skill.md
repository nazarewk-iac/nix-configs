---
name: kdn-journal
description: Read and update a repository's agent journals — summary, tasks, boards, worklogs, the local session sidecar, jj change mapping and Atuin Threads — and gate edits with doctor.
---

# `kdn-journal`

Use this skill when a repository keeps `docs/tasks` and `.cache/agents` journals, or when you need
to record the agent session identity and its jj changes.

## Catch up

```sh
kdn-journal summary --json
kdn-journal tasks --status in-progress --json
kdn-journal task <dir|slug> --json
kdn-journal board <path> --json
kdn-journal worklog <path> --json
kdn-journal doctor --parse-only --json
```

Use `--json`; the text output is for people. Never call `kdn-journal tui` from an agent: it needs a
terminal.

## Record the session identity

```sh
kdn-journal session init --task <task-dir> --json
kdn-journal session record-change <change-id> --json
kdn-journal session changes --json
kdn-journal session atuin --json
```

`session init` writes `.cache/agents/<harness>-<date>-<session>/session.json`, which is local and
git-ignored. `record-change` stores the jj mapping and calls `kdn-jj-meta` for the trailers.
`session atuin` links the Atuin Thread when the harness is captured; it is optional, and the
journal still works without it.

## Backfill an existing history

```sh
kdn-journal session backfill --dry-run --json
kdn-journal session backfill --json
```

`backfill` maps each mutable change to a session from the sidecars first, then from the Atuin
Thread whose interval covers the change. It skips a change with no session and never touches an
empty description.

## Journal rules

- Every agent run keeps a session worklog and board, plus a task pair when a task exists.
- The worklog is append-only; the board is a snapshot of the current state.
- Use the JSON envelope and the `issues` array; exit codes are 0 (ok), 1 (finding), 2 (usage).
- `doctor --parse-only` is the gate for the task tree.
