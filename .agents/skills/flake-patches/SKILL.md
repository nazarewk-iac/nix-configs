---
name: flake-patches
description: Manage .flake.patches — find fixes for build failures, check if patches landed in nixos-unstable, register or remove patches. Use when a nix build fails after a flake update.
type: Skill
timestamp: 2026-07-03T22:19:14+02:00
---

Full reference: [docs/flake-patches.md](../../docs/flake-patches.md)

Patches apply fixes to flake inputs (most commonly nixpkgs) that exist upstream but haven't
landed in the tracked channel (`nixos-unstable`) yet. Any input with a `{name}-upstream`
counterpart in `flake.nix` can be patched.

## Find a fix for a build failure

```bash
# 1. Search for fix PRs:
gh search prs "<failing-package>" --repo NixOS/nixpkgs --limit 10
gh search issues "<package> <error>" --repo NixOS/nixpkgs --state open --limit 5

# 2. Get the merge commit of the fix PR:
gh pr view <PR> --repo NixOS/nixpkgs --json mergeCommit --jq '.mergeCommit.oid'

# 3. Check if it's in nixos-unstable yet:
gh api "repos/NixOS/nixpkgs/compare/nixos-unstable...<commit-sha>" --jq '.status'
# "ahead"     → not yet landed — register the patch
# "behind"    → already landed — no patch needed (or remove existing one)
# "identical" → same commit — already landed
```

## Register a patch

Add to `.flake.patches/config.toml`:

```toml
[patch.nixpkgs.descriptive-name]
url = "https://github.com/NixOS/nixpkgs/pull/<PR>.patch?full_index=1"

# or a specific commit:
[patch.nixpkgs.descriptive-name]
url = "https://github.com/NixOS/nixpkgs/commit/<sha>.patch?full_index=1"
```

Then apply without re-fetching inputs:
```bash
nix run '.#update' -- g:patches
```

## Remove a landed patch

When a patch has landed in the tracked channel:
1. Comment out or delete the `[patch.<input>.<name>]` entry in `.flake.patches/config.toml`
2. Delete the `.patch` file under `.flake.patches/<input>/`
3. Verify: `nix run '.#update' -- g:patches`

## PR tracker web UIs (nixpkgs only, no API)

- https://nixpkgs-tracker.ocfox.me/?pr=<PR> — shows all channels, client-side only
- https://nixpk.gs/pr-tracker.html?pr=<PR> — reportedly broken since late 2025

## staging-next note

`staging-next` is a long-running branch that accumulates large/destructive changes before
merging to master. Fixes there take weeks to reach `nixos-unstable` — don't register patches
from staging-next PRs unless you're prepared to carry them for a long time.
