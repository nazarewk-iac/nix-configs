---
type: Rule
description: "Short pointer to the tasks convention: one directory per task under docs/tasks/<YYYY-MM>/<slug>/, recursive sub-tasks, a done-tag and a sibling solution file."
timestamp: 2026-09-10T12:00:00+02:00
---

# Tasks

Full doc: [docs/tasks/README.md](../../docs/tasks/README.md).

- **One directory per task** at `docs/tasks/<YYYY-MM>/<slug>/`. The month is the month the task
  starts; never move a task to a new month later. Files inside have fixed names:
  `definition.md`, `research.md`, `design.md`, `status.md`, `done.md`, and `<sub>.<kind>.md` for
  a supporting document (for example `tart.research.md`).
- **Sub-tasks nest, recursively.** A task directory can hold another task directory, for example
  `2026-09/generalization/001-slots-sharing-readiness/`. A sub-task keeps the parent's month
  directory. An **umbrella task** describes the family in its own `definition.md` and indexes the
  sub-tasks. Use a sub-task directory for a part with its own status; use `<sub>.<kind>.md` for a
  second research or design document of the same task.
- A finished task gets `status: done` and `solution: done.md` in `definition.md`, plus a sibling
  `done.md` with the solution. Every back-link inside the directory is a plain file name; a
  sub-task points at its parent with `../definition.md`.
- **Never track the status of a work run as a task.** A build, a verification run or a debug
  session belongs in `<task-dir>/.worklog.md` (append-only, dated) with the current state in
  `<task-dir>/.board.md`. The `.*.md` rule in `.gitignore` keeps both out of every commit. A
  helper script for one run belongs in a git-ignored path such as `.cache/agent-notes/`.
- **Parked work** gets a transient `status.md` (Done-so-far / Remaining / Next-directions) while
  `status: in-progress`; **delete it when the task is declared done** — a task is not done while
  a `status.md` remains.
- **`authored_by:` frontmatter is mandatory** — set `authored_by: agent` when an agent writes
  the file (easy to forget).
- `done.md` presents four sections in order: **Root cause analysis**, **Solution**,
  **Verification steps**, **Follow-up notes** (last one optional).
- **Legacy `TASKS.md`** (repo root) is being phased out: before working any entry there, first
  move it to `docs/tasks/<YYYY-MM>/<slug>/definition.md`; delete `TASKS.md` once its last entry
  is migrated out.
