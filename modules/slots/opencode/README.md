---
type: Reference
description: Standalone slot that configures in-devenv opencode declaratively (opencode.jsonc via devenv's opencode.settings) and ships an `opencode` wrapper binary. A bare capability — consumers supply the providers/models/upstreams via the settings option; brys wires its local model through a hostname-scoped devenv profile.
timestamp: 2026-08-30T00:00:00+02:00
---

# kdn.opencode — in-devenv opencode capability

A standalone slot that owns the opencode configuration used inside the devenv
shell. It generates a project-level `opencode.jsonc` (via devenv's native
`opencode.settings`), so opencode launched in the shell is configured
declaratively rather than depending on a hand-edited global
`~/.config/opencode/opencode.jsonc`. opencode deep-merges this project config
over the global one, so unrelated global settings still apply.

## Bare capability

The slot is intentionally generalised — it exposes the *capability* and declares
no specific providers, models, or upstreams itself:

- Generates `opencode.jsonc` from the `settings` option (free-form attrset).
- Ships the `opencode` wrapper as the `opencode` binary on PATH (loads
  `REQUESTY_API_KEY` from `~/.local/share/opencode/auth.json` via `jq`, then
  execs the real opencode by absolute path).

Because no specific model/provider wiring is baked in, enabling the slot
globally is harmless: a default `settings` skeleton (native `requesty` provider,
a working default model, and the permission block) is emitted on every host.
Consumers override/extend `settings` — typically via a hostname-scoped devenv
profile — to add the proxied/local providers they actually want.

## brys example

brys runs its local DeepSeek V4 Flash (llama-swap on `127.0.0.1:39703`) and
requesty through DSML proxies. A brys-specific devenv profile
(`hosts/brys/devenv.nix`, imported by the primary `devenv.nix` via
`profiles.hostname."brys".module`) supplies `kdn.opencode.settings` with the
three providers and enables the proxy instances. See that file for the exact
wiring.

## Options

| Option | Type | Default | Meaning |
|---|---|---|---|
| `enable` | bool | `false` | enable in-devenv opencode config |
| `package` | package | `pkgs.opencode` | real opencode binary the wrapper execs (kept off bare PATH) |
| `settings` | attrsOf anything | benign skeleton | opencode config written to `opencode.jsonc` (model, provider, permission) |

`settings` is written verbatim to `opencode.jsonc`; use it to set `model`,
`provider`, `permission`, or any other opencode key. The default skeleton is:
`model = "requesty/deepseek-v4-flash-0731"`, `provider.requesty = {}`, and the
permission block.

## `opencode` wrapper

`kdn.opencode` ships the opencode entrypoint as an **`opencode`** binary on PATH
that is itself the wrapper: it loads `REQUESTY_API_KEY` from
`~/.local/share/opencode/auth.json` via `jq` (`.requesty.key`), and also
applies key/env/pre-exec injection from `kdn.opencode.wrapper`, then execs the
real `pkgs.opencode` by absolute store path. The real binary is NOT put on PATH,
so a bare `opencode` in the shell always activates the wrapper — a `requesty-proxy`
provider authenticates without an extra `opencode-kdn` step. Run `opencode`
directly (the wrapper is `opencode`).

## Standalone

This slot uses only `lib`, `pkgs`, `config`, and plain devenv options
(`opencode.*`, `packages`). It never references or assigns an option declared
by `modules/universal/` or `modules/meta/`. See
[Slots Standalone](../../../.agents/rules/slots-standalone.md).
