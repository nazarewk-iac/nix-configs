---
type: Reference
description: Day-to-day discard and recover golden paths — jj restore, undo, and the operation log, proven by test_recover.py.
timestamp: 2026-09-03T00:00:00+02:00
---

# Discard / recover golden paths

Everyday ways to throw away a change or roll back a mistake. Branch-agnostic —
these need no fork slot. The executable proof is `test_recover.py`.

## Discard file changes in the working copy

```bash
jj restore <path>            # revert one file in @ to its parent's content
jj restore                    # revert the WHOLE @ to its parent (discard everything)
```

- `jj restore <path>` reverts only that file; unrelated changes in `@` stay
  (`test_restore_reverts_a_file_and_keeps_other_changes`).
- `jj restore` with no path resets `@` to match its parent, so `@` becomes empty
  and a new file added in `@` is removed
  (`test_restore_discards_all_working_copy_changes`).

## Bring a file back from another revision

```bash
jj restore --from <rev> <path>
```

Copies that file's content at `<rev>` into `@`
(`test_restore_from_a_revision`). Note: if `<rev>` does not have the file, the
restore deletes it in `@`.

## Drop a commit

```bash
jj abandon <id>
```

Removes the commit; its descendants rebase onto its parent, so their own changes
stay but the abandoned commit's changes are gone
(`test_abandon_reparents_descendants`). Only mutable commits can be abandoned;
for a published/immutable change, revert-forward instead (see
`test_restructure.md`).

## Roll back a mistake

```bash
jj undo                      # reverse the single last operation
jj op log                    # list operations (id + description)
jj op restore <op-id>         # roll the whole repo back to a chosen operation
```

- `jj undo` reverses the last operation — the fast escape hatch. After an
  `abandon`, one `jj undo` brings the commit back
  (`test_undo_reverses_the_last_operation`).
- For a multi-step backout, capture the good operation id from `jj op log`, then
  `jj op restore <op-id>` rewinds every later operation at once
  (`test_op_restore_rolls_back_multiple_operations`).

`jj undo` is the everyday recovery; `jj op log` + `jj op restore` is the
multi-step rewind when several operations must be undone together.
