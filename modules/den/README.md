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
| `entities/<host>.nix` | One parallel host. It never activates. |

## Outputs

| Output | Contents |
|---|---|
| `den` | The raw den evaluation. Use it to read `den.aspects` and `den.hosts` in a debug session. |
| `denConfigurations.<host>` | A nix-darwin system that den builds. |
| `denDevenvShells.<host>` | A devenv shell that den builds. |
| `denModules.<aspect>` | A **plain module** for an external adopter. It holds no den. |

`denModules` is the point of the whole tree. An adopter imports a plain module, and the adopter
never adopts den. Checkpoint
[006](../../docs/tasks/2026-09/generalization/006-direction-decision/definition.md) records the
direction decision.

## Why a den host is not in `hosts/`

`flake.hostConfigurations` reads the `./hosts` directory from a listing, and it sends every entry
through `modules/meta`. den replaces that pre-pass. A den host inside `hosts/` would inherit the
thing den replaces, so it would prove nothing. The entities live here instead.

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

# the devenv shell evaluates
nix eval --raw '.#denDevenvShells.den-darwin.shell.drvPath'
```

## Pins

den and `nix-effects` are pinned to the exact revisions the 004 spike measured. den is v0.x with no
stable API: `v0.16` and `v0.18` both broke `entity.aspect` semantics, den publishes no CHANGELOG,
and `den.lib.aspects.resolve` is labelled `Internal`. Do not move either pin without a re-run of
the spike commands in
[004-den-spike/research.md](../../docs/tasks/2026-09/generalization/004-den-spike/research.md).
