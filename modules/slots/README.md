---
type: Reference
description: Slots module architecture — how slot modules emit config into the nixos/darwin/home/devenv/users targets, and the standalone rule.
timestamp: 2026-08-29T00:00:00+02:00
---

# Slots Modules Architecture

A **slot** is a self-contained module under `modules/slots/<name>/`. Each slot
provides a small, reusable unit of configuration (a program, a tool, a
service) that a consuming repository or host can enable by name.

This file is the main reference for how slots work. The hard rules live in
[`.agents/rules/slots-standalone.md`](../../.agents/rules/slots-standalone.md);
this README holds the full architecture.

## Directory layout

```
modules/slots/
├── default.nix          # Auto-loader: recursively imports every **/default.nix
├── README.md            # THIS FILE
├── <slot>/
│   ├── default.nix      # The slot module (options + target configs)
│   └── README.md        # Optional per-slot usage doc
```

The slots loader is [`modules/slots/default.nix`](default.nix). It recursively
imports every `**/default.nix` under `modules/slots/` (except itself) into the
devenv-level `kdn-slots` evaluation. So **creating a slot is just adding a
`default.nix`** — no registration step.

The slot "shape" (what targets exist) is declared in
[`lib/slots/schema.nix`](../../lib/slots/schema.nix). The evaluation machinery
(`mkSlots`, `renderTarget`, `renderUsers`) is in
[`lib/slots/default.nix`](../../lib/slots/default.nix).

## A slot module

A slot module is a normal NixOS/HM-style module. It declares **its own**
top-level options (for example `kdn.llm.local.*`) and, in `config`, emits
config into one or more **targets**.

```nix
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.<slot>;
in
{
  options.kdn.<slot> = {
    enable = lib.mkEnableOption "...";
    # ...your own options...
  };

  config = lib.mkIf cfg.enable {
    nixos = { ... };
    home = { ... };
    devenv = { ... };
  };
}
```

## The target options

A slot has exactly these targets, declared in `lib/slots/schema.nix`:

| target | purpose |
|---|---|
| `nixos` | NixOS system module |
| `darwin` | nix-darwin system module |
| `home` | home-manager module (all users via sharedModules) |
| `devenv` | devenv.sh module |
| `users` | per-user home-manager modules, keyed by username |

The slot's outer `config` attribute only ever holds those five keys. It never
holds real NixOS/HM options directly. Real side effects live under a target.

## Emitting into a target: plain attrset vs module function

A target value is a `deferredModule`. You may write it as a plain attrset or
as a module function:

- **Plain attrset** — use when you only need the slot's own options and the
  standard nixpkgs options with static values. No function needed.

  ```nix
  config = lib.mkIf cfg.enable {
    nixos = {
      services.example.enable = true;
      environment.systemPackages = [ pkgs.example ];
    };
  };
  ```

- **Module function** — use when you must read the **target's own evaluated
  config** (the consumer's module set, after renderTarget splicing). Typical
  case: overriding a `systemd.services.*` unit that a nixpkgs module already
  defines, or reading `config.some.option`. Write it with the target's module
  arguments:

  ```nix
  config = lib.mkIf cfg.enable {
    nixos =
      { config, lib, pkgs, ... }:
      {
        services.example.enable = true;
        systemd.services.example.serviceConfig.ReadWritePaths = [ cfg.modelsDir ];
      };
  };
  ```

  The arguments inside the function are the *target* module's arguments, not
  the slot's.

### The two-level confusion trap

The slot's top-level function and each target function both bind names like
`config`, `lib`, `pkgs`. Do not conflate them:

- The **slot** level reads your own options: `config.kdn.<slot>`.
- The **target** level reads the consumer's module set.

Keep both distinct. If you only need your own options, use a plain attrset
and do not declare target-function arguments.

## The standalone rule

A slot must have **no dependency on** `modules/universal/`, `modules/meta/`,
or the `kdnConfig` special argument. Within its target configs it must
**neither reference nor assign** any option declared by those trees — that
includes all `kdn.*` options (`kdn.env.*`, `kdn.disks.*`, `kdn.hw.*`,
`kdn.profile.*`, ...) and `kdnConfig.util.*` guards.

Wiring a slot value into `modules/universal/`-declared options happens only
in the consuming host config (`hosts/*/default.nix`) or the consumer's own
`devenv.nix` — never inside a slot.

Full detail and rationale: [`.agents/rules/slots-standalone.md`](../../.agents/rules/slots-standalone.md).
