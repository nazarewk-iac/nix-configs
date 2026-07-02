# Flake Update — Fork Workflow

> **Agent note:** This file is installed as `.claude/rules/flake-update.fork.md` via the
> `kdn.jj.fork` devenv slot. See also [flake-update.md](flake-update.md) for the base workflow
> and [jj-workflows.md](jj-workflows.md) for jj patterns.
>
> In non-interactive contexts: `jj describe`/`jj split`/`jj bookmark set` are safe.
> `jj new`, `jj rebase` are non-interactive. `upstream@<fork-remote>` is the stable anchor —
> never use bare `upstream` in revsets.

Extends [flake-update.md](flake-update.md) for repos that maintain a private fork remote
alongside the public kdn remote. See [jj-workflows.md](jj-workflows.md) for the underlying
jj patterns.

---

## Commit structure

```
main@kdn ──► ...kdn-chain... ──► upstream
         \                              \
          \──────────── main ◄── @       (empty working copy)
         /
main@<fork-remote> ──► ...fork-chain...
```

The update adds new commits to the kdn side, then the fork merge commit absorbs them.

---

## Quick summary

```bash
# @ is the empty working copy on top of main and upstream
nix run '.#update'
# patch failed? remove from .flake.patches/config.toml + delete .patch file, then:
#   nix run '.#update' -- g:patches
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-

# create the fork merge commit:
jj new 'latest(upstream-candidates)' main@<fork-remote> -m 'chore(flake): upgrade & upstream merge'

# merge the flake.lock from both sides using a pre-update rev to avoid rebuilding the tool:
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- 'latest(upstream-candidates)'

# advance main and restore @:
jj bookmark set main -r @
jj new -d main -d upstream

# test builds (see flake-update.md Testing section)
```

---

## Step-by-step

### 1. Run the update

With `@` on top of `main` and `upstream`, run:

```bash
nix run '.#update'
```

If a patch fails, remove it from `.flake.patches/config.toml` and re-run:

```bash
nix run '.#update' -- g:patches
```

### 2. Name the update commit and advance upstream

```bash
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-
```

### 3. Create the fork merge commit

```bash
jj new 'latest(upstream-candidates)' main@<fork-remote> \
  -m 'chore(flake): upgrade & upstream merge'
```

This creates a merge commit with both the kdn update and the fork chain as parents,
and makes it the new `@`.

### 4. Merge the flake.lock files

`flake-lock-merge` reads the lock from the kdn update commit and uses it as a reference
to preserve pinned inputs. Use a pre-update revision of the tool to avoid rebuilding it
against the new inputs:

```bash
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- 'latest(upstream-candidates)'
```

### 5. Advance main and restore @

```bash
jj bookmark set main -r @
jj new -d main -d upstream
```

### 6. Post-update fixes

If the build fails, make fixes in `@`, then split them into a named kdn-side commit:

```bash
jj split -m 'fix(...): description' -- <changed-files>
jj bookmark set upstream -r 'latest(upstream-candidates)'
# rebase the fork merge commit onto the new upstream:
jj rebase --revision <merge-change-id> \
          --destination upstream \
          --destination main@<fork-remote>
jj bookmark set main -r <merge-change-id>
jj rebase -s @ -d main -d upstream
```

---

## Testing

Same as [flake-update.md](flake-update.md#testing), but note:

- Darwin `switch` requires sudo — hand off to the user.
- For NixOS remote hosts, use `./nixos-rebuild.sh build remote=<hostname>`.
