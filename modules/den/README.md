---
type: Reference
description: The parallel den implementation of this repository's module surface, additive to modules/slots and modules/universal.
timestamp: 2026-09-10T07:15:00+02:00
authored_by: agent
---

# modules/den

This tree is the **den** implementation of this repository's module surface. It is **phase 2** of
[004-den-spike](../../docs/tasks/2026-09/generalization/004-den-spike/definition.md).

## The one rule

**This tree is additive. It deletes nothing and it modifies nothing.**

`modules/slots/`, `modules/universal/` and `modules/meta/` stay exactly as they are. Every real
host keeps its present route. This tree adds flake outputs beside the existing ones, and it changes
no existing output.

Two lines in `flake.nix` are the only edit outside this directory: the `den` and `nix-effects`
inputs, and one `imports` entry for `flake-module.nix`. A flake input cannot live anywhere else.

## Layout

| Path | Role |
|---|---|
| `flake-module.nix` | The only wiring. It evaluates den and exports the outputs. |
| `classes/devenv.nix` | A den class for devenv. den ships none, and 13 of 18 slots target devenv. |
| `aspects/<slot>.nix` | One aspect per reimplemented slot. |

The hosts live **outside** this tree, at
[`hosts/den-mvp/<host>/`](../../hosts/den-mvp/README.md). That directory holds a build-only host per
class, and its README states why `flake.hostConfigurations` cannot see it.

## Outputs

| Output | Contents |
|---|---|
| `den` | The raw den evaluation. Use it to read `den.aspects` and `den.hosts` in a debug session. |
| `denConfigurations.<host>` | A nix-darwin or a NixOS system that den builds. Both classes share one flat set. |
| `denDevenvShells.<host>` | A devenv shell that den builds. |
| `denModules.<aspect>` | A **plain module** for an external adopter. It holds no den. |

`denModules` is the point of the whole tree. An adopter imports a plain module, and the adopter
never adopts den. Checkpoint
[006](../../docs/tasks/2026-09/generalization/006-direction-decision/definition.md) records the
direction decision.

## Why a den host is at `hosts/den-mvp/<host>/`

`flake.hostConfigurations` (`flake.nix:264`) reads `./hosts` **one level deep** and keeps an entry
only when that entry holds a `default.nix` plus a `meta.json` or a `meta.nix`. `hosts/den-mvp/` holds
none of the three, so the loader drops it and the nested hosts stay invisible.

That invisibility is the requirement. Every entry the loader keeps goes through `modules/meta`, and
den exists to replace that pre-pass. A den host that inherits `modules/meta` proves nothing.
Verified: `nix eval --json '.#hostConfigurations' --apply builtins.attrNames` lists no den host.

## The five conditions from the spike

The spike measured these. Each one is a rule for this tree, not advice.

1. **Assert a non-empty `imports` list on every export.** `den.lib.aspects.resolve` returns
   `{ imports = [ ]; }` for an aspect that reads entity data, with no warning and no error.
   `flake-module.nix` holds the guard (`resolveChecked`).
2. **Keep an adopter-facing aspect free of entity data.** An aspect that takes `{ host, ... }`
   crosses the boundary as an empty module. Use a plain option instead.
3. **Declare `nix-effects` as an explicit input.** den otherwise fetches it with
   `builtins.fetchTarball` at evaluation time, and no consumer lock records that fetch.
4. **Criterion 3 stays open** until
   [005](../../docs/tasks/2026-09/generalization/005-conditional-imports-requirement/definition.md)
   states the conditional-imports requirement.
5. **The adopter path is a den-resolved plain module.** `denModules` above.

## Status

| Item | State |
|---|---|
| devenv class | present |
| `rosetta-builder` aspect | core content only — the guest-size options are **not** ported |
| `den-darwin` host | evaluates a nix-darwin system and a devenv shell |
| `den-nixos` host | evaluates a NixOS system and a devenv shell. It carries **no** aspect yet. |
| A `nixos`-class aspect | not started — `den-nixos` is the landing place |
| `home` target | not started |
| A coupled pair of slots (`jj` plus `mcp`) | not started |
| Parity with all 18 slots | not started |

The slot tree remains the supported route. See
[docs/slots-for-adopters.md](../../docs/slots-for-adopters.md).

## Verify

```bash
# the aspect and host names den knows about
nix eval --json '.#den.aspects' --apply 'builtins.attrNames'

# the adopter-facing plain module — it must hold a non-empty `imports` list
nix eval --json '.#denModules.rosetta-builder' --apply 'm: builtins.length m.imports'

# the parallel Darwin host builds (Darwin machine only, and it never activates)
nix eval --raw '.#denConfigurations.den-darwin.config.system.build.toplevel.drvPath'

# the parallel NixOS host builds (it needs a Linux builder to build, not to evaluate)
nix eval --raw '.#denConfigurations.den-nixos.config.system.build.toplevel.drvPath'

# the devenv shells evaluate
nix eval --raw '.#denDevenvShells.den-darwin.shell.drvPath'
nix eval --raw '.#denDevenvShells.den-nixos.shell.drvPath'

# no den host leaks into the real host set
nix eval --json '.#hostConfigurations' --apply builtins.attrNames
```

## Pattern V1 works here, unlike everywhere else

The hub records that Pattern V1 (the `drvPath` equality gate) is unusable in this repository:
`flake.nix:250` sets `nix-configs = self`, so the whole tree hash enters every derivation and any new
file changes every path.

**A den configuration is immune to that.** den's evaluation never reads `self`. Measured on
2026-09-10: `denConfigurations.den-darwin` kept the byte-identical `drvPath`
`7zhp7889kchljri5j7phaakfvzv9j3ph-darwin-system-26.11.4cff07d.drv` across a file move **and** the
addition of a second host.

So a den host gives a real no-op gate, and the slot route does not. Use it for every den refactor.

## Pins

den and `nix-effects` are pinned to the exact revisions the 004 spike measured. den is v0.x with no
stable API: `v0.16` and `v0.18` both broke `entity.aspect` semantics, den publishes no CHANGELOG,
and `den.lib.aspects.resolve` is labelled `Internal`. Do not move either pin without a re-run of
the spike commands in
[004-den-spike/research.md](../../docs/tasks/2026-09/generalization/004-den-spike/research.md).
