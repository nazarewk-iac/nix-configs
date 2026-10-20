---
type: Research
description: Measured standalone profile of Qwen3.8-27B on brys at 32K context (llama-cpp-sessions-vulkan-noblas), with CPU and W6600-offload rows, memory, and the exact llm-routers.nix registration.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T19:36:03+02:00
---

# Qwen3.8-27B on brys: download, measurement, registration

This file records the deployment of `Qwen3.8-27B` on host `brys` only. It gives
the download, the standalone measurement, the GPU-offload comparison, and the
`hosts/brys/llm-routers.nix` change. No rebuild and no system switch was done;
another step deploys the config.

## Artifact

| field | value |
|---|---|
| HF repo | `unsloth/Qwen3.8-27B-GGUF` |
| HF file | `Qwen3.8-27B-UD-Q4_K_M.gguf` |
| size | 16,464,440,224 bytes (15.33 GiB) |
| LFS oid (sha256) | `322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482` |
| verified sha256 on brys | `322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482` (matches) |
| path on brys | `/var/lib/kdn/llms/models/surveyed/qwen3.8-27b.gguf` |
| download method | `hf download` on brys, token at `/run/configs/llms/huggingface/token` |

The Xet transfer path stalled at 1.34 GB. The download used
`HF_HUB_DISABLE_XET=1` and then completed at about 100 MB/s. The file was
renamed from `Qwen3.8-27B-UD-Q4_K_M.gguf` to `qwen3.8-27b.gguf` to match the
`surveyed` tree naming that `hfFile = "${name}.gguf"` expects. The HF cache was
removed after the move.

## Build and method

- Build: the served `llama-cpp-sessions-vulkan-noblas`
  (`/nix/store/z77bfs2b63wfzlzfczcaq6apsigwd0qw-llama-cpp-sessions-vulkan-noblas-0.6.0-unstable-2026-10-09/bin/llama-server`).
- One standalone `llama-server` per row on `127.0.0.1:39799`, `--parallel 1`,
  `--no-warmup`, `-t 16`, `-fa on`, `-c 32768`.
- Page cache was dropped before each load, so each `load_s` is a cold load.
- Decode: one short English prompt, 128-token cap, warm. Prefill: one unique
  prompt, `prompt_n` reported per row.
- Memory read from the real `llama-server` pid in `/proc/<pid>/status`. System
  `used` from `free -m`.
- Date: 2026-10-20. Box: Ryzen 5950X, 128 GB DDR4, one 8 GB AMD W6600.

## Measurements

Each throughput number below is measured. `ngl 0` is the CPU row; the others
offload that many layers to the W6600.

| config | ctx | ngl | load_s | decode_tok_s | prefill_tok_s | RssFile_MiB | RssAnon_MiB | VmRSS_MiB | SYS_used_MB | note |
|---|---|---|---|---|---|---|---|---|---|---|
| cpu-ngl0 | 32768 | 0 | 27.3 | 2.45 | 78.3 | 15388 | 3250 | 18639 | 22226 | prompt_n=1033; second CPU run |
| cpu-ngl0 | 32768 | 0 | 27.3 | 2.40 | 81.7 | 15388 | 3251 | 18640 | 22235 | prompt_n=1033; first CPU run |
| gpu-ngl24 | 32768 | 24 | 28.3 | 2.66 | 60.6 | 9415 | 2442 | 11857 | 21554 | prompt_n=1033 |
| gpu-ngl32 | 32768 | 32 | 29.3 | 3.05 | 56.4 | 7704 | 2169 | 9874 | 21162 | prompt_n=1033 |
| gpu-ngl36 | 32768 | 36 | 29.3 | 2.85 | 52.7 | 6874 | 2032 | 8907 | 21149 | prompt_n=1033 |
| gpu-ngl40 | 32768 | 40 | 30.3 | 3.13 | 49.2 | 6014 | 1896 | 7910 | 21278 | prompt_n=1033; best decode |
| gpu-ngl99 | 32768 | 99 | 32.3 | 1.62 | 24.8 | 714 | 1063 | 1778 | 25860 | prompt_n=1033; all layers; worst |

Reference CPU values from the 2026-10-19 suite for the same class:
`qwen3.6-27b` 3.13 t/s decode, 102 prefill; `granite-4.2-30b` 3.00 / 95.8.

## Findings

### GPU offload does not help at a useful point

- `ngl 99` is the worst row: decode 1.62 tok/s and prefill 24.8 tok/s. The 8 GB
  W6600 cannot hold 15.3 GB of weights plus the KV cache and compute buffers, so
  layers move across the PCIe link every token.
- Partial offload trades prefill for decode. From `ngl 0` to `ngl 40`, decode
  rises from 2.45 to 3.13 tok/s (about +28%) but prefill falls from about 80 to
  49 tok/s (about -39%). The model is memory-bandwidth bound on the activated
  weights, and the split cost is worse than the gain.
- At `ngl 40` the W6600 holds about 7.3 GB of 8 GB. It still runs, but the
  prefill loss makes it a poor fit for prompt-heavy work.
- Verdict: keep it at `-ngl 0` (CPU only), which is the registered shape. The
  task's predicted CPU decode of about 2.4 tok/s holds.

### The mmproj is not needed for text

The `mmproj-F16.gguf` projector (927,607,488 bytes, in the same repo) is only
for image input. Text-only serving needs no projector, and the server loaded and
answered text without it. The projector was NOT wired. A later step can add an
`mmproj` block in the model card if vision is wanted.

## Registration

Added one line to the CPU block of the `surveyed` set in
`hosts/brys/llm-routers.nix`, beside `qwen3.6-27b`:

```nix
"qwen3.8-27b" = mkCpu "qwen3.8-27b" 32768;
```

This uses the existing `mkCpu` factory. It resolves to
`hfRepo = "surveyed"`, `hfFile = "qwen3.8-27b.gguf"`, `mainRouter = "surveyed"`,
`download.enable = false`, `perf.contextSize = 32768`, `perf.threads = 8`, no
GPU offload, `parallel = 1`. It is not in `swap.persistentModels`, so it has
`evict_cost = 1` and a request for it never evicts the frontier.

The context of 32768 is the task recommendation and the measured context. The
native window is 262144 (YaRN to 1000000); the surveyed router keeps 32768 so
the CPU KV cost stays small.

## See also

- [mid-band-survey.research.md](mid-band-survey.research.md) — the desk survey
  that picked Qwen3.8-27B.
- [definition.md](definition.md) — this task.
- [llm-benchmark-suite/001-benchmark-suite/measurements.research.md](../llm-benchmark-suite/001-benchmark-suite/measurements.research.md)
  — the served-model suite, for the class reference numbers.
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) — the
  registration.
