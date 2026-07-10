---
type: Playbook
description: Explains how flake input patches are configured and applied ahead of upstream landing.
timestamp: 2026-07-03T16:33:57+02:00
---

# Flake Patches

> **Agent summary:** [.agents/rules/flake-patches.md](../.agents/rules/flake-patches.md)

Patches are applied on top of flake inputs when upstream fixes exist but haven't yet landed
in the channel we track (typically `nixos-unstable`). Patching is not exclusive to nixpkgs —
any input with an upstream fork (`{name}-upstream` in `flake.nix`) can have patches registered.

nixpkgs is the most complex case because:
- We track `nixos-unstable`, a release channel that lags `master` by days to weeks
- Fixes often land in `master` or `staging-next` long before reaching `nixos-unstable`
- `staging-next` is a long-running accumulator of larger changes — don't expect those soon

---

## Patch config

Patches live in `.flake.patches/config.toml`. Each entry names an input (`nixpkgs`, `sops-nix`,
`preservation`, etc.) and provides a URL or `gh-compare` spec:

```toml
[patch.nixpkgs.my-fix]
url = "https://github.com/NixOS/nixpkgs/pull/123456.patch?full_index=1"

# or a commit:
[patch.nixpkgs.my-commit-fix]
url = "https://github.com/NixOS/nixpkgs/commit/abcdef1234.patch?full_index=1"

# or a compare range from a fork:
[patch.nixpkgs.my-fork-fix]
repo = "NixOS/nixpkgs"
base = "nixos-unstable"
ref = "myuser:my-fix-branch"
skip = 0
```

---

## Finding patches for build failures

1. Search nixpkgs issues/PRs for the failing package:
   ```bash
   gh search prs "<package-name>" --repo NixOS/nixpkgs --limit 10
   gh search issues "<package-name> <error-keyword>" --repo NixOS/nixpkgs --state open --limit 5
   ```

2. Find the PR number of the fix and get its patch URL:
   ```
   https://github.com/NixOS/nixpkgs/pull/<PR>.patch?full_index=1
   ```

3. Register it in `.flake.patches/config.toml` and apply:
   ```bash
   nix run '.#update' -- g:patches
   ```

---

## Checking if a patch has landed in nixos-unstable

Before an update, check if previously-registered patches have landed — if so, remove them.

### Via GitHub API (programmatic)

```bash
# Get the merge commit of a PR:
gh pr view <PR> --repo NixOS/nixpkgs --json mergeCommit --jq '.mergeCommit.oid'

# Check if that commit is in nixos-unstable:
gh api "repos/NixOS/nixpkgs/compare/nixos-unstable...<commit-sha>" --jq '.status'
# "behind" = already in nixos-unstable (remove the patch)
# "ahead"  = not yet in nixos-unstable (keep the patch)
# "identical" = same commit (remove the patch)
```

### Via PR tracker web UIs

- **https://nixpkgs-tracker.ocfox.me/?pr=<PR>** — client-side, no API, shows all channels
- **https://nixpk.gs/pr-tracker.html?pr=<PR>** — reportedly broken since late 2025

Both trackers ultimately query GitHub API. When they're unavailable, use the `gh api` approach above.

---

## Checking out nixpkgs locally

The nixpkgs repo is several GB — only clone if it's already present:

```bash
# Check if already cloned:
g-dir github.com/NixOS/nixpkgs

# Only if already present, fetch and check:
cd "$(g-dir github.com/NixOS/nixpkgs)"
git fetch upstream nixos-unstable
git log nixos-unstable -- pkgs/path/to/package
```

Do NOT run `g-get github.com/NixOS/nixpkgs` unless you're prepared for a multi-GB download.

---

## Removing a landed patch

When a patch has landed in the channel we track:

1. Comment out or delete the `[patch.<input>.<name>]` entry in `.flake.patches/config.toml`
2. Delete the `.patch` file under `.flake.patches/<input>/`
3. Re-run patches to verify: `nix run '.#update' -- g:patches`
