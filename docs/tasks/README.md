---
type: Reference
description: Convention for tracking repository tasks as one directory per task under docs/tasks/<YYYY-MM>/<slug>/, with recursive sub-tasks, a done-tag and a sibling solution file.
timestamp: 2026-09-10T12:00:00+02:00
---

# Tasks convention

Each task is **one directory** at `docs/tasks/<YYYY-MM>/<slug>/`. The month is the month the task
starts. The slug is a short kebab-case name. Inside the directory, each file has a fixed name for
its role. A task directory can also hold another task directory, which makes a sub-task. A finished
task gets `status: done` in `definition.md` and a sibling `done.md` with the solution.

The month prefix puts the tasks in a timeline, so you can navigate them by date. It also keeps
`docs/tasks/` small: one directory per month, not one file per task-file.

This layout replaces the earlier flat `docs/tasks/<task>[.kind].md` naming. It also replaces the
legacy monolithic `TASKS.md` at the repo root (see [Legacy `TASKS.md`](#legacy-tasksmd)).

## Directory layout

```
docs/tasks/
├── README.md                       # this file
├── 2026-07/
│   └── flake-checks-output/
│       ├── definition.md
│       └── done.md
└── 2026-09/
    ├── darwin-vm-testing/
    │   ├── definition.md
    │   ├── research.md
    │   └── tart.research.md        # a supporting document of this task
    └── generalization/             # an umbrella task
        ├── definition.md           # describes the whole effort, indexes the sub-tasks
        ├── .worklog.md             # git-ignored: one dated section per work run
        ├── .board.md               # git-ignored: the current state
        ├── 001-slots-sharing-readiness/
        │   └── definition.md       # a sub-task, with its own status
        └── 008-sops-default-inventory/
            ├── definition.md
            └── research.md
```

## File names

| File | Purpose |
|---|---|
| `definition.md` | The task itself: context, root cause, proposed approach. Always present. |
| `research.md` | Findings that support the task. Optional. |
| `design.md` | The chosen design, when the task needs one before the work starts. Optional. |
| `status.md` | **Transient** progress checkpoint for a task that is paused mid-flight. Optional. Delete it when the task is done. |
| `done.md` | The solution, created **only when the task is done**. |
| `<sub>.<kind>.md` | A supporting document, for example `tart.research.md`. Use it when one task needs more than one research or design document. |
| `<sub-slug>/` | A **sub-task** directory. It holds the same file names as its parent. |
| `.worklog.md` | Git-ignored work record. See [The worklog and the board](#the-worklog-and-the-board). |
| `.board.md` | Git-ignored current state. Same section. |

The month comes from the `timestamp:` in `definition.md`. **Never move a task to a new month
later.** The month records when the task started, not when it finished.

## Sub-tasks and umbrella tasks

A task directory can hold another task directory. Use a sub-task when the work splits into parts
that are too large for one definition, but too closely related to stand alone.

- **Nesting is recursive.** A sub-task can hold its own sub-tasks. Keep the depth as low as the
  work allows.
- A sub-task directory uses the same file names and the same frontmatter as any other task.
- A sub-task **inherits the month of its parent**. Never give a sub-task its own month directory,
  even when it starts in a later month. The parent's month records when the effort started.
- Give an ordered family a number prefix, for example `001-`, so the directory list shows the
  order.
- An **umbrella task** is a task whose `definition.md` describes a family of sub-tasks and indexes
  them. It keeps `status: in-progress` while any sub-task is open.

A sub-task is not the same thing as a supporting document:

| What you have | What to use |
|---|---|
| More than one research or design document for **one** task | `<sub>.<kind>.md`, for example `tart.research.md` |
| A part with its **own** definition, status and solution | a sub-task directory |

## The worklog and the board

Two files record the state of the work, not the definition of it. Both live in the task directory
and both start with a dot. The `.*.md` rule in `.gitignore` keeps them out of every commit.

| File | Contents |
|---|---|
| `<task-dir>/.worklog.md` | Append-only. One dated section per work run. Never edit an older entry. |
| `<task-dir>/.board.md` | The current state. One row per open item. Overwrite it freely. |

A build, a verification run, a measurement or a debug session belongs here. An umbrella task keeps
one worklog and one board for the whole family, in the umbrella directory.

## Never track the status of a work run as a task

A task file describes a problem and its solution. It does not track the progress of a build, a
verification run, or a debug session. That belongs in `<task-dir>/.worklog.md`, and only there.

Two rules follow from this:

- **Do not create a task for a verification run.** For example, "rebuild these three hosts and
  report" is a worklog entry, not a task.
- **Do not add a temporary script to the repository.** A helper you need for one run belongs in a
  git-ignored path, for example `.cache/agent-notes/`. Prefix any other transient file with a dot
  and keep it out of every commit.

## Frontmatter schema

Every file uses OKF frontmatter (see [okf-format.md](../okf-format.md)). The keys below are a
**hard contract** — include all of them.

### `definition.md`

```yaml
---
type: Task
description: <one sentence — what is wrong / what needs doing>
status: open | in-progress | done
solution: done.md          # present once status: done; omit while open
authored_by: agent | human  # who wrote THIS file — people forget to set this; default to agent when an agent writes it
timestamp: <ISO 8601>
---
```

### `done.md`

```yaml
---
type: Solution
description: <one sentence — what the fix was>
task: definition.md        # back-link to the task
authored_by: agent | human
timestamp: <ISO 8601>
---
```

### `status.md`

```yaml
---
type: Status
description: <one sentence — where the work was parked and what remains>
task: definition.md        # back-link to the task
authored_by: agent | human
timestamp: <ISO 8601>
---
```

### `research.md`, `design.md`, `<sub>.<kind>.md`

```yaml
---
type: Research | Design
description: <one sentence>
task: definition.md        # back-link to the task
authored_by: agent | human
timestamp: <ISO 8601>
---
```

> **`authored_by:` is mandatory and easy to forget.** It records that a file was written by an
> AI agent rather than a person. When an agent creates or substantially rewrites a file in a task
> directory, it **must** set `authored_by: agent`. Humans set `authored_by: human`.

Because every file of one task sits in one directory, each back-link is a plain file name. A
sub-task links to its parent with `../definition.md`. A link out to `docs/` climbs three levels
from `<YYYY-MM>/<slug>/`, and one more level per sub-task.

## Body structure

**`definition.md`** — free-form, but lead with a one-line done banner once solved:

```markdown
> ✅ **Done** — see the solution in [done.md](done.md).
```

**`done.md`** — present these four sections, in order:

1. `## Root cause analysis` — why it was broken / what the real problem was.
2. `## Solution` — what was changed (code blocks welcome).
3. `## Verification steps` — the exact commands run and their observed output.
4. `## Follow-up notes` — anything still open, caveats, or "re-verify under X" (omit if none).

**`status.md`** — a transient checkpoint written when work is **parked mid-flight** (not
finished). Present these three sections, in order:

1. `## Done so far` — what has already landed / been verified.
2. `## Remaining` — what is still left to do.
3. `## Next directions` — the concrete next step(s) and any blocker that caused the pause.

It exists only while the task is paused: **do not** create a `status.md` for a task you finish in
one go, and **delete it** when you declare the task done (fold any lasting content into
`done.md`). A task may carry a `status.md` while `status: in-progress`.

## Lifecycle

1. **Create** `docs/tasks/<YYYY-MM>/<slug>/definition.md` with `status: open`. Use the current
   month. For a sub-task, create it inside the parent's directory and keep the parent's month.
2. **Start work** → flip to `status: in-progress`. Record each run in `<task-dir>/.worklog.md`.
3. **Park (optional)** → if work pauses before it is done, keep `status: in-progress` and write
   `status.md` with the Done-so-far / Remaining / Next-directions sections. Overwrite it on each
   later pause; it is the resume point.
4. **Finish** → set `status: done`, add `solution: done.md`, write the done banner, create
   `done.md` with the four sections above, and **delete `status.md`** (its content graduates into
   the solution). A task is not done while a `status.md` remains. An umbrella task is done only
   when every sub-task is done.

## Legacy `TASKS.md`

The repo root has a legacy monolithic `TASKS.md` that predates this convention and is being
phased out. Its header carries this instruction (kept in sync with this doc):

> **Before starting work on any entry in `TASKS.md`, first move it** to
> `docs/tasks/<YYYY-MM>/<slug>/definition.md`, then work it there. When the **last** entry is
> migrated out, **delete `TASKS.md`.**

The example that seeded this convention:
[2026-07/flake-checks-output/definition.md](2026-07/flake-checks-output/definition.md) and its
solution [2026-07/flake-checks-output/done.md](2026-07/flake-checks-output/done.md).
