---
type: Reference
description: Convention for tracking repository tasks as one file per task under docs/tasks/, with a done-tag and a sibling solution file.
timestamp: 2026-07-31T11:30:00+02:00
---

# Tasks convention

Each task is **one file per task** living under `docs/tasks/`. When a task is finished it is
tagged done in its frontmatter and gains a sibling `<task>.done.md` presenting the solution.

This replaces the legacy monolithic `TASKS.md` at the repo root (see
[Legacy `TASKS.md`](#legacy-tasksmd)).

## File naming

| File | Purpose |
|---|---|
| `docs/tasks/<task>.md` | The task itself: context, root cause, proposed approach. `<task>` is a short kebab-case slug. |
| `docs/tasks/<task>.done.md` | The solution, created **only when the task is done**. Cross-linked from the task via `solution:`. |

## Frontmatter schema

Both files use OKF frontmatter (see [okf-format.md](../okf-format.md)). The keys below are a
**hard contract** — include all of them.

### `<task>.md`

```yaml
---
type: Task
description: <one sentence — what is wrong / what needs doing>
status: open | in-progress | done
solution: <task>.done.md   # present once status: done; omit while open
authored_by: agent | human  # who wrote THIS file — people forget to set this; default to agent when an agent writes it
timestamp: <ISO 8601>
---
```

### `<task>.done.md`

```yaml
---
type: Solution
description: <one sentence — what the fix was>
task: <task>.md            # back-link to the task
authored_by: agent | human
timestamp: <ISO 8601>
---
```

> **`authored_by:` is mandatory and easy to forget.** It records that a file was written by an
> AI agent rather than a person. When an agent creates or substantially rewrites a task/solution
> file, it **must** set `authored_by: agent`. Humans set `authored_by: human`.

## Body structure

**`<task>.md`** — free-form, but lead with a one-line done banner once solved:

```markdown
> ✅ **Done** — see the solution in [<task>.done.md](<task>.done.md).
```

**`<task>.done.md`** — present these four sections, in order:

1. `## Root cause analysis` — why it was broken / what the real problem was.
2. `## Solution` — what was changed (code blocks welcome).
3. `## Verification steps` — the exact commands run and their observed output.
4. `## Follow-up notes` — anything still open, caveats, or "re-verify under X" (omit if none).

## Lifecycle

1. **Create** `docs/tasks/<task>.md` with `status: open`.
2. **Start work** → flip to `status: in-progress`.
3. **Finish** → set `status: done`, add `solution: <task>.done.md`, write the done banner, and
   create `<task>.done.md` with the four sections above.

## Legacy `TASKS.md`

The repo root has a legacy monolithic `TASKS.md` that predates this convention and is being
phased out. Its header carries this instruction (kept in sync with this doc):

> **Before starting work on any entry in `TASKS.md`, first move it** to `docs/tasks/<task>.md`,
> then work it there. When the **last** entry is migrated out, **delete `TASKS.md`.**

The example that seeded this convention: [flake-checks-output.md](flake-checks-output.md) and
its solution [flake-checks-output.done.md](flake-checks-output.done.md).
