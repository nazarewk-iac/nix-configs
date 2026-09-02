---
type: Reference
description: Golden paths for placing a change in the fork topology, with the frozen-vs-mutable rule, proven by test_placement.py.
timestamp: 2026-09-02T00:00:00+02:00
---

# Placement golden paths

Where a new change lands in the fork topology, and the shortest command to put it
there. The executable proof is `test_placement.py`; the base graph is
`topologies.build_base_tree`. This is the detailed layer — the base
`docs/jujutsu-vcs.md` holds the short form.

## Base state

`build_base_tree` is the realistic resting state: a published merge with an empty
`@` on top.

```
A ── U1 ── U2                 upstream-tip = U2; main@upstream = U2; upstream@fork = U2
│           \
│            M ── @           M = the merge; main, main@fork = M (pushed → frozen)
│           /
└── F1                        fork-sensitive
```

`fork-tip` = `M` (no local described work sits above the merge), `merge-frozen` =
`{M}`.

## Golden path 1 — add a generic (upstream) change

Two commands on a frozen tree (command 1 builds a mutable merge; command 2 places the change).
When a mutable merge already exists, skip command 1 — the single split in golden path 2 is enough
(proven by `test_second_upstream_change_into_existing_mutable_merge`):

```bash
# 1. edit files in @ (generic content), then:
jj new --no-edit -B @ -m 'chore(upstream): merge'
jj split -A upstream-tip -B fork-tip -m 'feat(...): generic' -- <generic files>
```

- Command 1 inserts a mutable merge commit between the frozen merge and `@`. It
  becomes the new `fork-tip`. The frozen merge is untouched.
- Command 2 grafts the generic commit `S` onto the old `upstream-tip` and makes
  it the new merge's upstream-side parent.

Verified post-conditions (`test_upstream_change_on_frozen_tree_unified_recipe`):

- `S` is a child of the old `upstream-tip`, and becomes the new `upstream-tip`.
- `fork-leaked` stays empty.
- the frozen merge keeps its commit id (not rewritten) and stays an ancestor of
  `@` — the precondition `jj sync-remotes` fast-forwards on.
- the merge on top is mutable (`merge-frozen` empty) — built forward, not a
  rewrite.

## Golden path 2 — a further generic change when a mutable merge already exists

Once a mutable merge is the `fork-tip` (for example right after golden path 1, or
mid-session), the next generic change needs only the single split — no `jj new`,
no rebase:

```bash
# edit files in @, then:
jj split -A upstream-tip -B fork-tip -m 'feat(...): generic' -- <generic files>
```

The mutable merge is reparented onto the new commit; the change stacks on the
previous `upstream-tip`. This is the "merge in the middle" case (confirmed live
2026-09-02, proven by `test_second_upstream_change_into_existing_mutable_merge`).

## The frozen-vs-mutable rule

`-B fork-tip` re-parents the fork tip onto the new commit, so it works only when
the fork tip is **mutable**. On a frozen tree the merge is immutable, so a bare
`-B fork-tip` would try to rewrite it and fail. That is the whole reason golden
path 1 runs `jj new --no-edit -B @` first: it manufactures a fresh mutable merge,
so the same `jj split -A upstream-tip -B fork-tip` then applies. Golden path 2 is
just golden path 1 without the manufacturing step, because the mutable merge is
already there.

## Golden path 3 — a fork-sensitive change

Fork content is routed by **kind** (decided 2026-09-02):

### 3a. Leaf tweak (a host tweak, a one-off) — above the merge

A leaf tweak is fork-only and short-lived. A plain split leaves it above the
merge, on the fork chain:

```bash
# fork-sensitive content in @, then:
jj split -m 'feat(fork): host tweak' -- <sensitive files>
```

It becomes the `fork-tip`, so a later `jj sync-remotes` pushes it to `main@fork`.
It never reaches upstream. `fork-leaked` lists it — for a leaf that is
**informational, not a gate** (proven by `test_fork_leaf_change_stays_above_the_merge`:
the leaf is on `fork-chain`, is the `fork-tip`, is not in `upstream-safe`, and the
`upstream-tip` and the merge are untouched).

### 3b. Durable fork-base change — into a new merge

A change to the maintained fork base belongs on the fork side, folded into the
merge. On a frozen tree you cannot rewrite the fork chain below the immutable
merge, so build a new merge forward:

```bash
# fork-sensitive content in @, then:
jj split -A fork-tip -m 'feat(fork): base wiring' -- <sensitive files>
jj new upstream-tip fork-tip -m 'chore(upstream): merge'
jj new                          # leave an empty @ on top; jj sync-remotes moves the bookmarks
```

The fork commit becomes the fork-side parent of a new merge, so `to-rebase` and
`fork-leaked` stay empty and `upstream-tip` is untouched (proven by
`test_fork_base_change_folds_into_a_new_merge`: the new merge is
`merge(upstream-tip, fork commit)`, it is mutable, and the old frozen merge keeps
its commit id and stays an ancestor).

## Golden path 4 — a mixed working copy, split by content

When `@` holds both generic and fork-sensitive content, route each part with the
recipes above: send the generic part down to the upstream chain, then carve the
sensitive remainder as a fork leaf.

```bash
# @ has generic + fork-sensitive files, then:
jj new --no-edit -B @ -m 'chore(upstream): merge'
jj split -A upstream-tip -B fork-tip -m 'feat(...): generic' -- <generic files>
jj split -m 'feat(fork): sensitive' -- <sensitive files>
```

The generic part folds below the new merge (becomes `upstream-tip`, never leaks);
the sensitive remainder stays above the merge as a fork leaf. Verified by
`test_mixed_working_copy_split_by_content`: `fork-leaked` holds only the sensitive
leaf, the generic part is not in it, and the frozen merge is untouched.
