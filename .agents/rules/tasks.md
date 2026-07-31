---
type: Rule
description: "Short pointer to the tasks convention: one file per task under docs/tasks/, with a done-tag and sibling solution file."
timestamp: 2026-07-31T11:30:00+02:00
---

# Tasks

Full doc: [docs/tasks/README.md](../../docs/tasks/README.md).

- **One file per task** at `docs/tasks/<task>.md`; a finished task gets `status: done` in
  frontmatter and a sibling `docs/tasks/<task>.done.md` with the solution.
- **Parked work** gets a transient `docs/tasks/<task>.status.md` (Done-so-far / Remaining /
  Next-directions) while `status: in-progress`; **delete it when the task is declared done** —
  a task is not done while a `.status.md` remains.
- **`authored_by:` frontmatter is mandatory** — set `authored_by: agent` when an agent writes
  the file (easy to forget).
- `<task>.done.md` presents four sections in order: **Root cause analysis**, **Solution**,
  **Verification steps**, **Follow-up notes** (last one optional).
- **Legacy `TASKS.md`** (repo root) is being phased out: before working any entry there, first
  move it to `docs/tasks/<task>.md`; delete `TASKS.md` once its last entry is migrated out.
