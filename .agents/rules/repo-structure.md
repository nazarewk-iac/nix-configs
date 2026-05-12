# Repository Structure

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

## Infrastructure files

| File | Purpose |
|---|---|
| `modules/universal/default.nix` | Entry point: auto-loader, HM injection, platform-specific flake input imports |
| `modules/universal/_options.nix` | Declares `kdn.{enable, hostName, nixConfig}` — loaded in both host and HM contexts |
| `modules/universal/_hm-bootstrap.nix` | HM-specific bootstrap (nixpkgs overlays/config bridging from parent, xdg, systemd) |
| `modules/meta/default.nix` | Meta-module: defines `kdnConfig` structure, `util.*` guards, `mkSubmodule`, `loadModules` |

## Host configurations

Hosts are in `hosts/<name>/` with `meta.json` (moduleType, system, features) + `default.nix`.

Build commands:
```bash
~/dev/github.com/nazarewk-iac/nix-configs/nixos-rebuild.sh build              # local NixOS host
~/dev/github.com/nazarewk-iac/nix-configs/nixos-rebuild.sh build remote=oams  # remote NixOS host
nix run '.#darwin-rebuild' -- switch remote=anji                              # Darwin (builds on remote anji host)
```

**Important**: Darwin hosts must be built on the target machine (or via `remote=<host>`). Do NOT use `nom build .#darwinConfigurations.<host>.system` — it will fail trying to build `aarch64-darwin` derivations locally on a linux host.

```bash
nom build .#sources  # builds symlink tree of all flake inputs for inspection
```

Tested NixOS hosts: brys, etra, oams. Darwin host: anji.
