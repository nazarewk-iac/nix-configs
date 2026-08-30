---
type: Reference
description: Standalone slot that configures in-devenv opencode declaratively (providers, permissions, model) via devenv's opencode.settings, and ships the opencode-kdn wrapper for the requesty-proxy provider. MVP wired into this repo's devenv (brys host).
timestamp: 2026-08-30T00:00:00+02:00
---

# kdn.opencode — in-devenv opencode configuration

A standalone slot that owns the opencode configuration used inside the devenv
shell. It generates a project-level `opencode.jsonc` (via devenv's native
`opencode.settings`), so opencode launched in the shell is configured
declaratively rather than depending on a hand-edited global
`~/.config/opencode/opencode.jsonc`. opencode deep-merges this project config
over the global one, so unrelated global settings still apply.

## Providers

| Provider | Model | Backend | Auth |
|---|---|---|---|
| `requesty/*` | native requesty | `router.requesty.ai` direct | key from `auth.json` |
| `requesty-proxy/sference/deepseek-v4-flash-0731` | requesty via DSML proxy | `127.0.0.1:9532` | `REQUESTY_API_KEY` (via `opencode-kdn`) |
| `local-llm-proxy/deepseek-v4-flash` | local llama-swap via DSML proxy | `127.0.0.1:9533` | none |

Default model: `requesty-proxy/sference/deepseek-v4-flash-0731`.

## opencode-kdn wrapper

`kdn.opencode` ships an `opencode-kdn` wrapper (on PATH inside the shell) that
loads `REQUESTY_API_KEY` from `~/.local/share/opencode/auth.json` via `jq`
(`.requesty.key`) and then execs the real `opencode`. Run OpenCode via
`opencode-kdn` so the `requesty-proxy` provider authenticates; a plain `opencode`
outside the wrapper won't have the key for that provider.

## How to enable

In this repo's `devenv.nix` (the devenv shell used on brys):

```nix
kdn.opencode.enable = true;
```

Optionally point the requesty proxy at an instance from `kdn.llm.proxy`:

```nix
kdn.llm.proxy.enable = true;
kdn.llm.proxy.instances.requesty = {
  enable = true;
  upstreamUrl = "https://router.requesty.ai";
  port = 9526;
  forwardClientAuth = true;
};
```

The opencode slot runs its own local proxy process (upstream
`127.0.0.1:39703`, the host llama-swap) unless `kdn.opencode.localProxy.enable`
is false.

## Options

| Option | Type | Default | Meaning |
|---|---|---|---|
| `enable` | bool | `false` | enable in-devenv opencode config |
| `package` | package | `pkgs.opencode` | opencode binary on PATH |
| `requestyProxyBaseURL` | string | `http://127.0.0.1:9532` | requesty DSML proxy base URL |
| `localProxyBaseURL` | string | `http://127.0.0.1:9533` | local DSML proxy base URL |
| `defaultModel` | string | `requesty-proxy/sference/deepseek-v4-flash-0731` | default model |
| `localProxy.enable` | bool | `true` | run the local proxy as a process |
| `localProxy.upstreamUrl` | string | `http://127.0.0.1:39703` | upstream local LLM backend |

## Standalone

This slot uses only `lib`, `pkgs`, `config`, and plain devenv options
(`opencode.*`, `packages`, `processes`). It never references or assigns an
option declared by `modules/universal/` or `modules/meta/`. See
[Slots Standalone](../../../.agents/rules/slots-standalone.md).
