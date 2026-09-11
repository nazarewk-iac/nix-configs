---
type: Rule
description: Slots modules must be standalone — no dependency on or assignment of modules/universal- or modules/meta-declared options inside their own target configs.
timestamp: 2026-08-29T00:00:00+02:00
---

# Slots Modules Standalone

A **slot** is any module under `modules/slots/**/default.nix`.

The full slots architecture (loader, targets, how to emit config) is in
[`modules/slots/README.md`](../../modules/slots/README.md). This file is the
hard **rule**; it lists what a slot may and must not do.

## Hard prohibition

Within its own target configs (`nixos`, `darwin`, `home`, `devenv`, `users`),
a slot must **neither reference nor assign** any option declared by
`modules/universal/` or `modules/meta/`.

This explicitly includes, but is not limited to, all `kdn.*` options:

- `kdn.env.packages`
- `kdn.env.variables`
- `kdn.disks.*`
- `kdn.hw.*`
- `kdn.profile.*`
- `kdn.networking.*`
- any other `kdn.*` option declared in the universal tree
- the `kdnConfig` special argument and `kdnConfig.util.*` guards
- any helper function or module imported from `modules/universal/`
  or `modules/meta/`

## Enforcement

`checks/standalone.nix` enforces this rule. It exports two checks:

| Check | It gates |
|---|---|
| `standalone-slots` | every `.nix` file under `modules/slots/` |
| `standalone-aspects` | every `.nix` file under `modules/den/aspects/` |

`standalone-slots` runs two mechanisms. A **source scan** greps each slot file for every
`kdn.*` leaf that `modules/universal/` declares, for the `modules/meta/` prefix, and for
`kdnConfig`. A **tree resolve** renders the whole slots tree through `mkSlots` with `pkgs` and
`inputs` as the only special arguments, so a slot that takes `kdnConfig` fails there.

The scan drops a whole-line comment and keeps a trailing comment. So a rule name inside a
trailing comment fails the check. Put such a name on its own comment line.

The scan cannot see a computed path such as `kdn.${name}.x`. Do not build one.

Run the gate:

```bash
nix build '.#checks.aarch64-darwin.standalone-slots'
```

There is **no allowlist for a slot**. Zero slots violate the rule, measured 2026-09-11, and the
check passes with 2 of 2 assertions. Keep it that way: fix the slot, never the check.

## What a slot may use

A slot may use the standard NixOS/HM module arguments:

- `lib`
- `pkgs`
- `config`
- `options`
- `inputs`
- `moduleType`

It may use plain nixpkgs options (`services.*`, `systemd.*`,
`environment.systemPackages`, etc.) directly — those belong to nixpkgs, not
to `modules/universal/`, and are always available.

A slot defines and serves **its own** options (for example `kdn.llm.local.*`)
and emits only those plus the plain nixpkgs options above.

## Emitting config: target options, never a flat `config`

A slot emits side effects only through the target options
(`nixos`/`darwin`/`home`/`devenv`/`users` from `lib/slots/schema.nix`). The
outer `config` attribute holds only those five keys — never real NixOS/HM
options directly.

Writer a target as a **plain attrset** when it only needs static values, or
as a **module function** (`{ config, lib, pkgs, ... }`) when it must read the
consumer's own evaluated config. Do not confuse the slot's function arguments
(your options via `config.kdn.<slot>`) with the target function's arguments
(the consumer's module set).

See `modules/slots/README.md` § "Emitting into a target" for the exact
patterns and the two-level trap.

## Where the universal wiring happens

Wiring a slot value into `modules/universal/`-declared options is only
allowed in the consuming host config:

- `hosts/*/default.nix` for NixOS/Darwin hosts
- the consumer's own `devenv.nix` for devenv shells

Do not do that wiring inside the slot.

## Why

`modules/universal/` and `modules/meta/` are deprecated and will be
rewritten. Slots must not inherit anything from them so that this rewrite
cannot break a standalone slot. A slot that uses only `lib`, `pkgs`,
`config`, `inputs`, `moduleType`, and plain nixpkgs options keeps working
unchanged no matter what happens to the rest of the repo.
