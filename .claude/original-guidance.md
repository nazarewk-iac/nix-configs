# Original Claude Code Guidance

This file contains the original CLAUDE.md content that was at the repository root. It provides practical guidance for working with the repository.

---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal Nix configuration repository managing NixOS, Home Manager, and nix-darwin configurations across multiple machines using a flake-based approach.

**Key Principle**: All modules MUST be side-effect free by default (enabled via `*.enable` options).

## Architecture

### Module Structure

The repository uses a three-tier module system:

- `modules/nixos/` - NixOS-specific modules
- `modules/home-manager/` - Home Manager modules
- `modules/nix-darwin/` - nix-darwin (macOS) modules
- `modules/shared/` - Cross-platform modules:
  - `modules/shared/universal/` - Universal modules defining options
  - `modules/shared/darwin-nixos-os/` - Shared between Darwin and NixOS

All modules automatically import their subdirectories' `default.nix` files through `lib.filesystem.listFilesRecursive`.

### Special Arguments System

The flake uses a custom `kdn.configure` function (in `flake.nix:270-316`) to propagate special arguments (`specialArgs`) through module boundaries. This enables:

- Passing `kdn` argument containing `self`, `inputs`, `lib`, and feature flags
- Tracking parent contexts through `kdn.parent`
- Type checking with `kdn.moduleType` and `kdn.isOfAnyType`
- Feature flags in `kdn.features` (e.g., `rpi4`, `microvm-host`, `chromeos-crostini-vm`)

### Host Configurations

Each host has a configuration at `modules/nixos/profile/host/${HOSTNAME}/default.nix` or defined directly in `flake.nix`. Hosts include:
- x86_64-linux: oams, brys, etra, pryll, obler, moss, gaz
- aarch64-linux: faro, briv, rpi4-bootstrap
- aarch64-darwin: anji

### Library Extensions

Custom library utilities in `lib/` extend `nixpkgs.lib` with:
- `lib.kdn.*` - Custom utilities organized by subdirectory names
- Recursive module loading pattern used throughout

### Overlays

The flake provides overlays (`self.overlays.packages` and `self.overlays.default`) that:
- Add custom packages under `pkgs.kdn.*`
- Include NUR, microvm, and platform-specific overlays (brew-nix for Darwin)
- Are automatically applied to all configurations via `modules/shared/darwin-nixos-os/`

## Development Commands

### Building Configurations

```bash
# Build a NixOS configuration
nix build '.#nixosConfigurations.<hostname>.config.system.build.toplevel'

# Build the install ISO
nix build '.#install-iso'
nom build '.#install-iso' --no-link --print-out-paths --print-build-logs  # with nix-output-monitor

# Build nix-darwin configuration
nix build '.#darwinConfigurations.anji.system'
```

### Flake Updates

```bash
# Update all inputs and apply patches
nix run '.#update' g:all

# Update only upstream inputs (those ending in -upstream)
nix run '.#update' g:upstreams

# Update and apply patches from .flake.patches/config.toml
nix run '.#update' g:patches

# Update specific input
nix run '.#update' i:nixpkgs
```

The update script (`flake-update.sh`) orchestrates:
1. `nix flake update` for specified inputs
2. `.flake.patches/update.py` to apply patches from `.flake.patches/config.toml`

### Checking

```bash
# Run checks
nix flake check
```

### REPL

```bash
# Interactive REPL with flake loaded
nix run '.#repl'
```

## Disk Configuration & Deployment

This repository uses `disko` for declarative disk partitioning with ZFS-on-LUKS and impermanence.

### Disk Setup Pattern

Typical disk configuration involves:
- Detached `/boot` on USB drive with LUKS headers
- ZFS pool on LUKS-encrypted devices
- Impermanence with ZFS snapshots for selective persistence
- Unlocking via TPM2 (unattended) or YubiKey FIDO2 (attended)

See README.md "Golden path for bootstrapping new physical machine" for detailed steps.

### Deploying with nixos-anywhere

```fish
# Deploy to a machine (Fish shell syntax)
set HOST_NAME <hostname>
set DISK_NAME <disk-name>
set HOST_CONNECTION root@<ip-address>

nixos-anywhere --phases disko,install \
  --disk-encryption-keys "/tmp/$DISK_NAME-$HOST_NAME.key" "$(pass show "luks/$DISK_NAME-$HOST_NAME/keyfile" | psub)" \
  --flake ".#$HOST_NAME" "$HOST_CONNECTION"

# Build on target for slower machines
nixos-anywhere --phases disko,install --build-on-remote \
  --disk-encryption-keys "/tmp/$DISK_NAME-$HOST_NAME.key" "$(pass show "luks/$DISK_NAME-$HOST_NAME/keyfile" | psub)" \
  --flake ".#$HOST_NAME" "$HOST_CONNECTION"
```

### LUKS Key Management

```fish
# Generate keyfile
dd if=/dev/random bs=1 count=2048 of=/dev/stdout | pass insert --force --multiline "luks/$DISK_NAME-$HOST_NAME/keyfile"

# Enroll TPM2 (unattended unlock)
ssh "$HOST_CONNECTION" sudo systemd-cryptenroll \
  --unlock-key-file="/tmp/$DISK_NAME-$HOST_NAME.key" \
  --tpm2-device=auto \
  "/dev/disk/by-partlabel/$DISK_NAME-$HOST_NAME-header"

# Enroll YubiKey FIDO2 (attended unlock)
ssh "$HOST_CONNECTION" sudo systemd-cryptenroll \
  --unlock-key-file="/tmp/$DISK_NAME-$HOST_NAME.key" \
  --fido2-device=auto \
  --fido2-with-client-pin=false \
  --fido2-with-user-verification=false \
  "/dev/disk/by-partlabel/$DISK_NAME-$HOST_NAME-header"
```

## Maintaining nixpkgs Fork with Patches

This repository maintains a patched nixpkgs fork using `.flake.patches/update.py`:

1. Define inputs in `flake.nix`:
   - `nixpkgs-upstream` - upstream NixOS branch
   - `nixpkgs` - your fork
2. Configure patches in `.flake.patches/config.toml`
3. Run `nix run '.#update' g:patches` to update and apply patches

Patches can be GitHub PR URLs, commit URLs, or compare URLs.

## Packages

Custom packages in `packages/` are exposed via overlay as `pkgs.kdn.*`. Notable packages:
- `netbird-*` - Custom Netbird components
- `kdn-*` - Personal utilities (secrets, nix helpers, YubiKey tools, etc.)
- `debug-*` - Debug builds of packages with build tracing

## Common Patterns

### Adding a New Host

1. Create `modules/nixos/profile/host/${HOSTNAME}/default.nix`
2. Enable baseline: `kdn.profile.machine.baseline.enable = true;`
3. Configure hardware detection options
4. Add host configuration to `flake.nix` nixosConfigurations
5. Set `system.stateVersion` and `networking.hostId`

### Module Development

- All modules under `modules/` auto-import their subdirectory `default.nix` files
- Use `config.kdn.enable` to guard module activation
- Access flake inputs via `kdn.inputs`
- Check parent module type with `kdn.hasParentOfAnyType ["nixos" "nix-darwin"]`
- Check features with `kdn.features.<feature-name>`

### Working with Secrets

- SOPS with age encryption (ssh-to-age for host keys)
- Add new host keys to `.sops.yaml` after deployment
- Keyfiles managed through `pass` (password-store)

## File Locations

- Flake entrypoint: `flake.nix`
- Library extensions: `lib/`
- Modules: `modules/{nixos,home-manager,nix-darwin,shared}/`
- Packages: `packages/`
- Host configs: `modules/nixos/profile/host/*/`
- Patch management: `.flake.patches/config.toml` and `.flake.patches/update.py`
- Update script: `flake-update.sh`

## Notes

- Uses Lix instead of standard Nix (`nix.package = pkgs.lixPackageSets.latest.lix`)
- Home Manager integrated through both NixOS and nix-darwin modules
- Stylix provides theming across the system
- Impermanence used extensively with ZFS snapshots
- All user data should be declared in `environment.persistence` entries
