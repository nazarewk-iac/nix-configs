---
type: Rule
description: Summarizes the mcp-gateway architecture and how to add/reload backends.
timestamp: 2026-07-03T22:19:14+02:00
---

# MCP Setup

Full doc: [docs/mcp-setup.md](../../docs/mcp-setup.md)

For mcpsnoop (traffic inspector): [docs/mcpsnoop.md](../../docs/mcpsnoop.md)

## Architecture

```
Claude Code → mcp-gateway → [git, filesystem, jj, devenv, nixos, time, fetch, memory-public, memory-sensitive]
```

One stdio connection. ~14 meta-tools regardless of backend count. Backends are managed by
`modules/slots/mcp/default.nix` via the `kdn.mcp` devenv option.

## Key files

| Path | Purpose |
|---|---|
| `modules/slots/mcp/default.nix` | Slot: generates YAML, registers with Claude Code |
| `modules/slots/mcp/basic-memory/default.nix` | basic-memory KB submodule |
| `.devenv/mcp-gateway.yaml` | Symlink → generated config in `/nix/store/` (read-only) |
| `devenv.nix` | Where backends are declared |

## Adding a backend

```nix
# mcp-servers-nix server:
kdn.mcp.programs.github.enable = true;

# custom stdio server:
kdn.mcp.extraBackends.my-server = {
  command = "${pkgs.my-server}/bin/my-server";
  description = "...";
};
```

After adding: rebuild devenv → re-enter shell → `gateway_kill_server` + `gateway_revive_server`.

## Reload without session restart

Use mcp-gateway meta-tools inside Claude Code:
```
gateway_kill_server <name>
gateway_revive_server <name>
```

## Inspecting traffic

If `kdn.mcp.snoop.enable = true` in devenv, run `mcpsnoop` in a separate terminal to see all
JSON-RPC frames live. See [docs/mcpsnoop.md](../../docs/mcpsnoop.md) for full usage.
