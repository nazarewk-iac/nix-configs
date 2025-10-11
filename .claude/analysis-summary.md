# Architecture Analysis Summary

**Analysis Date**: 2025-10-12
**Purpose**: Comprehensive repository analysis for future module consolidation

## Analysis Completed

This document tracks the analysis work completed and serves as a resume point for future work.

### ✅ Completed Steps

1. **Core Flake Configuration Analysis**
   - Analyzed flake.nix structure (442 lines)
   - Identified 30+ inputs with dependency follows
   - Mapped mkSpecialArgs function (lines 109-114)
   - Found 10 host configurations (8 NixOS, 1 Darwin, 1 bootstrap)

2. **Module System Architecture**
   - Identified 250 Nix files across modules/
   - Three-tier structure: shared/universal, shared/darwin-nixos-os, platform-specific
   - Auto-loading pattern via lib.filesystem.listFilesRecursive
   - Found 63 hm.nix files for Home Manager integration

3. **Meta Module System**
   - Core at modules/meta/default.nix (83 lines)
   - Defines kdn.configure function for specialArgs propagation
   - Tracks module types: nixos, nix-darwin, home-manager, checks
   - Features flags: rpi4, installer, darwin-utm-guest, microvm-host, microvm-guest
   - Parent tracking via kdn.parent and kdn.hasParentOfAnyType

4. **Module Structure Mapping**
   - **NixOS modules** (~160 files): modules/nixos/
   - **Darwin modules** (~7 files): modules/nix-darwin/
   - **Home Manager modules** (~6 files): modules/home-manager/
   - **Universal modules** (~10 files): modules/shared/universal/
   - **Shared Darwin-NixOS** (~5 files): modules/shared/darwin-nixos-os/

5. **kdn.* Options Analysis** (via agent)
   - 197 files defining kdn.* options
   - 13 major categories identified
   - Common patterns: enable options, lib.mkIf guards, config.kdn.enable
   - Profile composition pattern documented
   - Cross-module dependencies mapped

6. **Library Extensions**
   - lib/default.nix: Auto-loads subdirectories
   - lib/attrsets: recursiveMerge function
   - lib/flakes: overlayedInputs helper
   - lib/pkg: isSupported, onlySupported helpers
   - All exposed under lib.kdn.*

7. **specialArgs Propagation System**
   - flake.nix:109-114: mkSpecialArgs creates kdn module config
   - Evaluates modules/meta with kdn.{inputs, lib, self, moduleType}
   - kdn.configure creates child contexts with parent tracking
   - Used in: nixosSystem, darwinSystem, home-manager.extraSpecialArgs

## Key Findings

### Module Categories Breakdown

| Category | Files | Examples |
|----------|-------|----------|
| Profiles | ~30 | host/*, machine/*, user/*, hardware/* |
| Development | ~25 | golang, rust, python, java, nix, terraform |
| Programs | ~40 | firefox, chrome, slack, logseq, obs-studio |
| Hardware | ~20 | yubikey, gpu.amd, cpu.intel, bluetooth |
| Desktop | ~15 | kde, sway, base, remote-server |
| Networking | ~10 | netbird, resolved, router, tailscale |
| Virtualisation | ~10 | podman, docker, libvirtd, microvm |
| Services | ~10 | postgresql, caddy, syncthing, home-assistant |
| Toolsets | ~10 | essentials, unix, fs, network, ide |
| Security | ~5 | secrets, disk-encryption, secure-boot |
| Filesystem | ~5 | zfs, disko.luks-zfs, watch |
| Universal/Shared | ~10 | locale, hm, nix.remote-builder |
| Other | ~7 | helpers, monitoring, packaging |

### Common Patterns Identified

1. **Enable Pattern** (95% of modules)
```nix
options.kdn.<category>.<module>.enable = lib.mkEnableOption "...";
config = lib.mkIf cfg.enable (lib.mkMerge [{ /* ... */ }]);
```

2. **Default/HM Split** (60 modules)
```
module/
├── default.nix  # System-level config
└── hm.nix       # Home Manager config
```

3. **Home Manager Propagation**
```nix
home-manager.sharedModules = [{kdn.<module>.enable = cfg.enable;}];
```

4. **Profile Composition**
```nix
kdn.profile.machine.workstation.enable = true;
  ├─→ kdn.profile.machine.desktop.enable
  ├─→ kdn.profile.machine.dev.enable
  └─→ kdn.virtualisation.*.enable
```

5. **Conditional Enables**
```nix
apply = value: value && config.kdn.desktop.enable;
```

### Architecture Insights

1. **Side-effect free principle**: Every module guarded by enable option
   - Meta-module provides escape hatch for third-party modules with unconditional imports
2. **Smart defaults**: Auto-detection (ZFS, Home Manager, secrets)
3. **Secret-aware**: 20+ modules check config.kdn.security.secrets.allowed
4. **Type safety**: kdn.moduleType tracking, kdn.isOfAnyType helpers
5. **Platform abstraction**: Clean separation universal → shared → specific

## Files Analyzed

### Primary Files Read
- flake.nix (442 lines) - Main entry point
- modules/meta/default.nix (83 lines) - Core meta system
- modules/nixos/default.nix (37 lines) - NixOS module loader
- modules/nix-darwin/default.nix (56 lines) - Darwin module loader
- modules/home-manager/default.nix (59 lines) - HM module loader
- modules/shared/universal/default.nix (49 lines) - Universal options
- modules/shared/darwin-nixos-os/default.nix (51 lines) - Shared OS modules
- lib/default.nix (23 lines) - Library extension loader
- lib/attrsets/default.nix (70 lines) - recursiveMerge
- lib/flakes/default.nix (23 lines) - overlayedInputs
- lib/pkg/default.nix (13 lines) - platform helpers

### Agent Analysis
- **Agent**: general-purpose
- **Task**: Analyzed kdn.* option patterns across 197 files
- **Output**: Comprehensive categorization with examples
- **Key result**: Identified 13 categories, documented patterns, mapped dependencies

## Next Steps for Consolidation

### Phase 1: Documentation (Current)
- [✅] Create .claude/ directory
- [✅] Write analysis summary
- [ ] Document current architecture in detail
- [ ] Create consolidation strategy document
- [ ] Map migration paths

### Phase 2: Planning
- [ ] Design unified modules/ structure
- [ ] Plan meta-driven configuration approach
- [ ] Define migration milestones
- [ ] Identify breaking changes

### Phase 3: Implementation
- [ ] Create prototype unified structure
- [ ] Migrate universal modules
- [ ] Migrate platform-specific modules
- [ ] Update documentation

## Resume Points

If resuming this work later:

1. **Start here**: Read this file first
2. **Understand meta system**: Read modules/meta/default.nix
3. **See module patterns**: Browse modules/shared/universal/ examples
4. **Check agent findings**: See agent output in this file (kdn.* options section)
5. **Plan consolidation**: Create consolidation-plan.md

## Questions to Answer in Future Work

1. How to merge platform-specific implementations while keeping options universal?
2. Should meta module contain all kdn.* option definitions?
3. How to handle HM-only vs system-only vs universal options?
4. What's the migration strategy for existing hosts?
5. How to maintain backwards compatibility during transition?

## Git Commits Made

(Will be populated as documentation is committed)

## Agent Interactions Log

### Interaction 1: kdn.* Options Analysis
- **Agent Type**: general-purpose
- **Prompt**: Analyze kdn.* option patterns across modules/
- **Duration**: ~30 seconds
- **Result**: Comprehensive categorization of 197 option-defining files
- **Key Insights**:
  - 13 major categories identified
  - 95% use enable pattern
  - 60 modules have default.nix/hm.nix split
  - Clear dependency patterns documented
  - Examples provided for each category
