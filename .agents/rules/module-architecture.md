# Module Architecture

## Single Universal Tree

All modules live in `modules/universal/`. Each module is loaded in ALL contexts (NixOS host, Darwin host, Home Manager) via the auto-loader. Modules use `kdnConfig.util.*` guards to scope their behavior per context.

## Auto-loader

`modules/universal/default.nix` recursively loads:
- `**/default.nix` in HOST context (nixos/darwin)
- `**/default.nix` in HM context (via `home-manager.sharedModules` injection)

Files NOT ending in `/default.nix` (e.g. `keys.nix`, `bundle.nix`) are NOT auto-loaded — must be imported explicitly.

## Context Guards

Available via `kdnConfig.util.*` (defined in `modules/meta/default.nix`):

| Guard | Returns data when | Returns `{}` when |
|---|---|---|
| `ifTypes ["nixos"]` | moduleType is nixos | anything else |
| `ifTypes ["darwin"]` | moduleType is darwin | anything else |
| `ifTypes ["nixos" "darwin"]` | moduleType is nixos or darwin | anything else |
| `ifHM` | moduleType is home-manager | anything else |
| `ifHMParent` | moduleType is nixos/darwin/nix-on-droid (HM parent) | home-manager or other |
| `ifNotHMParent` | moduleType is home-manager | nixos/darwin/nix-on-droid |
| `hasParentOfAnyType ["nixos"]` | HM with nixos parent (bool) | — |

## Special Arguments (kdnConfig)

Propagated via `kdnConfig.output.mkSubmodule` (in `modules/meta/`):
- `kdnConfig.inputs` — Flake inputs
- `kdnConfig.lib` — Extended library
- `kdnConfig.self` — Self-reference to flake
- `kdnConfig.moduleType` — Current module type: `"root"`, `"nixos"`, `"darwin"`, `"home-manager"`, `"checks"`, `"easykubenix"`
- `kdnConfig.features.*` — Feature flags (rpi4, microvm-host, darwin-utm-guest, etc.)
- `kdnConfig.parent` — Parent context (snapshot of parent meta config)
- `kdnConfig.parents` — Full parent chain
- `kdnConfig.util.*` — Guard functions (ifTypes, ifHM, ifHMParent, hasParentOfAnyType, loadModules, etc.)

## Standard Module Pattern

```nix
{lib, config, kdnConfig, pkgs, ...}: let
  cfg = config.kdn.some.module;
in {
  options.kdn.some.module = {
    enable = lib.mkEnableOption "description";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Forward enable to HM children
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [{kdn.some.module = lib.mkDefault cfg;}];
    })
    # Cross-platform packages/variables (available everywhere)
    {
      kdn.env.packages = with pkgs; [ some-tool ];
    }
    # NixOS-specific config (services, hardware, etc.)
    (kdnConfig.util.ifTypes ["nixos"] {
      services.foo.enable = true;
      kdn.env.packages = with pkgs; [ some-linux-only-tool ];
    })
    # Home Manager-specific config (programs.*, HM services, etc.)
    (kdnConfig.util.ifHM {
      programs.foo.enable = true;
    })
  ]);
}
```

## Cross-Platform Packages and Variables

**Use `kdn.env.packages` and `kdn.env.variables`** instead of platform-specific options:

| `kdn.env.*` | NixOS | Darwin | Home Manager |
|---|---|---|---|
| `kdn.env.packages` | `environment.systemPackages` | `environment.systemPackages` | `home.packages` |
| `kdn.env.variables` | `environment.sessionVariables` | `environment.variables` | `home.sessionVariables` |

- Generic cross-platform packages → `kdn.env.packages` **outside** any `ifTypes` guard
- NixOS-only tooling → `kdn.env.packages` **inside** `ifTypes ["nixos"]`
- HM-only packages → `kdn.env.packages` inside `ifHM`
- **Never use** `environment.systemPackages`, `home.packages`, `environment.sessionVariables`, `home.sessionVariables`, or `environment.variables` directly (except in `env/default.nix` and `locale/default.nix`)

## Accessing Parent NixOS Config from HM

```nix
{config, osConfig ? {}, ...}: let
  hasWorkstation = (osConfig.kdn or {}).profile.machine.workstation.enable or false;
in { ... }
```

## Key Rules

1. **Options declared unconditionally** (outside any guard) so they exist in all contexts
2. **`ifHM`/`ifTypes` only wrap `config`**, never `options`
3. **`ifHMParent` forwarding** pushes parent module values into HM as `lib.mkDefault cfg`
4. **`home-manager.sharedModules` with `kdn.*` enables** must use `ifHMParent`, not `ifTypes ["nixos"]`
5. **Option defaults referencing host-only config** (e.g. `config.fileSystems`) must be guarded:
   ```nix
   default = if kdnConfig.moduleType == "nixos" then expr else fallback;
   ```
6. **Files imported explicitly** (not auto-loaded) that run in HM context should use `ifHM`, not `ifTypes ["nixos"]`
7. **Outer `config`** should use `lib.mkIf cfg.enable (lib.mkMerge [...])` with platform guards inside
