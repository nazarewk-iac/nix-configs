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

#### Branch Strategy

**Two types of branches:**

1. **`ai-agents` branch** - AI agent metadata and documentation
   - Contains `.claude/` directory with architecture docs, analysis, etc.
   - AI agents commit metadata updates here
   - User will merge to `main` after review
   - Merge `main` into `ai-agents` when catching up
   - **Reading metadata**: AI agents can read `.claude/` files from this branch without switching:
     ```bash
     git show ai-agents:.claude/analysis-summary.md
     ```

2. **`ai/*` branches** - Actual work (code changes, features, fixes)
   - AI agents can create these starting from `main` (e.g., `ai/module-consolidation`, `ai/fix-netbird`)
   - Contains code changes ONLY, NO metadata updates
   - Do NOT modify `.claude/` directory in these branches
   - Read metadata from `ai-agents` branch using `git show` if needed
   - User will push, review, and merge to `main`
   - Merge `main` into work branch when catching up

#### Branch Policy Rules

- **NEVER commit to `main`** - with ONE EXCEPTION:
  - ✅ AI agents CAN modify and commit `CLAUDE.md` (this file) to `main` branch
  - ❌ Do NOT commit any other files to `main`
  - User will still push changes
- AI agents CAN create `ai/*` branches from `main`: `git checkout -b ai/task-name main`
- AI agents CAN switch between `ai/*` branches, `ai-agents` branch, and `main` (for CLAUDE.md updates only)
- **NEVER push changes** (user will review and push)
- Read `.claude/` metadata from `ai-agents` branch without switching: `git show ai-agents:.claude/file.md`

#### File Modification Rules

**When on `ai-agents` branch:**
- ✅ Modify files in `.claude/` directory
- ✅ Update documentation and metadata
- ❌ Do NOT modify code outside `.claude/`

**When on `ai/*` branches:**
- ✅ Modify code as requested
- ✅ Create/update modules, configs, etc.
- ❌ Do NOT modify `.claude/` directory
- ❌ Do NOT update metadata

**Special case - CLAUDE.md updates:**
- ✅ Can switch to `main` branch to update CLAUDE.md
- ✅ Can commit CLAUDE.md directly to `main`
- ❌ Cannot commit any other file to `main`
- Example:
  ```bash
  git checkout main
  # Edit CLAUDE.md
  git add CLAUDE.md
  git commit -m "docs: update CLAUDE.md with new guidance"
  git checkout ai-agents  # or return to work branch
  ```

#### Commit Hygiene

- Commit frequently with clear, descriptive messages
- Use conventional commit format (feat:, docs:, chore:, fix:)
- Include "🤖 Generated with [Claude Code]" footer
- Add "Co-Authored-By: Claude <noreply@anthropic.com>"

### Example Workflows

#### Working on Metadata (`ai-agents` branch)
```bash
# User checks out ai-agents branch
# AI agent work starts here

# Catch up with main
git merge main

# Update documentation
# Edit .claude/analysis-summary.md, etc.
git add .claude/
git commit -m "docs(claude): update analysis with new findings

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# User will review and merge to main
```

#### Working on Code (`ai/*` branches)
```bash
# AI agent can create branch from main
git checkout -b ai/feature-x main

# Or user creates and checks out ai/feature-x branch
# AI agent work starts here

# Catch up with main if needed
git merge main

# Read metadata from ai-agents branch if needed
git show ai-agents:.claude/consolidation-strategy.md

# Make code changes (NO .claude/ changes!)
# Edit modules/, lib/, packages/, etc.
git add modules/
git commit -m "feat: add new module for feature-x

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# User will push, review, and merge to main
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
