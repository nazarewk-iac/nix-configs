---
type: Rule
description: Summarizes the flake update procedure and points to the full doc.
timestamp: 2026-07-10T12:19:48+02:00
---

# Flake Update Procedure

Full doc: [docs/flake-update.md](docs/flake-update.md)

For fork-specific workflow: [docs/flake-update.fork.md](docs/flake-update.fork.md) (installed via devenv slot).

For jj patterns: [docs/jujutsu-vcs.md](docs/jujutsu-vcs.md) — see also [jujutsu-vcs.md](.agents/rules/jujutsu-vcs.md).

## Quick summary

```bash
# @ is the empty working copy on top of upstream
nix run '.#update'
# patch failed? remove from .flake.patches/config.toml + delete .patch file, then:
#   nix run '.#update' -- g:patches
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-
# test builds (see Testing below)
# fix failures: jj split -m 'fix(...): desc' -- <files>
#               jj bookmark set upstream -r 'upstream-tip'
```

## Testing

```bash
# macOS — use pre-update rev to avoid rebuilding the tool itself:
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
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

- `jj split` opens an editor by default — pass `-m 'msg'` and `-- <files>` in non-interactive contexts.
- `jj bookmark set upstream -r @-` targets the just-described commit, not the new empty `@`.
- Alternatively use the explicit change ID or `upstream-tip` as the revision.
