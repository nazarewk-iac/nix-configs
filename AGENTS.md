# AGENTS.md

**AI Agent Guidance for nix-configs Repository**

## Key Principles

### Formatting
**All Nix files MUST be formatted with `nixfmt`** before committing. Run `nixfmt <file>` on any modified `.nix` files. The project uses the RFC-style `nixfmt` (from nixpkgs), not the older `nixfmt-classic`.

### Module Design
**All modules MUST be side-effect free by default** (enabled via `*.enable` options).

**Note**: The meta-module (`modules/meta/`) provides an escape hatch for integrating third-party modules with unconditional imports that don't adhere to this pattern.

### Version Control

This repo uses **Jujutsu (`jj`)** instead of raw git. Key differences:

- **`jj new -m "description"`** to create a new change (like a commit checkpoint)
- **`jj describe -m "..."`** to update the current change's description
- **`jj abandon @`** to discard the current change and revert to parent
- **`jj squash`** to fold the current change into its parent
- **`jj diff --from REV`** to compare against a previous state

**Workflow**: create frequent small changes with `jj new` as checkpoints during work. This makes it easy to `jj abandon` if something breaks. Once a logical unit of work is done, squash related changes together with `jj squash` so the history stays clean and reviewable.

- **Always leave an empty `jj` change on top** when finishing work — this gives the user a clean working copy to review from
- **NEVER push changes** (user will review and push)
- Use conventional commit format (feat:, docs:, chore:, fix:)

## Repository Structure

```
nix-configs/
├── flake.nix              # Main entry point
├── modules/
│   ├── meta/              # Core infrastructure & specialArgs
│   └── universal/         # ALL modules (heterogeneous, context-aware)
│       ├── _options.nix       # Top-level kdn.* option declarations (loaded in all contexts)
│       ├── _hm-bootstrap.nix  # Home Manager bootstrap config (nixpkgs, xdg, etc.)
│       ├── _stylix.nix        # Stylix theme integration
│       ├── default.nix        # Entry point: loader, imports, HM injection, platform configs
│       ├── apps/              # Application framework (kdn.apps.*)
│       ├── desktop/           # Desktop environments (sway, kde, base)
│       ├── development/       # Dev tooling (languages, tools, IDEs)
│       ├── disks/             # Disk/persistence management
│       ├── hw/                # Hardware modules (gpu, audio, yubikey, etc.)
│       ├── networking/        # Network config (netbird, tailscale, router, etc.)
│       ├── profile/           # Machine & user profiles
│       ├── programs/          # Individual program configs
│       ├── security/          # Secrets, disk encryption, secure boot
│       ├── services/          # System services
│       └── ...
├── hosts/                 # Per-host configurations (meta.json + default.nix)
├── lib/                   # Custom lib.kdn.* utilities
└── packages/              # Custom pkgs.kdn.* packages
```

## Module Architecture

### Single Universal Tree

All modules live in `modules/universal/`. Each module is loaded in ALL contexts (NixOS host, Darwin host, Home Manager) via the auto-loader. Modules use `kdnConfig.util.*` guards to scope their behavior per context.

### Context Guards

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

### Auto-loader

`modules/universal/default.nix` recursively loads:
- `**/default.nix` in HOST context (nixos/darwin)
- `**/default.nix` in HM context (via `home-manager.sharedModules` injection)

Files NOT ending in `/default.nix` (e.g. `keys.nix`, `bundle.nix`) are NOT auto-loaded. They must be imported explicitly.

### Standard Module Pattern

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
      # NixOS-only packages (systemd tools, kernel tools, etc.)
      kdn.env.packages = with pkgs; [ some-linux-only-tool ];
    })
    # Home Manager-specific config (programs.*, HM services, etc.)
    (kdnConfig.util.ifHM {
      programs.foo.enable = true;
    })
  ]);
}
```

### Cross-Platform Packages and Variables

**Use `kdn.env.packages` and `kdn.env.variables`** instead of platform-specific options. The `kdn.env` module (in `modules/universal/env/default.nix`) dispatches to the right target:

| `kdn.env.*` | NixOS | Darwin | Home Manager |
|---|---|---|---|
| `kdn.env.packages` | `environment.systemPackages` | `environment.systemPackages` | `home.packages` |
| `kdn.env.variables` | `environment.sessionVariables` | `environment.variables` | `home.sessionVariables` |

**Rules:**
- Generic cross-platform packages → `kdn.env.packages` **outside** any `ifTypes` guard
- NixOS-only tooling (systemd, kernel, hardware, Linux desktop) → `kdn.env.packages` **inside** `ifTypes ["nixos"]`
- HM-only packages (helix LSP extensions, `programs.*` deps) → `kdn.env.packages` inside `ifHM`
- **Never use** `environment.systemPackages`, `home.packages`, `environment.sessionVariables`, `home.sessionVariables`, or `environment.variables` directly (except in `env/default.nix` itself and `locale/default.nix` which is special)

### Accessing Parent NixOS Config from HM

In HM context, use `osConfig` as a **function argument** (not `config.osConfig`):

```nix
{config, osConfig ? {}, ...}: let
  hasWorkstation = (osConfig.kdn or {}).profile.machine.workstation.enable or false;
in { ... }
```

### Key Rules

1. **Options are always declared unconditionally** (outside any guard) so they exist in all contexts
2. **`ifHM`/`ifTypes` only wrap `config`**, never `options`
3. **`ifHMParent` forwarding** pushes parent module values into HM as `lib.mkDefault cfg`
4. **`home-manager.sharedModules` with `kdn.*` enables** must use `ifHMParent`, not `ifTypes ["nixos"]`
5. **Option defaults referencing host-only config** (e.g. `config.fileSystems`) must be guarded:
   ```nix
   default = if kdnConfig.moduleType == "nixos" then expr else fallback;
   ```
6. **Files imported explicitly** (not auto-loaded) that run in HM context should use `ifHM` on their config, not `ifTypes ["nixos"]`
7. **Outer `config` should use `lib.mkIf cfg.enable (lib.mkMerge [...])`** with platform guards inside, not wrapping the entire config in a single `ifTypes`

### Special Arguments (kdnConfig)

Propagated via `kdnConfig.output.mkSubmodule` (in `modules/meta/`):
- `kdnConfig.inputs` - Flake inputs
- `kdnConfig.lib` - Extended library
- `kdnConfig.self` - Self-reference to flake
- `kdnConfig.moduleType` - Current module type: `"root"`, `"nixos"`, `"darwin"`, `"home-manager"`, `"checks"`, `"easykubenix"`
- `kdnConfig.features.*` - Feature flags (rpi4, microvm-host, darwin-utm-guest, etc.)
- `kdnConfig.parent` - Parent context (snapshot of parent meta config)
- `kdnConfig.parents` - Full parent chain
- `kdnConfig.util.*` - Guard functions (ifTypes, ifHM, ifHMParent, hasParentOfAnyType, loadModules, etc.)

### Infrastructure Files

| File | Purpose |
|---|---|
| `modules/universal/default.nix` | Entry point: auto-loader, HM injection, platform-specific flake input imports, darwin/nixos top-level config |
| `modules/universal/_options.nix` | Declares `kdn.{enable, hostName, nixConfig}` — loaded in both host and HM contexts |
| `modules/universal/_hm-bootstrap.nix` | HM-specific bootstrap (nixpkgs overlays/config bridging from parent, xdg, systemd) |
| `modules/meta/default.nix` | Meta-module: defines `kdnConfig` structure, `util.*` guards, `mkSubmodule`, `loadModules` |

## Host Configurations

Hosts are in `hosts/<name>/` with `meta.json` (moduleType, system, features) + `default.nix`.

Build commands:
```bash
~/dev/github.com/nazarewk-iac/nix-configs/nixos-rebuild.sh build              # local NixOS host
~/dev/github.com/nazarewk-iac/nix-configs/nixos-rebuild.sh build remote=oams  # remote NixOS host
nix run "$HOME/dev/github.com/nazarewk-iac/nix-configs#darwin-rebuild" -- switch anji       # Darwin (run on anji directly)
```

Tested NixOS hosts: brys, etra, oams. Darwin host: anji.

## External Resources

- **NixOS**: https://nixos.org
- **Home Manager**: https://github.com/nix-community/home-manager
- **nix-darwin**: https://github.com/LnL7/nix-darwin
