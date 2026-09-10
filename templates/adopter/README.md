---
type: How-To
description: A copy-ready devenv starting point for an external adopter of this repository's modules/slots tree.
timestamp: 2026-09-10T07:20:00+02:00
authored_by: agent
---

# Adopter template

This directory is the smallest devenv shell that consumes `modules/slots`. It is for an **external
adopter** — anybody other than the author of this repository.

The full prose is in [docs/slots-for-adopters.md](../../docs/slots-for-adopters.md). Read that
first. The two files here carry the same facts as comments, so the template stands alone.

**This template is the interim route.** The author prefers that you consume a den config, and the
spike that tested it passed on 2026-09-10. That route replaces `mkSlots` here once it lands. See
[004-den-spike](../../docs/tasks/2026-09/generalization/004-den-spike/definition.md), phase 2,
condition 5.

## Use it

The flake declares no `templates` output, so copy the two files by hand:

```bash
cd <your-repo>
curl -fsSLO https://raw.githubusercontent.com/nazarewk-iac/nix-configs/main/templates/adopter/devenv.yaml
curl -fsSLO https://raw.githubusercontent.com/nazarewk-iac/nix-configs/main/templates/adopter/devenv.nix
devenv shell
```

Then change three things:

1. Set the `kdn.<slot>.enable` lines in `devenv.nix` to the slots you want. The template enables
   `kdn.zellij` as a worked example only.
2. Keep `nixpkgs` in `devenv.yaml` pointed at your own nixpkgs. Never write
   `follows: nix-configs/nixpkgs`.
3. Keep `overlays = [ inputs.nix-configs.overlays.packages ]`. Seven slots need it.

## direnv

This template ships no `.envrc`, because a devenv `.envrc` pins a `direnvrc` by hash and that hash
goes stale. Run `devenv init` in a scratch directory and copy the `.envrc` it writes.

## Verify

```bash
devenv eval 'enterShell'   # fast: evaluation only, no derivation build
devenv build shell         # the real check: the packages build
```
