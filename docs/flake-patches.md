---
type: Playbook
description: Explains how flake input patches are configured and applied ahead of upstream landing.
timestamp: 2026-07-03T16:33:57+02:00
---

# Flake Patches

> **Agent summary:** [.agents/skills/flake-patches/SKILL.md](../.agents/skills/flake-patches/SKILL.md)

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

---

## Inputs without an `-upstream` anchor

`.flake.patches` rewrites an input by comparing it with `{name}-upstream`, so an input without that
anchor cannot be patched at all. `nixos-hardware` is such an input today.

When the fix belongs there, override it in the module that consumes it instead — one worked
example is the Raspberry Pi kernel in
[modules/universal/profile/hardware/rpi4/default.nix](../modules/universal/profile/hardware/rpi4/default.nix):

```nix
boot.kernelPackages = lib.mkForce (
  pkgs.linuxPackagesFor (
    (pkgs.callPackage "${inputs.nixos-hardware}/raspberry-pi/common/kernel.nix" {
      rpiVersion = 4;
    }).overrideAttrs (old: { patches = [ ./my-fix.patch ] ++ (old.patches or [ ]); })
  )
);
```

Two rules that cost time to learn:

- **`overrideAttrs` on `patches`, not `.override { kernelPatches = …; }`.** A package that the
  module already `overrideAttrs`ed has an inert `.override`: passing `kernelPatches = [ ]` through
  it leaves the derivation byte-identical.
- **Vendor the patch file.** `fetchpatch` runs on the _remote builder_, so the bytes that get
  hashed on the client and the bytes the builder downloads can differ, and the build then fails
  with `expected path: … / got path: …`.

Add an upstream issue or PR reference in the comment, and delete the override once the input
carries the fix. Adding `{name}-upstream` to `flake.nix` is the alternative when the workaround
would be large.
