---
type: Reference
description: Fork-topology hazards and forbidden operations, and what jj does when you try them, proven by test_hazards.py.
timestamp: 2026-09-02T00:00:00+02:00
---

# Hazards and forbidden operations

Things you must not do in the fork topology, the exact jj behavior when you try,
and the safe pattern. The executable proof is `test_hazards.py`.

## 1. Do not rewrite a published commit

`main@fork` and its ancestors are pushed, so jj treats them as immutable.
`jj describe` / any rewrite of such a commit fails:

```
Error: Commit <id> is immutable
```

Build forward instead (a new commit / a new merge). Proven by
`test_cannot_rewrite_a_pushed_commit` (describe of the merge `M` and of its
ancestor `U2` both fail with `is immutable`).

## 2. Do not squash into a published commit

Same rule for `jj squash --into <published>`: it would rewrite immutable history
and fails with the immutable error. Build forward. Proven by
`test_cannot_squash_into_an_immutable_commit`.

## 3. `latest()` / `*-tip` follow commit time, not topology

`upstream-tip` = `latest(upstream-chain)` and `fork-tip` = `latest(fork-chain)`
pick the commit with the **newest commit time**, not the topological tip. A
commit that is the graph tip but has an older commit time does not win.

Detection: compare the resolved tip to the commit you intended. Fix: control the
commit time (the harness stamps increasing times via
`--config debug.commit-timestamp`; in normal use, create commits in order so
times increase). Proven by `test_latest_tip_follows_commit_time_not_topology`:
with `Y` the topological tip but an older time than `X`, `upstream-tip` = `X`;
after `Y` gets a newer time, `upstream-tip` = `Y`.

## 4. Do not `describe` a dual-parent `@`

After a publish you stack new work on a dual-parent `@` (`jj new -d main -d
upstream`, i.e. both tips as parents). If you `describe` that `@`, it becomes a
described **merge** that keeps both parents — including the fork parent — instead
of a clean upstream-side commit.

Safe pattern: commit upstream-side work while `@` has a single upstream-chain
parent (`jj new upstream-tip` first), then restore the dual-parent `@` with
`jj new -d main -d upstream`. Proven by
`test_describing_a_dual_parent_working_copy_keeps_both_parents`: the dual-parent
`@` has two parents, describing it keeps two, and a single-parent `@` has one.
