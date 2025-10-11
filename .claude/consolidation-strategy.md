# Module Consolidation Strategy

**Status**: Planning Phase
**Goal**: Consolidate `modules/` into unified structure with meta-driven configuration

## Current State

### Directory Structure
```
modules/
├── meta/           # Core infrastructure (1 file)
├── shared/
│   ├── universal/           # Cross-platform (10 files)
│   └── darwin-nixos-os/     # Darwin+NixOS shared (5 files)
├── nixos/          # NixOS-specific (~160 files)
├── nix-darwin/     # Darwin-specific (~7 files)
└── home-manager/   # HM-only (~6 files)
```

### Issues with Current Structure

1. **Platform separation creates duplication**
   - Same logical module split across platform directories
   - Example: locale defined in universal, darwin-nixos-os, nixos, nix-darwin

2. **Unclear module boundaries**
   - When should something go in shared/universal vs platform-specific?
   - Growing shared/ directory as more cross-platform needs arise

3. **HM integration scattered**
   - 63 hm.nix files distributed across platform modules
   - No clear single location for HM-specific logic

4. **Meta module underutilized**
   - Currently only infrastructure, not configuration-driving

## Proposed Future State

### Unified Module Structure
```
modules/
├── meta/                    # Meta-configuration driving system
│   ├── default.nix         # Core infrastructure (current)
│   ├── hosts.nix           # Host definitions
│   ├── platforms.nix       # Platform detection/config
│   └── features.nix        # Feature flag definitions
│
├── profiles/               # High-level profiles
│   ├── hosts/             # Per-host profiles
│   │   ├── oams.nix
│   │   ├── brys.nix
│   │   └── ...
│   ├── machines/          # Machine type profiles
│   │   ├── baseline.nix
│   │   ├── workstation.nix
│   │   ├── gaming.nix
│   │   └── ...
│   ├── users/             # User profiles
│   │   ├── kdn.nix
│   │   └── ...
│   └── hardware/          # Hardware profiles
│       ├── rpi4.nix
│       ├── dell-e5470.nix
│       └── ...
│
├── hardware/              # Hardware support
│   ├── cpu/
│   ├── gpu/
│   ├── yubikey.nix
│   └── ...
│
├── networking/            # Networking modules
│   ├── netbird/
│   ├── resolved.nix
│   └── ...
│
├── development/           # Development tools
│   ├── languages/
│   │   ├── golang.nix
│   │   ├── rust.nix
│   │   └── ...
│   └── tools/
│       ├── git.nix
│       ├── nix.nix
│       └── ...
│
├── desktop/               # Desktop environments
│   ├── base.nix
│   ├── kde.nix
│   ├── sway/
│   └── ...
│
├── programs/              # Applications
│   ├── browsers/
│   ├── communication/
│   ├── productivity/
│   └── ...
│
├── services/              # System services
│   ├── postgresql.nix
│   ├── caddy.nix
│   └── ...
│
├── security/              # Security modules
│   ├── secrets/
│   ├── disk-encryption.nix
│   └── ...
│
├── filesystem/            # Filesystem support
│   ├── zfs.nix
│   ├── disko/
│   └── ...
│
├── virtualisation/        # Virtualisation
│   ├── containers/
│   ├── libvirtd.nix
│   └── microvm/
│
└── toolsets/              # Tool collections
    ├── essentials.nix
    ├── unix.nix
    └── ...
```

### Module Structure Pattern

Each module would handle all platforms internally:

```nix
# modules/development/languages/golang.nix
{
  config,
  lib,
  pkgs,
  kdn,
  ...
}: let
  cfg = config.kdn.development.golang;
  isNixOS = kdn.isOfAnyType ["nixos"];
  isDarwin = kdn.isOfAnyType ["nix-darwin"];
  isHM = kdn.isOfAnyType ["home-manager"];
in {
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "Go development environment";
    version = lib.mkOption { /* ... */ };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Universal config (all platforms)
    {
      # Packages, environment variables, etc.
    }

    # NixOS-specific
    (lib.mkIf isNixOS {
      # System-level NixOS config
      home-manager.sharedModules = [{
        kdn.development.golang.enable = true;
      }];
    })

    # Darwin-specific
    (lib.mkIf isDarwin {
      # System-level Darwin config
      home-manager.sharedModules = [{
        kdn.development.golang.enable = true;
      }];
    })

    # Home Manager-specific
    (lib.mkIf isHM {
      # User-level config
      home.packages = with pkgs; [ go ];
    })
  ]);
}
```

## AI Agent Workflow

**IMPORTANT**: AI agents use two types of branches (see root CLAUDE.md for complete rules):

**`ai-agents` branch** - Metadata and documentation:
- Update `.claude/` directory only
- Do NOT modify code
- Merge `main` when catching up

**`ai/*` branches** - Code work:
- Make code changes as requested
- Do NOT modify `.claude/` directory
- Merge `main` when catching up

Common rules:
- NEVER commit to `main`
- NEVER switch branches (user handles this)
- NEVER push (user reviews and pushes)

## Migration Strategy

### Phase 1: Analysis & Documentation ✅ (Current)
- [x] Analyze current architecture
- [x] Document module patterns
- [x] Map dependencies
- [x] Create consolidation strategy

### Phase 2: Meta Module Enhancement
- [ ] Expand meta module with host definitions
- [ ] Add platform detection helpers
- [ ] Add feature flag system
- [ ] Create module type helpers for inline platform checks

### Phase 3: Create Unified Structure (Prototype)
- [ ] Create new unified directory structure
- [ ] Migrate 5-10 simple modules as proof of concept
- [ ] Test on single host (e.g., oams)
- [ ] Validate all three platforms work (NixOS, Darwin, HM)

### Phase 4: Systematic Migration
**Priority 1: Universal modules** (already work everywhere)
- [ ] Migrate modules/shared/universal/* to new locations
- [ ] Update imports

**Priority 2: Simple modules** (single file, minimal dependencies)
- [ ] Migrate simple nixos-only modules
- [ ] Merge with any darwin/hm equivalents

**Priority 3: Complex modules** (multiple files, dependencies)
- [ ] Migrate modules with default.nix + hm.nix patterns
- [ ] Consolidate into single module with platform checks

**Priority 4: Profile modules**
- [ ] Migrate host profiles
- [ ] Migrate machine profiles
- [ ] Migrate user profiles

**Priority 5: Cleanup**
- [ ] Remove old module directories
- [ ] Update all imports
- [ ] Test all hosts

### Phase 5: Meta-Driven Configuration
- [ ] Move host-specific options to meta module
- [ ] Implement meta-driven feature activation
- [ ] Reduce boilerplate in individual modules

## Key Decisions Needed

### 1. Module Loading Mechanism
**Option A**: Keep auto-loading via lib.filesystem.listFilesRecursive
- ✅ Automatic discovery
- ❌ All modules loaded even if unused
- ❌ Harder to reason about load order

**Option B**: Explicit import lists
- ✅ Clear dependencies
- ✅ Only load what's needed
- ❌ More maintenance
- ❌ Easy to forget to add imports

**Recommendation**: Hybrid - auto-load within categories, explicit category imports

### 2. Platform Check Location
**Option A**: Inside each module
```nix
config = lib.mkIf cfg.enable (lib.mkMerge [
  (lib.mkIf isNixOS { /* ... */ })
  (lib.mkIf isDarwin { /* ... */ })
  (lib.mkIf isHM { /* ... */ })
]);
```
- ✅ Single file per logical module
- ❌ More complex module files
- ✅ Clear what runs where

**Option B**: Separate files with shared options
```
golang/
├── options.nix    # Shared options
├── nixos.nix      # NixOS impl
├── darwin.nix     # Darwin impl
└── hm.nix         # HM impl
```
- ✅ Cleaner separation
- ❌ More files
- ❌ Options separated from implementation

**Recommendation**: Option A for simple modules, Option B for complex modules

### 3. Meta Module Scope
**Option A**: Minimal meta (current)
- Only infrastructure
- Options stay in respective modules

**Option B**: Comprehensive meta
- All kdn.* options defined in meta
- Modules only implement based on meta config

**Recommendation**: Start with A, migrate to B gradually

### 4. Backwards Compatibility
**Option A**: Break compatibility, update all hosts at once
- ✅ Clean break
- ❌ All-or-nothing migration
- ❌ Risky

**Option B**: Maintain compatibility layer
- ✅ Gradual migration
- ✅ Can test incrementally
- ❌ More complex during transition

**Recommendation**: Option B - add compatibility imports that forward to new locations

## Migration Checklist Template

For each module being migrated:

```markdown
- [ ] Identify current locations
  - [ ] nixos: path/to/module
  - [ ] nix-darwin: path/to/module
  - [ ] home-manager: path/to/module
  - [ ] shared/universal: path/to/module
  - [ ] shared/darwin-nixos-os: path/to/module

- [ ] Analyze dependencies
  - [ ] List all config.kdn.* references
  - [ ] List all kdn.features checks
  - [ ] List all home-manager.sharedModules propagations

- [ ] Create unified module
  - [ ] Merge options
  - [ ] Add platform checks
  - [ ] Consolidate implementations
  - [ ] Test on each platform

- [ ] Add compatibility layer
  - [ ] Old path imports new path
  - [ ] Add deprecation warnings

- [ ] Update documentation
  - [ ] Update option references
  - [ ] Update examples

- [ ] Test
  - [ ] Build test on NixOS
  - [ ] Build test on Darwin
  - [ ] Build test with HM
  - [ ] Verify no regressions
```

## Example: Consolidating `development/golang`

### Current State
```
modules/nixos/development/golang/
├── default.nix    # NixOS system config
└── hm.nix         # User config
```

### Migration Steps

1. **Create new unified module**:
```nix
# modules/development/languages/golang.nix
{config, lib, pkgs, kdn, ...}: let
  cfg = config.kdn.development.golang;
in {
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "Go development";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # From old hm.nix
    (lib.mkIf (kdn.isOfAnyType ["home-manager"]) {
      home.packages = with pkgs; [go gopls];
      programs.go.enable = true;
    })

    # From old default.nix
    (lib.mkIf (kdn.isOfAnyType ["nixos" "nix-darwin"]) {
      home-manager.sharedModules = [{
        kdn.development.golang.enable = true;
      }];
    })
  ]);
}
```

2. **Add compatibility layer**:
```nix
# modules/nixos/development/golang/default.nix
# DEPRECATED: Use modules/development/languages/golang.nix instead
builtins.trace "WARNING: modules/nixos/development/golang is deprecated"
  ../../development/languages/golang.nix
```

3. **Test**:
```bash
# Test NixOS build
nix build '.#nixosConfigurations.oams.config.system.build.toplevel'

# Test Darwin build
nix build '.#darwinConfigurations.anji.system'
```

4. **Remove old files** (after all hosts tested)

## Risks & Mitigation

### Risk 1: Breaking existing configurations
**Mitigation**: Compatibility layer + incremental rollout

### Risk 2: Platform-specific bugs hidden
**Mitigation**: Test matrix (NixOS × Darwin × HM)

### Risk 3: Module load order issues
**Mitigation**: Explicit dependencies via imports

### Risk 4: Performance regression
**Mitigation**: Benchmark build times before/after

## Success Criteria

- [ ] All hosts build successfully
- [ ] No functionality regressions
- [ ] Reduced code duplication
- [ ] Clearer module organization
- [ ] Easier to add new platforms (e.g., nix-on-droid)
- [ ] Better type safety
- [ ] Improved documentation

## Timeline Estimate

- **Phase 1**: Complete ✅
- **Phase 2**: 1-2 weeks (meta enhancement)
- **Phase 3**: 1 week (prototype)
- **Phase 4**: 4-6 weeks (systematic migration)
- **Phase 5**: 2-3 weeks (meta-driven config)

**Total**: 8-12 weeks for complete migration

## Next Actions

1. Enhance meta module with platform helpers
2. Create prototype with 5-10 modules
3. Test prototype on single host
4. Iterate on approach based on learnings
5. Begin systematic migration

## References

- Current architecture: See [agent-findings.md](agent-findings.md)
- Module patterns: See [analysis-summary.md](analysis-summary.md)
- Meta system: See [analysis-summary.md](analysis-summary.md#specialargs-propagation-system)
