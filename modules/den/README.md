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

The entities live **outside** this tree, at
[`checks/den-mvp/`](../../checks/den-mvp/README.md). That directory holds one build-only host per
class, plus every standalone devenv shell. Its README states the layout and the build commands.

## Outputs

| Output | Contents |
|---|---|
| `den` | The raw den evaluation. Use it to read `den.aspects` and `den.hosts` in a debug session. |
| `denConfigurations.<host>` | A nix-darwin or a NixOS system that den builds. Both classes share one flat set. |
| `denDevenvShells.<host>` | A devenv shell that den builds. |
| `denModules.<aspect>` | A **plain module** for an external adopter. It holds no den. |
| `denLib` | The adopter-facing library. `denLib.imports { … }` returns a list for `imports = [ … ]`. |

`denLib` and `denModules` are the point of the whole tree. An adopter imports a plain module, and
the adopter never adopts den. `denLib.imports` is the general form. `denModules.<aspect>` is the
zero-argument form for one aspect in its common class. Checkpoint
[006](../../docs/tasks/2026-09/generalization/006-direction-decision/definition.md) records the
direction decision.

## Why the entities are at `checks/den-mvp/`

They build and they never activate, so they are test artifacts. `checks/` states that in the path.

`hosts/` is wrong for a second reason. Every entry `flake.hostConfigurations` keeps goes through
`modules/meta`, and den exists to replace that pre-pass. A den host that inherits `modules/meta`
proves nothing. `checks/` sits outside the loader's reach by construction. Verified:
`nix eval --json '.#hostConfigurations' --apply builtins.attrNames` lists no den entity.

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

## den runs as a library, with no entity and no flake module

`den.nixModule inputs` is a second entry point. It imports four files (`lib.nix`, `policies.nix`,
`aspects.nix`, `pipes.nix`) and exposes exactly `{ aspects, lib, policies }`. It has **no**
`den.hosts`, **no** `den.schema`, **no** `den.classes` and **no** `den.default`. `den.flakeModule`
is what imports all of den's `modules/` tree, and that tree is where the batteries live.

`den.lib.aspects.resolve "<class>" <aspect>` accepts an arbitrary class name. It needs no entity, no
`den.classes` entry and no flake.

`flake.denLib` ships that route. [`lib.nix`](lib.nix) holds it, and it owns the aspect registry too,
so the library route and the `flakeModule` route read one list. The thin wrapper is one call:

```nix
# devenv.nix — or a nix-darwin module, or a NixOS module
{ inputs, ... }:
{
  imports = inputs.nix-configs.denLib.imports {
    class = "devenv";
    aspects = [ "gh" ];
  };
}
```

The raw machinery sits beside the wrapper, for a caller that needs more:

| Handle | Use |
|---|---|
| `denLib.imports` | The thin wrapper. It returns a list for `imports = [ … ]`. |
| `denLib.aspectModules` | The aspect registry — one path per reimplemented slot. |
| `denLib.eval` | One den library evaluation. It returns the `den` handle. |
| `denLib.resolve` | `resolve <den> <class> <aspect>`, with the non-empty-`imports` guard. |
| `denLib.nixModule` | den's own entry point, unwrapped. |

`imports` takes five arguments. `class` names any evaluation domain. `aspects` names registry
entries. `select` takes the `den` handle and returns a list of aspects, so an aspect of your own
needs no registry entry. `modules` adds den modules to the library evaluation. `extraInputs`
overrides an input, and it defaults to this repository's own inputs — so you need no
`nix-rosetta-builder` input of your own.

Measured on 2026-09-10, for both ported aspects, against the full `flakeModule` route:

| aspect | class | library-mode result | same `drvPath` as `flakeModule` |
|---|---|---|---|
| `gh` | `devenv` | `gh-2.100.0` in the shell, `claude.code.enable = true` | yes |
| `rosetta-builder` | `darwin` | `nix.buildMachines` carries `aarch64-linux x86_64-linux` | yes |

Three limits hold:

- **The consumer must pass `specialArgs.inputs` itself.** `den.nixModule inputs` closes over inputs
  for den's own use and forwards none. An aspect file that takes `inputs` otherwise fails with
  `error: attribute 'inputs' missing`.
- **Library mode covers aspects, not entities.** `den.policies` is present, but `den.schema.host` is
  not, so the host-to-devenv policy still needs the flake module.
- **Two simple aspects are not a full sample.** Cross-class forwarding, a parametric aspect and
  `hasAspect` are untested, and those may want `den.schema` or `den.classes`.
- **A whole-aspect function resolves to an empty module.** `{ host, ... }: { name = …; … }` gives
  `{ imports = [ ]; }`. A **per-target** function — `devenv = { host, ... }: …` — resolves
  non-empty, and it then fails inside the caller's own evaluation with `attribute 'host' missing`.
  Measured on 2026-09-10. `denLib.resolve` throws on the first shape. It cannot catch the second.

Two guards protect the wrapper. An unknown aspect name throws when the caller builds the list, not
later when the module system happens to force one element. An empty resolved `imports` list throws
with the reason above.

This repository's own entities still wire through `den.flakeModule`, because entity resolution needs
it. The adopter surface is library mode, and `flake.denLib` ships it.

## Status

| Item | State |
|---|---|
| devenv class | present |
| `rosetta-builder` aspect | core content only — the guest-size options are **not** ported |
| `gh` aspect | present — the first `devenv`-target aspect, a full port of `modules/slots/gh/` |
| `host-darwin` host | evaluates and builds a nix-darwin system plus a devenv shell |
| `host-nixos` host | evaluates a NixOS system plus a devenv shell. It carries **no** aspect yet. |
| Standalone devenv shells | present — `devenv-darwin` and `devenv-linux`, with no den entity |
| `checks.<system>.den-mvp` | present — the current architecture, with `.all` for every system |
| Library mode (`den.nixModule`) | shipped as `denLib` — a thin `imports` wrapper plus the raw machinery |
| A `nixos`-class aspect | not started — `host-nixos` is the landing place |
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

# the adopter-facing wrapper — one module per named aspect
nix eval '.#denLib.imports' --apply 'f: builtins.length (f { class = "devenv"; aspects = [ "gh" ]; })'

# an unknown aspect name must throw here, not later
nix eval '.#denLib.imports' --apply 'f: builtins.length (f { class = "devenv"; aspects = [ "hg" ]; })'

# the parallel Darwin host builds (Darwin machine only, and it never activates)
nix eval --raw '.#denConfigurations.host-darwin.config.system.build.toplevel.drvPath'

# the parallel NixOS host builds (it needs a Linux builder to build, not to evaluate)
nix eval --raw '.#denConfigurations.host-nixos.config.system.build.toplevel.drvPath'

# every shell — two from the hosts, two standalone
nix eval --json '.#denDevenvShells' --apply builtins.attrNames

# the whole MVP builds for this architecture
nix build '.#checks.aarch64-darwin.den-mvp'

# no den entity leaks into the real host set
nix eval --json '.#hostConfigurations' --apply builtins.attrNames
```

## Pattern V1 works here, unlike everywhere else

The hub records that Pattern V1 (the `drvPath` equality gate) is unusable in this repository:
`flake.nix:250` sets `nix-configs = self`, so the whole tree hash enters every derivation and any new
file changes every path.

**Every den output is immune to that.** den's evaluation never reads `self`. Measured on
2026-09-10: `denConfigurations.host-darwin` kept the byte-identical `drvPath`
`7zhp7889kchljri5j7phaakfvzv9j3ph-darwin-system-26.11.4cff07d.drv` across a file move, the addition
of a second host, and a rename. `denDevenvShells.devenv-darwin` kept
`k7iqgp8lv0qk2qp3vqkxii8m4gg8g7v3-devenv-darwin.drv` across a perturbation of an unrelated tracked
file.

The shells were **not** immune before. `kdn.den.devenv.root` held `"${self}"`, so the tree hash
reached each one. That assignment is gone, and the gate now covers all four outputs. Use it for
every den refactor. The slot route still has no such gate.

## Pins

den and `nix-effects` are pinned to the exact revisions the 004 spike measured. den is v0.x with no
stable API: `v0.16` and `v0.18` both broke `entity.aspect` semantics, den publishes no CHANGELOG,
and `den.lib.aspects.resolve` is labelled `Internal`. Do not move either pin without a re-run of
the spike commands in
[004-den-spike/research.md](../../docs/tasks/2026-09/generalization/004-den-spike/research.md).
