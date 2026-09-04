---
type: Reference
description: The jj fork topology, its revset aliases, and the verified fork-management golden paths.
timestamp: 2026-09-02T00:00:00+02:00
---

# Jujutsu (jj) VCS — Fork Workflow

**TL;DR.** A fork is a long-lived merge-style branch (see
[jujutsu-vcs.md](jujutsu-vcs.md#branch-workflows)) plus a content-routing and a second-remote
layer. This file documents only those extras. A private fork remote sits next to a public upstream
remote. One merge commit (`main`) joins both lines. `@` is a plain empty change with a single
parent — the merge. Split every local change by **content sensitivity**. Generic work goes on the
upstream chain. The task docs that record the work go there too. Only sensitive content stays
fork-side.

> **Agent note:** This file is installed as `.claude/rules/jujutsu-vcs.fork.md` in a repo with
> `kdn.jj.fork.enable = true`. For the fork-agnostic day-to-day golden paths (split, squash,
> absorb, amend, rebase, restore, bookmarks, conflicts), see
> [jujutsu-vcs.md](jujutsu-vcs.md#day-to-day-golden-paths). For the shared branch workflows
> (integrate trunk, hazards, X→Y), see [jujutsu-vcs.md](jujutsu-vcs.md#branch-workflows). This file
> does not repeat either. For the concrete update workflow, see
> [flake-update.fork.md](flake-update.fork.md).
>
> Every golden-path recipe below is proven by a test under `checks/jj-experiments/` (linked
> inline). The `jj fork-audit` tool command is the exception — it is verified by use, not by the
> pytest harness. Run `jj fork-help` to read this file from any shell in the repo.

## Topology

`main` is a single merge of both lines. `@` is a plain empty change with a single parent — the
merge:

```
main@<upstream-remote> ──► ...upstream-chain... ──► upstream
                       \                                    \
                        \────────────────── main ──────────► @
                       /
main@<fork-remote> ──► ...fork-chain...
```

`@` reaches `upstream` through the merge, not by a direct edge. This single-parent `@` is the
resting shape you review from. `upstream` and `main` are **bookmark** names; they differ from the
**remote** names (`kdn.jj.upstream.remote` / `kdn.jj.fork.remote`).

**Dual-parent `@`, one exception.** Right after you publish (`jj sync-remotes`), you stack new work
with `jj new -d main -d upstream` (equivalently `jj new fork-tip upstream-tip`). That gives `@`
both tips as parents and restores the state `nix run '.#update'` expects. This is the only place a
dual-parent `@` is correct. Never `jj describe` a dual-parent `@` — it becomes a merge that
inherits the fork parent (see [Hazards](#hazards)).

## Single-purpose merge

This repo keeps **one** merge and moves it forward. Every local change stays on top of the newest
upstream. You do not keep a second merge line. When the merge is still local it is rebased in
place; when it is published it is immutable, so you build a new merge forward instead.

## Content sensitivity, not task boundaries

Split a change by **what the content is**, not by which task produced it. The predicate is
`fork-direct` (see the alias table).

- **Generic content** (tools, conventions, shared modules, and the task docs that record the work)
  goes on the **upstream chain**.
- **Sensitive content** (private hosts, internal names, credentials) stays **fork-side**.

`jj fork-audit` lists any fork-sensitive content in your local commits, at line level (file paths,
diff lines, and messages that match the denied patterns). Run it before you treat a commit as
upstream-safe. A task that produces both kinds of content is normal — route each part.

## Named revset aliases

The `kdn.jj.fork` devenv slot defines these. Prefer the named alias over an inline revset. Their
behavior is verified in [test_revsets.md](../checks/jj-experiments/test_revsets.md).

| Alias                   | Meaning |
|-------------------------|---------|
| `tree-merge`            | The merge commit `@` sits on. The anchor between local work above and history below. |
| `upstream-incoming`     | Upstream commits fetched but not yet in the local tree. |
| `upstream-incoming-tip` | The public remote tip (`main@<upstream-remote>`). The integration destination. |
| `to-rebase`             | All local described work above the merge. |
| `upstream-safe`         | The content-clean subset of `to-rebase` (safe to push upstream). |
| `fork-leaked`           | Local work above the merge that carries fork-sensitive content. |
| `merge-frozen`          | Non-empty when the merge is already pushed or immutable. |
| `upstream-local`        | Local upstream-side commits below the merge, not yet on the public remote. |
| `pushed` / `pushed-fork` / `pushed-upstream` | Changes reachable from a (fork/upstream) remote bookmark. |
| `fork` / `fork-direct`  | Fork-tagged changes (topology + content) / the content-only predicate. |
| `upstream-chain` / `fork-chain` | Named non-empty commits on the upstream / fork side. |
| `upstream-tip` / `fork-tip` | Latest commit in the upstream / fork chain (by commit time). |

## State checks

```bash
jj fork-audit                    # fork-sensitive content in local commits, at line level
jj log -r 'fork-leaked'          # upstream-destined work carrying fork content — must be empty
jj log -r 'merge-frozen'         # empty → the merge is mutable; non-empty → build forward
jj git fetch --all-remotes; jj log -r 'upstream-incoming'   # unmerged upstream
```

To read the full topology of what a fetch brought in — arrived commits, your divergence, the merge
base, and `jj op show`/`jj op diff` — see
[Inspect what you fetched](jujutsu-vcs.md#inspect-what-you-fetched).

## Golden paths

### Place a generic (upstream) change — [test_placement.md](../checks/jj-experiments/test_placement.md)

Two commands that work on a frozen and a mutable tree:

```bash
# generic content in @, then:
jj new --no-edit -B @ -m 'chore(upstream): merge'
jj split -A upstream-tip -B fork-tip -m 'feat(...): generic' -- <generic files>
```

Command 1 inserts a fresh mutable commit above the current merge; it becomes the new merge once
command 2 adds the upstream parent. Command 2 grafts the generic commit onto `upstream-tip` and
into that merge. When a mutable merge already exists, the single
`jj split -A upstream-tip -B fork-tip` is enough. **Frozen-vs-mutable rule:** `-B fork-tip`
re-parents the fork tip, so it needs that tip **mutable**; command 1 manufactures a mutable merge
on a frozen tree. The old frozen merge stays an ancestor — the precondition `jj sync-remotes`
fast-forwards on.

### Place a fork-sensitive change — [test_placement.md](../checks/jj-experiments/test_placement.md)

- **Leaf tweak** (a one-off host tweak): `jj split -m 'feat(fork): ...' -- <sensitive files>`. It
  stays above the merge on the fork chain and becomes `fork-tip`; `jj sync-remotes` pushes it to
  `main@<fork-remote>`. `fork-leaked` lists it — for a leaf that is informational, not a gate.
- **Durable fork-base change** (folds into the merge):
  ```bash
  jj split -A fork-tip -m 'feat(fork): base wiring' -- <sensitive files>
  jj new upstream-tip fork-tip -m 'chore(upstream): merge'
  jj new                                   # empty @ on top
  ```
- **Mixed `@`** (generic + sensitive): route the generic part with the upstream recipe, then carve
  the sensitive remainder as a leaf.

### Pull upstream in, and make X an ancestor of Y

These are the shared branch workflows — see
[jujutsu-vcs.md § Branch workflows](jujutsu-vcs.md#branch-workflows) (proof:
[test_rebase.md](../checks/jj-experiments/test_rebase.md)). The fork's trunk is the upstream chain,
so its trunk aliases are `upstream-incoming-tip` and `upstream-local`: on a frozen merge build
forward with `jj new fork-tip upstream-incoming-tip`; on a mutable merge rebase with
`jj rebase -s 'roots(upstream-local)' -d 'upstream-incoming-tip'`. Make X an ancestor of Y with
`jj rebase -s Y -d X -d <Y-existing-parent>`, unchanged.

### De-leak an upstream-destined commit — [test_deleak.md](../checks/jj-experiments/test_deleak.md)

A commit on the upstream side carries fork content (`fork-leaked` lists it):

- **Split** the sensitive file out: `jj split -m 'feat(fork): ...' -- <sensitive file>` — the
  generic remainder is then `upstream-safe`.
- **Reword** when only the message matches a denied pattern: `jj describe -r <id> -m '<neutral>'`.

## Hazards

The hazards are shared — see [jujutsu-vcs.md § Branch workflows](jujutsu-vcs.md#branch-workflows)
(proof: [test_hazards.md](../checks/jj-experiments/test_hazards.md)): never rewrite a
pushed/immutable commit (build forward), never `jj describe` a dual-parent `@` (see
[Topology](#topology)), and the `upstream-tip`/`fork-tip` aliases follow commit time, not graph
position.

## Verify before you declare done

```bash
jj log -r 'fork-leaked'          # must be empty (or only intended fork leaves)
jj log -r 'upstream-incoming'    # must be empty after a pull
devenv build shell               # the build passes
```

Bookmarks are moved by `jj sync-remotes`, not by hand. See
[flake-update.fork.md](flake-update.fork.md) for the concrete update workflow that uses this
topology.
