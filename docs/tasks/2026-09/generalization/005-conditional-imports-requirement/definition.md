---
type: Task
description: Write down what modules/meta actually solves — data-driven conditional imports of third-party modules — as a testable requirement any target framework must satisfy.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 005 — the conditional-imports requirement

Hub: [../generalization-plan.md](../definition.md). Together with 004 it gates 006.

Goal: state what `modules/meta` solves as a written, testable requirement. Any framework that
replaces it must satisfy the requirement. Without this written down, 006 cannot be decided on
evidence.

## Why this exists

`modules/meta` is not accidental complexity. It solves a real problem, and the plan does **not**
retrofit `modules/universal` into slots partly because that would discard the solution without
replacing it.

## The requirement, as measured

`modules/meta/default.nix:207` declares 5 feature flags: `rpi4`, `installer`, `darwin-utm-guest`,
`microvm-host`, `microvm-guest`.

Those flags are **static data**, not module config. They come from `hosts/<host>/meta.json`, read
at `flake.nix:260`:

| Host | `features` in `meta.json` |
|---|---|
| `briv` | `{"rpi4":true}` |
| `kdn-rpi4-bootstrap` | `{"rpi4":true}` |
| `oams` | `{"microvm-host":true}` |
| the other 12 hosts | none |

`modules/meta` evaluates those flags in a separate `lib.evalModules` universe with
`class = "kdn-meta"`, **before** the NixOS/Darwin/HM evaluation, and injects the result as
`specialArgs.kdnConfig`. That ordering is the whole trick.

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

**Three third-party modules are imported only when a host declares the flag.** A plain
`evalModules` cannot do this from its own `config`, because `imports` must be known before
`config` is evaluated. That is the infinite recursion `modules/meta` avoids.

Other call sites of the same capability:

| File | Flag | Use |
|---|---|---|
| `modules/universal/virtualisation/microvm/guest/default.nix:15` | `microvm-guest` | `imports = … optionals (!flag)` |
| `modules/universal/profile/hardware/darwin-utm-guest/default.nix:13` | `darwin-utm-guest` | gate |
| `modules/universal/virtualisation/microvm/host/default.nix:19` | `microvm-host` | option default |
| `modules/universal/default.nix:109` | `microvm-guest` | `lib.mkIf` on config — **not** an import, so not in scope |
| `hosts/briv/default.nix:17,21`, `hosts/kdn-rpi4-bootstrap/default.nix:13,17` | `rpi4`, `installer` | assertions |

## The critical distinction

The requirement is **data-driven** conditional imports, not **config-driven** conditional imports.

The flags are static JSON per host. Nothing computes them from evaluated module `config`. This
matters directly for 004:

- den's resolution runs before `evalModules`, driven by entity and context **data**. That matches
  this requirement.
- den's open question (#569) is about imports that depend on module **config**. This repo does not
  appear to need that.

So the requirement may be an easier target than it first looks. **Confirm this** — audit for any
site where an `imports` list depends on evaluated `config` rather than on `meta.json` data. If one
exists, it changes the 006 decision.

## Deliverables

1. **The requirement statement** — one paragraph, precise enough to test against a framework.
2. **The audit** — every site where `imports` depends on data, and a confirmed statement that no
   site depends on evaluated `config` (or the list of sites that do).
3. **A conformance test** — a minimal reproduction that a candidate framework either passes or
   fails. It should express: "given a host that declares flag X as data, import third-party module
   Y; given a host that does not, do not import it, and do not evaluate it."
4. **What else `modules/meta` provides**, so nothing is lost silently. Beyond `features.*` it
   supplies `util.ifTypes`/`ifHM`/`ifHMParent`/`hasParentOfAnyType`/`loadModules`/`hasSops`,
   `output.mkSubmodule`, `hostName`, `k8s.clusters`, and the `parent`/`parents` chain. For each,
   state whether it is essential, replaceable, or removable.

Useful measured context for item 4: 182 of 194 files in `modules/universal/` reference
`kdnConfig`, across 316 guard call sites — but **275 of those 316 map directly onto slot target
keys**, so the guards are largely mechanical. The genuinely hard part is the conditional imports
above, plus the option coupling described in 006.

## Exit criteria

The conformance test from item 3 exists and runs. 004 can be scored against it.
