---
type: Rule
description: Documents repo directory layout and host build commands.
timestamp: 2026-07-02T14:00:04+02:00
---

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

## Local devenv slot settings

`devenv.nix` loads exactly one extra file into its `mkSlots` call: `devenv.slots.local.nix`.
Git ignores it, so no commit chain can add or remove it. It holds `kdn.*` slot settings only.
A path literal reaches an untracked file; only `inputs.nix-configs` (`git+file:.`) is
git-filtered.

**When the file is missing, restore it before you do other work.** Look for an example file and
copy it:

```bash
ls devenv.slots.local.*.example.nix
cp devenv.slots.local.<name>.example.nix devenv.slots.local.nix
```

Then re-enter the devenv shell. Some settings only take effect after that — for example
`kdn.jj.fork.enable`, which supplies the fork revset aliases (`jj fork-audit`,
`jj sync-remotes`) and the push checks.

Two things `devenv.nix` deliberately does NOT do:

- It does not scan the directory for `devenv.*.nix` files. A tracked file belongs to one commit
  chain. When the working copy moves to a chain without the file, jj deletes it and the settings
  turn off with no warning.
- It does not use devenv's own `devenv.local.nix`. devenv loads that file into the devenv module
  set, where the `kdn.*` slot options do not exist.

## Discovering devenv options

When the MCP gateway is unavailable, use `WebFetch` on **https://devenv.sh/reference/options/** to look up devenv module options (git-hooks, files, packages, etc.).

Alternatively, grep the devenv source directly from the Nix store:
```bash
DEVENV_SRC=$(nix flake prefetch "github:cachix/devenv/$(jq -r '.nodes.devenv.locked.rev' flake.lock)" --json | jq -r '.storePath')
grep -rn "your-option" "$DEVENV_SRC/src/modules/"
```
