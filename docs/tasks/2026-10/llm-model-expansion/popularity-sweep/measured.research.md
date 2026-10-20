---
type: Research
description: Download and standalone measurement on brys of the top new popularity-sweep candidates (Ornith-1.5-9B/35B-A3B, MiniCPM-V-4.7-35B-A3B, LFM2.5-2.6B, Muse-Glimmer-30B, Tiel-Coder-35B-A3B-MTP, Mellum2.1-12B-A2.5B, Hy-Memory-30B-A3B). One-off llama-server, ctx 32768, -ngl 0, one row per model, modality smoke tests, arch-support findings, plus a registration ranking.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T21:15:00+02:00
---

# Popularity-sweep candidates on brys: download and measurement

This file records the download and the standalone measurement on host `brys`
only, for the top new candidates of
[sweep.research.md](sweep.research.md). It does not register anything;
registration is a separate decision. The method is the same as
[qwen-specialized-measured.research.md](../qwen-specialized-measured.research.md)
and [new-candidates.research.md](../new-candidates.research.md).

## Method

- Builds tried per model:
  - **sessions**: the served `llama-cpp-sessions-vulkan-noblas` build 11539
    (`/nix/store/z77bfs2b63wfzlzfczcaq6apsigwd0qw-llama-cpp-sessions-vulkan-noblas-0.6.0-unstable-2026-10-09/bin/llama-server`).
  - **master**: the newest store build
    `llama-cpp-master-pin-hot-experts-vulkan` build 11539
    (`/nix/store/s19bsy6yi4p9l114d49m5qqq4v9cqvz9-llama-cpp-master-pin-hot-experts-vulkan-0.6.0-unstable-2026-10-08/bin/llama-server`).
    The master build is tried only when the sessions build fails an arch.
- One one-off `llama-server` per model on `127.0.0.1:39799`, one at a time,
  `--parallel 1`, `--no-warmup`, `-t 16`, `-fa on`, `-ngl 0`, `-c 32768`.
  Vision rows add `--mmproj <projector>`.
- `sync; echo 3 > /proc/sys/vm/drop_caches` before each load, so each `load_s` is
  a cold load.
- Decode: one short English prompt, 128-token cap, no prompt cache. Prefill: one
  unique long prompt, 1-token cap; `prompt_n` is about 1020 in every row.
- Memory read from the real `llama-server` pid in `/proc/<pid>/status`. System
  `used` from `free -m` after the load. `RssFile` / `RssAnon` / `VmRSS` are shown
  in MiB.
- Download: `hf download` on brys with `HF_HUB_DISABLE_XET=1`, token at
  `/run/configs/llms/huggingface/token`, into
  `/var/lib/kdn/llms/models/surveyed/`. Each file was renamed to `<slug>.gguf`.
- Arch read from the GGUF metadata (`general.architecture`) with `strings`.
- Date: 2026-10-20. Box: Ryzen 5950X, 128 GB DDR4, one 8 GB AMD W6600.

## Downloads

| # | repo | file | size GB | local name | note |
|---|---|---|---|---|---|
| 1 | `ornith-ai/Ornith-1.5-9B-GGUF` | `Ornith-1.5-9B-Q4_K_M.gguf` | 5.38 | `ornith-1.5-9b.gguf` | + mmproj 0.86 GB |
| 2 | `ornith-ai/Ornith-1.5-35B-A3B-GGUF` | `Ornith-1.5-35B-Q4_K_M.gguf` | 20.22 | `ornith-1.5-35b-a3b.gguf` | + mmproj 0.84 GB |
| 3 | `openbmb/MiniCPM-V-4.7-35B-A3B-gguf` | `MiniCPM-V-4_7-35B-A3B-Q4_K_M.gguf` | 19.71 | `minicpm-v-4.7-35b-a3b.gguf` | + mmproj 1.04 GB |
| 4 | `LiquidAI/LFM2.5-2.6B-GGUF` | `LFM2.5-2.6B-Q4_K_M.gguf` | 1.56 | `lfm2.5-2.6b.gguf` | text |
| 5 | `unsloth/Muse-Glimmer-30B-GGUF` | `Muse-Glimmer-30B-UD-Q4_K_XL.gguf` | 14.79 | `muse-glimmer-30b.gguf` | + mmproj 1.91 GB |
| 6 | `unsloth/Inkling-Small-GGUF` | `Inkling-Small-UD-Q4_K_M-*` | **158** | — | **not downloaded; see below** |
| 7 | `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP` | `Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf` | 21.19 | `tiel-coder-35b-a3b-mtp.gguf` | + mmproj 0.84 GB |
| 8 | `JetBrains/Mellum2.1-12B-A2.5B-Thinking-GGUF` | `Mellum2.1-12B-A2.5B-Thinking-Q4_K_M.gguf` | 7.52 | `mellum-2.1-12b-a2.5b-thinking.gguf` | text |
| 9 | `tencent/Hy-Memory-30B-A3B-GGUF` | `hy3a3b-memrl1009-step250-Q4_K_M-imat.gguf` | 16.98 | `hy-memory-30b-a3b.gguf` | text |

### Candidate 6: Inkling-Small is far larger than the sweep says

The sweep lists `Inkling-Small-UD-Q4_K_M` at 15.02 GB. The real tree sizes say
otherwise: the UD-Q4_K_M quant is five shards, about **158 GB** total
(for example shard 2 is 48.8 GB, shard 3 is 49.2 GB, shard 4 is 49.5 GB). Even
the smallest quant in the repo, `UD-IQ1_M`, is about 73 GB. The model is far
above the brys disk budget (about 79 GB free at the time of the run, and about
71 GB free after the eight models above). **Inkling-Small was not downloaded and
not measured.** The sweep size (15.02 GB) is an error. The model is out of range
for brys at any quant that WOULD fit the fit rules.

## Measurements

`ngl 0` for all rows (CPU only). Each throughput number is measured. Vision rows
that show a text value answered an image request; the empty cells are explained
in the notes. The MiniCPM row uses the text-only path, because its projector
does not load.

| model | repo | file | size GB | arch | load_s | decode_tok_s | prefill_tok_s | RssFile/RssAnon/VmRSS MiB | SYS_MB | modality smoke test | load OK? | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ornith-1.5-9B | `ornith-ai/Ornith-1.5-9B-GGUF` | Q4_K_M + mmproj BF16 | 5.38 + 0.86 | `qwen35` | 11.1 | 7.22 | 266.4 | 5393/1677/7070 | 20672 | image OK ("A red circle.") | yes (sessions) | dense 9B; vision works; best size/speed on the 8 GB GPU |
| Ornith-1.5-35B-A3B | `ornith-ai/Ornith-1.5-35B-A3B-GGUF` | Q4_K_M + mmproj BF16 | 20.22 + 0.84 | `qwen35moe` | 34.3 | 8.78 | 167.3 | 20211/1394/21606 | 20882 | image OK ("The image shows a red circle.") | yes (sessions) | MoE ~3B active; vision works |
| MiniCPM-V-4.7-35B-A3B | `openbmb/MiniCPM-V-4.7-35B-A3B-gguf` | Q4_K_M (text path) | 19.71 | `qwen35moe` | 32.3 | 13.89 | 184.7 | 20207/1225/21433 | 20262 | image NOT tested; projector fails to load | yes, text only (sessions) | projector type `minicpmv4_7` unsupported; see below |
| LFM2.5-2.6B | `LiquidAI/LFM2.5-2.6B-GGUF` | Q4_K_M | 1.56 | `lfm2` | 4.1 | 13.65 | 540.1 | 1620/601/2222 | 19039 | n/a (text) | yes (sessions) | tiny; fastest prefill of the set |
| Muse-Glimmer-30B | `unsloth/Muse-Glimmer-30B-GGUF` | UD-Q4_K_XL + mmproj Q8_0 | 14.79 + 1.91 | `muse-glimmer` | 28.3 | 1.88 | 100.5 | 15165/822/15988 | 19956 | image OK ("A red circle", in `reasoning_content`) | yes (sessions) | new arch; thinking model; very slow decode |
| Inkling-Small | `unsloth/Inkling-Small-GGUF` | UD-Q4_K_M | 158 (claimed 15) | — | — | — | — | — | — | — | no | not downloaded; real size ~158 GB |
| Tiel-Coder-35B-A3B-MTP | `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP` | UD-Q4_K_XL + mmproj BF16 | 21.19 + 0.84 | `qwen35moe` | 37.4 | 6.67 | 156.0 | 21350/1269/22620 | 20679 | image OK ("A red circle.") | yes (sessions) | MoE coder with an MTP head (MTP not exercised); vision works |
| Mellum2.1-12B-A2.5B-Thinking | `JetBrains/Mellum2.1-12B-A2.5B-Thinking-GGUF` | Q4_K_M | 7.52 | `mellum` | 13.1 | 14.75 | 411.0 | 7729/641/8370 | 19931 | n/a (text) | yes (sessions) | new arch; fast; small footprint |
| Hy-Memory-30B-A3B | `tencent/Hy-Memory-30B-A3B-GGUF` | Q4_K_M imat | 16.98 | `hy_v3` | 29.3 | 14.30 | 236.6 | 17419/3151/20570 | 22132 | n/a (text) | yes (sessions) | new arch; MoE; fast decode |

Reference CPU values from the same class: `qwen3.8-27b` 2.45 decode / 78
prefill; `north-mini-code-1.0` 18.0 / 178; `lfm2.5-24b-a2b` 24.1 / 280.

## Arch support

| arch | model | sessions build 11539 | master build 11539 |
|---|---|---|---|
| `qwen35` | Ornith-1.5-9B | yes | not tried |
| `qwen35moe` | Ornith-1.5-35B-A3B | yes | not tried |
| `qwen35moe` | MiniCPM-V-4.7-35B-A3B (base) | yes | not tried |
| `qwen35moe` | Tiel-Coder-35B-A3B-MTP | yes | not tried |
| `lfm2` | LFM2.5-2.6B | yes | not tried |
| `muse-glimmer` | Muse-Glimmer-30B | yes | not tried |
| `mellum` | Mellum2.1-12B-A2.5B-Thinking | yes | not tried |
| `hy_v3` | Hy-Memory-30B-A3B | yes | not tried |

### Every base model loaded on the served sessions build

All eight measured base models loaded on the served `sessions` build. No base
architecture needed the master build. The new architectures (`muse-glimmer`,
`mellum`, `hy_v3`) are all implemented by build 11539.

### The MiniCPM-V-4.7 projector is unsupported on both builds

The base model `qwen35moe` loads and answers text (13.89 tok/s decode). The
vision path fails: the projector `mmproj-model-f16.gguf` declares projector type
`minicpmv4_7`, which neither build knows. The exact error on **both** the
sessions and the master build is:

```
clip_init: failed to load model '.../mmproj-minicpm-v-4.7-35b-a3b.gguf':
load_hparams: unknown projector type: minicpmv4_7
```

So MiniCPM-V-4.7 runs text-only on brys. The two builds tried were the only ones
in the store. Vision for this model needs a newer llama.cpp than either build.

### Muse-Glimmer is a thinking model

The Muse-Glimmer-30B reply put its answer in `reasoning_content`, not in
`content`: "Image shows red circle on white background." A 64-token cap for the
image test was fully used by the reasoning, so the `content` field was empty.
The vision test is a pass; the model reasons before it answers.

## Findings

### The MoE models decode far faster than the dense models

- **Mellum2.1-12B-A2.5B-Thinking** is the fastest (14.75 tok/s decode, 411
  tok/s prefill) with the smallest 20B-plus footprint (8.4 GiB VmRSS). It is a
  MoE with about 2.5B active.
- **Hy-Memory-30B-A3B** decodes 14.3 tok/s at 236 tok/s prefill (30B total /
  3B active). Strong general speed for a 17 GB file.
- **LFM2.5-2.6B** is the smallest and has the highest prefill of the set (540
  tok/s) at 13.65 tok/s decode.
- **MiniCPM-V-4.7-35B-A3B** (text path) is the fastest of the 35B-A3B class:
  13.89 tok/s decode.
- **Ornith-1.5-35B-A3B** (8.78), **Tiel-Coder-35B-A3B-MTP** (6.67), and
  **Ornith-1.5-9B** (7.22) sit in the middle.
- **Muse-Glimmer-30B** is the outlier: 1.88 tok/s decode, 100 tok/s prefill.
  Despite the 14.79 GB file it decodes like a dense model. The arch is new and
  the decode path is slow; it is not a good CPU fit.

### Vision works on every VL model except MiniCPM-V-4.7

The Ornith-1.5-9B, Ornith-1.5-35B-A3B, Muse-Glimmer-30B, and
Tiel-Coder-35B-A3B rows each loaded a projector and answered the image request
with a correct red-circle answer. Only MiniCPM-V-4.7 failed, at the projector
load, not the base model.

### Eight models loaded; one model was out of disk range

No base-model load failure occurred. Inkling-Small was not downloaded because its
real size (about 158 GB at UD-Q4_K_M) is far above the sweep figure (15.02 GB)
and above the free disk.

### The swap server was left untouched

The one-off servers ran on port 39799. The `llama-swap` service was not stopped
or restarted. After the measurements, `GET /v1/models` on `127.0.0.1:39700`
still returns 34 ids.

## Ranking: which to register

Ranking by measured speed, fit, size, and role. All eight measured models run on
brys.

1. **Mellum2.1-12B-A2.5B-Thinking** — the best new fit. Fastest decode (14.75
   tok/s), 411 prefill, small footprint (7.52 GB, 8.4 GiB VmRSS), a fresh
   JetBrains code specialist (12B / 2.5B MoE), Apache-2.0. Register first.
2. **Hy-Memory-30B-A3B** — 14.3 tok/s decode, 17 GB, a 30B / 3B MoE with a
   memory-augmented design and Apache-2.0. Strong general model at a good speed.
   Register second.
3. **Ornith-1.5-35B-A3B** — 8.78 tok/s decode, vision works, MIT, 20.22 GB. A
   35B-A3B MoE VLM with the same 262K context as Qwen3.8. Register third for the
   vision + general role.
4. **Ornith-1.5-9B** — 7.22 tok/s decode, vision works, MIT, only 5.38 GB +
   0.86 GB. The best small VLM; fits the 8 GB W6600 at partial offload. Register
   fourth, for the GPU tier.
5. **Tiel-Coder-35B-A3B-MTP** — 6.67 tok/s decode, vision works, MIT, 21.19 GB.
   A second code candidate beside Mellum and North-Mini-Code. Optional.
6. **MiniCPM-V-4.7-35B-A3B** — fast text (13.89 tok/s) but the projector is
   unsupported, so vision fails. The whole point of the model is vision.
   Optional; register only as a text model, or wait for a newer llama.cpp.
7. **LFM2.5-2.6B** — 13.65 tok/s decode, 540 prefill, only 1.56 GB. A tiny,
   fast sibling of the served LFM2.5-24B. Useful for the GPU tier or a fast
   small role. Optional but cheap.
8. **Muse-Glimmer-30B** — new arch works and vision works, but 1.88 tok/s decode
   is a poor CPU fit for a 15 GB file. Optional at best.

### Worth registering

The top three: **Mellum2.1-12B-A2.5B-Thinking** (fast code specialist),
**Hy-Memory-30B-A3B** (fast general MoE), and **Ornith-1.5-35B-A3B** (vision +
general). **Ornith-1.5-9B** is a strong fourth for the GPU tier.

### Failed to load

None of the base models. The MiniCPM-V-4.7 **projector** failed on both the
sessions and the master build (projector type `minicpmv4_7`). Inkling-Small was
not measured (size).

## See also

- [sweep.research.md](sweep.research.md) — the desk sweep that picked these
  candidates.
- [definition.md](definition.md) — this task.
- [../qwen-specialized-measured.research.md](../qwen-specialized-measured.research.md)
  — the same method for the Qwen specialized set.
- [../new-candidates.research.md](../new-candidates.research.md) — the same
  method for the mid-band set.
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) — the
  registration point.
