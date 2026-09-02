---
type: Task
description: Define and verify the full matrix of jj change-placement cases in the fork topology, build a 3-repo pytest harness, and rewrite the skill examples.
status: done
authored_by: agent
timestamp: 2026-09-02T00:00:00+02:00
---

# jj fork change-placement — case matrix, least-command recipes, test harness, skill rewrite

## Problem

The skill and the fork docs give inconsistent guidance on `jj split` placement. `-A`/`-B` were
presented as the default, but they **re-parent** the target's descendants and therefore **fail
on a frozen (pushed) tree-merge** — which is the usual state. We need one coherent, verified
reference: for every combination of tree state and change kind, the shortest correct command
sequence, proven by an automated harness, and mirrored in short skill examples.

## Goal

- Define the full case matrix (below) and the shortest (least-command) correct sequence for each.
- Identify the missing cases (candidates below) and settle them.
- Build a 3-repo pytest harness (local, upstream, fork) with isolated devenv activation, and test
  every case.
- Rewrite and shorten the skill and fork-doc examples to match the verified matrix.

## Background context (so the future session needs no re-research)

Fork topology and alias definitions: `docs/jujutsu-vcs.fork.md` (Topology + alias table); alias
source in `modules/slots/jj/fork/default.nix` (`revset-aliases`). Exact expressions:

| Alias | Expression |
|---|---|
| `trunk()` | `main@<fork-remote>` |
| `tree-merge` | `heads(::@ & merges())` |
| `upstream-chain` | `~description("") & ~fork` |
| `fork-chain` | `~description("") & fork` |
| `upstream-tip` | `latest(upstream-chain)` |
| `fork-tip` | `latest(fork-chain)` |
| `to-rebase` | `tree-merge..@ & ~description("")` |
| `upstream-safe` | `to-rebase & ~fork-direct` |
| `fork-leaked` | `to-rebase & fork-direct` |
| `merge-frozen` | `tree-merge & (immutable() \| pushed)` |
| `pushed` | `::remote_bookmarks()` |
| `upstream-local` | `pushed-upstream..(::tree-merge & ~fork)` |
| `fork-direct` | content predicate (paths/diff/description matching the configured denied patterns) |

Flag semantics (jj 0.44.0, verified with `jj split --help`):

- `-A`/`--insert-after`, `-B`/`--insert-before`: **re-parent** the target's descendants onto the
  new commit. Repeat to make a merge. Valid **only when the affected merge is mutable**.
- `-d`/`-o`/`--destination`: set **only** the new commit's parents; **no re-parent**. `-o` is an
  alias of `--destination`. Safe next to frozen tips.

Existing authoritative recipes (reconcile, do not duplicate):

- `docs/flake-update.fork.md` § "Post-update fixes":
  - **tips NOT pushed (mutable):** `jj split --insert-after upstream-tip --insert-before fork-tip
    -m '…' -- <files>`.
  - **tips ALREADY pushed (frozen):** `jj describe …` → `jj rebase -r @ -d upstream-tip` →
    `jj new fork-tip <fix> -m 'chore(fork): merge …'` → `jj new fork-tip`.
  - **fork-specific fix:** plain `jj split -m '…' -- <files>` on the fork side.
- `docs/jujutsu-vcs.fork.md` use cases 4 (pull upstream), 5 (build new merge when frozen),
  6 (make X an ancestor of Y: `jj rebase -s Y -d X -d P`).

Bookmarks/push: the user runs `jj sync-remotes` (defined in `modules/slots/jj/fork/default.nix`).
It only advances `main`→`fork-tip`, `upstream`→`upstream-tip`, then pushes. It builds **no** merge.
Never push in-agent; never rewrite a pushed/immutable commit.

Content routing: generic content → upstream chain; fork-sensitive content (matching the
configured denied patterns) → fork side.
`fork-leaked` must stay empty on the upstream side.

## Case matrix to define and verify (shortest sequence for each)

"Immutable tree" = `merge-frozen` non-empty (tips pushed). "Mutable tree" = `merge-frozen` empty.

Immutable tree (build forward; no rewrite of pushed history):
1. upstream (generic) change
2. fork (sensitive) change
3. mixed upstream + fork change in `@` (split by content, place each part)
4. make the tree mutable via `jj new -m 'chore(upstream): merge' upstream-tip fork-tip`, then act
5. make the tree mutable by adding a fork change (a `jj split` variant that yields a new mutable
   fork-tip merge)

Mutable tree (splice/rewrite allowed):
6. upstream change
7. fork change
8. mixed upstream + fork change
9. squash updates into an existing (mutable) commit

Candidate missing cases (confirm/add):
- fork change that **depends on a new upstream commit** not yet in its ancestry (use case 6, X→Y)
  — both immutable and mutable variants.
- a change that is **partly generic and partly sensitive** (split hunks, or reword to
  remove sensitive content) — `fork-leaked` handling.
- amend/reword needed on an **already-pushed** commit (expected answer: forbidden; build-forward a
  correction instead).
- **multiple stacked upstream commits** (ordering; repeated build-forward vs one merge).
- abandon/drop a not-yet-pushed change.
- **pull-in new upstream** while local generic + fork work sits above the merge (interaction of
  use case 4 with `to-rebase`).
- squash into an **immutable** commit (forbidden; build-forward instead).

For each case, record: the shortest correct sequence, a topology sketch, and the post-conditions
(`fork-leaked` empty; old tips stay ancestors so `jj sync-remotes` fast-forwards; no force-push).

## Test harness (to build)

A pytest suite with **three real repos** — local/working, upstream remote, fork remote — plus
isolated devenv activation, so the repo-scoped jj revset aliases and `jj sync-remotes` /
`jj fork-help` exist for a throwaway repo.

Open items for the future session (locate; do not assume):
- where existing tests/checks live (search `packages/`, `checks`, `modules/slots/jj`, flake
  `checks` outputs).
- how devenv is activated in isolation for a temp repo, and how the jj fork slot config
  (`kdn.jj.fork.*` → the `revset-aliases`) is applied to that throwaway repo.
- a way to simulate `jj sync-remotes` push against local bare repos.

Each case = one test: set up the 3-repo topology at the required state (mutable/frozen), run the
candidate sequence, assert the resulting graph (parents, bookmarks after a simulated sync,
`fork-leaked` empty, fast-forward-able tips).

## Deliverables

- One coherent placement reference (likely consolidated in `docs/jujutsu-vcs.fork.md`,
  cross-referenced from `docs/flake-update.fork.md`), covering the full matrix.
- Rewritten, **shortened** skill examples in `.agents/skills/jujutsu-vcs/SKILL.md` (the source;
  the `.claude/skills/...` copy is devenv-installed and untracked — never edit it directly).
- The pytest 3-repo harness, wired as a check/test.
- **Correct the current wrong state:** the uncommitted edits in `@` to `SKILL.md` and
  `docs/jujutsu-vcs.fork.md` (yesterday's "`-A`/`-B`, never `-d`/`-o`") are wrong. Revert or
  rewrite them as part of this task — do not keep them.
- Delete the obsolete memory TODO `project_jj_split_placement_docs.md` and its `MEMORY.md` line
  (its premise — "a different split flag avoids the rebase" — was wrong).

## Constraints

- Simple Technical English (ASD-STE100) for all doc prose.
- Never push; the user runs `jj sync-remotes`. Never rewrite a pushed/immutable commit.
- Doc and skill are generic → they land on the upstream chain (`fork-leaked` empty).

## Current live example state (2026-09-02, usable as a fixture)

- `upstream-tip` = `nypyzyyytvvo` (`main@kdn`) — feat(kdn-ssh-access): generic SSH access …
- `fork-tip` = `tree-merge` = `xrlvmywqlypt` (`main@<fork-remote>`, pushed) — feat(kdn): access homelab …
- `merge-frozen` non-empty (both tips pushed).
- `@` holds the wrong, uncommitted doc edits that this task must correct.
