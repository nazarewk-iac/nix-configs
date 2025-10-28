# CLAUDE.md

**Claude Code Guidance for nix-configs Repository**

## 📚 Documentation

All architecture documentation, analysis, and practical guidance is in the **`.claude/`** directory.

**Start here**: [.claude/00-index.md](.claude/00-index.md)

**Note**: The `.claude/` directory is maintained on the `ai-agents` branch and merged to `main` after review. AI agents can read from it using `git show ai-agents:.claude/file.md` without switching branches.

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
   - **Merge `main` into `ai-agents` when catching up** to get latest CLAUDE.md and other updates:
     ```bash
     # Execute merge script from ai-agents branch
     bash <(git show ai-agents:.claude/merge-main-to-ai-agents.sh)
     ```
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
   - Merge `main` into work branch when catching up: `git merge main`

#### Branch Policy Rules

- **NEVER commit to `main`** - with ONE EXCEPTION:
  - ✅ AI agents CAN modify and commit `CLAUDE.md` (this file) to `main` branch
  - ❌ Do NOT commit any other files to `main`
  - User will still push changes
  - Can update without checking out main using git plumbing commands
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

**Special case - Cross-branch updates without checkout:**

AI agents can commit to any allowed branch without checking it out using git plumbing:

**Updating CLAUDE.md on `main` (when on other branches):**

Helper script available in `.claude/` on the `ai-agents` branch:

```bash
# Use the helper script stored in ai-agents branch
# 1. Prepare your updated file
mkdir -p /tmp/kdn/nix-configs
git show main:CLAUDE.md > /tmp/kdn/nix-configs/CLAUDE.md.new
# ... edit the file ...

# 2. Execute the helper script directly from ai-agents branch
bash <(git show ai-agents:.claude/update-claude-main.sh) \
    "docs: update CLAUDE.md guidance"
```

Manual approach:
```bash
# Read, edit, create blob
git show main:CLAUDE.md > /tmp/kdn/nix-configs/CLAUDE.md.new
# ... edit the file ...
BLOB=$(git hash-object -w /tmp/kdn/nix-configs/CLAUDE.md.new)

# Create new tree with updated file
PARENT_COMMIT=$(git rev-parse main)
CURRENT_TREE=$(git cat-file -p $PARENT_COMMIT | grep '^tree' | cut -d' ' -f2)
NEW_TREE=$(git mktree <<EOF
100644 blob $BLOB	CLAUDE.md
$(git ls-tree $CURRENT_TREE | grep -v "CLAUDE.md")
EOF
)

# Create commit and update main
NEW_COMMIT=$(git commit-tree $NEW_TREE -p $PARENT_COMMIT -m "docs: update CLAUDE.md")
git update-ref refs/heads/main $NEW_COMMIT
```

**Updating `.claude/` on `ai-agents` (when on other branches):**

Helper scripts are available in `.claude/` on the `ai-agents` branch:

```bash
# Use the helper script stored in ai-agents branch
# 1. Prepare your updated file
mkdir -p /tmp/kdn/nix-configs
git show ai-agents:.claude/analysis-summary.md > /tmp/kdn/nix-configs/analysis-summary.md.new
# ... edit the file ...

# 2. Execute the helper script directly from ai-agents branch
bash <(git show ai-agents:.claude/update-claude-metadata.sh) \
    analysis-summary.md \
    "docs(claude): update analysis summary"
```

Manual approach (if you prefer full control):
```bash
# Read, edit, create blob for a file in .claude/
mkdir -p /tmp/kdn/nix-configs
git show ai-agents:.claude/analysis-summary.md > /tmp/kdn/nix-configs/analysis-summary.md.new
# ... edit the file ...
BLOB=$(git hash-object -w /tmp/kdn/nix-configs/analysis-summary.md.new)

# Get current state
PARENT_COMMIT=$(git rev-parse ai-agents)
CURRENT_TREE=$(git cat-file -p $PARENT_COMMIT | grep '^tree' | cut -d' ' -f2)

# Get .claude directory tree object
CLAUDE_DIR_SHA=$(git ls-tree $CURRENT_TREE | grep ".claude" | awk '{print $3}')

# Create new .claude tree with updated file
NEW_CLAUDE_TREE=$(git mktree <<EOF
$(git ls-tree $CLAUDE_DIR_SHA | grep -v "analysis-summary.md")
100644 blob $BLOB	analysis-summary.md
EOF
)

# Create new root tree with updated .claude
NEW_TREE=$(git mktree <<EOF
$(git ls-tree $CURRENT_TREE | grep -v ".claude")
040000 tree $NEW_CLAUDE_TREE	.claude
EOF
)

# Create commit and update ai-agents
NEW_COMMIT=$(git commit-tree $NEW_TREE -p $PARENT_COMMIT -m "docs(claude): update analysis")
git update-ref refs/heads/ai-agents $NEW_COMMIT
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

# Catch up with main using helper script (from any branch)
bash <(git show ai-agents:.claude/merge-main-to-ai-agents.sh)

# Or if on ai-agents branch, can use regular merge
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
├── modules/               # Module system (250 files, 197 with kdn.* options)
│   ├── meta/             # Core infrastructure & specialArgs (escape hatch location)
│   ├── shared/           # Cross-platform modules
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

### Special Arguments (kdn*)
The `kdnConfig` & `kdnMeta` arguments are propagated through modules via `kdnConfig.output.mkSubmodule` function (in `modules/meta/`):
- `kdnConfig.inputs` - Flake inputs
- `kdnConfig.lib` - Extended library
- `kdnConfig.self` - Self-reference to flake
- `kdnConfig.moduleType` - Current module type (nixos, nix-darwin, home-manager, checks)
- `kdnConfig.features.*` - Feature flags (rpi4, microvm-host, darwin-utm-guest, etc.)
- `kdnConfig.parent` - Parent context tracking
- `kdnConfig.output.mkSubmodule` - Create child contexts
- `kdnConfig.util.isOfAnyType` - Type checking helper
- `kdnConfig.hasParentOfAnyType` - Parent type checking

### Common Module Pattern
```nix
{config, lib, ...}: let
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
