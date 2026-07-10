---
name: flake-update-fork
description: Flake update with fork merge — create merge commit, run flake-lock-merge, advance main. Use when updating flake inputs in a repo with both a public (kdn) and private (fork) remote.
type: Skill
timestamp: 2026-07-10T12:19:48+02:00
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
FORK_UPDATE=$(jj log -r @ --no-graph -T 'change_id.short()')

# split non-flake.lock changes onto upstream; flake.lock stays in the fork update:
jj split -r "$FORK_UPDATE" --insert-after upstream -m 'chore(flake): update' -- .flake.patches/
# @ is now the upstream-side commit

# merge in public flake inputs from the fork update:
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"
jj bookmark set upstream -r @

# go to the fork update (flake.lock only) and create the merge commit:
jj edit "$FORK_UPDATE"
jj new -m 'chore(flake): upgrade & upstream merge'
jj bookmark set main -r @
jj new -d main -d upstream
```

## Post-update fixes

```bash
jj split -m 'fix(...): description' -- <changed-files>
jj bookmark set upstream -r 'upstream-tip'
jj rebase -r "$FORK_UPDATE" -d upstream
jj rebase --revision <merge-change-id> \
          --destination "$FORK_UPDATE" \
          --destination main@<fork-remote>
jj bookmark set main -r <merge-change-id>
jj rebase -s @ -d main -d upstream
```

## Agent notes

- `upstream@<fork-remote>` is the stable anchor — never use bare `upstream` in revsets
- `jj split --insert-after upstream` inserts the selected files as a new commit after `upstream` and rebases `$FORK_UPDATE` (and any other children) onto it automatically; `flake.lock` stays in `$FORK_UPDATE`
- `flake-lock-merge "$FORK_UPDATE"` reads the fork update's lock as reference to populate only public inputs into the upstream-only commit
- Non-`flake.lock` changes (`.flake.patches/`) go on the upstream chain; only `flake.lock` stays in the fork update
- `jj new` and `jj rebase` are non-interactive; `jj edit` switches working copy non-interactively
- After `jj split`, `@` lands on the new upstream-side commit — no need to `jj edit` it
- Test with pre-update rev: `nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#darwin-rebuild" -- build`
- Never run `switch` — hand off to user (requires sudo)
