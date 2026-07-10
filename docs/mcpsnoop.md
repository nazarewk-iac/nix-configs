---
type: Reference
description: Explains mcpsnoop, a transparent MCP JSON-RPC traffic inspector proxy.
timestamp: 2026-07-03T22:19:14+02:00
---

# mcpsnoop — MCP Traffic Inspector

[mcpsnoop](https://github.com/kerlenton/mcpsnoop) is a transparent debugging proxy for MCP.
It intercepts all JSON-RPC frames between Claude Code and the MCP server (in our case,
`mcp-gateway`), showing them in a live terminal UI. Unlike the official MCP Inspector, it
observes **real client-server traffic** — not a separate test connection.

See [mcp-setup.md](mcp-setup.md) for the gateway architecture mcpsnoop sits in front of.

---

## How it works

mcpsnoop splits into two cooperating components in the same binary:

- **Shim mode** (`mcpsnoop -- <server-command>`): transparent proxy registered with Claude Code
  instead of the real server; forwards bytes verbatim and copies each JSON-RPC frame to a
  local socket
- **UI mode** (`mcpsnoop`): terminal interface that reads from that socket and displays frames

The two can be started in any order. When the shim is active, open a second terminal and run
`mcpsnoop` to see everything that's flowing.

---

## Setup

mcpsnoop is **enabled by default** via the `kdn.mcp.snoop` slot
(`modules/slots/mcp/snoop/default.nix`). No `devenv.nix` change needed — it activates
automatically whenever `kdn.mcp.enable = true`.

The slot wraps `mcp-gateway-wrapper` so Claude Code actually launches:
```
mcpsnoop -- mcp-gateway-wrapper
```

**To disable** for a session, add to `devenv.nix`:
```nix
kdn.mcp.snoop.enable = false;
```
Then rebuild devenv and re-enter the shell.

**Implementation files:**
- `packages/mcpsnoop/default.nix` — `buildGoModule` derivation, v0.1.1
- `modules/slots/mcp/snoop/default.nix` — devenv slot; auto-loaded by the slots loader
- `packages/default.nix` — `mcpsnoop` entry

---

## Using mcpsnoop in practice

### Start the UI

Open a terminal (separate from wherever Claude Code is running) and run:

```bash
mcpsnoop
```

The TUI starts and waits for frames. It connects to the shim's socket automatically — no
configuration needed. You can open the UI before or after Claude Code starts.

### Trigger activity

In Claude Code (or any MCP client), invoke any tool. Every JSON-RPC frame — initialization,
tool calls, responses, notifications — appears in the list immediately.

### Navigate the TUI

| Key | Action |
|---|---|
| `j` / `k` or `↓` / `↑` | Move between frames |
| `Enter` | Drill into a frame (pretty-printed JSON) |
| `Esc` | Go back |
| `/` | Open filter input |
| `r` | Replay the selected call |
| `c` | Show capabilities (client-server handshake) |
| `y` | Copy frame to clipboard |
| `p` | Pause / unpause live capture |
| `f` | Toggle follow mode (auto-scroll to newest) |
| `ctrl-d` | Delete selected frame |

### Filtering

The filter supports token syntax:

| Token | Example | Matches |
|---|---|---|
| `tool:` | `tool:filesystem` | Calls to the filesystem backend |
| `status:` | `status:error` | Frames with error status |
| `dir:` | `dir:in` | Inbound frames (client → server) |
| `kind:` | `kind:notification` | Notification frames |
| `id:` | `id:42` | Frame with a specific request ID |
| plain text | `read_file` | Any frame containing that string |

Combine tokens: `tool:jj status:error` shows only failed jj calls.

---

## Common workflows

### "What exactly did the agent pass to this tool?"

Filter by `tool:<backend-name>`, select the call, press `Enter` to read the full JSON
request. The `params` field shows every argument the LLM sent.

### "Why is this backend responding slowly?"

mcpsnoop shows live timers on in-flight calls. Any call stuck open will show its elapsed
time. This pinpoints which backend is the bottleneck without reading logs.

### "Why is my new backend not appearing?"

Open the TUI and press `c` (capabilities). The initialization handshake shows which tools
each backend advertised. If your backend is missing, the gateway never connected to it —
check `cat .devenv/mcp-gateway.yaml` to confirm it's listed.

### "Reproduce a specific tool call in isolation"

Select the call in the TUI and press `r` to replay it. mcpsnoop re-sends the exact same
JSON-RPC request and shows the new response alongside the original. Useful for testing
whether a backend is deterministic or for isolating flaky behavior.

### "Something broke after a devenv rebuild"

Watch initialization frames (filter `kind:request dir:in`) to see if the handshake
completes. If a backend errors on startup, it shows up here before any tool calls happen.
