---
type: Reference
description: The jj fork topology, its revset aliases, and the common fork-management use cases they cover.
timestamp: 2026-08-04T00:00:00+02:00
---

# Jujutsu (jj) VCS — Fork Workflow

**TL;DR.** A private fork remote sits next to a public upstream remote. One merge commit (`main`)
joins both lines. `@` sits on top of both `main` and `upstream`. You rebase that one merge forward
onto new upstream. Split every local change by **content sensitivity**: generic work — including
the task docs that record it — goes on the upstream chain; only sensitive content stays fork-side.

> **Agent note:** This file is installed as `.claude/rules/jujutsu-vcs.fork.md` in a repo with
> `kdn.jj.fork.enable = true`. See [jujutsu-vcs.md](jujutsu-vcs.md) for the fork-agnostic base
> patterns this extends, and [flake-update.fork.md](flake-update.fork.md) for the concrete update
> workflow that uses this topology.
>
> **Run `jj fork-help` to read this file** from any shell in the repo. It opens a pager when
> interactive (`$PAGER`, then `less`, then `cat`), and prints plain text when piped.

## Overview

The fork keeps **one** merge and rebases it proactively, so every local change stays on top of the
newest upstream. Named revset aliases make the common checks short: which local work is unsafe to
push, whether the merge can be reused or must be rebuilt, and what upstream is not integrated yet.
The use cases below are ordered from "what is my state" to "change the graph".

## Contents

- [Topology](#topology) — the shape of the graph
- [Single-purpose merge](#single-purpose-merge) — why there is only one merge
- [Content sensitivity, not task boundaries](#content-sensitivity-not-task-boundaries) — how to
  split a change
- [Named revset aliases](#named-revset-aliases) — the alias table
- [Common use cases](#common-use-cases) — step-by-step recipes
  1. [What is on top of the merge that should not be there?](#1-what-is-on-top-of-the-merge-that-should-not-be-there)
  2. [Do I need a new merge, or can I reuse the current one?](#2-do-i-need-a-new-merge-or-can-i-reuse-the-current-one)
  3. [What new upstream commits are not integrated yet?](#3-what-new-upstream-commits-are-not-integrated-yet)
  4. [Pull upstream in — rebase the local upstream chain](#4-pull-upstream-in--rebase-the-local-upstream-chain-onto-the-new-upstream)
  5. [Build a new merge (the default when the merge is frozen)](#5-build-a-new-merge-the-default-when-the-merge-is-frozen)
  6. [Make X an ancestor of Y without breaking the topology](#6-make-x-an-ancestor-of-y-without-breaking-the-topology)
  7. [Verify before you declare done](#7-verify-before-you-declare-done)
- [Warnings](#warnings)

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

## Content sensitivity, not task boundaries

Split a change by **what the content is**, not by which task produced it. The predicate is
`fork-direct` — the sensitive-content check (see the alias table). Route each part by that:

- **Generic content** (tools, conventions, shared modules, and the **task docs that record the
  work as done**) goes on the **upstream chain**. Upstream then shows the task is complete.
- **Sensitive content** (employer hosts, internal names, credentials) stays **fork-side**, above
  the merge.

A task that produces both is normal. Move the generic parts down onto the upstream chain and keep
only the sensitive parts on the fork side. Write the task docs employer-neutral so they can live
upstream. `jj split -m 'msg' -- <paths>` and `jj squash --from <src> --into <dst> -- <paths>` move
content between commits without an editor.

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

### 5. Build a new merge (the default when the merge is frozen)

When `merge-frozen` is non-empty, this is the **default** — not an edge case. A frozen merge is
already published, so you build a new one rather than rewrite it. Constructing the `main` merge
topology is a legitimate, structural use of `jj new` — not a work checkpoint:

```bash
jj new 'fork-tip' 'upstream-incoming-tip' -m 'chore(merge): merge in upstream'
jj bookmark set main -r @
jj new -d main -d upstream
```

### 6. Make X an ancestor of Y without breaking the topology

Use this when a fork-side change Y depends on a generic change X (for example, host wiring Y that
uses a slot defined in X), but Y does not yet have X in its ancestry. Add X as a second parent of
Y and keep Y's existing parent. `jj rebase -s` moves Y (and its descendants) onto the given
destinations, and multiple `-d` flags make Y a merge of all of them:

```bash
jj rebase -s Y -d X -d <Y-existing-parent>
```

Concrete example — make the slot commit `X` an ancestor of the host-wiring commit `Y`, while `Y`
keeps its old merge parent `P`:

```bash
jj rebase -s Y -d X -d P
```

`Y` becomes a merge of `X` and `P`, so the dependency of `Y` on `X` now shows in the graph. The
descendants of `Y` (the merge, `@`) follow and keep their shape. Confirm afterward:

```bash
jj log -r 'parents(Y)'      # must list both X and P
jj log -r 'fork-leaked'     # must stay empty
```

### 7. Verify before you declare done

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
