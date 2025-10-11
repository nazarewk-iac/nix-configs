# CLAUDE.md

**Claude Code Guidance for nix-configs Repository**

## 📚 Documentation

All architecture documentation, analysis, and practical guidance is in the **`.claude/`** directory.

**Start here**: [.claude/00-index.md](.claude/00-index.md)

## 🎯 Key Principles

### Module Design
**All modules MUST be side-effect free by default** (enabled via `*.enable` options).

**Note**: The meta-module (`modules/meta/`) provides an escape hatch for integrating third-party modules with unconditional imports that don't adhere to this pattern.

### AI Agent Git Workflow

**CRITICAL RULES - AI agents must follow these strictly:**

1. **Branch Policy**:
   - ONLY commit to the `ai-agents` branch
   - NEVER commit to `main` or any other branch
   - NEVER switch branches (user handles branch switching)
   - NEVER push changes (user will review and push)

2. **Staying Current**:
   - Always merge `main` into `ai-agents` when catching up or resuming work
   - This ensures AI work builds on latest main branch changes

3. **File Modifications**:
   - Documentation work: Modify files in `.claude/` directory
   - Code work: Only when explicitly requested by user
   - NEVER modify files outside designated scope without permission

4. **Commit Hygiene**:
   - Commit frequently with clear, descriptive messages
   - Use conventional commit format (feat:, docs:, chore:, fix:)
   - Include "🤖 Generated with [Claude Code]" footer
   - Add "Co-Authored-By: Claude <noreply@anthropic.com>"

### Example Workflow
```bash
# When resuming work or catching up (AI agent should do this):
git merge main  # Merge latest changes from main into ai-agents

# Work, make changes...
git add .claude/
git commit -m "docs: update analysis..."

# User will handle:
# - Reviewing commits on ai-agents branch
# - Merging to main when ready
# - Pushing to remote
```

## 🏗️ Repository Structure

```
nix-configs/
├── flake.nix              # Main entry point
├── modules/
│   ├── meta/             # Core infrastructure & specialArgs (escape hatch location)
│   ├── shared/
│   │   ├── universal/       # All platforms
│   │   └── darwin-nixos-os/ # Darwin + NixOS
│   ├── nixos/            # NixOS-specific (~160 modules)
│   ├── nix-darwin/       # Darwin-specific (~7 modules)
│   └── home-manager/     # Home Manager-only (~6 modules)
├── lib/                   # Custom lib.kdn.* utilities
├── packages/              # Custom pkgs.kdn.* packages
└── .claude/              # 📚 AI agent documentation (work here!)
```

## 📊 Repository Stats

- **250** Nix files across modules/
- **197** files defining kdn.* options
- **13** major option categories
- **63** Home Manager integration files (hm.nix)
- **10** host configurations (8 NixOS, 1 Darwin, 1 bootstrap)

## 🎓 Essential Concepts

### Three-Tier Module System
```
universal (all platforms)
    ↓
darwin-nixos-os (macOS + NixOS)
    ↓
platform-specific (nixos, nix-darwin, home-manager)
```

### Special Arguments (kdn)
The `kdn` argument is propagated through modules via `kdn.configure` function (in `modules/meta/`):
- `kdn.inputs` - Flake inputs
- `kdn.lib` - Extended library
- `kdn.self` - Self-reference to flake
- `kdn.moduleType` - Current module type (nixos, nix-darwin, home-manager, checks)
- `kdn.features.*` - Feature flags (rpi4, microvm-host, darwin-utm-guest, etc.)
- `kdn.parent` - Parent context tracking
- `kdn.configure` - Create child contexts
- `kdn.isOfAnyType` - Type checking helper
- `kdn.hasParentOfAnyType` - Parent type checking

### Common Module Pattern
```nix
{config, lib, kdn, ...}: let
  cfg = config.kdn.some.module;
in {
  options.kdn.some.module = {
    enable = lib.mkEnableOption "description";
  };

  config = lib.mkIf cfg.enable {
    # Module implementation
  };
}
```

## 📖 Quick Links

- **[Analysis Summary](.claude/analysis-summary.md)** - Work completed, key findings, resume points
- **[Agent Findings](.claude/agent-findings.md)** - Detailed kdn.* options catalog (197 modules)
- **[Consolidation Strategy](.claude/consolidation-strategy.md)** - Module consolidation plan
- **[Original Guidance](.claude/original-guidance.md)** - Practical commands and deployment guide

## 🔗 External Resources

- **Claude Code**: https://claude.com/claude-code
- **NixOS**: https://nixos.org
- **Home Manager**: https://github.com/nix-community/home-manager
- **nix-darwin**: https://github.com/LnL7/nix-darwin
