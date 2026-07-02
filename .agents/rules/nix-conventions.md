---
paths:
  - "**/*.nix"
---

# Nix Conventions

## Formatting

**Format all Nix files with `nixfmt`** before committing. Uses RFC-style `nixfmt` from nixpkgs, not `nixfmt-classic`. Use `nix run .#kdn-nix-fmt --` as a shortcut to format files in the repo.

## Option Declarations

**Prefer flat `foo.bar =` over nested `foo = { bar =`** everywhere — `options` declarations,
`config` assignments, and module consumer code. Nested attrset syntax is only appropriate when
setting multiple sibling keys at once and the grouping genuinely aids readability.

## Module Design

**All modules must be side-effect free by default** (enabled via `*.enable` options). The meta-module (`modules/meta/`) is the escape hatch for third-party modules that don't follow this pattern.

For full module architecture details see [module-architecture.md](module-architecture.md).
