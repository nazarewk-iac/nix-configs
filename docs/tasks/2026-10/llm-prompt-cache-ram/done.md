---
type: Solution
description: Add a `perf.cacheRam` slot option and set the Qwen specialisations to `--cache-ram 36864`, so the prompt cache stops evicting; activated on brys.
task: definition.md
authored_by: agent
timestamp: 2026-10-09T18:45:00+02:00
---

# Raise the Qwen prompt cache to 37 GiB

## Root cause analysis

The log line `making room for prompt cache entry, removing oldest entry` is
from llama.cpp's **prompt cache** (`server_prompt_cache`), not the KV cache.
The prompt cache keeps KV states of processed prompts for prefix reuse; its
size is bounded by `--cache-ram` / `-cram`, default **8192 MiB**. On
`qwen3.8-flash-next` one long prompt is ~5.7 GiB, so the 8 GiB default held
barely one entry and evicted constantly. The KV cache is a separate,
preallocated structure (`ctx-size` = 1048576, `kv-unified = on`) and was never
the thing being evicted.

The slot exposed no `--cache-ram` option, so every model inherited the 8192 MiB
default.

## Solution

- `modules/slots/llm/default.nix`: add `perf.cacheRam` (`nullOr int`, `null`
  default) and emit `cache-ram = <N>` when set. `-1` means no limit, `0`
  disables the cache. Mirrored in `modules/den/aspects/llm.nix`.
- `hosts/brys/llm.nix`: add a `qwenCacheRam` argument, folded into `qwenPerf`
  as `cacheRam`, so `llm-qwen` and `llms-frontier` share it and cannot drift.
- `hosts/brys/llm-qwen.nix`, `hosts/brys/llms-frontier.nix`: set
  `qwenCacheRam = 36864` (37 GiB).
- Docs: `docs/local-llms.md` (RAM levers table + note) and
  `modules/slots/llm/README.md` (option table).

Rendered `models-preset.ini` (new):

```ini
[qwen3.8-flash-next]
...
ctx-size = 1048576
...
cache-ram = 36864
```

The DeepSeek section is unchanged.

## Verification steps

- Preset renders: `nix build .#nixosConfigurations.brys.config.specialisation.llms-frontier.configuration.services.llama-cpp.settings.models-preset`
  contains `cache-ram = 36864` in the Qwen section, nothing in the DS4 section.
- `den-eval-llm` passes (11/11) after the aspect mirror, run with
  `NIX_CONFIG='netrc-file = /dev/null'` (the `/etc/nix/netrc` GitHub credential
  is deprecated; see the [follow-up](#follow-up-notes)).
- Full closure built: `nix build '.#nixosConfigurations.brys.config.system.build.toplevel'`.
- Activated on brys: `./nixos-rebuild.sh switch remote=brys --specialisation llms-frontier`.
  `/run/current-system` is now the new `…-brys-llms-frontier-…` toplevel.
- End-to-end: a one-token request loaded Qwen; the child's `/proc/<pid>/cmdline`
  contains `--cache-ram 36864` (and `--ctx-size 1048576`).
- Post-load baseline (`free -m`): `MemFree` ~1.1 GiB, `MemAvailable` ~60 GiB;
  child `RssAnon` ~58 GiB, `RssFile` ~58 GiB.

## Follow-up notes

- The runtime criterion ("evictions stop, `MemAvailable` stays ≥ ~8 GiB") needs
  the normal long-prompt workload to fill the larger cache; observe
  `journalctl -u llama-cpp | grep 'prompt cache'` over a session.
- The `switch` exited status 4, caused by the **pre-existing** atuin login
  failures (`kdn-atuin-login-kdn/root`, key mismatch) plus a Caddy reload
  timeout — unrelated to this change; all serving units are active.
- `den-eval-llm` (and any check that fetches the `gen-schema` input) needs
  `NIX_CONFIG='netrc-file = /dev/null'`. The root cause is the hand-placed
  `/etc/nix/netrc` with a deprecated `github.com` password credential. The
  documented workaround is in
  `docs/tasks/2026-09/declarative-certificates/006-zellij-migration/done.md`.
  A permanent fix (drop the `github.com` line, or use the SOPS `access-tokens`
  PAT) is still open.
