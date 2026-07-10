---
type: Reference
description: Devenv slot module adding two isolated basic-memory MCP backends behind mcp-gateway.
timestamp: 2026-06-23T14:51:05+02:00
---

# kdn.mcp.basic-memory

Devenv slot module that adds two isolated [basic-memory](https://github.com/basicmachines-co/basic-memory) MCP backends behind mcp-gateway.

## Options

- `kdn.mcp.basic-memory.enable` — enables the module

## What it does when enabled

- Builds `basic-memory-public` (`bmp`) and `basic-memory-sensitive` (`bms`) wrapper binaries with baked-in paths and shell completions (bash/zsh/fish)
- Adds them to `packages` so they're on PATH inside `devenv shell`
- Registers `memory-public` and `memory-sensitive` as mcp-gateway backends
- Installs `.claude/rules/basic-memory.md` (from `routing.md`) as an always-on Claude Code rule

## Knowledge base layout

```
~/.local/share/kdn-nix-configs/knowledge/
├── .config/
│   ├── basic-memory-public/    ← isolated db + config for public instance
│   └── basic-memory-sensitive/ ← isolated db + config for sensitive instance
├── public/
│   └── default/               ← default project markdown root (BASIC_MEMORY_HOME)
│   └── <other-project>/       ← additional public projects
└── sensitive/
    └── default/               ← default project markdown root
    └── <other-project>/       ← additional sensitive projects
```

## Files

| File | Purpose |
|---|---|
| `default.nix` | Nix module (`kdn.mcp.basic-memory`) |
| `routing.md` | Claude Code rule: routing + OKF format guidance (installed as `.claude/rules/basic-memory.md`) |
| `routing-*.md` | Employer-specific routing addenda (loaded separately in overlay commits, not part of kdn) |

## Usage in devenv.nix

```nix
kdn.mcp.basic-memory.enable = true;
```

Requires `kdn.mcp.enable = true` (provided by `modules/slots/mcp/default.nix`).
