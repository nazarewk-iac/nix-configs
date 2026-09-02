---
type: Reference
description: Branch-agnostic move/restructure golden paths (reorder, split, abandon, revert, duplicate, simplify-parents), proven by test_restructure.py.
timestamp: 2026-09-03T00:00:00+02:00
---

# Move / restructure golden paths

Everyday history-restructuring, independent of the fork topology. The executable
proof is `test_restructure.py` (a plain repo, no fork slot).

## Reorder two changes

Move `A` to after `B` (flip `A→B` into `B→A`):

```bash
jj rebase -r <A> --insert-after <B>
```

`A` now follows `B`; `B` takes `A`'s old parent
(`test_reorder_two_changes`).

## Split an already-committed commit

Carve a committed commit into two by content:

```bash
jj split -r <id> -m 'msg for the selected part' -- <files>
```

The **selected** files go to the first (parent) commit with the new message; the
**remainder** stays in a child that keeps the original message
(`test_split_committed_commit`).

## Abandon a change

```bash
jj abandon <id>
```

The change is gone; its descendants rebase onto its parent, content preserved
(`test_abandon_reparents_descendants`).

## Revert-forward (undo without rewriting)

Use this for a pushed or immutable change — build a new commit that inverts the
target instead of rewriting history. The command is `jj revert` (this jj has no
`backout`):

```bash
jj revert -r <target> --insert-after <tip>   # or -d/--onto <dest>
```

It creates a `Revert "<subject>"` commit that inverts the target's diff; the
target is untouched (`test_revert_creates_an_inverse_commit`).

## Duplicate a commit (cherry-pick)

```bash
jj duplicate <id> --onto <dest>
```

A copy with the same content and a new change id lands on `<dest>`
(`test_duplicate_copies_a_commit`). Duplicating onto a descendant of the source
warns and yields an empty copy — pick a destination that does not already contain
the change.

## Simplify redundant merge parents

When a merge has a parent that is already reachable through another parent (a
redundant edge), drop it:

```bash
jj simplify-parents -r <merge>
```

jj does not remove such edges on its own, so a merge built with `jj new <p> <q>`
where `p` is an ancestor of `q` keeps both parents until you simplify
(`test_simplify_parents_drops_a_redundant_edge`).
