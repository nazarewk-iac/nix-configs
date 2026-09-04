---
name: jujutsu-vcs
description: jj version control patterns — working copy, split/squash, bookmarks, fork rebase. Single source of truth for jj usage in this repo; use whenever reaching for a raw git command, or when working with jj commits, splits, rebases, or bookmark management.
type: Skill
timestamp: 2026-09-02T00:00:00+02:00
---

<!--
  Agent-safety notes below are informed by two external MIT-licensed sources:
  danverbraganza/jujutsu-skill, and stevenhobartwork-create/claude-plugin-jj-english
  (English translation of kawaz/claude-plugin-jj). Content here is filtered/rewritten for this
  repo's @-only convention (neither source's "jj new per task" workflow is used here).
-->

This skill is the short index. Full detail lives in the docs and the verified examples:

- New to jj? Read the "For git users" primer in [docs/jujutsu-vcs.md](../../../docs/jujutsu-vcs.md#for-git-users--start-here) first.
- Day-to-day golden paths + index: [docs/jujutsu-vcs.md](../../../docs/jujutsu-vcs.md#day-to-day-golden-paths).
- Fork topology: [docs/jujutsu-vcs.fork.md](../../../docs/jujutsu-vcs.fork.md).
- Verified worked examples: `checks/jj-experiments/test_<group>.py` + `test_<group>.md`.
- Test a jj case on-demand (or embed it): add a harness test, run `nix run .#jj-experiments-run -- -k <name>`. A throwaway check is loose; a committed one MUST follow the conventions in [checks/jj-experiments/README.md](../../../checks/jj-experiments/README.md). To add or verify a recipe, copy `test_push` (`checks/jj-experiments/test_push.py` + `test_push.md`) as the template.
- Deep troubleshooting: the `jj-expert` subagent.

## Critical rules (agent safety)

- **Never push.** The user reviews and pushes. (This rule is for agents; the push recipes in the
  docs are for the maintainer to run.)
- **Never rewrite a pushed or immutable commit** — jj errors `is immutable`. Build forward.
- **Always pass `-m 'msg'` and `-- <files>`; set `JJ_EDITOR=true`.** Never interactive
  (`jj split -i`, `jj squash -i`, `jj resolve` open a picker and hang).
- **`--no-pager`** on `jj log`/`jj diff`/`jj show`.
- ⚠️ **Never `git worktree`** (this includes the Agent/Workflow `isolation: "worktree"` option).
  It is colocated, shares the one `.jj` store, and a concurrent writer corrupts files (confirmed
  2026-07-29). For parallel work, use `jj workspace add <path>` with a sibling dir OUTSIDE this
  repo. Then run `jj new` inside it. Verify the isolation with `jj workspace list`.
- **Never Claude Code `/commit`** — it runs raw `git commit`, bypasses jj, and `jj-guard` cannot
  catch it. Use `jj describe`/`jj commit`.
- **`@` empty is a manual convention** — `jj describe`/`jj commit` do not create a fresh `@`. Run
  `jj new` yourself, and only to wrap up finished work.
- **Read a file from any revision with `jj file show -r <id> <path>`** — never `jj edit` to read.
- **Investigate config with `jj config list --repo`** (never poke `.jj/`). Empty or `#schema`-only
  output means the repo config is not loaded — pause and ask the user to re-enter the devenv shell.
- **Stale `.git/index.lock`** with no git process running is a colocation artifact, safe to remove.

## Golden paths (one line each; detail behind the links)

`jj rebase` and `jj edit` are normal, safe tools on **mutable** commits — not a "last resort".
Never run them on a pushed/immutable commit. Detail and proofs are in
[docs/jujutsu-vcs.md](../../../docs/jujutsu-vcs.md#day-to-day-golden-paths); the `test_*.md` files
below are under `checks/jj-experiments/`.

| Task | Golden path | Proof |
|---|---|---|
| Carve `@` into a commit | `jj split -m 'msg' -- <files>` | test_branch.md |
| Fold `@` into a commit | `jj squash --into <id> -- <files>` | test_squash_absorb.md |
| Auto-fold fixups | `jj absorb` | test_squash_absorb.md |
| Amend in place | `jj edit <id>` … edit … `jj new <tip>` | test_amend.md |
| Reword | `jj describe -r <id> -m 'msg'` | test_amend.md |
| Reorder / move | `jj rebase -r <id> --insert-after/-before <x>` | test_restructure.md |
| Abandon | `jj abandon <id>` (descendants reparent) | test_restructure.md |
| Revert forward | `jj revert -r <id> -A <tip>` | test_restructure.md |
| Discard / recover | `jj restore [--from <rev>] [<paths>]`; `jj undo`; `jj op restore <op>` | test_recover.md |
| Bookmarks | `jj bookmark create/set/delete`; `jj git push --remote <r> -b <name>` | test_bookmarks.md |
| Untrack (gitignore first) | `jj file untrack <path>` | test_bookmarks.md |
| Inspect | `jj diff -r <id>` / `--from`/`--to`; `jj show <id>`; `jj file show -r <id> <path>` | test_inspect.md |
| Conflicts | detect `jj log -r 'conflicts()'`; edit to merged content; snapshot | test_conflicts.md |

## Fork topology (only when this repo is a fork)

Quick check: `jj config list --repo` lists `revset-aliases.fork-tip`. If it does not, skip this —
a plain repo uses only the day-to-day paths above. The shared branch workflows (integrate trunk,
hazards, X→Y) live in [docs/jujutsu-vcs.md](../../../docs/jujutsu-vcs.md#branch-workflows); only the
fork-specific content routing below is fork-only. Full detail:
[docs/jujutsu-vcs.fork.md](../../../docs/jujutsu-vcs.fork.md). Proofs: `test_placement.md`,
`test_rebase.md`, `test_hazards.md`, `test_deleak.md`, `test_revsets.md`.

- **Add a generic upstream change:** `jj new --no-edit -B @ -m 'chore(upstream): merge'` then
  `jj split -A upstream-tip -B fork-tip -m 'msg' -- <files>`. A single split is enough when a
  mutable merge already exists. `-B fork-tip` needs the fork tip **mutable**.
- **Fork-sensitive leaf tweak:** `jj split -m 'msg' -- <sensitive files>` (stays above the merge).
- **Fork-base change:** `jj split -A fork-tip -m 'msg' -- <files>`, then
  `jj new upstream-tip fork-tip -m 'chore(upstream): merge'`, then `jj new` to park an empty `@`.
- **Pull upstream in:** frozen → `jj new fork-tip upstream-incoming-tip -m 'chore(upstream): merge'`;
  mutable → `jj rebase -s 'roots(upstream-local)' -d 'upstream-incoming-tip'`.
- **Audit fork-sensitive content:** `jj fork-audit` (lists matches at line level).
- **Bookmarks are moved by `jj sync-remotes`, not by hand.** Never `jj bookmark set` `main`/`upstream`.

## Deep troubleshooting

Divergent changes, conflict-marker surgery, revset/template/fileset questions, or graph surgery
beyond split/squash → the `jj-expert` subagent has the full decision tree and a git↔jj map.
