---
type: Reference
description: Explains mcpsnoop, a transparent MCP JSON-RPC traffic inspector proxy.
timestamp: 2026-07-20T00:00:00+02:00
---

# mcpsnoop — MCP Traffic Inspector

[mcpsnoop](https://github.com/kerlenton/mcpsnoop) is a transparent debugging proxy for MCP.
It intercepts all JSON-RPC frames between Claude Code and the MCP server (in our case,
`mcp-gateway`), showing them in a live terminal UI. Unlike the official MCP Inspector, it
observes **real client-server traffic** — not a separate test connection.

See [mcp-setup.md](mcp-setup.md) for the gateway architecture mcpsnoop sits in front of.

---

## How it works

mcpsnoop splits into two cooperating roles in the same binary:

- **Shim mode** (`mcpsnoop -- <server-command>`): transparent proxy registered with Claude Code
  instead of the real server; forwards bytes verbatim and copies each JSON-RPC frame to the hub
- **Hub / UI mode** (`mcpsnoop`): terminal interface that reads from the hub's socket and
  displays frames; also backfills past sessions from disk

The two can be started in any order — they find each other on a well-known socket. When the
shim is active, open a second terminal and run `mcpsnoop` to see everything that's flowing.

The hub loads the newest 100 saved sessions by default. Use `--history-limit N` to change that,
or `--history-limit 0` to load full history. Older sessions stay reachable via
`mcpsnoop open <session-id>` and `mcpsnoop export <session-id>` regardless of the load limit.

For a streamable-HTTP MCP server (not our setup, which is stdio), mcpsnoop can also run as a
reverse proxy: `mcpsnoop http --target http://localhost:3000/mcp --listen :7000`.

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
- `packages/mcpsnoop/default.nix` — `buildGoModule` derivation, v0.12.0
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

Haven't wired anything up yet? `mcpsnoop demo` plays a scripted session in the TUI with no
setup, useful for a first look at the interface.

### Trigger activity

In Claude Code (or any MCP client), invoke any tool. Every JSON-RPC frame — initialization,
tool calls, responses, notifications — appears in the list immediately.

### Navigate the TUI

| Key | Action | | Key | Action |
|---|---|---|---|---|
| `j` / `k` or `↓` / `↑` | move between frames | | `s` | tool summary |
| `enter` | drill into a frame (pretty-printed JSON) | | `y` | copy frame to clipboard |
| `esc` | go back | | `e` | export session |
| `/` | open filter input | | `f` | toggle follow mode (auto-scroll to newest) |
| `:` | open command mode | | `ctrl-d` | delete selected frame / session |
| `g` / `G` | jump to top / bottom | | `p` | pause / unpause live capture |
| `ctrl-f` / `ctrl-b` | page down / up | | `shift`+`<key>` | sort by column |
| `r` | replay the selected call | | `c` | show capabilities (client-server handshake) |
| `?` | show full keybinding help | | | |

Press `?` in the app for the complete, up-to-date list.

### Filtering

Press `/` and combine space-separated tokens, ANDed. Plain text matches the method, tool, id,
and payload.

| Token | Example | Matches |
|---|---|---|
| `tool:` | `tool:filesystem` | Calls to the filesystem backend |
| `method:` | `method:tools/call` | Frames with a specific JSON-RPC method |
| `status:` | `status:error` | Call outcome: `ok`, `error`, `pending`, `bad`, `warn`, `mismatch` |
| `dir:` | `dir:c2s` | Direction: `c2s` (client→server) or `s2c` (server→client) |
| `kind:` | `kind:notify` | Frame type: `req`, `resp`, `notify`, `stderr`, `invalid` |
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
time. This pinpoints which backend is the bottleneck without reading logs. Press `s` for a
tool summary with per-tool call counts and latency percentiles.

### "Why is my new backend not appearing?"

Open the TUI and press `c` (capabilities). The initialization handshake shows which tools
each backend advertised. If your backend is missing, the gateway never connected to it —
check `cat .devenv/mcp-gateway.yaml` to confirm it's listed.

### "Reproduce a specific tool call in isolation"

Select the call in the TUI and press `r` to replay it. mcpsnoop re-sends the exact same
JSON-RPC request and shows the new response alongside the original. Useful for testing
whether a backend is deterministic or for isolating flaky behavior.

### "Something broke after a devenv rebuild"

Watch initialization frames (filter `kind:req dir:c2s`) to see if the handshake
completes. If a backend errors on startup, it shows up here before any tool calls happen.

### "Did a backend's tool definitions change without me noticing?"

`mcpsnoop check --fail-on drift session.jsonl` compares tool descriptions and input schemas
against a trusted per-server-label baseline. See [Detecting tool-definition drift](#detecting-tool-definition-drift-and-gating-ci)
below.

### "Compare behavior before/after a config change"

`mcpsnoop diff before-session after-session` reports added/removed tools, schema changes,
call status changes, and notable duration shifts between two captured sessions.

---

## Exporting sessions

Turn any captured session into a portable file:

```bash
mcpsnoop export -T json|html|text|har|otlp [-o file|-] [session-id|log.jsonl|-]
```

| Format | What you get |
|---|---|
| `json` | correlated calls, per-tool counts and p50/p95/p99 latency, slowest calls, capabilities, and raw frames |
| `html` | a self-contained browser file with search and collapsible JSON |
| `text` | a pretty plain-text dump |
| `har` | one entry per correlated call, openable in browser devtools and anything else that reads HAR |
| `otlp` | OTLP JSON with a trace per session and a span per correlated call |

```bash
mcpsnoop export -T html -o out.html       # an HTML file to open in a browser
mcpsnoop export -T json | jq              # the newest session, piped to jq
```

Omit the session to take the newest, or pass `-` to read JSONL from stdin. In the TUI, press
`e` to export the selected session as HTML, or run `:export json|html|text|har|otlp [path]`
from command mode (`:`).

To stream completed calls live to an OTLP/HTTP JSON traces collector instead of exporting
after the fact, pass `--otlp-endpoint` (and repeatable `--otlp-header` for auth) to the shim
or to `mcpsnoop http`. Delivery is best-effort and never blocks proxied traffic.

---

## Comparing sessions

```bash
mcpsnoop diff before-session after-session
mcpsnoop diff old.jsonl new.jsonl
```

Reports tools added/removed, description and `inputSchema` changes, matching call status
changes, and notable duration shifts (calls are matched by tool name + arguments, so
reordering doesn't break the comparison). Duration changes must clear both
`--duration-threshold` (default `100ms`) and `--duration-ratio` (default `2`) to be reported.
Pass `--exit-code` to gate CI: it exits non-zero on any regression (dropped tool, description
or schema change, worse call status, slowdown); improvements always exit zero.

---

## Checking sessions in CI

```bash
mcpsnoop check [--format text|junit] [--fail-on error,invalid,warn,mismatch,pending,drift] [session-id|log.jsonl|-]
```

Default signals (`error,invalid,warn`) fail the check. Add `pending` for calls that never got
a response, `mismatch` for a routing header (`Mcp-Method`/`Mcp-Name`) disagreeing with the
body, or `drift` for tool-definition drift (opt-in, see below). Omit the session to check the
newest capture. `--format junit` writes one JUnit `<testcase>` per signal/session.

Beyond signal counts, assert the shape of a run — these compose with `--fail-on` and with each
other:

| Flag | Fails when |
|---|---|
| `--max-duration <dur>` | a completed tool call exceeded the budget, e.g. `500ms` |
| `--expect-tool <name>` | the named tool was never called (repeatable) |
| `--forbid-tool <name>` | the named tool was called (repeatable) |

```bash
mcpsnoop check --expect-tool search --forbid-tool delete --max-duration 2s run.jsonl
```

```yaml
- name: Check captured MCP session
  run: |
    mkdir -p test-results
    mcpsnoop check --format junit artifacts/session.jsonl > test-results/mcpsnoop.xml
- name: Upload mcpsnoop JUnit report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: mcpsnoop-junit
    path: test-results/mcpsnoop.xml
```

### Detecting tool-definition drift and gating CI

The first complete `tools/list` observed for a server label becomes its trusted baseline.
Later sessions compare descriptions and input schemas against it. Baselines are stored under
the mcpsnoop state directory (`MCPSNOOP_HOME` / `XDG_STATE_HOME` apply), keyed by `--label`.

```bash
mcpsnoop check --fail-on drift session.jsonl
mcpsnoop baseline session.jsonl             # inspect the current baseline diff
mcpsnoop baseline --accept session.jsonl    # trust a legitimate definition change
mcpsnoop baseline --reset session.jsonl     # trust the next complete tools/list
```

In ephemeral CI the state directory starts empty each run, so the first run only records the
baseline and reports no drift — point `--baseline` at a checked-in or cached directory (or set
`MCPSNOOP_HOME`) for drift detection to actually compare across runs:

```bash
mcpsnoop check --fail-on drift --baseline .mcpsnoop/baselines session.jsonl
```

---

## Pruning old sessions

`mcpsnoop prune` deletes saved session logs older than a cutoff — it never runs on its own,
and `--older-than` is required (no default that would delete anything):

```bash
mcpsnoop prune --older-than 30d --dry-run   # list what would go, remove nothing
mcpsnoop prune --older-than 30d             # delete after confirming
mcpsnoop prune --older-than 72h --yes       # skip the prompt in a script
```

Tool baselines are left alone, since a baseline is keyed by server label rather than by
session.

---

## Watching from another machine

Keep capture local to where the traffic happens and tunnel over SSH:

```bash
# on your workstation
mcpsnoop
ssh remote-user@remote-host 'mkdir -p ~/.local/state/mcpsnoop'
mcpsnoop remote remote-user@remote-host    # prints the ssh -R command to run

# on the remote host
mcpsnoop -- node build/index.js
```

`mcpsnoop remote` requires a Unix remote (Linux or macOS) since it uses SSH Unix-socket
forwarding. Pass `--remote-home`, `--remote-mcpsnoop-home`, or `--remote-xdg-state-home` if the
remote's home/state directory doesn't match the Linux `/home/<user>` default guess.

For post-mortem review of a remote session without a live tunnel:

```bash
ssh remote-user@remote-host 'cat ~/.local/state/mcpsnoop/sessions/session.jsonl' | mcpsnoop open -
```

---

## Redacting secrets

Captured frames can include prompts, tool arguments, credentials, and results. Redaction
scrubs the *saved trace copies* while proxied bytes still pass through unchanged:

```bash
mcpsnoop --redact-secrets -- node build/index.js              # built-in preset of common secret keys
mcpsnoop --redact-key token,api_key,password -- node build/index.js
mcpsnoop --redact-path '$.params.arguments.password' -- node build/index.js
mcpsnoop --redact-value 'sk-[A-Za-z0-9]+' -- node build/index.js
```

Key-based redaction (`--redact-secrets` / `--redact-key`) replaces whole values under matching
JSON keys and best-effort scrubs matching keys in the wrapped server's command-line arguments
too. Path-based redaction (`--redact-path`, repeatable, JSONPath, wildcards supported) targets
one specific location. Value-based redaction (`--redact-value`, regex) applies to string
values, stderr, and non-JSON text. All modes are best effort — regexes can miss or overmatch.

These flags apply to both shim mode and `mcpsnoop http`, and can also live in a
`.mcpsnoop.toml` file in the working directory (see upstream README for the full key list).
