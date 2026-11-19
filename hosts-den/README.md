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

| Item        | Rule                                                                                                                          |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Path        | `hosts-den/<name>/default.nix`                                                                                                |
| `meta.json` | **none.** The host file states its own system and its own class.                                                              |
| Output      | `denConfigurations.<name>` and `nixosConfigurations.<name>`, plus `denDevenvShells.<name>` from `den.policies.host-to-devenv` |
| Name        | the same short name as the old-tree twin in `hosts/`                                                                          |

The loader keeps a directory alone, so this file stays out of the module list.

## Why the name repeats the old tree's name

The output prefix keeps the two apart, and the compare command stays short:

```bash
nix eval --json '.#hosts.orr.nix.settings.substituters'                 # the old tree
nix eval --json '.#denConfigurations.orr.config.nix.settings.substituters'  # den
```

A den host **is** wired into the standard `nixosConfigurations`, so `nixos-rebuild`, `nh` and the
build farm find a den-replaced host by its usual output name. Den wins where a name exists in both
trees (`orr`, `pryll` are mid-migration twins, and the old-tree `orr` no longer evaluates).

`flake.hosts` is different: it stays **universal-only**. Two k8s modules do a by-name lookup there
for `kdn.networking.*`, which a den host does not declare, so the root flake binds the old-tree
NixOS set once and feeds it to `flake.hosts` while merging den on top for `nixosConfigurations`.
Never write a den host's config into `flake.hosts`.

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

| Directory | Class   | System          | Old-tree twin          | Aspects                                                                                       |
| --------- | ------- | --------------- | ---------------------- | --------------------------------------------------------------------------------------------- |
| `brys/`   | `nixos` | `x86_64-linux`  | **removed** 2026-11-18 | the whole old surface, plus the Niri session; `users.data.nix` carries the test passwords     |
| `orr/`    | `nixos` | `aarch64-linux` | `hosts/orr/`           | `nix-config`, `nix-remote-builder`                                                            |
| `pryll/`  | `nixos` | `x86_64-linux`  | `hosts/pryll/`         | `hw-*`, `locale`, `nix-config`, `secrets`, `user`, `disks`, `desktop-kde`, `stylix`, `ssh-ca` |
