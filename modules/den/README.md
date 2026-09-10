---
type: Reference
description: The parallel den implementation of this repository's module surface, additive to modules/slots and modules/universal.
timestamp: 2026-09-10T13:05:00+02:00
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
| `denHomeConfigurations.<name>` | A **standalone** home-manager configuration. It belongs to no den host. |
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

## The drop-in rule — no `specialArgs`, no machinery

**A consumer imports a resolved module and passes nothing else.** No `specialArgs`, no
`kdnConfig`, no wrapper function, no overlay. The creator stated this goal again on 2026-09-10:
the `modules/universal` plus `modules/meta` pair needs `kdnConfig` in `specialArgs`, and that
requirement is what made each new module kind expensive. The slot tree avoided it. This tree must
avoid it too.

One mechanical rule keeps it true:

> **A target module takes `config`, `lib` and `pkgs` only** — the arguments that every NixOS,
> nix-darwin, home-manager and devenv evaluation already gives. An argument such as `inputs` or
> `kdnConfig` makes the consumer supply `specialArgs`. When an aspect needs a flake input, take it
> in **the aspect file's own** arguments (`{ inputs, ... }:` at the top of the file) and close over
> it. den supplies that from its own evaluation, so the value is already bound when the resolved
> module reaches the consumer.

`den-eval-routes` proves the property: it evaluates `denModules.rosetta-builder` inside a bare
`nix-darwin.lib.darwinSystem` with **no** `specialArgs`, and it compares the `drvPath` against the
library route. `modules/slots/` needs one `overlays` line for `pkgs.kdn.*`; an aspect that needs a
custom package must carry it the same way — through this file's own arguments, never through the
consumer's `pkgs`.

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
- **`denModules.<aspect>` cannot carry a multi-class aspect.** That zero-argument form names one
  common class per aspect, and `devenv-cli` has four. So the registry ships no
  `denModules.devenv-cli`. `denLib.imports { class = …; aspects = [ "devenv-cli" ]; }` is the general
  form, and `den-eval-devenv-cli` asserts it resolves one module on each of the four classes.

### Two traps the den entity model sets

Both cost real time to find, and neither gives an error.

1. **A den user's `classes` defaults to `[ "user" ]`, with no `homeManager`**
   (`<den>/nix/lib/entities/host.nix:157`). A user that omits it silently gets no home-manager
   generation, and the `homeManager` half of every aspect it includes goes nowhere.
2. **den partitions an aspect by scope.** A four-target aspect must be included **twice** on a
   host: once in the host aspect for `nixos`/`darwin`/`devenv`, and once in the user aspect for
   `homeManager`. Measured on 2026-09-10 with `devenv-cli`: host scope alone gave **0** devenv in
   `home-manager.users.dev.home.packages`; both scopes gave **1**.

den imports home-manager into a host by itself, through
`<den>/modules/aspects/batteries/home-manager.nix`. A host needs no home-manager import — it needs
a user. [`checks/den-mvp/users/`](../../checks/den-mvp/README.md) holds the one this tree uses.

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
| `ssh-agent` aspect | present — the first **`homeManager`-only** aspect. A full port of `modules/slots/ssh-agent/`. |
| `ca` aspect | present — the first **`nixos`-only** aspect. A full port of `modules/slots/ca/`. It declares `kdn.ca` **inside** its own `nixos` target, so one plain module both declares the option and serves it. |
| `devenv-cli` aspect | present — the **four-target** aspect. It ports `modules/slots/devenv/` and adds a `devenv` target the slot has none of. |
| `zellij` aspect | present — a full port of `modules/slots/zellij/`. It is the first aspect with a Claude Code hook, the first that installs a repository file, and the first that reaches a `packages/` derivation with a plain `pkgs.callPackage` and **no overlay**. |
| `kdn.isSourceRepo` | present — [common/source-repo.nix](common/source-repo.nix) declares it once. An aspect imports that file **by path**, because the module system dedupes an import by path and rejects two inline declarations of one option. |
| `host-darwin` host | evaluates and builds a nix-darwin system, a devenv shell and one home-manager generation |
| `host-nixos` host | evaluates a NixOS system, a devenv shell and one home-manager generation. It carries a real `nixos`-class aspect. |
| Standalone devenv shells | present — `devenv-darwin` and `devenv-linux`, with no den entity |
| Standalone home-manager | present — `home-darwin` and `home-linux`, with no den entity. This is the adopter shape. |
| The `dev` den user | present — one shared user at `checks/den-mvp/users/`. It makes the `homeManager` class reachable. |
| `checks.<system>.den-mvp` | present — the current architecture, with `.all` for every system |
| Test harness | present — 8 evaluation checks, 7 artifact checks, 4 smoke runs. See [checks/den-mvp/README.md](../../checks/den-mvp/README.md#tests). |
| Smoke-test runner | present — `nix run '.#checks.aarch64-darwin.den-mvp.smoke'`. 11 of 11 pass on this machine. |
| A VM test for `host-nixos` | deferred — tier 1 and tier 2 read every value a guest would, and no darwin VM framework exists |
| An automated `hosts/anji` parity check | deferred — it evaluates a whole personal host (~93 s) and it reads sops metadata |
| Library mode (`den.nixModule`) | shipped as `denLib` — a thin `imports` wrapper plus the raw machinery |
| A `nixos`-class aspect | present — `devenv-cli` reaches `host-nixos` |
| `home` target | present — through `devenv-cli`, on both routes |
| A coupled pair of slots (`jj` plus `mcp`) | not started — order 7 of the milestone 2 plan |
| Parity with all 18 slots | **the milestone 2 goal**, set 2026-09-10. 6 of 18 done, 12 left (~3,478 LOC). See [004-den-spike](../../docs/tasks/2026-09/generalization/004-den-spike/definition.md#milestone-2-covers-every-slot--scope-decision-2026-09-10). |

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
