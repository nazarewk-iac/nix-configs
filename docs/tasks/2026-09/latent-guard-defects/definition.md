---
type: Task
status: open
description: Two guard defects in modules/universal that laziness hides today. A den port makes both reachable.
authored_by: agent
timestamp: 2026-09-11T00:00:00Z
---

# Two latent guard defects in `modules/universal`

Both defects are **pre-existing**. Neither one breaks the tree today, because Nix laziness never
forces the wrong branch. A den port removes that protection, so record them now.

Parent context: [../generalization/definition.md](../generalization/definition.md), and the guard
analysis in [../generalization/014-machine-layer-migration/definition.md](../generalization/014-machine-layer-migration/definition.md).

## Defect 1 — `hasParentOfAnyType` is false on the host itself

`modules/universal/programs/keepassxc/default.nix:33`

```nix
++ lib.optional (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) pkgs.kdn.kdn-keepass;
```

`hasParentOfAnyType` tests the **parent chain**. A NixOS host has an empty parent chain, so the
guard returns `false` on the NixOS host itself. It returns `true` only inside a Home Manager module
whose parent is that host.

So `pkgs.kdn.kdn-keepass` never reaches `environment.systemPackages` on a NixOS host. It reaches
`home.packages` only.

**The question to answer:** does the author want the package on the host, in the user profile, or in
both? The fix follows from the answer:

| Intent | Fix |
|---|---|
| Linux only, either context | `pkgs.stdenv.hostPlatform.isLinux` |
| the user profile only | keep the guard, and say so in a comment |
| both | `kdnConfig.util.ifTypes [ "nixos" ]` beside the current line |

The measurement that matters: **25 of the 30 `hasParentOfAnyType` call sites want
`pkgs.stdenv.hostPlatform.isLinux`, not a parent read.** This site is one of them.

## Defect 2 — a Home Manager branch reads a NixOS-only option

`modules/universal/virtualisation/containers/default.nix:96`

```nix
hooks_dir = [ config.boot.kernelPackages.oci-seccomp-bpf-hook ];
```

The line sits inside an `ifHM` branch. `boot.kernelPackages` does not exist in a Home Manager
module set, so the read fails whenever something forces it.

Laziness hides it: no current host forces that attribute path in the Home Manager context.

**The fix:** read the parent value through `osConfig`, and test for `null` first.

```nix
{ config, osConfig ? null, ... }:
# osConfig is null when Home Manager runs standalone
```

A `?` probe alone is not enough. A `null` test must come first.

## Why this is one task

Both defects share one root cause: **a guard or an option read that assumes a context the module
does not run in.** Both are invisible today and both become real the moment a den aspect forces the
value. Fix them together, and add a test that forces each attribute path.

## Exit test

1. A check forces `pkgs.kdn.kdn-keepass` in the NixOS context and in the Home Manager context.
2. A check forces `virtualisation.containers.containersConf.settings` in the Home Manager context.
3. Both checks pass, and every existing host keeps its option values.
