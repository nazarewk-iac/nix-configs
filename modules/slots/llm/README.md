---
type: Reference
description: Standalone NixOS slot serving local LLMs via llama-swap, with sequential, concurrency-capped model downloads. Currently applied to the brys host.
timestamp: 2026-08-30T00:00:00+02:00
---

# kdn.llm.local — local LLM serving

A standalone NixOS slot that serves several local LLMs behind
[llama-swap](https://github.com/mostlygeek/llama-swap). llama-swap spawns an
underlying `llama-server` (from llama.cpp) on demand and exposes a single
OpenAI-compatible HTTP API. One model runs at a time; the others stay on disk.

Currently applied to the **brys** host (`hosts/brys/default.nix`). See
[`docs/local-llms.md`](../../../docs/local-llms.md) for a deployment example
and the exact brys state.

## Characteristics

- **Standalone.** This slot uses only `lib`, `pkgs`, `config`, and plain NixOS
  options. It never references or assigns a `modules/universal/`- or
  `modules/meta/`-declared option (no `kdn.env.*`, `kdn.disks.*`, `kdnConfig`).
  See [Slots Standalone](../../../.agents/rules/slots-standalone.md).
- **One model at a time.** llama-swap loads the requested model into RAM and
  unloads it when you ask for a different one.
- **Sequential downloads.** A single download service walks all enabled models
  one at a time in the host network namespace, with HF transfer concurrency
  capped by `download.mode` (slow / fast-polite).

## How to enable

In a NixOS host (`hosts/<name>/default.nix`), inside the existing `mkSlots`
block:

```nix
slots = kdnConfig.self.mkSlots {
  inherit pkgs;
  # ...existing slot enables...

  kdn.llm.local.enable = true;
  kdn.llm.local.modelsDir = "/var/lib/kdn/llms/models"; # required, no default

  kdn.llm.local.download.mode = "slow";      # global (default "slow" | "fast-polite")

  kdn.llm.local.models = {
    qwen3-30b-a3b = {
      enable = true;
      hfRepo = "Qwen/Qwen3-30B-A3B-GGUF";
      hfFile = "Qwen3-30B-A3B-Q4_K_M.gguf";
      aliases = [ "fast" ];
    };
    # ...more models...
  };
};
```

`modelsDir` has no default and must be supplied by the host. The host may also
register the same path in its own persistence machinery (for example
`kdn.disks.persist...` in a repo that uses `modules/universal/`). The slot
does not create or own any specific mountpoint.

## Serving

- llama-swap listens on `127.0.0.1:39703` by default. Override with
  `kdn.llm.local.server.host` / `server.port`.
- `server.healthCheckTimeout` (default `300`) — seconds llama-swap waits for a
  model to become ready before failing it. Multi-hundred-GB CPU models can take
  minutes to load, so this is raised above llama-swap's ~120s default.
- Send requests to `POST /v1/chat/completions` at that address. Set the
  `model` field to a model name or alias. llama-swap loads or swaps the model
  automatically.
- `services.llama-swap.openFirewall` is left to the host to set if the server
  must be reachable beyond localhost.

## Downloading models

A single `systemd` service `kdn-llm-download` downloads the GGUF of every
**enabled** model with the `hf` CLI into `<modelsDir>/<hfRepo>/<hfFile>`,
**one model at a time, sequentially** (never concurrently). After each
download it logs a status line (size + path). It skips models whose file
already exists (unless `download.force`).

Downloads run directly in the host network namespace; `download.mode` controls
how aggressively HF transfers (env-based concurrency capping — the Xet Tier 1
mitigation set).

Global download options (`kdn.llm.local.download.*`):

- `download.mode` (default `"slow"`) — `"slow"` or `"fast-polite"`. Applied to
  **all** models.
  - `"slow"` (default): disable Xet high-performance transfer
    (`HF_XET_HIGH_PERFORMANCE=false`, `HF_HUB_DISABLE_XET=true`). Falls back
    to regular HTTP transfer, gentlest on a shared link.
  - `"fast-polite"`: keep Xet enabled but pin concurrency low (disable
    adaptive ramping, fixed low concurrency). Faster than `"slow"`, far
    gentler than Xet's full `"fast"`. This is the Tier 1 XET mitigation.
- `download.xetConcurrency` (default `2`) — Xet download concurrency used in
  `"fast-polite"` mode (the value of `HF_XET_FIXED_DOWNLOAD_CONCURRENCY` and
  `HF_XET_NUM_CONCURRENT_RANGE_GETS`). Higher = faster but more aggressive.
- `download.tokenFile` (default `null`) — path to a file with a HuggingFace
  token, loaded via systemd `LoadCredential`. The host wires this (e.g. via
  sops-nix to `/run/configs/llms/huggingface/token`). When null, downloads run
  anonymously (rate-limited).

## Per-model options

| Option | Type | Default | Meaning |
|---|---|---|---|
| `enable` | bool | `false` | serve this model in llama-swap |
| `hfRepo` | string | required | HuggingFace repo `owner/name` |
| `hfFile` | string | required | GGUF path within `hfRepo`; may be a subdir path or the first shard of a split |
| `download.glob` | string or null | `null` | glob within `hfRepo` that the download fetches (e.g. all shards of a split); when set the download always runs |
| `aliases` | list of string | `[]` | extra names llama-swap answers to |
| `threads` | int or null | `null` | `llama-server -t` (null lets llama-server choose) |
| `ttl` | int | `3600` | seconds llama-swap keeps the model loaded after its last request before unloading (1h default; set higher for slow-to-load models like `deepseek-v4-flash`) |
| `download.enable` | bool | `true` | include in the sequential download run |
| `download.force` | bool | `false` | re-download even if present |

`ttl` is per model. Set, for example, `ttl = 86400` (24h) on a large model you
want to keep resident instead of re-loading repeatedly.

Download mode (`download.mode`) is **global** (`kdn.llm.local.download.mode`),
not per model.

Only `enable = true` models are configured and downloaded. Keep the other
models declared-but-disabled to add them later with a one-line change.

## Operations

- **Status:** `kdn-llm-status` (installed into PATH) shows llama-swap status,
  the download service, and recent download logs.
- **Run a download:** `systemctl start kdn-llm-download` (or the
  `kdn-llm-download.target`).
- **Watch a download:** `journalctl -fu kdn-llm-download`.

## Notes for a CPU-only 128 GB machine (brys)

- Prefer MoE models; they activate a fraction of their parameters and are far
  more RAM-bandwidth efficient on DDR4.
- A ~103 GB model loads in several minutes (disk + DDR4 bandwidth bound). A
  ~18 GB model loads in under a minute.
- First request to a loaded model may appear to hang while it loads — that is
  normal.

See [`docs/eli5-llama-swap.md`](../../../docs/eli5-llama-swap.md) for a
plain-English explanation of how model swapping works.
