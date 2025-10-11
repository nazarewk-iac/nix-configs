# nix-configs Architecture Documentation

This directory contains AI agent-optimized documentation for the nix-configs repository architecture. The documentation is split into focused, digestible files for efficient AI context loading.

## Documentation Structure

1. **[01-overview.md](01-overview.md)** - High-level repository overview and key principles
2. **[02-flake-structure.md](02-flake-structure.md)** - Flake architecture, inputs, outputs, and entry points
3. **[03-meta-system.md](03-meta-system.md)** - Meta module system and specialArgs propagation
4. **[04-module-architecture.md](04-module-architecture.md)** - Module organization, patterns, and loading mechanisms
5. **[05-kdn-options.md](05-kdn-options.md)** - Complete reference of kdn.* options by category
6. **[06-library-extensions.md](06-library-extensions.md)** - Custom lib.kdn.* utilities and helpers
7. **[07-module-patterns.md](07-module-patterns.md)** - Common patterns and best practices for module development
8. **[08-consolidation-plan.md](08-consolidation-plan.md)** - Architectural plan for consolidating modules

## Quick Navigation by Task

### Understanding the System
- New to the repo? Start with **01-overview.md**
- Understanding module loading? See **04-module-architecture.md**
- Need to understand how arguments flow? Read **03-meta-system.md**

### Working with Modules
- Adding a new module? See **07-module-patterns.md**
- Looking for existing options? Check **05-kdn-options.md**
- Understanding shared vs platform-specific? See **04-module-architecture.md**

### Refactoring and Consolidation
- Planning module consolidation? See **08-consolidation-plan.md**
- Understanding dependencies? See **05-kdn-options.md** (dependencies section)

### Custom Utilities
- Need custom lib functions? See **06-library-extensions.md**
- Understanding flake helpers? See **02-flake-structure.md**

## Key Metrics

- **Total modules**: ~250 Nix files
- **kdn.* options**: ~197 module files defining options
- **Home Manager integration files**: 63 hm.nix files
- **Host configurations**: 10 (8 NixOS, 1 Darwin, 1 bootstrap)
- **Module categories**: 13 major categories

## Design Principles

1. **Side-effect free by default**: All modules MUST use `*.enable` options
2. **Composable architecture**: High-level profiles compose lower-level modules
3. **Platform abstraction**: Universal → Darwin-NixOS-OS → Platform-specific layers
4. **Smart defaults**: Auto-detection where possible (e.g., ZFS, Home Manager)
5. **Secret-aware**: Conditional activation based on secrets availability
6. **Type-safe boundaries**: Clear module type tracking via `kdn.moduleType`

## Future Direction

The repository is evolving towards:
- **Module consolidation**: Single `modules/` directory instead of platform-specific splits
- **Meta-driven configuration**: Configuration driven by `modules/meta` values
- **Enhanced kdn.* options**: Pull kdn-specific options into meta module
- **Reduced implementation details**: Keep implementation details in specific modules, expose only necessary options

See **08-consolidation-plan.md** for detailed consolidation strategy.
