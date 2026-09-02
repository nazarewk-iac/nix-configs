---
type: Reference
description: Advanced agent-centric analysis idioms for the fork topology, proven by test_advanced.py.
timestamp: 2026-09-02T00:00:00+02:00
---

# Advanced / agent-centric idioms

Read-only revset and template idioms an agent uses to reason about the graph
before it changes anything. The executable proof is `test_advanced.py`, run over
`topologies.build_reference` (labels A, P1, P2, U1, U2, F1, M, L1, L2, L3, `@`).

## Reachability membership as a verdict

Intersect a change with `::<target>` and read emptiness as the answer
(`test_reachability_membership_as_a_verdict`):

```bash
jj log -r '<rev> & ::main@fork'   # non-empty → <rev> is published on the fork
jj log -r '<rev> & ::@'           # non-empty → integrated (ancestor of @); empty → diverged/incoming
```

- `A & ::main@fork` = `{A}` (published).
- `U2 & ::@` = `{U2}` (integrated).
- `P2 & ::@` = `{}` (not integrated — new upstream, or diverged).

## Reusable-vs-frozen merge check

`tree-merge & (immutable() | pushed)` — non-empty means the merge is published,
so build a new merge instead of rewriting it. On the frozen reference it is
`{M}` (`test_reusable_vs_frozen_merge_check`).

## roots() of a subgraph

`roots(<set>)` gives the base commit(s) to feed a `rebase -s`
(`test_roots_of_a_subgraph`): `roots(to-rebase)` = `{L1}`,
`roots(upstream-local)` = `{U1}`.

## Scoping sets

`test_scoping_sets`:

- `mutable() & ~root()` = `{L1, L2, L3, @}` — the local work above the frozen
  merge; the pushed history is immutable and excluded. This is the set you may
  rewrite.
- `mine() & ~root()` = every harness-authored commit.
- `conflicts()` = `{}` on a clean tree (a non-empty result gates further work).

## files() history

`::@ & files("<path>")` returns the commits that touched a path
(`test_files_history`): `modules/shared.nix` → `{U1, U2}`.

## Parent introspection

Render a merge's parents inline to confirm its two sides
(`test_parent_introspection_template`):

```bash
jj log -r 'tree-merge' -T 'parents.map(|p| p.change_id().shortest(12)).join(",")'
```

For the reference merge this is exactly the upstream tip `U2` and the fork commit
`F1`.

## Identity probe

`X ~ Y` is empty exactly when `X` is contained in `Y`; two single revisions are
identical when both differences are empty (`test_identity_probe`):

- `U2 ~ U2` = `{}` (same), `U2 ~ U1` = `{U2}` (different).
- `latest(A..U2) ~ U2` = `{}` ⇒ `U2` is the newest commit in the range (nothing
  sits above it) — the "nothing diverged / is this the head" check.

## `jj file show` as a cross-revision diff engine

`jj file show -r <rev> <path>` reads a file at any revision with no checkout — the
safe substitute for `jj edit` + read. Pipe two of them through `diff`/`jq` to
compare a file between revisions (`test_file_show_as_a_cross_revision_diff_engine`:
`modules/shared.nix` is `# u1` at `U1` and `# u2` at `U2`).

## Description-filtered ancestry

Select ancestors of `@` by a description keyword, and drop empties
(`test_description_filtered_ancestry`):

```bash
jj log -r '::@ & description(substring:"<keyword>") & ~empty()'
```

- `substring:` sets a substring match. A bare `description("x")` is an exact match
  and rarely what you want.
- `~empty()` drops the empty working copy `@` and any other no-change commit.
- On the reference graph, `description(substring:"generic")` = `{L1, L3}`.

## Op-log forensics and restore

The operation log records every mutation. `jj op restore` rewinds the repo to any
recorded operation (`test_op_log_forensics_and_restore`):

```bash
jj op log -T 'id.short() ++ " " ++ time.end().ago()'   # find the target operation
jj op restore <operation-id>                            # rewind the repo to it
```

- Nothing is truly lost. An abandon, a bad rebase, or a wrong squash reverses with
  one `op restore`.
- The test abandons a leaf commit, confirms the op log still records the
  pre-abandon operation, then restores it and the commit returns.
