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
- Ships the `opencode` wrapper as the `opencode` binary on PATH. The wrapper reads
  every credential named in `authKeys` from `authFile` via `jq`, then execs the
  real opencode by absolute path.

The slot names no provider and no model of its own, so a global enable is
harmless. Only the permission baseline is emitted on every host, and
`allowedPaths` states which path globs a read-only tool reaches. Consumers extend
`settings` — typically through a hostname-scoped devenv profile — to add the
providers they want.

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
| `settings` | attrsOf anything | `{ }` | opencode config written to `opencode.jsonc` (model, provider, permission) |
| `allowedPaths` | listOf str | `[ "/nix/store/**" ]` | path globs a read-only tool reaches with no question |
| `authFile` | str | `$HOME/.local/share/opencode/auth.json` | opencode's own credential store, read by the wrapper |
| `authKeys` | attrsOf str | `{ }` | env var name → provider id in `authFile` |

`settings` is written verbatim to `opencode.jsonc`; use it to set `model`,
`provider`, `permission`, or any other opencode key. The default is empty. The
slot merges the permission baseline under `settings` in its own `config`, so a
`permission` key here replaces that baseline in full.

## `opencode` wrapper

`kdn.opencode` ships the opencode entrypoint as an **`opencode`** binary on PATH
that is itself the wrapper. For each `authKeys.<VAR> = "<provider>"` entry it
reads `.<provider>.key` out of `authFile` with `jq` and exports `<VAR>`. It also
applies key/env/pre-exec injection from `kdn.opencode.wrapper`, then execs the
real `pkgs.opencode` by absolute store path. The real binary is NOT put on PATH,
so a bare `opencode` in the shell always activates the wrapper — a proxied
provider authenticates with no extra step. Run `opencode` directly (the wrapper
is `opencode`).

## Standalone

This slot uses only `lib`, `pkgs`, `config`, and plain devenv options
(`opencode.*`, `packages`). It never references or assigns an option declared
by `modules/universal/` or `modules/meta/`. See
[Slots Standalone](../../../.agents/rules/slots-standalone.md).
