---
type: Reference
description: The build-only den entities that prove the parallel den tree evaluates and builds.
timestamp: 2026-09-10T10:15:00+02:00
authored_by: agent
---

# den MVP entities

These entities exist to build. They never activate. They give the den tree a target that is
independent of any real host, so a den change is provable before it touches `hosts/`.

The task is [004-den-spike](../../docs/tasks/2026-09/generalization/004-den-spike/definition.md).
The tree itself is [modules/den/](../../modules/den/README.md).

## Layout

| Path | Kind | den output |
|---|---|---|
| `host-darwin/` | den host, class `darwin`, `aarch64-darwin` | `denConfigurations.host-darwin`, `denDevenvShells.host-darwin` |
| `host-nixos/` | den host, class `nixos`, `x86_64-linux` | `denConfigurations.host-nixos`, `denDevenvShells.host-nixos` |
| `devenv/` | standalone shells, no den host | `denDevenvShells.devenv-darwin`, `denDevenvShells.devenv-linux` |

A den host produces two results: a system, and a shell from
`den.policies.host-to-devenv`. Both read one aspect list. The `devenv/` directory holds every
standalone shell in one file, because a standalone shell needs no entity.

`modules/den/flake-module.nix` imports each directory into the den evaluation.

## Why these live here and not in `hosts/`

`hosts/` holds real machines. `flake.hostConfigurations` reads that directory one level deep and
keeps an entry that holds `default.nix` plus `meta.json` or `meta.nix`. A den entity has neither,
and a reader must not mistake it for a machine. `checks/` states the purpose in the path.

## Why no den host has `class = "devenv"`

den always includes its `insecure-predicate` aspect through `den.default.includes`. That aspect
injects `${host.class}.imports` with an OS-shaped module, and the module sets `config.nixpkgs`. A
host whose class is not an OS class then fails:

```
error: The option 'nixpkgs' does not exist. Definition values:
       - In 'devenv@insecure-predicate/os'
```

A bare `den.lib.aspects.resolve "devenv" <aspect>` never reads `den.default`, so it carries no such
limit. The standalone route uses that call and declares no entity.

Measured on 2026-09-10: the bare resolve and the same resolve from a library-only
`den.nixModule` evaluation give one identical shell drvPath
(`aw4jl6iwdyxh9flfchlnykp3cj4sbfx0`).

## Build

```bash
# current architecture only — no remote builder needed
nix build '.#checks.aarch64-darwin.den-mvp'

# every entity of every system — a foreign system needs a builder for that platform
nix build '.#checks.aarch64-darwin.den-mvp.all'
```

`nix flake check` builds the default check only. `.all` sits in `passthru`, so it stays opt-in.

## Verify without a build

```bash
nix eval --raw '.#denConfigurations' --apply 'v: toString (builtins.attrNames v)'
nix eval --raw '.#denDevenvShells'   --apply 'v: toString (builtins.attrNames v)'
nix eval --raw '.#denConfigurations.host-darwin.config.system.build.toplevel.drvPath'
nix eval --raw '.#denConfigurations.host-nixos.config.system.build.toplevel.drvPath'
```

## Pattern V1 applies here

A den evaluation reads no `self`, so no den drvPath carries this repository's tree hash. A drvPath
that does not change proves a refactor is a no-op. This holds for every den output, including the
shells — verified on 2026-09-10 by a perturbation of an unrelated tracked file.

Pattern V1 does **not** hold for the `modules/universal` route, because `flake.nix` sets
`nix-configs = self`.
