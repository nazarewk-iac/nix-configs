---
type: Research
description: Desk survey of 2026-generation models in the 10-40B band that could run on host brys (AMD 5950X, 128 GB DDR4, 8 GB W6600); fills the ~9B-27B hole with one table and short notes per model.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T18:48:05+02:00
---

# Mid-band (10-40B) model survey for brys

A desk survey only. No hardware and no builds. This file fills the hole between
about 9B and 27B that the prior survey
([models-2026-mid-large.research.md](../brys-grunt-colocation/models-2026-mid-large.research.md))
left open. Every candidate is 2026-generation, except where marked.

Target host `brys`: AMD Ryzen 5950X (AVX2, no AVX512), 128 GB DDR4, one 8 GB AMD
W6600 GPU, about 350 GB free disk. CPU-first. A model that fits the 8 GB card
(<= ~6 GB of weights) can use the GPU. A larger model runs on the CPU and is
memory-bandwidth bound. Predicted CPU decode = 40 GB/s / active-GB-per-token.

**Evidence:** `[V]` verified against the Hugging Face API (createdAt, config,
model card, GGUF blob sizes) at 2026-10-20; `[I]` inferred (param math, naming).
Sizes are the actual GGUF file size read from the blob list.

## Master table

| model | HF repo | released | params tot/act | arch / attention | license | GGUF | Q4 file | ctx | modalities | tool-call | fit verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Qwen3.8-27B | `Qwen/Qwen3.8-27B` | 2026-08-14 | 27B dense | dense, hybrid Gated DeltaNet + Gated Attention | Apache-2.0 | unsloth `[V]` | 16.46 GB (UD-Q4_K_M) | 262K native, 1M YaRN | text + vision + video | strong `[I]` | fits CPU (~2.4 t/s pred) |
| Qwen3.6-27B | `Qwen/Qwen3.6-27B` | 2026-04-21 | 27B dense | dense, hybrid linear attn | Apache-2.0 | unsloth `[V]` | 16.4 GB (UD-Q4_K_M) | 262K | text + vision | strong `[I]` | fits CPU |
| Qwen3.6-35B-A3B | `Qwen/Qwen3.6-35B-A3B` | 2026-04-15 | 35B / ~3B | MoE, qwen3_5_moe | Apache-2.0 | unsloth `[V]` | 22.13 GB (UD-Q4_K_M) | 262K | text + vision | strong `[I]` | fits CPU (~13 t/s) |
| Gemma-4-12B-it | `google/gemma-4-12B-it` | 2026-07-20 | 12B dense | dense, gemma4_unified | Apache-2.0 | unsloth + Google QAT `[V]` | 7.12 GB (Q4_K_M) | 128K `[I]` | text + vision + audio | good `[I]` | fits CPU; too big for 8 GB GPU |
| Gemma-4-26B-A4B-it | `google/gemma-4-26B-A4B-it` | 2026-07-20 | 26B / 4B | MoE, gemma4_unified | Apache-2.0 | Google QAT + unsloth `[V]` | ~16 GB `[I]` | 128K `[I]` | text + vision + audio | good `[I]` | fits CPU (~9 t/s pred) |
| Gemma-4-31B-it | `google/gemma-4-31B-it` | 2026-07-20 | 31B dense | dense, gemma4 | Apache-2.0 | unsloth + Google QAT `[V]` | 18.32 GB (Q4_K_M) | 128K `[I]` | text + vision + audio | good `[I]` | fits CPU (~2.2 t/s) |
| Granite-4.2-30B | `ibm-granite/granite-4.2-30b` | 2026-09-04 | 30B dense | dense | Apache-2.0 | official `[V]` | 17.72 GB (Q4_K_M) | 128K `[I]` | text | good `[I]` | fits CPU (~2.4 t/s) |
| Granite-Switch-4.1-30B | `ibm-granite/granite-switch-4.1-30b` | 2026-10-15 | 30B dense | dense + router | Apache-2.0 | community `[I]` | ~18 GB `[I]` | 128K `[I]` | text | good `[I]` | fits CPU |
| Olmo-3.1-32B-Think | `allenai/Olmo-3.1-32B-Think` | 2026-10-13 | 32B dense | dense | Apache-2.0 | unsloth + bartowski `[V]` | 19.48 GB (Q4_K_M) | 64K `[I]` | text | weak `[I]` | fits CPU (~2.0 t/s) |
| GLM-4.7-Flash | `zai-org/GLM-4.7-Flash` | 2026-01-29 | 30B / 3B | MoE, glm4_moe_lite | MIT | community `[V]` | 17.0 GB, measured | 128K `[I]` | text | strong `[V]` | fits CPU (16 t/s measured) |
| GLM-4.1V-9B-Thinking | `zai-org/GLM-4.1V-9B-Thinking` | 2026-07-22 | 9B dense | dense, glm4v | MIT | community `[I]` | ~5.8 GB `[I]` | 64K `[I]` | text + vision | modest `[I]` | fits GPU (Q4 <= 6 GB) |
| Mistral-Small-4-119B | `mistralai/Mistral-Small-4-119B-2603` | 2026-07-15 | 119B `[I]` | MoE `[I]` | Mistral Research | unsloth `[V]` | ~66 GB `[I]` | 256K `[I]` | text | strong `[I]` | too big for fast CPU |
| Ministral-3-14B | `mistralai/Ministral-3-14B-Instruct-2512` | 2025-12 (pre-2026) | 14B dense | dense + vision | Apache-2.0 | community `[I]` | ~8 GB `[I]` | 256K `[I]` | text + vision | good `[I]` | fits CPU; noted, pre-2026 |
| LFM2.5-24B-A2B | `LiquidAI/LFM2.5-24B-A2B` | 2026-10-13 | 24B / 2B | MoE, lfm2_moe | LFM Open `[I]` | LiquidAI + unsloth `[V]` | 14.53 GB (Q4_K_M) | 32K `[I]` | text | modest `[I]` | fits CPU (~17 t/s pred) |
| Nemotron-3-Nano-30B-A3B | `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-BF16` | 2026-08-24 | 30B / 3B | hybrid Mamba (nemotron_h) | OpenMDW `[I]` | unsloth `[V]` | 24.57 GB (Q4_K_M) | 128K `[I]` | text | good `[I]` | fits CPU (~13 t/s pred) |
| Nemotron-3-Nano-Omni-30B-A3B | `nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning` | 2026-10 `[I]` | 30B / 3B | hybrid Mamba, omni | OpenMDW `[I]` | unsloth `[V]` | ~20 GB `[I]` | 128K `[I]` | text + vision + audio | good `[I]` | fits CPU |
| Ling-3.0-tiny | `inclusionAI/Ling-3.0-tiny` | 2026-09-24 | ~8B dense | dense, bailing_hybrid | MIT | community `[I]` | ~4.5 GB `[I]` | 128K `[I]` | text | modest `[I]` | fits GPU (Q4 <= 6 GB) |
| ERNIE-4.5-21B-A3B-Thinking | `baidu/ERNIE-4.5-21B-A3B-Thinking` | 2025-11 (pre-2026) | 21B / 3B | MoE, ernie4_5_moe | Apache-2.0 | community `[I]` | ~13 GB `[I]` | 128K `[I]` | text | good `[I]` | fits CPU; noted, pre-2026 |

## Notes per model

### Qwen3.8-27B (primary candidate)

The current Qwen open flagship in the mid band. Dense 27B, native
vision-language model, 64 layers. The text stack is a hybrid: 16 blocks of
3 x (Gated DeltaNet -> FFN) then 1 x (Gated Attention -> FFN). This mix keeps
the KV cache small, so long context is cheap. Native context 262,144 tokens,
extensible to 1,000,000 with YaRN. Thinking is on by default with
`reasoning_effort` (xhigh, medium, low) and `preserve_thinking`. Apache-2.0.
Unsloth publishes a full GGUF set; `UD-Q4_K_M` is 16.46 GB, `Q4_0` is 16.06 GB,
and a separate `mmproj` file (0.93 GB) enables the vision tower in llama.cpp.
Strong agent and coding scores (Terminal Bench 2.1 73.0, SWE-bench Pro 61.7).
Fit: fits CPU. Predicted decode about 2.4 t/s (dense, reads all 16.5 GB per
token). The GPU cannot hold it; keep it at `-ngl 0`.

### Qwen3.6 family

Qwen3.6 (April 2026) is the prior tier. `Qwen3.6-27B` is dense, 262K context,
text + vision, Apache-2.0. `Qwen3.6-35B-A3B` is a MoE (35B total, about 3B
active) with the same 262K context; Q4 is 22.13 GB and it decodes about 13 t/s
on the CPU. On the 2026 benchmarks Qwen3.8-27B beats Qwen3.6-27B clearly (for
example SWE-bench Pro 61.7 vs 53.5). This makes Qwen3.6-27B redundant if
Qwen3.8-27B fits.

### Qwen3.7 does not exist as an open release

A search of Hugging Face returns no `Qwen/Qwen3.7-*` weights. Only a hosted
`Qwen3.7-Plus` appears in the Qwen3.8-27B benchmark table, behind the Qwen
Cloud API. No open repo to survey.

### Gemma-4 mid sizes (July 2026)

Three mid sizes: `gemma-4-12B-it` (dense), `gemma-4-26B-A4B-it` (MoE, 26B total
with about 4B active), and `gemma-4-31B-it` (dense). All are Apache-2.0 and
multimodal. There is no Gemma-4-27B. The 12B and 31B use the `gemma4` and
`gemma4_unified` architectures; the 26B-A4B was already in the prior survey.
Google ships QAT checkpoints (`-qat-q4_0-gguf`); the 31B QAT file is about
17.3 GB. Unsloth also publishes `gemma-4-12b-it-GGUF` (Q4_K_M 7.12 GB) and
`gemma-4-31B-it-GGUF` (Q4_K_M 18.32 GB). Fit: the 12B fits the CPU and is
marginally too big for the 8 GB card; the 26B-A4B is the fastest of the three on
the CPU (MoE, about 9 t/s predicted); the 31B is dense (about 2.2 t/s).

### Mistral family

`Mistral-Small-4-119B-2603` is the only new mid/large Mistral; it is 119B and
too big for fast CPU serving (about 66 GB at Q4). `Ministral-3-14B`, `-8B`,
`-3B` and `Devstral-Small-2-24B` carry `2512` dates, so they are pre-2026 and
outside the scope; `Ministral-3-14B` is listed only as the closest mid-band
Mistral. The oldest 2026 Mistral items are small (Shieldstral-1.0-3B,
Leanstral, Timestral), none in the 10-40B band. There is no `Mistral-Small-4`
below 119B.

### GLM

GLM-5, GLM-5.1, GLM-5.2, GLM-5.3, and GLM-5.3-Flash are all 300B or larger;
none fit brys. The only GLM model in the band is `GLM-4.7-Flash` (30B / 3B,
MIT), already measured at 16 t/s on the CPU. `GLM-4.1V-9B-Thinking` is a 9B
vision model (MIT) that fits the GPU at Q4.

### OLMo-3.1

`allenai/Olmo-3.1-32B-Think` (October 2026) is dense 32B, Apache-2.0, fully
open data. Also `Olmo-3.1-32B-Instruct`. GGUF from unsloth, bartowski, and
lmstudio-community; `Q4_K_M` is 19.48 GB. Tool-calling is weak; this is a
research or reasoning model, not an agent model.

### IBM Granite 4.2

`granite-4.2-30b` is dense 30B, Apache-2.0, with an official GGUF
(`Q4_K_M` 17.72 GB). `granite-switch-4.1-30b` (October 2026) adds a router on
top of the same size class. The 8B and 3B siblings are GPU-or-CPU fits. Good
tool-calling.

### Other strong 2026 10-40B candidates

- **LFM2.5-24B-A2B** (LiquidAI, October 2026): MoE, 24B total with about 2B
  active. Q4_K_M is 14.53 GB. Fast on the CPU (about 17 t/s predicted). LFM Open
  license. Modest tool-calling.
- **Nemotron-3-Nano-30B-A3B** (NVIDIA, August 2026): 30B total with about 3B
  active, hybrid Mamba-Transformer. Q4_K_M is 24.57 GB. OpenMDW license.
  About 13 t/s predicted. The `Omni` variant adds vision and audio.
- **Ling-3.0-tiny** (Ant Group / inclusionAI, September 2026): about 8B dense,
  MIT, hybrid. Fits the GPU at Q4 (about 4.5 GB).
- **ERNIE-4.5-21B-A3B-Thinking** (Baidu): MoE 21B / 3B, Apache-2.0, but dated
  2025-11, so pre-2026. Noted for completeness.
- **RedNote dots.llm1**: only about 1.5B total; below the band, excluded.
- **Moonshot Kimi-K3 / Kimi-K2.7-Code**: 2.7T+ parameters; far too big.
- **Agentica**: no model repo of this size found. **MiniMax**: only audio and
  enormous MoE. **DeepSeek V4 / V4.1**: all 100B+ MoE. **Phi**: no Phi-5;
  Microsoft only published `Phi-4-reasoning-vision-15B` (prior survey).

## Ranked shortlist for brys (mid band)

1. **Qwen3.8-27B** — native VL, 262K-1M context, strong agent and code; unsloth
   Q4_K_M 16.46 GB. Fits CPU at about 2.4 t/s. The single best quality-per-GB
   dense pick, and the task's priority candidate.
2. **Qwen3.6-35B-A3B** — MoE, about 13 t/s CPU, Q4 22.13 GB, Apache-2.0. Best
   speed/quality if a lower quality than Qwen3.8 is acceptable.
3. **LFM2.5-24B-A2B** — MoE, about 17 t/s CPU (fastest in band), Q4 14.53 GB.
   New this month.
4. **Nemotron-3-Nano-30B-A3B** — hybrid Mamba, about 13 t/s CPU, Q4 24.57 GB;
   Omni variant adds vision and audio.
5. **Gemma-4-26B-A4B-it** — MoE, about 9 t/s CPU, multimodal; the fastest
   Gemma-4 mid size.
6. **Gemma-4-12B-it** — dense 12B, Q4 7.12 GB; GPU-marginal, CPU fits.
7. **Granite-4.2-30B** — dense 30B, official GGUF, good tool-calling; slow
   (about 2.4 t/s).
8. **Olmo-3.1-32B-Think** — open 32B, reasoning; weak tool-calling.

## Ready GGUFs (repo + file)

- Qwen3.8-27B: `unsloth/Qwen3.8-27B-GGUF` -> `Qwen3.8-27B-UD-Q4_K_M.gguf`
  (16.46 GB) plus `mmproj-F16.gguf` for vision.
- Qwen3.6-35B-A3B: `unsloth/Qwen3.6-35B-A3B-GGUF` ->
  `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` (22.13 GB).
- Qwen3.6-27B: `ggml-org/Qwen3.6-27B-GGUF` and `unsloth/Qwen3.6-27B-MTP-GGUF`.
- Gemma-4-31B-it: `unsloth/gemma-4-31B-it-GGUF` ->
  `gemma-4-31B-it-Q4_K_M.gguf` (18.32 GB); also
  `google/gemma-4-31B-it-qat-q4_0-gguf`.
- Gemma-4-12B-it: `unsloth/gemma-4-12b-it-GGUF` ->
  `gemma-4-12b-it-Q4_K_M.gguf` (7.12 GB); also
  `google/gemma-4-12B-it-qat-q4_0-gguf`.
- Granite-4.2-30B: `ibm-granite/granite-4.2-30b-GGUF` ->
  `granite-4.2-30b-Q4_K_M.gguf` (17.72 GB).
- Olmo-3.1-32B-Think: `unsloth/Olmo-3.1-32B-Think-GGUF` ->
  `Olmo-3.1-32B-Think-Q4_K_M.gguf` (19.48 GB).
- LFM2.5-24B-A2B: `LiquidAI/LFM2.5-24B-A2B-GGUF` ->
  `LFM2.5-24B-A2B-Q4_K_M.gguf` (14.53 GB); also `unsloth/LFM2.5-24B-A2B-GGUF`.
- Nemotron-3-Nano-30B-A3B: `unsloth/Nemotron-3-Nano-30B-A3B-GGUF` ->
  `Nemotron-3-Nano-30B-A3B-Q4_K_M.gguf` (24.57 GB).

## See also

- [models-2026-mid-large.research.md](../brys-grunt-colocation/models-2026-mid-large.research.md)
  — the prior survey (27B and larger), with measured brys numbers.
- [models-2026.research.md](../brys-grunt-colocation/models-2026.research.md)
  — the small GPU grunt shortlist.
- [definition.md](definition.md) — this task.
