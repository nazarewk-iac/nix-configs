---
type: Reference
description: Long-lived-branch mode of operation and a cross-check against the fork golden paths, proven by test_branch.py.
timestamp: 2026-09-03T00:00:00+02:00
---

# Long-lived-branch mode

A long-lived branch tracks a shared trunk on one remote `origin`. It is the fork
model minus the fork remote and the content split. The executable proof is
`test_branch.py`; the fixture is `topologies.build_branch_tree` (no fork slot).

## Topology

```
A ── T1 ── T2        trunk on origin; main@origin = T2 (pushed → immutable)
│
└── B1 ── B2 ── @    long-lived branch off A (local, mutable); @ empty on the branch tip
```

Branch-mode revset aliases (flag overlays, the direct analogs of the fork ones):

| Alias | Definition | Fork analog |
|---|---|---|
| `trunk()` | `main@origin` | `trunk() = main@<fork-remote>` |
| `trunk-incoming` | `@..main@origin` | `upstream-incoming` |
| `trunk-incoming-tip` | `main@origin` | `upstream-incoming-tip` |
| `branch` | `trunk()..@ & ~description("")` | `to-rebase` |
| `branch-tip` | `heads(branch)` | `fork-tip` |

So `trunk-incoming` = `{T1, T2}`, `branch` = `{B1, B2}`; the pushed trunk is
immutable, the branch is mutable.

## Golden paths

- **Add a change to the branch** — a plain split on top; no dual-parent merge:
  ```bash
  jj split -m 'feat: ...' -- <files>
  ```
  Proven by `test_add_change_to_branch_is_a_plain_split` (single parent, becomes
  `branch-tip`).
- **Integrate new trunk — rebase (linear):**
  ```bash
  jj rebase -s 'roots(branch)' -d 'trunk-incoming-tip'
  ```
  The branch lands on the new trunk tip, `trunk-incoming` empties, the pushed
  trunk keeps its commit id, and no merge appears
  (`test_integrate_trunk_by_rebase`).
- **Integrate new trunk — merge (fork-shaped):**
  ```bash
  jj new branch-tip trunk-incoming-tip -m 'merge trunk'
  ```
  A merge of the branch tip and the new trunk; `trunk-incoming` empties; the old
  trunk stays an ancestor (`test_integrate_trunk_by_merge`).
- **Hazard — never rewrite the pushed trunk.** `jj describe -r <pushed trunk>`
  fails with the immutable error; build forward instead
  (`test_cannot_rewrite_a_pushed_trunk_commit`).

## Upstream-only — no branch, no fork

The simplest case has no long-lived branch. Local work sits on the trunk, and a
fetch plus a rebase onto the fetched tip keeps it current
(`test_upstream_only_fetch_then_rebase_onto_tip`; models `docs/jujutsu-vcs.md`
"Without a fork"):

```bash
jj git fetch --remote=<remote>
jj rebase -s <work> -d main@<remote>    # or -d <upstream-bookmark>
```

The fetch advances `main@<remote>`. The rebase re-parents the local work onto it.
No merge, no content split.

## Fork <-> branch cross-check

| Operation | Fork golden path | Branch analog | Class |
|---|---|---|---|
| Add a change | placement by content (`jj new -B @` + `jj split -A upstream-tip -B fork-tip`) | plain `jj split -m … -- <files>` | DIFFERS — the fork routes by content into one merge; a branch just appends |
| Integrate new trunk (mutable) | `jj rebase -s 'roots(upstream-local)' -d upstream-incoming-tip` | `jj rebase -s 'roots(branch)' -d trunk-incoming-tip` | SHARED |
| Integrate new trunk (frozen/merge) | `jj new fork-tip upstream-incoming-tip -m …` | `jj new branch-tip trunk-incoming-tip -m …` | SHARED |
| Rewrite a pushed commit | forbidden — build forward | forbidden — build forward | SHARED |
| `latest()` / `*-tip` timestamp rule | applies | applies | SHARED |
| Dual-parent `@`, never `describe` it | applies (single-merge model) | applies only in merge-style integration | SHARED (merge style) / N/A (rebase style) |
| Make X an ancestor of Y | `jj rebase -s Y -d X -d P` | same | SHARED |
| Day-to-day (inspect, split, squash/`absorb`, amend, restructure, recover, bookmarks, conflicts) | branch-agnostic | identical | SHARED |
| De-leak / `fork-direct` / `fork-leaked` / `jj fork-audit` | content-sensitivity routing | — | FORK-ONLY |
| `jj sync-remotes` (advance `main`+`upstream`, push both) | two-remote bookmark dance | a branch pushes one bookmark to `origin` | FORK-ONLY / DIFFERS |

## Conclusion — "~90% the same" confirmed

The mechanics are SHARED: trunk integration (both rebase and merge shapes), the
immutable-pushed hazard, the `latest()`/timestamp rule, X→Y, and every day-to-day
operation. The branch aliases are one-to-one renames of the fork aliases
(`trunk-incoming` ≡ `upstream-incoming`, `branch` ≡ `to-rebase`, `branch-tip` ≡
`fork-tip`).

The genuinely FORK-ONLY part is the **content-sensitivity layer** —
`fork-direct`/`fork-leaked`, de-leak, `jj fork-audit` — and the **two-remote
sync** (`sync-remotes`). The fork's placement-by-content recipe is a consequence
of that layer plus the single-merge choice; a plain branch appends instead. A
merge-style branch reuses the fork's merge recipe verbatim; a rebase-style branch
does not need a merge at all.

So a fork is a long-lived (merge-style) branch **plus** a content-routing and a
second-remote layer. The general branch operations already live in
`docs/jujutsu-vcs.md`; only that extra layer is fork-specific and lives in
`docs/jujutsu-vcs.fork.md`.
