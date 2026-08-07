---
type: Playbook
description: Extends the flake update workflow for repos maintaining a private fork remote.
timestamp: 2026-08-07T00:00:00+02:00
---

# Flake Update — Fork Workflow

> **Agent note:** This file is installed as `.claude/rules/flake-update.fork.md` via the
> `kdn.jj.fork` devenv slot. See also [flake-update.md](flake-update.md) for the base workflow
> and [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for fork-specific jj patterns.
>
> In non-interactive contexts: `jj split`/`jj describe` are safe with `-m` and `-- <files>`.
> `jj new` and `jj rebase` are non-interactive. `upstream@<fork-remote>` is the stable anchor —
> never use bare `upstream` in revsets.

Extends [flake-update.md](flake-update.md) for repos that maintain a private fork remote
alongside the public kdn remote. See [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for the
underlying jj patterns.

---

## Two rules that override everything

1. **NEVER move bookmarks by hand.** Do NOT run `jj bookmark set` for `main` or `upstream`.
   The `jj sync-remotes` command moves both bookmarks for you. It reads the topology through two
   revset aliases and moves each bookmark to the correct tip:
   - `upstream-tip = latest(upstream-chain)` → the `upstream` bookmark target
   - `fork-tip = latest(fork-chain)` → the `main` bookmark target

   Your only job is to build the correct commit topology. The user runs `jj sync-remotes`
   manually to place the bookmarks and push. See `modules/slots/jj/fork/default.nix` for the
   alias definitions.

2. **`@` is never a content-holding merge.** The working copy `@` stays an empty change. When
   `nix run '.#update'` writes `flake.lock` into a merge `@`, that state is transient. The first
   step carves the content into a described commit and leaves `@` empty. A content merge in `@`
   is a mistake — split it down at once.

---

## Commit structure

After a completed update, the graph looks like this (as `jj log` draws it):

```
@    (empty working copy)                             parents = fork-tip + upstream-tip
├─╮
│ ○  fork merge — "chore(flake): update"              full flake.lock    ◄ fork-tip → main
╭─┤
○ │  upstream update — "chore(flake): update (public inputs)"  public lock  ◄ upstream-tip → upstream
│ ◆  main@<fork-remote>                               fork parent, full flake.lock
╭─┤
◆    upstream@<fork-remote>                            public parent
```

- **upstream update**: public flake inputs only (patch file changes go here too). Its parent is
  the public tip.
- **fork merge**: `flake.lock` with all inputs (public + fork-specific). Its two parents are the
  **upstream update** and the fork `main`. So the fork merge sits directly on top of the upstream
  update — that link is the point of the shape.
- **`@`**: an empty working copy. Its two parents are the two tips (fork merge + upstream update).

The fork merge carries the full lock, so the fork (macOS) build uses it. The upstream update
carries the public-only lock, so the personal NixOS machines build from it in parallel.

---

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
#    in ONE command — it re-parents the fork merge automatically:
jj new --insert-after upstream-tip -m 'chore(flake): update (public inputs)'
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"

# 3. park a fresh empty working copy on top of both tips:
jj new fork-tip upstream-tip

# 4. test builds (see Testing). NEVER run `jj bookmark set` — `jj sync-remotes` does that.
```

---

## Step-by-step

### 1. Run the update

With `@` on top of `main` and `upstream`, run:

```bash
nix run '.#update'
```

This updates all inputs and applies patches. The result lands in `@`, which has both `main` and
`upstream` as parents. So `@` is now a content-holding merge. This state is transient. Step 2
fixes it.

If a patch fails to apply, remove it from `.flake.patches/config.toml` and delete the `.patch`
file, then re-run patches only:

```bash
nix run '.#update' -- g:patches
```

### 2. Carve the update into the fork merge

Split the content out of `@` into a described merge commit. The split keeps both parents on the
described commit and adds a fresh empty `@` on top:

```bash
jj split -m 'chore(flake): update' -- flake.lock .flake.patches/
FORK_UPDATE=$(jj log -r @- --no-graph -T 'change_id.short()')
```

Use `jj split`, not `jj describe`. `jj describe` leaves the content in `@` and keeps `@` a
content merge. `jj split` moves the content into `@-` (the fork merge) and leaves `@` empty.

### 3. Insert the upstream update in one command

Insert the public-only commit between the public tip and the fork merge. `--insert-after
upstream-tip` puts a new commit after the public tip and re-parents the fork merge onto it
automatically. So no separate rebase step is needed:

```bash
jj new --insert-after upstream-tip -m 'chore(flake): update (public inputs)'
```

`@` is now the upstream update commit, in place between the public tip and the fork merge.
Populate its `flake.lock` with public inputs. `flake-lock-merge` reads the fork merge's lock as
reference and keeps only the public inputs:

```bash
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"
```

`flake-lock-merge` writes to the working copy, so `@` must be the upstream update when you run
it. It removes the fork-specific inputs. This removal is correct.

### 4. Park the working copy

Put a fresh empty working copy on top of both tips. This restores the full lock in the working
copy and gives the user a clean review point:

```bash
jj new fork-tip upstream-tip
```

### 5. Verify the topology

```bash
jj log -r 'ancestors(@, 4)' -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
jj log -r 'upstream-tip' --no-graph -T 'change_id.short() ++ "\n"'   # → upstream update
jj log -r 'fork-tip'     --no-graph -T 'change_id.short() ++ "\n"'   # → fork merge
```

Confirm the upstream update holds a public-only lock. It must NOT contain fork-specific inputs.

---

## Patch file changes

Patch file changes (`.flake.patches/`) are public. They belong on the upstream update, not in
the fork merge. Step 2 puts them in the fork merge first. After step 3, move them down into the
upstream update:

```bash
jj squash --from "$FORK_UPDATE" --into upstream-tip -- .flake.patches/
```

The most common update touches only `flake.lock`. Then this step does nothing and you skip it.

---

## Post-update fixes

If a build fails, fix the files in `@` (the empty top). Then split the fix onto the correct
chain, so the topology stays correct and `jj sync-remotes` picks the right tips.

A **public** fix (docs, patch files, any non-sensitive change) goes on the upstream chain,
between the upstream update and the fork merge. Use BOTH insert flags:

```bash
jj split --insert-after upstream-tip --insert-before fork-tip \
  -m 'fix(...): description' -- <public-files>
```

`--insert-after upstream-tip` places the new commit on the public chain. `--insert-before
fork-tip` re-parents the fork merge onto it. You need BOTH: `--insert-after` alone leaves the
new commit as a dangling sibling and does NOT re-parent the fork merge, so `fork-tip` would
still point past it and the fix would miss the fork build. After the split, `@` stays the empty
working copy on both tips.

A **fork-specific** fix goes on the fork chain, above or in the fork merge (a plain
`jj split -m '...' -- <files>` on the fork side, no insert flags needed).

If the public commit already exists on the chain, and you edit those same files again in `@`,
fold the new edits into that commit instead of making a new one:

```bash
# @ holds fresh edits to files already committed in <public-commit> (e.g. the docs commit):
jj squash --from @ --into <public-commit> -- <files>
```

`jj squash --from @ --into wwvkwkto -- docs/flake-update.fork.md` moves the working-copy edits
of that file into the existing docs commit `wwvkwkto`, and `@` stays empty. Use this to amend a
past commit on the correct chain without disturbing the two tips. `--from @` is the default, so
`jj squash --into wwvkwkto -- <files>` is equivalent. Note `--into` (`-t`) cannot combine with
`-r`/`--revision`; use `--from`/`--into`.

Do NOT run `jj bookmark set` — `jj sync-remotes` moves the bookmarks after the topology is
correct. See [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for the graph surgery.

---

## Testing

Same as [flake-update.md](flake-update.md#testing), with these fork notes:

- Build the fork (macOS) from the fork merge, on the macOS machine. Darwin `switch` requires
  sudo — hand off to the user.
- Build the personal NixOS machines from the upstream update. Run these on the NixOS hosts, or
  from a NixOS builder with `./nixos-rebuild.sh build remote=<hostname>`. You cannot build a
  NixOS host from the macOS machine.
