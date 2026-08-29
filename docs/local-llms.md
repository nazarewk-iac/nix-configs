---
type: Reference
description: Local LLM serving via the kdn.llm.local slot — full option synopsis, architecture, and the brys host as a concrete deployment example.
timestamp: 2026-08-30T00:00:00+02:00
---

# Local LLM serving

How the `kdn.llm.local` standalone slot serves local LLMs on a NixOS host.
This document covers the concept, the global download behaviour, and a
concrete example single-host deployment on **brys**.

Reference docs: [slot README](../modules/slots/llm/README.md), [beginner
guide](eli5-llama-swap.md).

## Concept

`kdn.llm.local` runs local LLMs behind llama-swap, which exposes one
OpenAI-compatible HTTP API and spawns an underlying `llama-server` per model on
demand. One model runs in RAM at a time; the others stay on disk. Models are
downloaded sequentially by a single service, directly in the host network
namespace, with HF transfer concurrency capped by `download.mode`.

To enable on any NixOS host, inside its `mkSlots` block:

```nix
kdn.llm.local.enable = true;
kdn.llm.local.modelsDir = "/var/lib/kdn/llms/models";    # required, no default
kdn.llm.local.download.mode = "slow";                    # global: slow | fast-polite
# ... per-model `kdn.llm.local.models.<name>` entries ...
```

Full option reference: [slot README](../modules/slots/llm/README.md).

## Global download behaviour

Applies to all models equally (not per model):

- **`download.mode`** — how aggressively to transfer:
  - `"slow"` (default): Xet disabled, regular HTTP. Gentlest.
  - `"fast-polite"`: Xet enabled, low pinned concurrency (Tier 1 mitigation).
    Faster than `"slow"` while staying gentle on a shared link.
  how aggressive Xet is.
- **`download.tokenFile`** — optional HF token path, loaded via systemd
  `LoadCredential`.

The download service (`kdn-llm-download`) walks all enabled models one at a
time, logs a status line after each, and skips files already present.

## Example deployment: brys

The **brys** host (Ryzen 5950X, 128 GB DDR4, CPU-only with an effectively
unusable 8 GB AMD GPU for this workload) is the primary deployment of this
slot.

### Serving endpoint

- llama-swap HTTP API: `http://127.0.0.1:39703` (OpenAI-compatible).
- Talk to it with any OpenAI-compatible client; set the `model` field to a
  model name or alias. llama-swap loads the requested GGUF and unloads the
  previous one automatically.

### Models (all enabled on brys)

| Name | Alias | hfRepo / file | Size |
|---|---|---|---|
| `qwen3-30b-a3b` | `fast` | `Qwen/Qwen3-30B-A3B-GGUF` / `Qwen3-30B-A3B-Q4_K_M.gguf` | ~18 GB |
| `qwen3-next-80b` | `balanced` | `unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF` / `...-Q4_K_M.gguf` | ~48 GB |
| `deepseek-v4-flash` | `frontier` | `unsloth/DeepSeek-V4-Flash-GGUF` / `UD-IQ3_XXS/...-00001-of-00004.gguf` | ~103 GB (multi-shard) |
| `qwen3-235b` | — | `mradermacher/Qwen3-235B-A22B-i1-GGUF` / `...IQ2_M.gguf.part1of2` | ~77 GB |
| `qwen3-coder-next` | — | `Qwen/Qwen3-Coder-Next-GGUF` / `...-Q4_K_M-00001-of-00004.gguf` | ~48 GB |
| `gpt-oss-120b` | — | `unsloth/gpt-oss-120b-GGUF` / `gpt-oss-120b-F16.gguf` | ~65 GB |
| `phi-4` | — | `microsoft/phi-4-gguf` / `phi-4-Q4_K.gguf` | ~9 GB |

### Download configuration on brys

- **Service:** `kdn-llm-download` — sequential, one model at a time.
- **Mode:** `fast-polite` — Xet enabled with low pinned concurrency (Tier 1
  mitigation), so downloads are faster than `"slow"` while staying gentle on
  the shared link. Runs directly in the host network namespace.
- **Token:** `HF_TOKEN` via systemd `LoadCredential` from
  `/run/configs/llms/huggingface/token` (wired through sops-nix).

### Persistence

Model files live at `/var/lib/kdn/llms/models`, registered under
`kdn.disks.persist."usr/data"` (ZFS `usr/data` dataset) so they survive
reboots.

### Secrets

The HF token (`huggingface.token` in `llms.nonsensitive.sops.yaml`) is
decrypted to `/run/configs/llms/huggingface/token` by the host's
`sops-install-secrets` wiring (`kdn.security.secrets.sops.files."llms"` in
`hosts/brys/default.nix`, basePath `/run/configs/llms`, keyPrefix
`huggingface`).

### Status / known state

- `qwen3-30b-a3b` and `qwen3-next-80b` were fully downloaded and verified on
  the 2026-08-29 smoke test.
- `deepseek-v4-flash` still only has a 5 MB stub from the earliest attempt; a
  `systemctl start kdn-llm-download` run (fast-polite) will fetch it fully.
- Go-to status command: `kdn-llm-status`.
