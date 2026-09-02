---
type: Reference
description: The fork revset aliases, the reference topology that exercises them, and the tests that prove each alias resolves to the right change set.
timestamp: 2026-09-03T00:00:00+02:00
---

# Fork revset aliases — reference topology and proofs

This doc explains the fork revset aliases and the graph the tests build to check
them. The executable proof is `test_revsets.py`; the builder is
`topologies.build_reference`. This is the detailed layer — the base
`docs/jujutsu-vcs.md` and `docs/jujutsu-vcs.fork.md` hold the short golden paths.

## Reference topology

`build_reference` makes real bare `upstream` and `fork` remotes and this graph
(frozen: the merge is pushed to the fork remote):

```
A ── P1 ── P2                 public upstream line; main@upstream = P2 (fetched, not merged)
│
├── U1 ── U2                  local upstream line; upstream, upstream@fork = U2
│           \
│            M ── L1 ── L2 ── L3 ── @   M = the merge; main, main@fork = M
│           /
└── F1                        fork-sensitive
```

- `P1`, `P2` are public upstream commits, fetched but not merged into `@`.
- `U1`, `U2` are the local upstream chain below the merge.
- `F1` carries fork-sensitive content (its path matches a denied pattern).
- `M` is the one merge. `L1`/`L3` are generic; `L2` is fork-sensitive.
- `@` is the resting working copy on `L3`.

Content sensitivity uses placeholder patterns (`PLACEHOLDER-SENSITIVE`,
`PLACEHOLDER-PREFIX-`), never a real sensitive term.

## Alias -> expected set -> test

| Alias | Expected set | Test |
|---|---|---|
| `tree-merge` | `{M}` | `test_tree_merge_is_the_single_merge` |
| `upstream-incoming` | `{P1, P2}` | `test_upstream_incoming_is_fetched_but_unmerged` |
| `upstream-incoming-tip` | `{P2}` | same |
| `to-rebase` | `{L1, L2, L3}` | `test_to_rebase_is_local_described_work_above_the_merge` |
| `fork-direct` | `{F1, L2}` | `test_fork_direct_matches_content_only` |
| `upstream-safe` | `{L1, L3}` | `test_upstream_safe_is_the_clean_subset` |
| `fork-leaked` | `{L2}` | `test_fork_leaked_is_sensitive_work_above_the_merge` |
| `upstream-local` | `{U1, U2}` | `test_upstream_local_is_the_pre_merge_upstream_chain` |
| `pushed` (minus `root()`) | `{A, P1, P2, U1, U2, F1, M}` | `test_pushed_reachability` |
| `pushed-fork` (minus `root()`) | `{A, U1, U2, F1, M}` | same |
| `pushed-upstream` (minus `root()`) | `{A, P1, P2}` | same |
| `upstream-tip` | `{U2}` | `test_tips_resolve_by_time` |
| `fork-tip` | `{L3}` | same |
| `fork-chain` | `{F1, M, L1, L2, L3}` | `test_chains` |
| `upstream-chain` | `{A, P1, P2, U1, U2}` | same |
| `merge-frozen` (pushed) | `{M}` | `test_merge_frozen_when_pushed` |
| `merge-frozen` (unpushed) | `{}` | `test_merge_mutable_when_unpushed` |

## The `~fork` trap (caveat)

`fork` tags every descendant of `main@fork` (the merge), so `to-rebase & ~fork`
is empty — it drops even the content-clean local changes `L1` and `L3`. So
`upstream-safe` subtracts only the content predicate `~fork-direct`, not `~fork`.
`test_fork_trap_drops_safe_local_changes` proves both: `to-rebase & ~fork` is
empty while `to-rebase & ~fork-direct` is `{L1, L3}`.

## Determinism

`upstream-tip`/`fork-tip` use `latest()`, which picks by commit time. The builder
creates nodes in a fixed order and the harness stamps each with an increasing
time, so the tips are stable. `fork-tip` is `L3` (the newest fork-chain commit),
not `F1`, once local work exists.

## The virtual root

`pushed`, `pushed-fork`, and `pushed-upstream` are `::remote_bookmarks(...)`, so
they also reach jj's virtual root commit (`root()`). The tests intersect with
`~root()` to assert the meaningful set.
