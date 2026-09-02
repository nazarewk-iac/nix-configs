---
type: Reference
description: Day-to-day golden paths for moving working-copy edits into earlier commits — squash vs jj absorb — proven by test_squash_absorb.py.
timestamp: 2026-09-02T00:00:00+02:00
---

# Move edits into earlier commits — squash vs `jj absorb`

Branch-agnostic day-to-day moves (no fork slot). The proof is
`test_squash_absorb.py`.

## `jj squash --from @ --into <id> -- <files>`

Fold chosen files from `@` into a chosen earlier **mutable** commit. The target
gains the content; the rest stays in `@`.

```bash
jj squash --from @ --into <change-id> -- path/to/file
```

Verified (`test_squash_from_into_routes_chosen_files`): the file lands in the
target commit; an unrelated file stays in `@`.

## `jj absorb`

Auto-route each changed hunk in `@` to the closest **mutable** ancestor that last
touched those lines. Flags (jj 0.44): `-f/--from` (default `@`), `-t/--into
<REVSETS>`, `--interactive`, and a `[FILESETS]` positional.

```bash
jj absorb            # distribute all @ hunks to their last-toucher ancestors
jj absorb -- path    # only these paths
```

Verified behavior (`test_absorb_routes_each_hunk_to_its_last_toucher`,
`test_absorb_does_not_move_into_an_immutable_ancestor`):

- Each hunk goes to the ancestor that last modified those lines (edit to `a.txt`
  → the commit that introduced `a.txt`; edit to `b.txt` → its commit).
- A hunk with **no clear ancestor** (a brand-new file) is **left in `@`**.
- A hunk whose last-toucher is **immutable** is **left in `@`** — `jj absorb`
  prints "Nothing changed" and rewrites no published commit.
- The source `@` is abandoned only if all its changes are absorbed and it has no
  description; otherwise the leftover stays in `@`.

## When to use which

- **`jj absorb`** — the low-cognitive-load default when your `@` holds fixups
  that each clearly belong to a recent ancestor. It figures out the targets, and
  it is safe: it never touches an immutable ancestor and leaves ambiguous hunks
  behind. Prefer it for "spread these small fixes back into the stack".
- **`jj squash --from/--into -- <files>`** — when you want a **specific** target
  (not the auto-detected one), or the right ancestor is ambiguous, or you must
  move a whole file regardless of which lines changed. Precise and explicit.

So `jj absorb` may stand in for a manual squash when the routing is unambiguous
and the targets are mutable; reach for explicit `squash` when you need control.
