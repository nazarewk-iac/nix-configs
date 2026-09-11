---
type: Reference
description: What lives in hosts-den, how the loader finds a host, and the command that compares a den host with its old-tree twin.
timestamp: 2026-09-11T00:00:00Z
authored_by: agent
---

# `hosts-den/`

One directory per **real** den host. `modules/den/flake-module.nix` reads this directory with
`builtins.readDir`, so a new host needs one directory and no wiring edit.

`checks/den-mvp/` keeps the build-only test entities. A real machine belongs here instead: that
directory's own README states "These entities exist to build. They never activate."

## The shape of a host

| Item | Rule |
|---|---|
| Path | `hosts-den/<name>/default.nix` |
| `meta.json` | **none.** The host file states its own system and its own class. |
| Output | `denConfigurations.<name>`, plus `denDevenvShells.<name>` from `den.policies.host-to-devenv` |
| Name | the same short name as the old-tree twin in `hosts/` |

The loader keeps a directory alone, so this file stays out of the module list.

## Why the name repeats the old tree's name

The output prefix keeps the two apart, and the compare command stays short:

```bash
nix eval --json '.#nixosConfigurations.orr.config.nix.settings.substituters'
nix eval --json '.#denConfigurations.orr.config.nix.settings.substituters'
```

**Never add a den host to `nixosConfigurations`.** `flake.nix` merges that output into
`flake.hosts`, and two k8s modules do a by-name lookup there. A den host holds none of the
`kdn.networking.*` options, so such a lookup fails or returns a wrong address.

## Compare a value, never a `drvPath`

`modules/universal/profile/machine/baseline/default.nix:141` copies the whole repository into the
store, so any tracked-file edit moves every old-tree host path. A `drvPath` equality proof is
therefore invalid across the two routes. Probe option **values**:

```bash
nix eval --no-eval-cache --json '.#denConfigurations.orr.config.nix.settings'
nix eval --no-eval-cache --json '.#denConfigurations.orr.config.nixpkgs.config'
```

A den-to-den `drvPath` comparison is still valid, because den never reads `self`.

## The hosts

| Directory | Class | System | Old-tree twin | Aspects |
|---|---|---|---|---|
| `orr/` | `nixos` | `aarch64-linux` | `hosts/orr/` | `nix-config`, `nix-remote-builder` |
