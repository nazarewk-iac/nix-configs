# Agent Analysis Findings

This document contains the detailed output from the general-purpose agent that analyzed kdn.* options patterns.

## Agent Task Summary

- **Agent Type**: general-purpose
- **Task**: Analyze kdn.* option patterns across /home/kdn/dev/github.com/nazarewk-iac/nix-configs/modules
- **Date**: 2025-10-12
- **Files Analyzed**: 197 files defining kdn.* options (out of 250 total .nix files)

## Detailed Findings

### Categories of kdn.* Options

#### Meta/Infrastructure (1 file)
**Location**: `modules/meta/default.nix`

Core `kdn` namespace infrastructure:
- `kdn.inputs` - Flake inputs access
- `kdn.lib` - Extended library
- `kdn.self` - Self-reference to flake
- `kdn.nix-configs` - Reference to nix-configs flake
- `kdn.parent` - Parent module context
- `kdn.configure` - Function to create child contexts
- `kdn.moduleType` - Current module type (nixos, nix-darwin, home-manager, checks)
- `kdn.isOfAnyType` - Type checking function
- `kdn.hasParentOfAnyType` - Parent type checking
- `kdn.features.*` - Feature flags:
  - `rpi4` - Raspberry Pi 4 hardware
  - `installer` - Installer ISO mode
  - `darwin-utm-guest` - macOS UTM VM guest
  - `microvm-host` - MicroVM host capability
  - `microvm-guest` - Running as MicroVM guest

#### Profile Options (~30 files)

**Host Profiles** (9 hosts):
- `kdn.profile.host.oams` - x86_64 workstation
- `kdn.profile.host.brys` - x86_64 server (microvm-host)
- `kdn.profile.host.etra` - x86_64 laptop
- `kdn.profile.host.pryll` - x86_64 workstation
- `kdn.profile.host.obler` - x86_64 server
- `kdn.profile.host.moss` - x86_64 cloud server
- `kdn.profile.host.faro` - aarch64 darwin-utm-guest
- `kdn.profile.host.briv` - aarch64 rpi4
- `kdn.profile.host.kdn-rpi4-bootstrap` - aarch64 rpi4 bootstrap
- `kdn.profile.host.anji` - aarch64 darwin (macOS)

**Machine Profiles**:
- `kdn.profile.machine.baseline` - Base server profile (headless, secrets, user setup)
- `kdn.profile.machine.basic` - Basic machine setup
- `kdn.profile.machine.desktop` - Desktop environment profile
- `kdn.profile.machine.workstation` - Full development workstation
- `kdn.profile.machine.dev` - Development tools
- `kdn.profile.machine.gaming` - Gaming-specific configuration
- `kdn.profile.machine.hetzner` - Hetzner cloud provider specific

**User Profiles**:
- `kdn.profile.user.kdn` - Primary user (defined in universal + darwin-nixos-os)
- `kdn.profile.user.bn` - Secondary user
- `kdn.profile.user.sn` - Secondary user

**Hardware Profiles**:
- `kdn.profile.hardware.rpi4` - Raspberry Pi 4
- `kdn.profile.hardware.dell-e5470` - Dell E5470 laptop
- `kdn.profile.hardware.darwin-utm-guest` - macOS UTM guest

#### Hardware Options (~20 files)

**Core Hardware**:
- `kdn.hw.yubikey` - YubiKey + GnuPG Smart Card configuration
- `kdn.hw.disks` - Persistence@ZFS@LUKS-volumes with detached headers
- `kdn.hw.basic` - Basic hardware support
- `kdn.hw.bluetooth` - Bluetooth support
- `kdn.hw.audio` - Audio configuration

**GPU Support**:
- `kdn.hw.gpu.amd` - AMD GPU drivers
- `kdn.hw.gpu.intel` - Intel GPU drivers

**CPU Support**:
- `kdn.hw.cpu.amd` - AMD CPU optimizations
- `kdn.hw.cpu.intel` - Intel CPU optimizations

**Peripherals**:
- `kdn.hw.modem` - Modem support
- `kdn.hw.edid` - EDID configuration
- `kdn.hw.qmk` - QMK keyboard firmware
- `kdn.hw.nanokvm` - Nano KVM support
- `kdn.hw.usbip` - USB over IP
- `kdn.hw.intel-graphics-fix` - Intel graphics workarounds

#### Networking Options (~10 files)

**VPN/Overlay Networks**:
- `kdn.networking.netbird` - Netbird VPN (multi-instance support)
  - `kdn.networking.netbird.clients.<name>` - Per-client configuration
  - `kdn.networking.netbird.useOwnPackages` - Use custom packages
  - `kdn.networking.netbird.admins` - Admin users list
- `kdn.networking.tailscale` - Tailscale VPN
- `kdn.networking.openvpn` - OpenVPN client
- `kdn.networking.openfortivpn` - FortiVPN client

**Network Services**:
- `kdn.networking.resolved` - systemd-resolved DNS
- `kdn.networking.router` - Router functionality
- `kdn.networking.dynamic-hosts` - Dynamic /etc/hosts management

#### Development Options (~25 files)

**Languages**:
- `kdn.development.golang` - Go development
- `kdn.development.rust` - Rust development
- `kdn.development.python` - Python development
- `kdn.development.java` - Java development
- `kdn.development.lua` - Lua development
- `kdn.development.nodejs` - Node.js development
- `kdn.development.elixir` - Elixir development
- `kdn.development.dotnet` - .NET development
- `kdn.development.nickel` - Nickel language

**Tools**:
- `kdn.development.git` - Git configuration (has hm.nix)
- `kdn.development.nix` - Nix development tools
- `kdn.development.terraform` - Terraform
- `kdn.development.ansible` - Ansible (has hm.nix)
- `kdn.development.shell` - Shell development tools

**Domain-Specific**:
- `kdn.development.web` - Web development
- `kdn.development.cloud` - Cloud development
- `kdn.development.cloud.azure` - Azure-specific tools
- `kdn.development.data` - Data science tools
- `kdn.development.db` - Database tools
- `kdn.development.kernel` - Kernel development
- `kdn.development.android` - Android development
- `kdn.development.rpi` - Raspberry Pi development
- `kdn.development.k8s` - Kubernetes tools
- `kdn.development.documents` - Document processing
- `kdn.development.jetbrains` - JetBrains IDEs
- `kdn.development.llm.online` - Online LLM access (has hm.nix)

#### Desktop/UI Options (~15 files)

**Core Desktop**:
- `kdn.desktop.enable` - Master desktop toggle
- `kdn.desktop.base` - Desktop base (has hm.nix)
- `kdn.desktop.kde` - KDE Plasma
- `kdn.desktop.sway` - Sway window manager
  - `kdn.desktop.sway.systemd` - Systemd integration
  - `kdn.desktop.sway.remote` - Remote Sway server

**Remote Access**:
- `kdn.desktop.remote-server` - Remote desktop server

#### Programs Options (~40 files)

**Browsers**:
- `kdn.programs.firefox` - Firefox (universal + darwin-nixos-os)
- `kdn.programs.chrome` - Google Chrome
- `kdn.programs.chromium` - Chromium
- `kdn.programs.browsers` - Browser aggregation

**Communication**:
- `kdn.programs.slack` - Slack
- `kdn.programs.signal` - Signal messenger
- `kdn.programs.element` - Matrix Element client (has hm.nix)
- `kdn.programs.thunderbird` - Thunderbird email
- `kdn.programs.beeper` - Beeper messaging
- `kdn.programs.weechat` - WeeChat IRC
- `kdn.programs.rambox` - Rambox messaging aggregator

**Media**:
- `kdn.programs.tidal` - Tidal music
- `kdn.programs.spotify` - Spotify (has hm.nix)

**Productivity**:
- `kdn.programs.logseq` - Logseq knowledge base
- `kdn.programs.keepassxc` - KeePassXC password manager
- `kdn.programs.nextcloud-client` - Nextcloud client (has hm.nix)
- `kdn.programs.obs-studio` - OBS Studio
- `kdn.programs.ente-photos` - Ente Photos

**Editors**:
- `kdn.programs.editors.photo` - Photo editing
- `kdn.programs.editors.video` - Video editing

**System Tools**:
- `kdn.programs.gnupg` - GnuPG
- `kdn.programs.direnv` - direnv
- `kdn.programs.fish` - Fish shell
- `kdn.programs.zsh` - Zsh shell
- `kdn.programs.atuin` - Atuin shell history
- `kdn.programs.dconf` - dconf editor
- `kdn.programs.ydotool` - ydotool automation
- `kdn.programs.nix-utils` - Nix utilities
- `kdn.programs.nix-index` - nix-index
- `kdn.programs.handlr` - handlr file handler
- `kdn.programs.kdeconnect` - KDE Connect
- `kdn.programs.wofi` - Wofi launcher

#### Services Options (~10 files)

**Databases**:
- `kdn.services.postgresql` - PostgreSQL server

**Web Services**:
- `kdn.services.caddy` - Caddy web server
- `kdn.services.coredns` - CoreDNS server
- `kdn.services.home-assistant` - Home Assistant
- `kdn.services.zammad` - Zammad helpdesk
- `kdn.services.photoprism` - PhotoPrism

**System Services**:
- `kdn.services.printing` - Printing services
- `kdn.services.syncthing` - Syncthing sync
- `kdn.services.nextcloud-client-nixos` - Nextcloud system service
- `kdn.services.iperf3` - iperf3 network testing

#### Security Options (~5 files)

**Secrets Management**:
- `kdn.security.secrets` - Secrets management (SOPS/age)
  - `kdn.security.secrets.enable` - Enable secrets
  - `kdn.security.secrets.allow` - Allow secrets
  - `kdn.security.secrets.allowed` - Computed allowed state
  - `kdn.security.secrets.age` - age encryption
  - `kdn.security.secrets.sops` - SOPS integration
  - `kdn.security.secrets.impl` - Implementation details

**Disk Security**:
- `kdn.security.disk-encryption` - LUKS disk encryption
- `kdn.security.secure-boot` - Secure Boot (Lanzaboote)

#### Filesystem Options (~5 files)

**Filesystems**:
- `kdn.fs.zfs` - ZFS configuration
  - Auto-detects ZFS filesystems
  - `kdn.fs.zfs.containers.enable` - Container integration
- `kdn.fs.watch` - Filesystem watching

**Disk Management**:
- `kdn.fs.disko.luks-zfs` - ZFS on LUKS2 via disko
  - Mutually exclusive with kdn.hw.disks

#### Virtualisation Options (~10 files)

**Containers**:
- `kdn.virtualisation.containers` - Container base
- `kdn.virtualisation.containers.podman` - Podman
- `kdn.virtualisation.containers.docker` - Docker
- `kdn.virtualisation.containers.distrobox` - Distrobox
- `kdn.virtualisation.containers.dagger` - Dagger CI
- `kdn.virtualisation.containers.x11docker` - X11 Docker

**VMs**:
- `kdn.virtualisation.libvirtd` - libvirt/KVM
- `kdn.virtualisation.vagrant` - Vagrant
- `kdn.virtualisation.microvm.host` - MicroVM host
- `kdn.virtualisation.microvm.guest` - MicroVM guest

#### Toolset Options (~10 files)

**Tool Collections**:
- `kdn.toolset.essentials` - Essential CLI tools
- `kdn.toolset.unix` - Unix utilities
- `kdn.toolset.fs` - Filesystem tools
  - `kdn.toolset.fs.encryption` - FS encryption tools
- `kdn.toolset.network` - Networking tools
- `kdn.toolset.ide` - IDE tools (has hm.nix)
- `kdn.toolset.tracing` - System tracing tools
- `kdn.toolset.print-3d` - 3D printing tools
- `kdn.toolset.mikrotik` - MikroTik tools (has hm.nix + default.nix)
- `kdn.toolset.logs-processing` - Log processing (has hm.nix)

#### Emulation/Gaming (~2 files)

- `kdn.emulation.wine` - Wine Windows emulation (has hm.nix)
- `kdn.profile.machine.gaming` - Gaming profile

#### Universal/Shared Options (~10 files)

**Platform Detection**:
- `kdn.hm` - Home Manager detection
  - `kdn.hm.enable` - HM mode active
  - `kdn.hm.type` - Type: "home-manager" or null
- `kdn.darwin` - Darwin platform flag
- `kdn.linux` - Linux platform flag

**Core Configuration**:
- `kdn.locale` - Locale configuration (universal)
- `kdn.nixConfig` - Nix configuration
- `kdn.hostName` - Host name
- `kdn.types` - Platform type list

**Remote Building**:
- `kdn.nix.remote-builder` - Remote builder configuration

**Fixes**:
- `kdn.darwin.apps-fix` - Darwin application fixes

#### Other Options

**System**:
- `kdn.enable` - Master enable for kdn namespace
- `kdn.headless.base` - Headless system base
- `kdn.managed` - Managed infrastructure

**Monitoring**:
- `kdn.monitoring.prometheus-stack` - Prometheus monitoring

**Packaging**:
- `kdn.packaging.asdf` - ASDF package manager

**Helpers**:
- `kdn.helpers` - Helper functions

### Common Structural Patterns

#### 1. Enable Pattern (95% of modules)
```nix
options.kdn.<category>.<module> = {
  enable = lib.mkEnableOption "descriptive text";
  # additional options...
};

config = lib.mkIf cfg.enable (lib.mkMerge [
  # Configuration blocks
  { /* ... */ }
]);
```

#### 2. Default/HM Split Pattern (60 modules)
Many modules split system and user configuration:

**System** (`default.nix`):
```nix
options.kdn.desktop.base.enable = lib.mkOption { /* ... */ };
config = lib.mkIf cfg.enable (lib.mkMerge [
  {home-manager.sharedModules = [{kdn.desktop.base.enable = cfg.enable;}];}
  # System-level config
]);
```

**User** (`hm.nix`):
```nix
options.kdn.desktop.base.enable = lib.mkOption { /* ... */ };
config = lib.mkIf cfg.enable (lib.mkMerge [
  # User-level config
]);
```

Modules with this pattern:
- development/git
- development/ansible
- development/java
- development/rust
- development/llm/online
- desktop/base
- profile/machine/desktop
- profile/machine/workstation
- programs/nextcloud-client
- programs/spotify
- programs/element
- toolset/ide
- toolset/mikrotik
- toolset/logs-processing
- emulation/wine

#### 3. Home Manager Propagation
```nix
home-manager.sharedModules = [{
  kdn.<module>.enable = true;
  kdn.<module>.<option> = value;
}];
```

Used extensively to propagate system decisions to user environment.

#### 4. Conditional Application Pattern
```nix
options.kdn.desktop.base.enable = lib.mkOption {
  type = lib.types.bool;
  default = false;
  apply = value: value && config.kdn.desktop.enable; # Guard
};
```

Ensures dependent options only activate when parent is enabled.

#### 5. Config Guard Pattern
Only core infrastructure modules use top-level `config.kdn.enable`:
- modules/shared/universal/default.nix
- modules/shared/darwin-nixos-os/default.nix
- modules/nixos/default.nix
- modules/nix-darwin/default.nix
- modules/home-manager/default.nix

All other modules guard on their specific `cfg.enable`.

#### 6. Submodule Pattern (Complex Options)
For structured data:

```nix
options.kdn.networking.netbird.clients = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
    options = {
      enable = lib.mkOption { /* ... */ };
      port = lib.mkOption { /* ... */ };
      users = lib.mkOption { /* ... */ };
      # 15+ more options
    };
  }));
};
```

Used in:
- kdn.networking.netbird.clients
- kdn.hw.disks (devices, luks.volumes, persist)
- kdn.desktop.sway.systemd

### Platform Organization

#### Universal Modules (`modules/shared/universal/`)
Available across all platforms (NixOS, Darwin, Home Manager):

- `kdn.enable` - Master toggle
- `kdn.hostName` - Host name
- `kdn.locale` - Locale settings
- `kdn.hm` - Home Manager detection
- `kdn.darwin` - Darwin flag
- `kdn.linux` - Linux flag
- `kdn.profile.machine.baseline` - Universal baseline
- `kdn.profile.machine.workstation` - Universal workstation
- `kdn.profile.user.kdn` - Universal user
- `kdn.hw.disks` - Universal disk config
- `kdn.fs.disko.luks-zfs` - Universal disko
- `kdn.nix.remote-builder` - Universal remote builder
- `kdn.darwin.apps-fix` - Universal (but Darwin-only active)

#### Darwin-NixOS Shared (`modules/shared/darwin-nixos-os/`)
Shared between macOS and NixOS (excludes Home Manager-only):

- `kdn.profile.machine.baseline` - OS-level baseline additions
- `kdn.profile.user.kdn` - OS-level user setup
- `kdn.programs.firefox` - Firefox across Darwin/NixOS
- `kdn.nix.remote-builder` - Remote builder setup
- Locale forwarding to system

#### Platform-Specific

**NixOS only** (`modules/nixos/`): ~160 modules
- All hardware modules (gpu, cpu, bluetooth, audio, etc.)
- All desktop modules (kde, sway, etc.)
- All services (postgresql, caddy, etc.)
- Most networking (netbird, resolved, router)
- All security (secrets, disk-encryption, secure-boot)
- Filesystem (zfs)
- Virtualisation

**Darwin only** (`modules/nix-darwin/`): ~7 modules
- Darwin-specific overrides
- Homebrew integration
- Darwin locale
- Darwin profile/host/anji

**Home Manager only** (`modules/home-manager/`): ~6 modules
- programs/ssh-client
- User-specific app configurations

### Cross-Module Dependencies

#### Primary Dependency Chains

**Profile Aggregation**:
```
workstation
├─→ desktop
│   ├─→ base
│   └─→ (kde | sway)
├─→ dev
│   ├─→ golang
│   ├─→ rust
│   ├─→ python
│   └─→ ...
└─→ virtualisation.*
```

**Baseline Profile**:
```
baseline
├─→ headless.base
├─→ security.secrets
├─→ locale
├─→ profile.user.kdn
├─→ development.shell
├─→ fs.zfs (mkDefault)
└─→ hw.yubikey (mkDefault)
```

#### Feature Dependencies

**Desktop Features**:
- All `kdn.desktop.*` → requires `kdn.desktop.enable`
- Desktop → base + (kde | sway)
- Sway → base + systemd integration

**Hardware Dependencies**:
- `kdn.hw.yubikey` → enables `kdn.programs.gnupg`
- GPU modules → kernel modules + OpenGL

**Secret-Aware Modules** (20+ modules):
Check `config.kdn.security.secrets.allowed`:
- networking.netbird.clients.*
- All SSH configurations
- VPN configurations
- Service credentials

**Auto-Detection**:
- `kdn.fs.zfs` → auto-detects ZFS in filesystems
- `kdn.hm.type` → auto-detects Home Manager context
- `kdn.virtualisation.containers` → detected by ZFS module

#### Most Referenced Options

**By grep count**:
- `config.kdn.` - 415 occurrences across 232 files
- `lib.mkIf cfg.enable` - 226 occurrences across 212 files
- `kdn.enable` - 8 occurrences (core guards only)
- `config.kdn.security.secrets.allowed` - 20+ modules
- `config.kdn.desktop.enable` - 15+ modules

### Key Examples

#### Example 1: Simple Module with Enable
**File**: `modules/nixos/hw/yubikey/default.nix`
```nix
options.kdn.hw.yubikey = {
  enable = lib.mkEnableOption "YubiKey + GnuPG Smart Card config";
  appId = lib.mkOption {
    type = lib.types.str;
    default = "pam://${config.kdn.hostName}";
  };
  devices = lib.mkOption { /* ... */ };
};

config = lib.mkIf cfg.enable (lib.mkMerge [
  {kdn.programs.gnupg.enable = true;}
  # YubiKey-specific config
]);
```

#### Example 2: Complex Submodule
**File**: `modules/nixos/networking/netbird/default.nix`
```nix
options.kdn.networking.netbird.clients = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      type = lib.mkOption {
        type = lib.types.enum ["persistent" "ephemeral"];
        default = "persistent";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 51820;
      };
      users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [];
      };
      # 10+ more options...
    };
  }));
};
```

#### Example 3: Auto-Detection
**File**: `modules/nixos/fs/zfs/default.nix`
```nix
options.kdn.fs.zfs = {
  enable = lib.mkOption {
    type = lib.types.bool;
    default = builtins.any
      (fs: fs.fsType == "zfs")
      (builtins.attrValues config.fileSystems);
  };
};
```

#### Example 4: Profile Composition
**File**: `modules/nixos/profile/machine/workstation/default.nix`
```nix
config = lib.mkIf cfg.enable (lib.mkMerge [
  {
    kdn.desktop.sway.enable = true;
    kdn.profile.machine.desktop.enable = true;
    kdn.profile.machine.dev.enable = true;
    kdn.virtualisation.libvirtd.enable = true;
    kdn.virtualisation.containers.podman.enable = true;
    kdn.development.android.enable = true;
    # 15+ more enables...
  }
]);
```

#### Example 5: Home Manager Detection
**File**: `modules/shared/universal/hm/default.nix`
```nix
options.kdn.hm = {
  type = lib.mkOption {
    type = with lib.types; enum [null "home-manager"];
    default = if config ? home then "home-manager" else null;
  };
  enable = lib.mkOption {
    type = with lib.types; bool;
    default = cfg.type != null;
    apply = enable:
      lib.trivial.throwIf (enable && cfg.type == null)
      "`kdn.hm` enabled, but `kdn.hm.type == null`!"
      enable;
  };
};
```

## Key Statistics

| Metric | Value |
|--------|-------|
| Total modules defining kdn.* options | 197 |
| Modules with enable pattern | ~188 (95%) |
| Modules with default.nix/hm.nix split | 60 |
| Major option categories | 13 |
| Host configurations | 10 |
| Modules checking secrets.allowed | 20+ |
| Modules checking desktop.enable | 15+ |
| Core infrastructure files using kdn.enable | 5 |

## Architectural Observations

1. **Consistent patterns**: 95% use enable + mkIf pattern
2. **Smart defaults**: Auto-detection minimizes configuration
3. **Layered abstraction**: Universal → Shared → Specific
4. **Secret integration**: Pervasive secrets.allowed checks
5. **Type safety**: Strong module type tracking
6. **Profile composition**: High-level profiles aggregate features
7. **Platform awareness**: Clear separation of concerns
8. **Home Manager integration**: Deep integration via sharedModules
