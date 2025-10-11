# CLAUDE.md

**Claude Code Guidance for nix-configs Repository**

## 📚 Documentation

All architecture documentation, analysis, and practical guidance is in the **`.claude/`** directory.

**Start here**: [.claude/00-index.md](.claude/00-index.md)

## 🎯 Key Principle

**All modules MUST be side-effect free by default** (enabled via `*.enable` options).

**Note**: The meta-module provides an escape hatch for integrating third-party modules with unconditional imports that don't adhere to this pattern.

## Quick Links

- **[Analysis Summary](.claude/analysis-summary.md)** - Work completed, key findings, resume points
- **[Agent Findings](.claude/agent-findings.md)** - Detailed kdn.* options catalog (197 modules)
- **[Consolidation Strategy](.claude/consolidation-strategy.md)** - Module consolidation plan
- **[Original Guidance](.claude/original-guidance.md)** - Practical commands and deployment guide
