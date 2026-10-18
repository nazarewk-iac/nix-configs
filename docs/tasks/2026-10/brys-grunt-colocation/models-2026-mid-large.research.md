---
type: Research
description: Survey of 2026-era mid/large models (Qwen3.6 27B/35B-A3B, GLM 5.x, Gemma 4 31B, Mistral 2026, Nemotron, Granite, Tmax, MiMo, Seed) beyond the small GPU grunt shortlist, with placement and predicted CPU decode.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T12:00:00+02:00
---

# 2026 mid/large models — beyond the small GPU grunt

A follow-up to [models-2026.research.md](models-2026.research.md), which covered
only small GPU-fit grunts (Qwen3.5-0.8B/2B/4B/9B, GLM-4.7-Flash, Gemma-4-E4B/12B/26B-A4B,
Nemotron-3.5-Lightning-30B-A3B, Qwen3.5-35B-A3B). This file adds the 27B-32B and
larger classes and the other families (GLM, Gemma, Mistral, Nemotron, Granite,
Tmax, MiMo, Seed, Phi, InternLM, Jamba). Released 2026-01-01 or later, unless
marked.

**Placement rule for brys:** an 8 GB GPU fits Q4 weights <= ~6 GB. A larger model
runs on the CPU (memory-bandwidth bound). Predicted CPU decode = 40 GB/s /
activated-GB-per-token: a dense model reads its whole weight file per token; a
MoE model reads only its active experts.

**Evidence:** `[V]` verified against the HF API (createdAt/config/README/blob
sizes) at 2026-10-18; `[I]` inferred (param math, naming). Q4 sizes marked `[V]`
were read from the GGUF blob list; others scaled from bf16 bytes / 3.3.

## Master table

| model | HF repo | GGUF | released | params tot/act | Q4 size | placement | license | tool-calling |
|---|---|---|---|---|---|---|---|---|
| Qwen3.6-27B | `Qwen/Qwen3.6-27B` | unsloth `[V]` | 2026-04-21 | 27B dense | ~16.8 GB | CPU | Apache-2.0 | strong `[I]` |
| Qwen3.6-35B-A3B | `Qwen/Qwen3.6-35B-A3B` | unsloth `[V]` | 2026-04-15 | 35B / ~3B | ~22 GB | CPU (~13 t/s) | Apache-2.0 | strong `[I]` |
| Qwen3.5-27B | `Qwen/Qwen3.5-27B` | unsloth `[I]` | 2026-02-24 | 27B dense | ~16.8 GB | CPU | Apache-2.0 | strong `[I]` |
| Qwen3.5-122B-A10B | `Qwen/Qwen3.5-122B-A10B` | unsloth `[I]` | 2026-02-24 | 122B / 10B | ~68 GB | CPU (~4 t/s) | Apache-2.0 | strong `[I]` |
| Qwen3.5-397B-A17B | `Qwen/Qwen3.5-397B-A17B` | yes `[I]` | 2026-02-16 | 397B / 17B | ~215 GB | too big | Apache-2.0 | strong `[I]` |
| GLM-4.7-Flash | `zai-org/GLM-4.7-Flash` | community `[V]` | 2026-01-19 | 30B / 3B | ~18 GB | CPU (~13 t/s) | MIT | strong `[I]` |
| GLM-5.3-Flash | `zai-org/GLM-5.3-Flash` | community `[V]` | 2026-08-25 | 320B / 18B | ~180 GB | too big | MIT | excellent `[V]` |
| GLM-5.2 / GLM-5.3 | `zai-org/GLM-5.2`,`-5.3` | community | 2026-06/-08 | ~355B / ~30B; ~560B | ~200-300 GB | too big | custom | strong |
| Gemma-4-31B-it | `google/gemma-4-31B-it` | Google QAT + unsloth `[V]` | 2026-06 | 31B dense | ~18.3 GB | CPU | Apache-2.0 | good `[I]` |
| Mistral-Small-4-119B | `mistralai/Mistral-Small-4-119B-2603` | likely `[I]` | 2026-01-23 | 119B | ~66 GB | CPU, slow | Mistral Research | strong `[I]` |
| DeepSeek-V4-Flash | `deepseek-ai/DeepSeek-V4-Flash-0731` | gguf `[V]` | 2026-07-31 | ~180B MoE | ~100 GB | borderline | custom | strong `[I]` |
| DeepSeek-V4.1-Flash | `deepseek-ai/DeepSeek-V4.1-Flash-1017` | community `[V]` | 2026-10-17 | ~256B MoE | ~140 GB | too big | custom | strong `[I]` |
| Phi-4-reasoning-vision-15B | `microsoft/Phi-4-reasoning-vision-15B` | gguf `[I]` | 2026-01-23 | 15B | ~9 GB | CPU (~4.5 t/s) | MIT `[I]` | good `[I]` |
| Granite-4.2-30B | `ibm-granite/granite-4.2-30b` | official `[V]` | 2026-08 | 30B dense | ~17.7 GB | CPU | Apache-2.0 | good `[I]` |
| Granite-4.2-8B / 3B | `ibm-granite/granite-4.2-{8b,3b}` | official `[V]` | 2026-08 | 8B / 3B | 5 / 2 GB | GPU (3B) | Apache-2.0 | good `[I]` |
| Granite-Switch-4.1-30B | `ibm-granite/granite-switch-4.1-30b` | — | 2026-10-14 | 30B | ~18 GB | CPU | Apache-2.0 | good `[I]` |
| Tmax-27B | `allenai/tmax-27b` | pending `[V]` | 2026-06-21 | 27B dense | ~16.8 GB | CPU | Apache-2.0 | agent SOTA `[V]` |
| Tmax-9B / 8B / 2B | `allenai/tmax-{9b,8b,2b}` | mradermacher `[V]` | 2026-06-17 | 9/8/2B | 5/4.5/1.2 GB | GPU/CPU | Apache-2.0 | agent `[V]` |
| Nemotron-3.5-Bolt-74B-A9B | `nvidia/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB` | official `[V]` | 2026-10-07 | 74B / 9B | ~44 GB | CPU (~4.4 t/s) | OpenMDW-1.1 | tool-choice `[V]` |
| Nemotron-3.5-Super-VL-120B-A12B | `nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B` | gguf `[V]` | 2026-10-12 | 120B / 12B | ~72 GB | CPU (~3.3 t/s) | OpenMDW-1.1 | strong `[I]` |
| Nemotron-Dory-1.0-4B | `nvidia/NVIDIA-Nemotron-Labs-Dory1.0-4B` | official `[V]` | 2026-10-16 | 4B | ~2.5 GB | GPU | OpenMDW | modest `[I]` |
| MiMo-V2.6-Distill-Qwen-9B | `XiaomiMiMo/MiMo-V2.6-Distill-Qwen-9B` | bartowski `[V]` | 2026-09-21 | 9B dense | ~5.8 GB | GPU | Apache-2.0 `[I]` | good `[I]` |
| MiMo-V2.6-Pro-RL | `XiaomiMiMo/MiMo-V2.6-Pro-RL` | community `[V]` | 2026-09-21 | ~575B | ~300 GB | too big | Apache-2.0 `[I]` | strong `[I]` |
| Seed-OSS-36B | `ByteDance-Seed/Seed-OSS-36B-Instruct` | unsloth `[V]` | 2026 rehost | 36B dense | ~21.8 GB | CPU (~1.8 t/s) | Apache-2.0 | good `[I]` |
| Intern-Decision 0.8/2/4B | `internlm/Intern-Decision-*` | few `[I]` | 2026-09-26 | 0.8/2/4B | 0.5/1.4/2.8 GB | GPU | Apache-2.0 `[I]` | weak `[I]` |
| Jamba-2-3B | `llmware/jamba-2-3b-gguf` | yes `[V]` | 2026-09 | 3B | ~2 GB | GPU | Apache-2.0 `[I]` | weak `[I]` |
| OLMo-3.1-32B | `allenai/Olmo-3.1-32B` | community `[V]` | 2026 | 32B | ~18 GB | CPU | Apache-2.0 | weak `[I]` |

## Family notes

- **Qwen 2026.** The Qwen3.5 line (Feb 2026) spans 0.8B-397B. Qwen3.6 (Apr 2026) is
  the new tier: **27B dense** and **35B-A3B MoE**, Apache-2.0, mature unsloth
  GGUF. Qwen4 exists only as scattered NVFP4 experiments, no general release.
- **GLM.** After GLM-4.7-Flash (Jan 2026), GLM-5 -> 5.3 are all enormous
  (320B-560B); none fit 128 GB at a usable quant. GLM leads on tool-calling.
- **Gemma 4.** Only materially larger new model is **Gemma-4-31B-it** (dense,
  multimodal, Google QAT q4_0 GGUF). 26B-A4B got a QAT refresh.
- **Mistral 2026.** New are Mistral-Small-4-119B-2603 and Mistral-Large-3-675B
  (both enormous). Ministral-3 / Devstral-Small-2 / Magistral-Small carry
  `2512`/`2509` dates -> **pre-2026, excluded**.
- **DeepSeek.** V4-Pro / V4-Flash / V4.1-Flash are all 100B+ MoE. No small 2026
  distill.
- **Microsoft.** No Phi-5. Only Phi-4-reasoning-vision-15B (MIT).
- **IBM Granite 4.2.** A genuine Apache-2.0 refresh (3B/8B/30B, official GGUF +
  MLX). 30B dense is CPU-resident. Granite-Switch-4.1 (Oct) is a router variant.
- **AllenAI.** Tmax (Jun 2026) is the standout: Tmax-27B = Qwen3.6-27B + DPPO for
  terminal agents (43% Terminal-Bench 2.0), Apache-2.0. No GGUF for the 27B yet.
- **Nvidia Nemotron 3.5.** Efficient hybrid-Mamba line: Bolt-74B-A9B (official
  24GB GGUF, auto-tool-choice), Super-VL-120B-A12B, tiny Dory-1.0-4B.
- **Xiaomi MiMo V2.6.** Flagship Pro-RL (~575B, too big) plus a useful
  **Distill-Qwen-9B** (dense, Q4 ~5.8 GB, GPU-fit).
- **ByteDance Seed-OSS-36B.** Dense 36B, Apache-2.0, 512K ctx.
- **Yi, Cohere, AI21.** No 2026 base release worth listing (Yi quiet; Cohere
  latest base is Aya-expanse 2024; AI21 only a tiny Jamba-2-3B).

## Ranked shortlist (new mid-size candidates on this box)

1. **Qwen3.6-35B-A3B** — 2026 MoE, ~3B active -> ~13 t/s CPU, Q4 ~22 GB,
   Apache-2.0. Best speed/quality.
2. **AllenAI Tmax-27B** — dense but terminal/coder-agent SOTA; Apache-2.0.
3. **Qwen3.6-27B** — newest dense Qwen, 262K ctx, unsloth Q4 ~16.8 GB.
4. **Nemotron-3.5-Bolt-74B-A9B** — 74B/9B hybrid Mamba, ~4.4 t/s CPU, official
   24GB GGUF + tool-choice.
5. **Gemma-4-31B-it** — only materially larger 2026 Gemma, dense multimodal.
6. **MiMo-V2.6-Distill-Qwen-9B** — Q4 ~5.8 GB, fits the 8 GB GPU.
7. **Granite-4.2-30B** — Apache-2.0 dense 30B, official GGUF.
8. **Seed-OSS-36B-Instruct** — dense 36B, Apache-2.0, 512K ctx.

## Excluded (pre-2026)

Ministral-3-3B-8B-14B (`2512`), Devstral-Small-2-24B (`2512`),
Magistral-Small-2509, Mistral-Large-3 (`2512`), OLMo-3-7B, gpt-oss, SmolLM3,
Seed-OSS-36B as `2508`, Phi-4 family.

## Measured on brys (llama-bench, 2026-10-18)

Q4_K_M, `-p 512 -n 128 -r 2 -t 16`. CPU column is `-ngl 0`; the W6600 column is
`-ngl 99 --device Vulkan0` (partial offload; the model exceeds the 8 GB card).
Units: tokens/second.

| model | weights | CPU pp512 | CPU tg128 | W6600 pp512 | W6600 tg128 |
|---|---|---|---|---|---|
| GLM-4.7-Flash 30B-A3B | 17.05 GiB | 182.6 | **16.02** | 98.3 | 10.00 |
| Qwen3.5-35B-A3B | 20.49 GiB | 168.0 | **10.85** | 89.5 | 7.49 |
| Granite-4.2-30B (dense) | 16.50 GiB | 98.1 | **2.50** | 39.7 | 1.40 |

Two findings:

1. **MoE decodes several times faster than dense at similar weight size.** GLM
   30B-A3B (16 t/s) and Qwen3.5-35B-A3B (10.9 t/s) both beat the dense
   Granite-4.2-30B (2.5 t/s), because a MoE reads only its ~3B active experts per
   token while a dense model reads the whole 16.5 GiB. This matches the
   bandwidth-ceiling arithmetic (40 / active-GB): GLM 40/2.7 ~ 15, Granite
   40/16.5 ~ 2.4.
2. **GPU offload of an oversized model is slower than pure CPU.** Copying an
   8 GB slice to/from the W6600 every token costs more than the CPU saves, so
   every >8 GB row is faster at `-ngl 0`. Models above the card belong on the CPU;
   only a <= ~6 GB model gains from the GPU (see models-2026.research.md).

For comparison on the same box, the small GPU-fit grunts decode at 62-125 t/s on
the W6600 (Qwen3.5-4B 62, Qwen3.5-2B 125). So the shape is: a small model on the
GPU for speed, and a MoE like GLM-4.7-Flash on the CPU for medium-quality work.

## See also

- [models-2026.research.md](models-2026.research.md) — the small GPU grunt shortlist (measured W6600 numbers).