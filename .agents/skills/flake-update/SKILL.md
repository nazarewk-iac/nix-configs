---
name: flake-update
description: Update flake.lock, handle patches, and test builds. Use when asked to update the flake, run nix run .#update, handle patch failures, or test darwin/nixos builds after an update.
type: Skill
timestamp: 2026-09-09T18:00:00+02:00
---

> **This skill applies when `kdn.jj.fork.enable = false`.** In a repo with a private fork remote,
> use the **`flake-update-fork`** skill instead. It overrides every step below. Check with
> `jj config get revset-aliases.fork-tip` — when that alias exists, the repo is a fork repo.

Full reference (stable URLs — a consumer repo has no `docs/` directory):

- [flake-update.md](https://github.com/nazarewk-iac/nix-configs/blob/main/docs/flake-update.md)
- [flake-update.fork.md](https://github.com/nazarewk-iac/nix-configs/blob/main/docs/flake-update.fork.md)
- [flake-patches.md](https://github.com/nazarewk-iac/nix-configs/blob/main/docs/flake-patches.md)

## Quick summary (no fork)

```bash
jj git fetch --all-remotes   # ALWAYS first — the update itself never fetches
# @ is the empty working copy on top of upstream
nix run '.#update'
devenv update    # updates devenv.lock (separate resolver; no fork = same commit, no strip)
# patch failed? find the cause first — see Patch failures below
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-      # non-fork repo ONLY; a fork repo uses jj sync-remotes
# test (see Testing below), fix failures with jj split + squash
```

## Patch failures

Find the cause first. The action differs per cause, so never default to deletion.

1. Search nixpkgs for a fix: `gh search prs "<package>" --repo NixOS/nixpkgs --limit 5`
2. Check whether the fix is in nixos-unstable:
   `gh api "repos/NixOS/nixpkgs/compare/nixos-unstable...<commit>" --jq '.status'`

| Result | Meaning | Action |
|---|---|---|
| `ahead` | the fix has not landed yet | register or keep the patch |
| `behind` / `identical` | the fix already landed | remove the entry and delete the `.patch` file |
| the patch URL 404s | the PR was closed or rewritten | decide whether the change is still wanted; re-derive or drop it |

3. Add to `.flake.patches/config.toml`:
   ```toml
   [patch.nixpkgs.my-fix]
   url = "https://github.com/NixOS/nixpkgs/pull/<PR>.patch?full_index=1"
   ```
4. Re-run: `nix run '.#update' -- g:patches`

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

- **Fetch before you start.** `nix run '.#update'` runs `nix flake update` and the patch updater
  only. It never fetches, so every later placement reads a stale remote-tracking ref.
- **Run `devenv update` too.** `devenv.lock` has its own resolver. A run that skips it leaves the
  file stale, and no later step catches that.
- `main@<public-remote>` is the pre-update anchor here. `upstream@<fork-remote>` is the fork-repo
  anchor and does not exist in a non-fork repo.
- `jj bookmark set upstream -r @-` targets the just-described commit, not the new empty `@`. In a
  fork repo, never run `jj bookmark set` — `jj sync-remotes` places both bookmarks.
- Run `nix run '.#darwin-rebuild' -- build` in the background: pass `run_in_background=true`.
- Never run `switch` — hand off to the user (it needs sudo).
