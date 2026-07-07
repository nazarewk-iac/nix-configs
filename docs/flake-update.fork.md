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

After a completed update, the graph looks like:

```
upstream@<fork-remote> ──► upstream-update ──► upstream
                                                        \
                                                         ──► main ◄── @  (empty working copy)
                                                        /
main@<fork-remote> ──► fork-update (flake.lock only)
```

- `upstream-update`: patch file changes + public flake inputs only
- `fork-update`: `flake.lock` with all inputs (public + fork-specific)
- `main`: merge commit combining both

---

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

# create the fork merge commit:
jj edit "$FORK_UPDATE"
jj new -m 'chore(flake): upgrade & upstream merge'
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

This updates all inputs and applies patches. The result lands in `@` (working copy), which has
both `main` and `upstream` as parents.

If a patch fails to apply, remove it from `.flake.patches/config.toml` and delete the `.patch`
file, then re-run patches only:

```bash
nix run '.#update' -- g:patches
```

### 2. Name the fork update and capture its ID

```bash
jj describe -m 'chore(flake): update'
FORK_UPDATE=$(jj log -r @ --no-graph -T 'change_id.short()')
```

### 3. Split non-flake.lock changes onto upstream

Patch file changes belong on the public upstream chain, not in the fork update:

```bash
jj split -r "$FORK_UPDATE" --insert-after upstream -m 'chore(flake): update' -- .flake.patches/
```

`--insert-after upstream` inserts the selected files as a new commit after `upstream` and
rebases `$FORK_UPDATE` (and any other children) onto it automatically. The remaining changes
(`flake.lock`) stay in `$FORK_UPDATE`. After the split, `@` lands on the new upstream-side commit.

### 4. Merge in public flake inputs

The upstream-side commit now needs its `flake.lock` populated with public inputs. Use
`flake-lock-merge` with the fork update as reference (it has all public inputs already):

```bash
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"
jj bookmark set upstream -r @
```

### 5. Create the fork merge commit

```bash
jj edit "$FORK_UPDATE"
jj new -m 'chore(flake): upgrade & upstream merge'
jj bookmark set main -r @
jj new -d main -d upstream
```

### 6. Post-update fixes

If the build fails, make fixes in `@`, then split them into a named kdn-side commit:

```bash
jj split -m 'fix(...): description' -- <changed-files>
jj bookmark set upstream -r 'latest(upstream-candidates)'
# rebase fork update and merge commit onto new upstream:
jj rebase -r "$FORK_UPDATE" -d upstream
jj rebase --revision <merge-change-id> \
          --destination "$FORK_UPDATE" \
          --destination main@<fork-remote>
jj bookmark set main -r <merge-change-id>
jj rebase -s @ -d main -d upstream
```

---

## Testing

Same as [flake-update.md](flake-update.md#testing), but note:

- Darwin `switch` requires sudo — hand off to the user.
- For NixOS remote hosts, use `./nixos-rebuild.sh build remote=<hostname>`.
