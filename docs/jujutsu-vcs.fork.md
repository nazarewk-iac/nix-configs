---
type: Reference
description: Human-readable overview of the jj fork revset aliases and the common fork-management use cases they cover.
timestamp: 2026-08-03T16:00:00+02:00
---

# Jujutsu (jj) VCS — Fork Workflow

> **Agent note:** This file is installed as `.claude/rules/jujutsu-vcs.fork.md` in a repo with
> `kdn.jj.fork.enable = true`. See [jujutsu-vcs.md](jujutsu-vcs.md) for the fork-agnostic base
> patterns this extends, and [flake-update.fork.md](flake-update.fork.md) for the concrete
> update workflow that uses this topology.
>
> **Run `jj fork-help` to print this file** from any shell in the repo.

## Topology

A private fork remote sits next to the public upstream remote. `main` is a single merge of both
lines. `@` sits on top of both `main` and `upstream`:

```
main@<upstream-remote> ──► ...upstream-chain... ──► upstream
                       \                                    \
                        \────────────────── main ──────────► @
                       /
main@<fork-remote> ──► ...fork-chain...
```

`upstream` and `main` are **bookmark** names in this repo's convention. `upstream` tracks the
public chain tip. `main` tracks the merge of both chains. Both are distinct from the **remote**
names (`kdn.jj.upstream.remote` / `kdn.jj.fork.remote`), which may differ.

## Single-purpose merge

This repo keeps **one** merge and rebases it proactively. Every local change stays on top of the
upstream tip. This avoids a second merge line: you do not maintain one merge to pull safe changes
into the fork main and a separate merge to pull the upstream main into the working copies. One
merge, always rebased forward onto the newest upstream.

## Named revset aliases

The `kdn.jj.fork` devenv slot defines these aliases. Prefer the named alias over an inline revset
so the common checks stay short. Use `jj log -r '<alias>'` to list any set.

| Alias                   | Meaning |
|-------------------------|---------|
| `tree-merge`            | The merge commit `@` sits on. The anchor between local work above and history below. |
| `upstream-incoming`     | Upstream commits fetched but not yet in the local tree. |
| `upstream-incoming-tip` | The newest upstream-incoming commit. The rebase destination. |
| `to-rebase`             | All local described work above the merge. The changes to relocate onto new upstream. |
| `upstream-safe`         | The content-clean subset of `to-rebase` (safe to push upstream). |
| `fork-leaked`           | Local work above the merge that carries fork-sensitive content. |
| `merge-frozen`          | Non-empty when the merge is already pushed or immutable. |
| `upstream-local`        | Local upstream-side commits below the merge, not yet on the public remote (the pre-merge chain). |
| `pushed`                | Changes reachable from any remote bookmark. |
| `pushed-fork`           | Changes reachable from a fork remote bookmark. |
| `pushed-upstream`       | Changes reachable from an upstream remote bookmark. |
| `fork`                  | Fork-tagged changes (topology plus content). |
| `fork-direct`           | Fork-sensitive content predicate (content only). |
| `upstream-chain`        | Named non-empty commits on the upstream side. |
| `fork-chain`            | Named non-empty commits on the fork side. |
| `upstream-tip`          | Latest commit in the upstream chain. |
| `fork-tip`              | Latest commit in the fork chain. |

## Common use cases

### 1. What is on top of the merge that should not be there?

```bash
jj log -r 'to-rebase'     # all local work above the merge
jj log -r 'fork-leaked'   # the subset that carries fork-sensitive content
```

`fork-leaked` non-empty means a change would fail an upstream push. Rename the sensitive term or
keep the change fork-side.

### 2. Do I need a new merge, or can I reuse the current one?

```bash
jj log -r 'merge-frozen'    # empty → reuse the merge; non-empty → build a NEW merge
```

Empty means the merge is still local and mutable. Rebase it in place. Non-empty means it is
already pushed or immutable. Build a new merge instead (see use case 5).

### 3. What new upstream commits are not integrated yet?

```bash
jj git fetch --remote=<upstream-remote> --remote=<fork-remote>
jj log -r 'upstream-incoming'
```

### 4. Pull upstream in — rebase the local upstream chain onto the new upstream

This is the single-purpose merge in action. The local upstream-side commits below the merge
(`upstream-local`) form a chain that diverged from the public tip. Rebase the **root** of that
chain onto the new upstream tip. The chain, the merge, `to-rebase`, and `@` all follow as
descendants, and the merge keeps its fork parent:

```bash
jj rebase -s 'roots(upstream-local)' -d 'upstream-incoming-tip'
jj bookmark set upstream -r 'upstream-incoming-tip'
jj bookmark set main -r 'tree-merge'
jj new -d main -d upstream   # fresh empty @ on both parents
devenv build shell           # confirm the pulled-in upstream still builds
```

> **Do NOT** rebase `tree-merge` directly with `-d upstream-incoming-tip -d main@<fork-remote>`.
> That replaces the merge parents and orphans the pre-merge `upstream-local` chain out of the
> merge ancestry. Rebase `roots(upstream-local)` so the whole chain moves and the merge keeps its
> original parents.

### 5. Build a new merge (when `merge-frozen` is non-empty)

Constructing the `main` merge topology is a legitimate, structural use of `jj new` — not a work
checkpoint:

```bash
jj new 'fork-tip' 'upstream-incoming-tip' -m 'chore(merge): merge in upstream'
jj bookmark set main -r @
jj new -d main -d upstream
```

### 6. Verify before you declare done

```bash
# no fork content leaked into the local work:
jj log -r 'fork-leaked'         # must be empty

# upstream has exactly one parent (not a stray merge):
jj log -r 'parents(upstream)' --no-graph -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'

# all upstream is integrated:
jj log -r 'upstream-incoming'   # must be empty after the rebase

# the build passes:
devenv build shell
```

When `upstream` has more than one parent, rebase it onto just the upstream chain tip:

```bash
jj rebase --revision upstream --destination 'upstream-tip'
jj bookmark set upstream -r upstream
```

## Warnings

> `jj describe` on a multi-parent `@` (when `@` sits on top of both `main` and `upstream`) creates
> a merge commit that inherits all parents, including the fork ones. Always commit upstream-side
> work while `@` has a single upstream-chain parent. Then restore the multi-parent `@` with
> `jj new -d main -d upstream`.

See [flake-update.fork.md](flake-update.fork.md) for the concrete update workflow that feeds into
this topology.
