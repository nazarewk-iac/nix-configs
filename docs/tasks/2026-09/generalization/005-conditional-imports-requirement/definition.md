---
type: Task
description: Write down what modules/meta actually solves — data-driven conditional imports of third-party modules — as a testable requirement any target framework must satisfy.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 005 — the conditional-imports requirement

Hub: [../generalization-plan.md](../definition.md). Together with 004 it gates 006.

Goal: state what `modules/meta` solves as a written, testable requirement. Any framework that
replaces it must satisfy the requirement. Without this written down, nobody can decide 006 on
evidence.

## Why this exists

`modules/meta` is not accidental complexity. It solves a real problem. The plan does **not**
retrofit `modules/universal` into slots. One reason: a retrofit discards the solution and puts
nothing in its place.

## The requirement, as measured

`modules/meta/default.nix:207` declares 5 feature flags: `rpi4`, `installer`, `darwin-utm-guest`,
`microvm-host`, `microvm-guest`.

Those flags are **static data**, not module config. They come from `hosts/<host>/meta.json`, which
`flake.nix:260` reads:

| Host | `features` in `meta.json` |
|---|---|
| `briv` | `{"rpi4":true}` |
| `kdn-rpi4-bootstrap` | `{"rpi4":true,"installer":true}` |
| `oams` | `{"microvm-host":true}` |
| the other 12 hosts | none |

The table covers the **15** host directories that carry a `meta.json`. `hosts/` holds 16
directories; `hosts/install-iso/` has no `meta.json`, because it is an installer image and not a
host. So 3 + 12 = 15 is right, and a "16 hosts" figure elsewhere counts the image too.

`modules/meta` evaluates those flags in a separate `lib.evalModules` universe with
`class = "kdn-meta"`. It runs **before** the NixOS/Darwin/HM evaluation. It then injects the result
as `specialArgs.kdnConfig`. That order is the whole trick.

The payoff is at `modules/universal/profile/hardware/rpi4/default.nix:22`:

```nix
  imports = self.lib.lists.optionals rpi4.any (
    [
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ]
    ++ self.lib.lists.optionals rpi4.any [
      inputs.argon40-nix.nixosModules.default
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
    ]
    ++ self.lib.lists.optional rpi4.installer "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
  );
```

**The tree imports three third-party modules only when a host declares the flag.** A plain
`evalModules` cannot do this from its own `config`. `imports` must resolve before the evaluation of
`config`. That is the infinite recursion `modules/meta` avoids.

**Correction, measured on 2026-09-11.** A plain `lib.evalModules` **can** meet this requirement.
`specialArgs` reaches `imports`, because Nix resolves a `specialArgs` value before the module set.
Only two routes recurse: module `config`, and `_module.args`. So `modules/meta` is not the
capability — it is a typed pre-pass that computes the `specialArgs` payload. A candidate framework
needs one `specialArgs`-shaped route and nothing more. That makes the requirement a much easier
target than the hub states. See [research.md](research.md) § "The four routes".

Other call sites of the same capability:

| File | Flag | Use |
|---|---|---|
| `modules/universal/virtualisation/microvm/guest/default.nix:15` | `microvm-guest` | `imports = … optionals (!flag)` |
| `modules/universal/profile/hardware/darwin-utm-guest/default.nix:13` | `darwin-utm-guest` | gate |
| `modules/universal/virtualisation/microvm/host/default.nix:19` | `microvm-host` | option default |
| `modules/universal/default.nix:135` | `microvm-guest` | `lib.mkIf` on config — **not** an import, so not in scope |
| `hosts/briv/default.nix:17,21`, `hosts/kdn-rpi4-bootstrap/default.nix:13,17` | `rpi4`, `installer` | assertions |

## The critical distinction

The requirement is **data-driven** conditional imports, not **config-driven** conditional imports.

The flags are static JSON per host. Nothing computes them from evaluated module `config`. This
matters directly for 004:

- den's resolution runs before `evalModules`. Entity and context **data** drive it. That matches
  this requirement.
- den's open question (#569) is about imports that depend on module **config**. This repo does not
  appear to need that.

So the requirement may be an easier target than it first looks. **Confirm this** — audit for any
site where an `imports` list depends on evaluated `config` rather than on `meta.json` data. If one
exists, it changes the 006 decision.

## Deliverables

1. **The requirement statement** — one paragraph, precise enough to test against a framework.
2. **The audit** — every site where `imports` depends on data. Add a confirmed statement that no
   site depends on evaluated `config`. List the sites that do, if any exist.
3. **A conformance test** — a minimal reproduction that a candidate framework either passes or
   fails. It should express: "given a host that declares flag X as data, import third-party module
   Y; given a host that does not, do not import it, and do not evaluate it."
4. **What else `modules/meta` provides**, so you lose nothing silently. Beyond `features.*` it
   supplies `util.ifTypes`/`ifHM`/`ifHMParent`/`hasParentOfAnyType`/`loadModules`/`hasSops`,
   `output.mkSubmodule`, `hostName`, `k8s.clusters`, and the `parent`/`parents` chain. For each,
   state whether it is essential, replaceable, or removable.

Useful measured context for item 4: 182 of 194 files in `modules/universal/` reference `kdnConfig`,
across 316 guard call sites. But **275 of those 316 map directly onto slot target keys**, so the
guards are largely mechanical. The genuinely hard part is the conditional imports above, plus the
option coupling that 006 describes.

## Exit criteria

The conformance test from item 3 exists and runs. You can score 004 against it.

Met on 2026-09-11.

## The deliverables, as landed

| Item | Where |
|---|---|
| 1. the requirement statement | [done.md](done.md) § "Solution" |
| 2. the audit | [research.md](research.md) § "Every `imports` site" — 37 sites, **0** driven by evaluated `config` |
| 3. the conformance test | `checks/conditional-imports.nix` plus `checks/conditional-imports/` |
| 4. what else `modules/meta` provides | [research.md](research.md) § "The rest of `modules/meta`" |

The audit found **6** third-party conditional import sites, not 3. Three kinds of static data
drive them: `features.*` at 3 sites, `moduleType` at 5 sites, `parent == null` at 1 site. Two
sites the text above misses are `modules/universal/default.nix:21` and
`modules/universal/_stylix.nix:19`.

Run the test:

```bash
nix build '.#checks.aarch64-darwin.conditional-imports-mechanism'
nix build '.#checks.aarch64-darwin.conditional-imports-repository'
nix run   '.#checks.aarch64-darwin.conditional-imports-mechanism.recursion'
```
