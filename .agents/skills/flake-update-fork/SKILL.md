---
name: flake-update-fork
description: Flake update with fork merge — create merge commit, run flake-lock-merge, advance main. Use when updating flake inputs in a repo with both a public (kdn) and private (fork) remote.
---

Full reference: [docs/flake-update.fork.md](../../../../docs/flake-update.fork.md)
Base workflow: see `flake-update` skill.

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

# merge the flake.lock using a pre-update rev to avoid rebuilding the tool:
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- 'latest(upstream-candidates)'

# advance main and restore @:
jj bookmark set main -r @
jj new -d main -d upstream
```

## Post-update fixes

```bash
jj split -m 'fix(...): description' -- <changed-files>
jj bookmark set upstream -r 'latest(upstream-candidates)'
jj rebase --revision <merge-change-id> \
          --destination upstream \
          --destination main@<fork-remote>
jj bookmark set main -r <merge-change-id>
jj rebase -s @ -d main -d upstream
```

## Agent notes

- `upstream@<fork-remote>` is the stable anchor — never use bare `upstream` in revsets
- `jj new` and `jj rebase` are non-interactive
- `jj bookmark set upstream -r @-` targets the just-described commit, not the new empty `@`
- Test with pre-update rev: `nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#darwin-rebuild" -- build`
- Never run `switch` — hand off to user (requires sudo)
