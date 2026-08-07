---
name: flake-update-fork
description: Flake update with fork merge — split the update onto fork/upstream sides, run flake-lock-merge, let jj sync-remotes place bookmarks. Use when updating flake inputs in a repo with both a public (kdn) and private (fork) remote.
type: Skill
timestamp: 2026-08-07T00:00:00+02:00
---

Full reference: [docs/flake-update.fork.md](../../../../docs/flake-update.fork.md)
Base workflow: see `flake-update` skill.

## Two rules that override everything

1. **NEVER run `jj bookmark set`** for `main` or `upstream`. `jj sync-remotes` moves both from
   topology (`upstream-tip` → `upstream`, `fork-tip` → `main`). You only build the topology; the
   user runs `jj sync-remotes` manually to place the bookmarks and push.
2. **`@` is a plain empty change on top of the fork merge** — single parent, no content, never
   in the middle of the graph. `nix run '.#update'` leaves the lock in a merge `@` transiently;
   carve it into a described commit at once and keep `@` empty on top.

## Quick summary

```bash
# @ is the empty working copy on top of main and upstream
nix run '.#update'
# patch failed? remove from .flake.patches/config.toml + delete .patch file, then:
#   nix run '.#update' -- g:patches

# 1. carve the update into the fork merge; @ becomes empty on top (never a content merge):
jj split -m 'chore(flake): update' -- flake.lock .flake.patches/
FORK_UPDATE=$(jj log -r @- --no-graph -T 'change_id.short()')

# 2. insert the public-only upstream update between the public tip and the fork merge,
#    in ONE command — BOTH flags: --insert-after adds it, --insert-before re-parents the merge:
jj new --insert-after upstream-tip --insert-before fork-tip -m 'chore(flake): update (public inputs)'
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"

# 3. park a fresh empty working copy on top of the fork merge (single parent):
jj new fork-tip

# 4. patch files present? move them down onto the public side (skip if lock-only update):
jj squash --from "$FORK_UPDATE" --into upstream-tip -- .flake.patches/

# 5. the user tests, then runs `jj sync-remotes` (moves bookmarks + pushes). AFTER that the
#    merge is immutable, so stack new work over BOTH tips (dual-parent @ is correct HERE only):
jj new fork-tip upstream-tip
```

Resulting shape (fork merge sits directly on the upstream update; `@` is single-parent):

```
@    (empty)                                          single parent = fork merge
○    fork merge — "chore(flake): update"              full lock    ◄ fork-tip → main
├─╮
│ ○  upstream update — "…(public inputs)"             public lock  ◄ upstream-tip → upstream
◆ │  main@<fork-remote>
◆    upstream@<fork-remote>
```

## Post-update fixes

Fix in the empty `@`, then split onto the correct chain — never move bookmarks:

```bash
# public fix → onto the upstream chain (BOTH flags: --insert-before re-parents the fork merge):
jj split --insert-after upstream-tip --insert-before fork-tip -m 'fix(...): description' -- <files>
# amend an EXISTING public commit instead (e.g. the docs commit):
jj squash --from @ --into <public-commit> -- <files>
```

## Agent notes

- `upstream@<fork-remote>` is the stable anchor — never use bare `upstream` in revsets.
- Use `jj split`, NOT `jj describe`, in step 1 — `describe` keeps the content in `@` and leaves
  `@` a content merge; `split` moves it into `@-` and keeps `@` empty.
- `jj new --insert-after upstream-tip --insert-before fork-tip` inserts the upstream update AND
  re-parents the fork merge onto it in one command — no separate `jj rebase` step. You need BOTH
  flags: `--insert-after` alone leaves a dangling sibling and does NOT re-parent the fork merge.
- `@` is single-parent on the fork merge for review. Park it with `jj new fork-tip`; it reaches
  the upstream update through the merge. EXCEPTION: after `jj sync-remotes` the merge is
  immutable, so stack new work with `jj new fork-tip upstream-tip` (dual-parent @) — that is the
  only place a dual-parent @ is correct.
- `flake-lock-merge "$FORK_UPDATE"` reads the fork merge's lock as reference and writes a
  public-only lock into `@`; run it while `@` is the upstream update. It removes fork-specific
  inputs — that removal is correct.
- Never run `jj bookmark set` — `jj sync-remotes` places `upstream` and `main` from topology.
- `jj new`, `jj rebase`, `jj squash` are non-interactive with `-m`/`--`.
- Build the fork (macOS) from the fork merge on the macOS machine. Build the personal NixOS
  machines from the upstream update on NixOS hosts — you cannot build a NixOS host from macOS.
- Never run `switch` — hand off to the user (requires sudo).
