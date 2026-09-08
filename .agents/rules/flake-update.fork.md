---
type: Rule
description: Summarizes the fork flake update workflow and points to the full doc and the skill.
timestamp: 2026-09-08T00:00:00+02:00
---

# Flake Update — Fork Workflow

Full doc: [docs/flake-update.fork.md](../../docs/flake-update.fork.md)

Base procedure: [flake-update.md](flake-update.md). Fork jj topology:
[docs/jujutsu-vcs.fork.md](../../docs/jujutsu-vcs.fork.md) — `jj fork-help` prints it.
For the command-by-command walk-through, use the `flake-update-fork` skill.

## Two rules that override everything

1. **NEVER move a bookmark by hand.** Do not run `jj bookmark set` for `main` or `upstream`.
   `jj sync-remotes` reads the topology and moves both: `upstream-tip` → `upstream`,
   `fork-tip` → `main`. You build the topology only. The user runs `jj sync-remotes` and pushes.
2. **`@` is a plain empty change on top of the fork merge.** It has one parent and holds no
   content. `nix run '.#update'` writes the lock files into a merge `@`, but that state is
   transient. Carve the content into a described commit at once, and keep `@` empty above it.
   One exception: after `jj sync-remotes` both tips are immutable, so you stack new work with
   `jj new fork-tip upstream-tip`. That is the only correct dual-parent `@`.

## Commit shape after a finished update

```
@                      empty working copy, single parent
○   fork merge         "chore(flake): update"                  full locks    ◄ fork-tip → main
├─╮
│ ○ upstream update    "chore(flake): update (public inputs)"  public locks  ◄ upstream-tip → upstream
◆ │ main@<fork-remote>
```

- The **upstream update** holds the public inputs only, in `flake.lock` and `devenv.lock`. Patch
  file changes go there too. Its parent is the public tip.
- The **fork merge** holds all inputs. Its two parents are the upstream update and the fork
  `main`, so it sits directly on top of the upstream update. That link is the point of the shape.
- Both lock files get the same split. `flake-lock-merge` writes `flake.lock`. It cannot write
  `devenv.lock` — strip the fork nodes with `jq` (see the full doc).

## Quick sequence

```bash
# @ is the empty working copy on top of main and upstream
nix run '.#update'
devenv update                    # devenv.lock uses a separate resolver
# 1. carve the update into the fork merge:
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/
# 2. insert the public-only update — BOTH flags, one command:
jj new --insert-after upstream-tip --insert-before fork-tip -m 'chore(flake): update (public inputs)'
# 3. write the public-only locks into it (see the skill), then park an empty @:
jj new fork-tip
# 4. test the builds. NEVER run `jj bookmark set`.
```

## Agent notes

- Pass `-m 'msg'` and `-- <files>` to `jj split`/`jj describe`/`jj squash`. They open an editor by
  default. `jj new` and `jj rebase` need no editor.
- Never use bare `upstream` in a revset. Use `upstream@<fork-remote>`, the stable anchor.
- Run `jj fork-audit` before you treat a commit as upstream-safe.
