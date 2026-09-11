---
type: Research
description: The measurements behind the conditional-imports requirement — the four routes into imports, every imports site in the tree, the rest of modules/meta, and den's verdict.
authored_by: agent
timestamp: 2026-09-11T12:00:00Z
---

# 005 — the measurements

Parent: [definition.md](definition.md). Solution: [done.md](done.md).

Every number here comes from a command I ran on 2026-09-11, on `aarch64-darwin`.

## The four routes

A conditional `imports` list needs a value that Nix resolves **before** the module set. Four
routes exist. Two work, two recurse.

| Route | Result | Command |
|---|---|---|
| module `config` → `imports` | `error: infinite recursion encountered` | `nix eval --impure` on a `{ config, ... }: { imports = lib.optionals config.flag [ … ]; }` module |
| `_module.args` → `imports` | `error: infinite recursion encountered` | the same module, with `_module.args.hostData` in place of `config` |
| `specialArgs` → `imports` | `"present"` | the same module, with `specialArgs.hostData` |
| `specialArgs` false, poisoned module | `"absent"` | the excluded module holds a `throw`, and nothing forces it |

nixpkgs prints its own cause on both failures, from `lib/modules.nix:269`:

```
… if you get an infinite recursion here, you probably reference `config` in `imports`. If you are
trying to achieve a conditional import behavior dependent on `config`, consider importing
unconditionally, and using `mkEnableOption` and `mkIf` to control its effect.
```

### Two consequences

1. **The hub overstates the problem.** The hub says a plain `evalModules` cannot do this. It can,
   through `specialArgs`. `modules/meta` is not the capability — it is a typed pre-pass that
   computes the payload. So the requirement is an easy target for any framework that resolves
   static data first.
2. **`_module.args` is a trap.** `_module.args` is part of `config`, so it recurses too. A
   framework that hands entity data to a target module through `_module.args` alone **fails** the
   requirement. This is the detail that decides den's verdict below.

### A third consequence, for the test itself

`builtins.tryEval` does **not** catch `error: infinite recursion encountered`. It catches `throw`
alone:

```
$ nix eval --impure --expr 'builtins.tryEval (throw "x")'
{ success = false; value = false; }
$ nix eval --impure --expr 'builtins.tryEval (let x = x; in x)'
error: infinite recursion encountered
```

So no in-Nix assertion can state "this route must fail". The negative half of the conformance test
runs the two probe files through `nix-instantiate` from a shell runner instead. A build sandbox has
no daemon, so that runner is an app and not a check.

## Every `imports` site

Trees scanned: `modules/universal/`, `modules/meta/`, `hosts/`. 50 raw grep hits; 13 triaged out
as prose, as `gotools # goimports`, or as a `denLib.imports { … }` function call. That leaves **37
real `imports` attribute sites**.

### Sites driven by evaluated module `config`: 0

```bash
grep -rn -A8 -E "^[[:space:]]*imports[[:space:]]*=" --include="*.nix" \
  modules/universal/ modules/meta/ hosts/ \
  | grep -E "config\.(kdn|nixpkgs|networking|boot|home|system)"
```

Four hits come back, and none is a condition:

- `modules/universal/desktop/sway/default.nix:73` — an option `default` **inside** a module the
  list contains.
- `hosts/oams/default.nix:36`, `hosts/brys/default.nix:138`, and the work host's `default.nix:53`
  — `home-manager.sharedModules`, not `imports`, and `slots.config` is the separate slots
  evaluation.

A wider sweep adds only `slots.config.{nixos,darwin}` — again the slots universe.

**This is the finding that matters for 006.** den's open question about config-driven imports does
not apply to this repository. Nothing here needs it.

### Sites where static data drives a third-party import: 6

| file:line | driving data | third-party modules |
|---|---|---|
| `modules/universal/default.nix:21` | `moduleType`, plus `pathExists` on `${self}/data/*.nix` | 12 — `sops-nix`, `home-manager`, `nix-homebrew`, `angrr`, `disko`, `lanzaboote`, `nur`, `preservation`, in their `nixosModules`/`darwinModules`/`homeManagerModules` shapes |
| `modules/universal/_stylix.nix:19` | `moduleType`, plus `parent == null` | 4 — `stylix.{nixosModules,darwinModules,nixOnDroidModules,homeModules}.stylix`, one per branch |
| `modules/universal/profile/hardware/rpi4/default.nix:32` | `features.rpi4`, `features.installer`, `moduleType` | 4 — two nixpkgs sd-card image modules, `argon40-nix`, `nixos-hardware` |
| `modules/universal/profile/hardware/darwin-utm-guest/default.nix:17` | `features.darwin-utm-guest`, `moduleType` | 1 — nixpkgs `profiles/qemu-guest.nix` |
| `modules/universal/virtualisation/microvm/host/default.nix:12` | `moduleType` | 1 — `microvm.nixosModules.host` |
| `modules/universal/virtualisation/microvm/guest/default.nix:15` | `!features.microvm-guest` | 1 — `microvm.nixosModules.microvm-options` |

The task text above names 3 sites. It misses `modules/universal/default.nix:21` and
`modules/universal/_stylix.nix:19`, and both are essential.

### Three kinds of driving data, not one

| Kind | Sites | What it answers |
|---|---|---|
| `features.*` from `hosts/<host>/meta.json` | 3 | "does this machine have that hardware?" |
| `moduleType` | 5 | "which evaluation universe am I in?" |
| `parent == null` | 1 | "am I a standalone home-manager evaluation, or a child of a host?" |

A framework must answer all three, not only the first. den answers `moduleType` natively, because
it names one class per target and needs no data for it.

### Two live-code corrections

- `hosts/kdn-rpi4-bootstrap/meta.json` holds `{"rpi4":true,"installer":true}`, not `{"rpi4":true}`.
- **No host activates `darwin-utm-guest` or `microvm-guest`.** `hosts/brys/default.nix:296` sets
  `kdn.features.microvm-guest = true`, but it sits inside the `/* … */` block that spans
  `:280-338`. It is dead code, and it also uses a `kdn.features` path that no module declares. So
  nixpkgs' `qemu-guest.nix` is never imported today, and `microvm-options` is always imported.

### The repository still satisfies the requirement

Each rpi4 third-party module declares one option that nothing else declares, so the option proves
the import. `nix eval` on the two hosts:

| option | `briv` (`features.rpi4`) | `oams` (no flag) |
|---|---|---|
| `sdImage` | true | false |
| `programs.argon` | true | false |
| `hardware.raspberry-pi` | true | false |

This is an option-value probe, not a `drvPath` compare. `kdnConfig.self` reaches evaluated config
in this repository, so any edit moves every host `drvPath` and a `drvPath` diff proves nothing.

## The pre-pass mechanism, in three parts

1. **The root evaluation** — `flake.nix:269-278` runs `lib.evalModules { class = "kdn-meta"; … }`.
   It passes **no** `specialArgs`. `inputs`, `lib`, `self` and `nix-configs` arrive as option
   values (`modules/meta/default.nix:93-96`).
2. **The per-host evaluation** — `flake.nix:279-301` reads `hosts/<host>/meta.json` with
   `builtins.fromJSON (builtins.readFile json)` at `:297`, and feeds it to
   `output.mkSubmodule` at `:293`. `mkSubmodule` (`modules/meta/default.nix:28-48`) runs a second
   `kdn-meta` evaluation and injects the parent's config as `parent` at priority 1099.
3. **The injection** — `modules/meta/default.nix:86-92` declares
   `specialArgs = { kdnConfig = config; lib = config.lib; }`. `flake.nix:335-351` hands it to
   `lib.nixosSystem`, `:353-371` to `lib.darwinSystem`, and
   `modules/universal/default.nix:90-92` hands the child meta config to
   `home-manager.extraSpecialArgs`.

The pipeline runs one way and has no feedback edge. Because zero `imports` sites read evaluated
`config`, the pre-pass never observes the thing it configures, so no recursion is possible through
this path today.

## The rest of `modules/meta`

Item 4 of the task: state whether each capability is **essential**, **replaceable** or
**removable**. Call-site counts cover `modules/universal/` plus `hosts/`.

### Essential

| Capability | Sites | Why it is essential |
|---|---|---|
| `features.*` (5 flags, `:207-228`) | 13 lines, 15 mentions | the only per-host JSON data that drives a third-party import. 3 of the 5 flags do. |
| `moduleType` (`:74-77`) | 17 lines | it drives 5 of the 6 third-party import sites, and every `util.if*` guard. |
| `parent` (`:97`) / `parents` (`:99-107`) | 2 direct, 30 through `hasParentOfAnyType` | it answers the standalone-home-manager question at `_stylix.nix:19`. Nothing else can. |
| `output.mkSubmodule` (`:61-64`) | 2 here, 4 in `flake.nix` | it **is** the pre-pass. It builds the child meta config for home-manager. |
| `specialArgs` (`:86-92`) | 0 direct | the payload. `flake.nix` reads it at 6 places. |
| `system` (`:71-73`) | 0 direct | `flake.nix` reads it to pick the platform. |
| `modules` (`:78-85`) | 0 direct | `flake.nix` builds the module list from it. |

### Replaceable

| Capability | Sites | The replacement |
|---|---|---|
| `util.ifTypes` (`:151-155`) | 162 | a slot target key, or a den class name. Mechanical. |
| `util.ifHMParent` (`:161-169`) | 58 | the same. |
| `util.ifHM` (`:179-183`) | 57 | the same. |
| `util.hasParentOfAnyType` (`:184-188`) | 30 | it walks the ancestor chain, so a flat target key cannot express it. It needs den's scope model. Replaceable, with care. |
| `util.ifNotHMParent` (`:170-178`) | 9 | a target key. |
| `util.isOfType` (`:130-134`) | 6 | a target key. |
| `util.modules.forwardAttrsAsDefaults` (`:194-200`) | 3 | a plain `lib` helper. It needs no pre-pass. |
| `util.hasSops` (`:135-143`) | 2 | it is `moduleType ∈ { nixos, darwin, home-manager }` — a constant per class. |
| `util.loadModules` (`:189-193`) | 2 | den's `batteries.import-tree`, or a slot's own loader. |
| `hostName` (`:66-69`) | 3 | den's host entity already carries `name` and `hostName`. |
| `k8s.clusters` (`modules/meta/k8s/clusters/default.nix:8-91`) | 6 | plain per-cluster data. It fits a `data/` file or a den host schema extension. It needs no pre-pass. |
| `inputs` (`:93`) | 9 | a plain `specialArgs.inputs`. |
| `self` (`:95`) | 50 | a plain `specialArgs`. The count is high, so the flip is large. |
| `nix-configs` (`:96`) | 3 | the same. |
| `lib` (`:94`) | 0 direct | the module system supplies `lib`. |

### Removable — zero call sites outside `modules/meta` itself

`util.emptyParent` (`:109-113`), `util.knownModuleTypes` (`:114-124`), `util.isKnownType`
(`:125-129`), `util.ifTypes'` (`:144-150`), `util.ifNotTypes` (`:156-160`), `util.args`
(`:201-205`), `output.imports` (`:59`).

## The candidate framework: den

Source read: den at rev `d50f0fce6fc1a8ba00fd0d310746d0e8ecc2f70d`, the rev `flake.lock` pins.

### Verdict: PASS, on the den-native route

den has the mechanism. Two parts make it:

1. **Static host data.** `den.schema.host.imports = [ <module> ]` extends the host entity with
   options of your own. den's own template does exactly that, at
   `templates/microvm/modules/microvm-integration.nix:153`.
2. **Entity data drives an `imports` list, at resolve time.** The same template, lines 60-66:

   ```nix
   (include (
     { host }:
     {
       ${host.class}.imports = [ host.microvm.hostModule ];
     }
   ))
   ```

   It reads a host option and writes an `imports` list. It even picks the class key from the
   entity.

den resolves an aspect **before** it calls `instantiate` (`nix/lib/entities/host.nix:80-105`
declares `instantiate`, defaulting to `inputs.nixpkgs.lib.nixosSystem`). So the list is already a
literal when `nixosSystem` runs, and no recursion is possible. This repository already reads
`host.name` and `host.system` this way, at `modules/den/classes/devenv.nix:157`.

### Verdict: FAIL, across the adopter export boundary

`modules/den/lib.nix:119-144` and `modules/den/flake-module.nix:88-106` both throw for an aspect
that takes an entity argument: it resolves to `{ imports = [ ]; }`, a silent no-op. That is this
repository's aspect rule 1, "no entity argument".

The two verdicts do not conflict. They describe two kinds of aspect:

| Kind | May take `{ host, ... }` | Example |
|---|---|---|
| a **host** aspect, inside this repository's own den evaluation | yes | `den.aspects.host-nixos` in `checks/den-mvp/host-nixos/` |
| an **exported library** aspect, in `denModules.*` | no | every aspect in `modules/den/aspects/` |

So the rpi4 concern belongs in a host aspect, not in a library aspect. A library aspect keeps a
plain option and the host sets it — but a plain option cannot drive `imports`, so the conditional
import must live on the host side. **State this in 006.**

### Verdict: UNKNOWN, two questions for 004

1. **Does a den target class module receive `host` through `_module.args`?** den sets
   `config._module.args.host` at `nix/lib/entities/host.nix:154` and
   `nix/lib/entities/home.nix:137`, but both sit inside den's own entity submodule, not inside
   `nixosSystem`. If a target class module does get `host` that way, then a target module cannot
   drive its own `imports` from it — route 2 above recurses. Measure it.
2. **Does den express `parent == null`?** `_stylix.nix:19` needs "am I a standalone home-manager
   evaluation?". den partitions by scope, host versus user, so the question should map onto den's
   scoping. I ran no probe.

## The conformance test

`checks/conditional-imports.nix`, plus two probe files in `checks/conditional-imports/`.

| Part | Assertions | Runs in |
|---|---|---|
| `conditional-imports-mechanism` | 2 — the `specialArgs` route imports the module; the excluded module stays unevaluated | `nix flake check` |
| `conditional-imports-repository` | 3 — `briv` gets all three markers, `oams` gets none, and the flag comes from `meta.json` | `nix flake check` |
| `.recursion` | 2 — the `config` route and the `_module.args` route both recurse | `nix run '.#checks.<system>.conditional-imports-mechanism.recursion'` |

A failure prints `want <json>, got <json>` per assertion and exits 1, the same shape as
`checks/standalone.nix` and `checks/den-mvp/tests.nix` tier 1.

### How to score a candidate framework

Answer three questions. The `mechanism` group names the pass condition for each.

1. Does the framework resolve static per-entity data **before** the target `evalModules`? A
   `specialArgs`-shaped route passes. An `_module.args`-shaped route fails.
2. Does an excluded third-party module stay **unevaluated**? Put a `throw` in it and check.
3. Can the framework answer all three kinds of driving data — hardware data, the evaluation
   universe, and the parent chain?
