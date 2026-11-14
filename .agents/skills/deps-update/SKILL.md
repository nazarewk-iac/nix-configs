---
name: deps-update
description: Update the repository's dependencies as one flow — flake inputs and devenv.lock, and the separate rosec fork/input. Ask the user with a multi-select which groups to update; every group is selected by default. Use when asked to update dependencies, flake inputs, devenv, or the rosec fork.
type: Skill
timestamp: 2026-11-14T22:00:00+01:00
---

# Dependencies update

This is the umbrella for every dependency update in this repository. It asks which groups to
update, then delegates each group to its own procedure.

## Ask first (multi-select)

Ask the user with the `question` tool (`multiple: true`) before doing anything. List every group,
each marked recommended (selected by default):

> Which dependency groups should this run update?
>
> - `flake inputs + devenv.lock` (Recommended)
> - `rosec fork + input` (Recommended)

If the user deselects a group, skip it and say so. Never update a group the user did not select.

## Group: flake inputs

Follow
[flake-update.md](https://github.com/nazarewk-iac/nix-configs/blob/main/docs/flake-update.md) and
the `flake-update` skill. When `jj config get revset-aliases.fork-tip` returns an alias, the repo
is a fork repo: use
[flake-update.fork.md](https://github.com/nazarewk-iac/nix-configs/blob/main/docs/flake-update.fork.md)
and the `flake-update-fork` skill instead. That procedure covers `jj git fetch --all-remotes`,
`nix run '.#update'`, `devenv update`, the patch failures, the commit shape, and the build/switch
tests.

## Group: rosec fork + input

Follow [rosec.md](https://github.com/nazarewk-iac/nix-configs/blob/main/docs/rosec.md):

1. Update the fork (`nazarewk-iac/rosec`) per its `docs/MAINTAINING.md`: fetch upstream, rebase
   `sops-provider` and `devenv`, re-join `main`, run the tests, push the bookmarks.
2. `nix flake update rosec`; review the new rev in `flake.lock`.
3. Commit the lock (`chore(flake): update rosec`), then build, switch and verify per `rosec.md`
   (`rosec --version`, `rosec-sops conflicts list`, the private-bus `secret-tool` test while the
   provider is off the live bus).

The rosec update changes a separate repository, so it is never silent: it is a group the user
selects.

## Order

When both groups are selected, update the **rosec fork first**, then run the flake update: `nix run
'.#update'` then resolves the new rosec `main` in the same lock pass. If the flake update ran
first, run `nix flake update rosec` afterwards.

## Rules

- Fetch before the flake update: `jj git fetch --all-remotes`.
- Never run the flake update without `devenv update` in the same run.
- Never update a group the user did not select, and never push without the user.
- End with an empty, unnamed `@`.
