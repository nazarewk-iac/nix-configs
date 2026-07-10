---
name: flake-update
description: Update flake.lock, handle patches, and test builds. Use when asked to update the flake, run nix run .#update, handle patch failures, or test darwin/nixos builds after an update.
type: Skill
timestamp: 2026-07-03T22:19:14+02:00
---

Full reference: [docs/flake-update.md](../../docs/flake-update.md)
Fork workflow: [docs/flake-update.fork.md](../../docs/flake-update.fork.md) (if fork remote configured)
Patch handling: [docs/flake-patches.md](../../docs/flake-patches.md)

## Quick summary (no fork)

```bash
# @ is the empty working copy on top of upstream
nix run '.#update'
# patch failed? remove from .flake.patches/config.toml + delete .patch file, then:
#   nix run '.#update' -- g:patches
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-
# test (see Testing below), fix failures with jj split + squash
```

## Patch failures

1. Search nixpkgs for a fix: `gh search prs "<package>" --repo NixOS/nixpkgs --limit 5`
2. Check if fix is in nixos-unstable: `gh api "repos/NixOS/nixpkgs/compare/nixos-unstable...<commit>" --jq '.status'`
   - `"ahead"` = not yet landed → register patch
   - `"behind"` / `"identical"` = already landed → remove old patch
3. Add to `.flake.patches/config.toml`:
   ```toml
   [patch.nixpkgs.my-fix]
   url = "https://github.com/NixOS/nixpkgs/pull/<PR>.patch?full_index=1"
   ```
4. Re-run: `nix run '.#update' -- g:patches`

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

- `jj bookmark set upstream -r @-` — targets the just-described commit, not the new empty `@`
- Run `nix run '.#darwin-rebuild' -- build` in background: pass `run_in_background=true`
- Never run `switch` — hand off to user (requires sudo)
