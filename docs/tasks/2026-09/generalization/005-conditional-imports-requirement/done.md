---
type: Solution
description: The conditional-imports requirement, as a testable statement, plus the three-part conformance test that scores a candidate framework.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T12:00:00Z
---

# 005 — the conditional-imports requirement, solved

Parent: [definition.md](definition.md). Measurements: [research.md](research.md).

## Root cause analysis

The hub overstated the problem. It claimed a plain `lib.evalModules` cannot import a third-party
module from static per-host data. That claim made `modules/meta` look irreplaceable, so nobody
could score a candidate framework.

A probe of the four routes into `imports` corrected the claim. Two routes work and two recurse
([research.md](research.md) § "The four routes"):

| Route | Result |
|---|---|
| module `config` → `imports` | infinite recursion |
| `_module.args` → `imports` | infinite recursion |
| `specialArgs` → `imports` | works |
| `specialArgs` false, poisoned module | the module stays unevaluated |

nixpkgs names the cause itself, at `lib/modules.nix:269`. So `modules/meta` is not the capability.
It is a typed pre-pass that computes the `specialArgs` payload, in three parts: the root
evaluation at `flake.nix:269-278`, the per-host evaluation at `flake.nix:279-301`, and the
injection at `modules/meta/default.nix:86-92`.

A second root cause sat in the count. The task text named 3 conditional import sites. The audit
found **6**, and it found **0** sites that read evaluated `config`. The two missed sites are
`modules/universal/default.nix:21` and `modules/universal/_stylix.nix:19`, and both are
essential.

`builtins.tryEval` hid the negative half of the test. It catches a `throw` and does not catch
`error: infinite recursion encountered`. So no in-Nix assertion can state "this route must
fail".

## Solution

### The requirement statement

A candidate framework must resolve static per-entity data **before** it evaluates the target
module set. It must expose that data on a route that reaches `imports`. A `specialArgs`-shaped
route meets the requirement. A module `config` route and an `_module.args` route both recurse, so
both fail. The framework must import a third-party module only when the data asks for it, and it
must leave an excluded module unevaluated. The data has three kinds: hardware data per host, the
evaluation universe, and the parent chain.

### The three kinds of driving data

| Kind | Sites | The question it answers |
|---|---|---|
| `features.*` from `hosts/<host>/meta.json` | 3 | does this machine have that hardware? |
| `moduleType` | 5 | which evaluation universe am I in? |
| `parent == null` | 1 | am I a standalone home-manager evaluation? |

A framework must answer all three. den answers `moduleType` for free, because it names one class
per target.

### The conformance test

`checks/conditional-imports.nix` plus two probe files in `checks/conditional-imports/`. It has
three parts:

| Part | Assertions | What it proves |
|---|---|---|
| `conditional-imports-mechanism` (`:87-119`) | 2 | the `specialArgs` route imports the module, and the excluded module stays unevaluated |
| `conditional-imports-repository` (`:183-213`) | 3 | `briv` gets all three rpi4 markers, `oams` gets none, and the flag comes from `meta.json` |
| `.recursion` (`:123-130`) | 2 | the `config` route and the `_module.args` route both recurse |

The recursion part is an app, not a check, because a build sandbox has no daemon. It reaches the
two probe files through `passthru.recursion` on the mechanism check (`:216-223`).

`checks/default.nix:51-54` wires the file in. `checks/bundles.nix:75-85` puts both checks in
`bundle-core`.

### The scoring questions

A candidate framework answers three questions ([research.md](research.md) § "How to score a
candidate framework"):

1. Does it resolve static per-entity data before the target `evalModules`?
2. Does an excluded third-party module stay unevaluated?
3. Does it answer all three kinds of driving data?

den scores **PASS** on its native route and **FAIL** across the adopter export boundary. A den
library aspect may take no entity argument, so a conditional import must live in a host aspect.

## Verification steps

```bash
SYS=aarch64-darwin   # or x86_64-linux, or aarch64-linux
nix build --no-eval-cache -L ".#checks.$SYS.conditional-imports-mechanism"    # 1.3 s
nix build --no-eval-cache -L ".#checks.$SYS.conditional-imports-repository"   # 2.0 s
nix run "$PWD#checks.$SYS.conditional-imports-mechanism.recursion"
nix build --no-eval-cache -L --keep-going ".#checks.$SYS.bundle-core"         # 11.1 s
```

The two times come from [checks/README.md](../../../../../checks/README.md), rows
`conditional-imports-mechanism` and `conditional-imports-repository`. `bundle-core` holds both.

A failed assertion prints `want <json>, got <json>` and exits 1, the same shape as
`checks/standalone.nix`.

## Follow-up notes

- **Two questions stay UNKNOWN, and 004 owns them.** Does a den target class module receive
  `host` through `_module.args`? den sets `config._module.args.host` at
  `nix/lib/entities/host.nix:154`, inside its own entity submodule. If a target module gets it
  that way, that module cannot drive its own `imports` from it. Second: does den express
  `parent == null`? I ran no probe.
- **006 must record the export-boundary verdict.** `modules/den/lib.nix:119-144` and
  `modules/den/flake-module.nix:88-106` both resolve an entity-argument aspect to
  `{ imports = [ ]; }`, a silent no-op.
- **Two live-code corrections.** `hosts/kdn-rpi4-bootstrap/meta.json` holds
  `{"rpi4":true,"installer":true}`. And `hosts/brys/default.nix:296` sets
  `kdn.features.microvm-guest = true` inside the comment block that spans `:280-338`, so it is
  dead code on a path no module declares.
- **Do not prove a refactor here with `drvPath` equality.** `kdnConfig.self` reaches evaluated
  config, so any edit moves every host `drvPath`. Probe option values instead.
