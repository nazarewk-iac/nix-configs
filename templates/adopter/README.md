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

**Two routes exist, and the owner has not chosen between them.** This template uses `mkSlots`, the
route every real host in this repository runs on. The den route needs no overlay and no `mkSlots`
call, and it is proven by evaluation only. See
[docs/den-for-adopters.md](../../docs/den-for-adopters.md) and
[006-direction-decision](../../docs/tasks/2026-09/generalization/006-direction-decision/definition.md),
which stays `status: open`.

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
