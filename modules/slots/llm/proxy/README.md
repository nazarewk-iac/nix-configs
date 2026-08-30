---
type: Reference
description: Standalone slot that runs one or more opencode_compat_proxy instances to translate DeepSeek DSML / Qwen XML tool calls into OpenAI-compatible JSON for OpenCode, against any upstream (Requesty, local llama-swap).
timestamp: 2026-08-30T00:00:00+02:00
---

# kdn.llm.proxy — OpenCode DSML compatibility proxy

A standalone slot that runs one or more
[opencode_compat_proxy](https://github.com/ladiossoop5star/opencode_compat_proxy)
instances. Each instance is a thin FastAPI layer between OpenCode and an LLM
backend that turns raw DeepSeek DSML / Qwen XML tool-call markup into
OpenAI-compatible `tool_calls` JSON, so OpenCode can drive agentic tool loops
against models that emit raw markup.

## Why

DeepSeek V4 Flash (and friends) intermittently leak DSML tool-call markup
(`<｜DSML｜tool_calls>`, degraded `<||DSML||…>` tokens) into the content stream
instead of emitting structured `tool_calls`. Routers like Requesty pass that
markup through unchanged, so OpenCode hangs waiting for a response. This proxy
intercepts the stream and translates the markup on the fly.

## How to enable

In a NixOS host (`hosts/<name>/default.nix`), inside the existing `mkSlots`
block:

```nix
slots = kdnConfig.self.mkSlots {
  inherit pkgs;
  # ...existing slot enables...

  kdn.llm.proxy.enable = true;

  # Requesty router. forwardClientAuth makes the proxy forward the client's
  # Authorization header to the upstream on the streaming path too — Requesty
  # authenticates with that key.
  kdn.llm.proxy.instances.requesty = {
    enable = true;
    upstreamUrl = "https://router.requesty.ai";
    port = 9526;
    forwardClientAuth = true;
  };

  # Local llama-swap DeepSeek model, on a second port. No auth needed.
  kdn.llm.proxy.instances.local = {
    enable = true;
    upstreamUrl = "http://127.0.0.1:39703";
    port = 9527;
  };
};
```

## Upstream authentication

Authentication is purely client-side pass-through. The proxy holds **no secret
of its own**: the OpenCode client authenticates to the upstream directly with
its own `Authorization: Bearer <key>` header, and the proxy forwards that
header to the upstream unchanged. So the Requesty API key only ever lives on
the OpenCode side.

The original proxy already forwards the client's `Authorization` on
**non-streaming** requests, but silently drops it on the **streaming** path
(which is what OpenCode uses). A small patch to `proxy.py` adds a
`FORWARD_AUTHORIZATION` env flag that extends forwarding to streaming.

Per instance, `forwardClientAuth = true` enables that streaming-path
forwarding. Leave it `false` (default) for a local, auth-less backend such as
llama-swap so the client's key is never sent to it.

## Options

### Top-level

| Option | Type | Default | Meaning |
|---|---|---|---|
| `enable` | bool | `false` | enable the slot |
| `package` | package | `pkgs.opencode-compat-proxy` | package for instances that don't override theirs |

### `instances.<name>`

| Option | Type | Default | Meaning |
|---|---|---|---|
| `enable` | bool | `false` | run this instance |
| `upstreamUrl` | string | *required* | upstream LLM backend base URL (e.g. `https://router.requesty.ai` or `http://127.0.0.1:39703`) |
| `host` | string | `127.0.0.1` | bind address |
| `port` | int | `9526` | listen port |
| `openFirewall` | bool | `false` | open this port in the nixos firewall |
| `forwardClientAuth` | bool | `false` | forward the client's Authorization header to the upstream on the streaming path (upstream is authenticated via client key) |
| `package` | package | top-level `package` | override per instance |

## Targets

- **nixos**: a `systemd` service `kdn-llm-proxy-<name>` per enabled instance.
  Runs as a `DynamicUser` with hardened `serviceConfig`, listening on
  `host:port`, forwarding to `upstreamUrl`.
- **devenv**: a process `proxy-<name>` per enabled instance, plus the package
  on PATH, when the slot is pulled into a devenv shell.

## Pointing OpenCode at a proxy

Two requesty modes coexist in the global `opencode.json`:

- **`requesty/*`** — the native requesty provider, kept at its real API
  (`router.requesty.ai`). Direct, no proxy, no env var needed. Good when DSML
  isn't an issue.
- **`requesty-proxy/*`** — an `@ai-sdk/openai-compatible` provider that points
  `baseURL` at the local proxy (`http://127.0.0.1:<port>/v1`) and uses
  `{env:REQUESTY_API_KEY}`. Because the proxy forwards the client's
  `Authorization` header unchanged (streaming when `forwardClientAuth = true`),
  the Requesty key only ever needs to exist on the OpenCode side.
- **`local-llm-proxy/*`** — points at the local llama-swap proxy instance; no
  auth (`apiKey: "dummy"`).

Example `opencode.json` provider entries:

```jsonc
{
  "model": "requesty-proxy/sference/deepseek-v4-flash-0731",
  "provider": {
    "requesty": {}, // native, direct
    "requesty-proxy": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "DeepSeek V4 Flash (Requesty via DSML proxy)",
      "options": {
        "baseURL": "http://127.0.0.1:9526/v1",
        "apiKey": "{env:REQUESTY_API_KEY}"
      },
      "models": {
        "sference/deepseek-v4-flash-0731": {
          "name": "deepseek-v4-flash-0731 (proxied)",
          "limit": { "context": 65536, "output": 8192 }
        }
      }
    },
    "local-llm-proxy": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "DeepSeek V4 Flash (local llama-swap via DSML proxy)",
      "options": { "baseURL": "http://127.0.0.1:9527/v1", "apiKey": "dummy" },
      "models": {
        "deepseek-v4-flash": {
          "name": "deepseek-v4-flash (local)",
          "limit": { "context": 65536, "output": 8192 }
        }
      }
    }
  }
}
```

### `opencode-kdn` wrapper (devenv)

The `requesty-proxy` provider needs `REQUESTY_API_KEY` set. The slot ships an
`opencode-kdn` wrapper (installed in the devenv `packages` when the slot is
active) that loads the key from `~/.local/share/opencode/auth.json` via `jq`
(`.requesty.key`) and then execs the real `opencode`:

```bash
opencode-kdn           # inside the devenv shell; sets REQUESTY_API_KEY
```

Run OpenCode via `opencode-kdn` (in the devenv shell) so the proxied requesty
provider authenticates. Raw `opencode` outside the wrapper won't have the key
for `requesty-proxy/*`.

## Operations

- NixOS: `systemctl status kdn-llm-proxy-<name>`, `journalctl -fu
  kdn-llm-proxy-<name>`.
- devenv: `devenv processes list` / `devenv up` to start instances.
- devenv: use `opencode-kdn` (installed on PATH) to run OpenCode with
  `REQUESTY_API_KEY` loaded for the `requesty-proxy` provider.

## Standalone

This slot uses only `lib`, `pkgs`, `config`, and plain nixpkgs options
(`systemd.services.*`, `networking.firewall.*`, devenv `processes.*`). It never
references or assigns an option declared by `modules/universal/` or
`modules/meta/`. See [Slots Standalone](../../../../.agents/rules/slots-standalone.md).
