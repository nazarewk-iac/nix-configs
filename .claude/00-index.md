# nix-configs Architecture Documentation

This directory contains AI agent-optimized documentation for the nix-configs repository architecture. The documentation is split into focused, digestible files for efficient AI context loading.

## Documentation Structure

1. **[analysis-summary.md](analysis-summary.md)** - Analysis work completed, key findings, and resume points for future work
2. **[agent-findings.md](agent-findings.md)** - Detailed agent output analyzing kdn.* options across 197 modules, categorized by function
3. **[consolidation-strategy.md](consolidation-strategy.md)** - Detailed strategy for consolidating modules/ into unified structure
4. **[original-guidance.md](original-guidance.md)** - Original practical guidance from CLAUDE.md (commands, deployment, common patterns)

## Quick Navigation by Task

### Understanding the System
- New to the repo? Start with **[analysis-summary.md](analysis-summary.md)** for overview
- Need practical commands? See **[original-guidance.md](original-guidance.md)**
- Understanding module structure? Read **[agent-findings.md](agent-findings.md)** (Module Structure section)

### Working with Modules
- Looking for existing options? Check **[agent-findings.md](agent-findings.md)** for complete catalog
- Understanding patterns? See **[agent-findings.md](agent-findings.md)** (Common Structural Patterns)
- Understanding dependencies? See **[agent-findings.md](agent-findings.md)** (Cross-Module Dependencies)

### Refactoring and Consolidation
- Planning module consolidation? See **[consolidation-strategy.md](consolidation-strategy.md)**
- Understanding current architecture? Read **[analysis-summary.md](analysis-summary.md)**

### Practical Usage
- Need deployment commands? See **[original-guidance.md](original-guidance.md)** (Disk Configuration & Deployment)
- Adding a new host? See **[original-guidance.md](original-guidance.md)** (Common Patterns)
- Working with secrets? See **[original-guidance.md](original-guidance.md)** (Working with Secrets)

## Key Metrics

- **Total modules**: ~250 Nix files
- **kdn.* options**: ~197 module files defining options
- **Home Manager integration files**: 63 hm.nix files
- **Host configurations**: 10 (8 NixOS, 1 Darwin, 1 bootstrap)
- **Module categories**: 13 major categories

## Design Principles

1. **Side-effect free by default**: All modules MUST use `*.enable` options
   - Note: Meta-module provides escape hatch for third-party modules with unconditional imports
2. **Composable architecture**: High-level profiles compose lower-level modules
3. **Platform abstraction**: Universal → Darwin-NixOS-OS → Platform-specific layers
4. **Smart defaults**: Auto-detection where possible (e.g., ZFS, Home Manager)
5. **Secret-aware**: Conditional activation based on secrets availability
6. **Type-safe boundaries**: Clear module type tracking via `kdn.moduleType`

## AI Agent Guidelines

**CRITICAL**: AI agents must follow these rules (detailed in root CLAUDE.md):

### Branch Strategy

**Two types of branches:**

1. **`ai-agents` branch** - For `.claude/` metadata/documentation
   - Update architecture docs, analysis, findings
   - Merge `main` when catching up
   - Do NOT modify code outside `.claude/`

2. **`ai/*` branches** - For actual code work
   - Make code changes as requested
   - Do NOT modify `.claude/` directory
   - Merge `main` when catching up

### Core Rules

- NEVER commit to `main`
- NEVER switch branches (user handles this)
- NEVER push changes (user will push after review)
- Work on current branch only
- Merge `main` when catching up: `git merge main`

### Commit Hygiene

- Use conventional commits (feat:, docs:, chore:, fix:)
- Include "🤖 Generated with [Claude Code]" footer
- Add "Co-Authored-By: Claude <noreply@anthropic.com>"

## Future Direction

The repository is evolving towards:
- **Module consolidation**: Single `modules/` directory instead of platform-specific splits
- **Meta-driven configuration**: Configuration driven by `modules/meta` values
- **Enhanced kdn.* options**: Pull kdn-specific options into meta module
- **Reduced implementation details**: Keep implementation details in specific modules, expose only necessary options

See **[consolidation-strategy.md](consolidation-strategy.md)** for detailed consolidation strategy.
