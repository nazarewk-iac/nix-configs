---
type: Rule
description: Summarizes the non-fork flake update procedure and points to the full doc.
timestamp: 2026-09-09T18:00:00+02:00
---

# Flake Update Procedure

Full doc: [../../docs/flake-update.md](../../docs/flake-update.md)

For jj patterns: [../../docs/jujutsu-vcs.md](../../docs/jujutsu-vcs.md) — see also
[jujutsu-vcs.md](jujutsu-vcs.md).

> **This rule applies when `kdn.jj.fork.enable = false`.** In a fork repo, use
> [flake-update.fork.md](flake-update.fork.md) (full doc:
> [../../docs/flake-update.fork.md](../../docs/flake-update.fork.md), installed via devenv slot)
> and the `flake-update-fork` skill. The fork procedure **overrides every step below**.
>
> In a fork repo, `jj sync-remotes` moves every bookmark from the topology. **Never run
> `jj bookmark set`** there.

## Quick summary

```bash
jj git fetch --all-remotes             # ALWAYS first — placement reads remote-tracking refs
# @ is the empty working copy on top of upstream
nix run '.#update'
devenv update                          # devenv.lock has a separate resolver — both are required
# patch failed? find the cause first — see docs/flake-patches.md and the flake-patches skill
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-         # non-fork repo ONLY
# test builds (see Testing below)
# fix failures: jj split -m 'fix(...): desc' -- <files>
#               jj bookmark set upstream -r 'upstream-tip'
```

## Testing

```bash
# macOS — use pre-update rev to avoid rebuilding the tool itself:
PRE_UPDATE_REV=$(jj log -r 'main@<public-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#darwin-rebuild" -- build
# or current tree:
nix run '.#darwin-rebuild' -- build
# switch (requires sudo — hand off to user):
nix run '.#darwin-rebuild' -- switch

# NixOS local:
./nixos-rebuild.sh build
./nixos-rebuild.sh switch   # requires sudo

# NixOS remote:
./nixos-rebuild.sh build  remote=<hostname>
./nixos-rebuild.sh switch remote=<hostname>
```

## Agent notes

- **Run `jj git fetch --all-remotes` before anything else.** `nix run '.#update'` never fetches.
- **Run `devenv update` too.** A run that skips it leaves `devenv.lock` stale, and no later step
  catches that.
- `main@<public-remote>` is the pre-update anchor in a non-fork repo. `upstream@<fork-remote>` is
  the fork-repo anchor and does not exist here.
- `jj split` opens an editor by default — pass `-m 'msg'` and `-- <files>` in non-interactive
  contexts.
- `jj bookmark set upstream -r @-` targets the just-described commit, not the new empty `@`.
  Alternatively use the explicit change ID or `upstream-tip` as the revision.
