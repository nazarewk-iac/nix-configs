---
type: Research
description: Desk survey of 2026-generation SPECIALIZED open models (code, vision, reasoning, embedding/rerank, speech) that could run on host brys (AMD 5950X, 128 GB DDR4, 8 GB W6600, CPU-first). No hardware and no builds.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T18:55:00+02:00
---

# Specialized model survey for brys

A desk survey only. No hardware and no builds. This file covers the specialized
classes that the mid-band survey
([mid-band-survey.research.md](mid-band-survey.research.md)) does not. Every
candidate is 2026-generation, except where the text says otherwise.

Target host `brys`: AMD Ryzen 5950X (AVX2, no AVX512), 128 GB DDR4, one 8 GB AMD
W6600 GPU, about 350 GB free disk. CPU-first. A model that fits the 8 GB card
(<= ~6 GB of weights) can use the GPU. A larger model runs on the CPU and is
memory-bandwidth bound. A specialized model that only fits a large GPU is
reported as **no fit**.

**Evidence:** `[V]` verified against the Hugging Face API (createdAt, config,
model card, GGUF blob sizes) at 2026-10-20; `[I]` inferred. File sizes are the
actual GGUF blob size read from the blob list.

## Summary by class

| class | best brys fit | GGUF | verdict |
|---|---|---|---|
| code | `CohereLabs/North-Mini-Code-1.0` (30B MoE, ~3B active) | community `[V]` | fits CPU; best all-round code specialist |
| code (alt) | `Qwen/Qwen3-Coder-Next` (80B / 3B, 512 experts) | official `[V]` | fits CPU but 48 GB Q4, slow to load |
| vision | `Qwen/Qwen3-VL-8B-Instruct` or `-4B` | official `[V]` | 8B fits GPU (Q4 5.03 GB); 4B is a clean GPU fit |
| reasoning | no dedicated 2026 open fit | — | no fit; use the general fleet's thinking mode |
| embedding | `Qwen/Qwen3-Embedding-4B` (2560-d) | official `[V]` | fits CPU easily |
| reranker | `Qwen/Qwen3-Reranker-4B` | community `[V]` | fits CPU easily |
| speech | `Qwen/Qwen3-ASR-0.6B` (ASR) | community `[I]` | optional, tiny |

## 1. Code-specialized

### `CohereLabs/North-Mini-Code-1.0` — best code fit `[V]`

- HF repo: `CohereLabs/North-Mini-Code-1.0` (also `-w4a16`, `-fp8`, `-eagle`).
- Released: 2026-06-05. Params: 30.5B total, MoE (`Cohere2MoeForCausalLM`, 128
  experts, 49 layers, hidden 2048), about 3B active `[I]`.
- License: Apache-2.0.
- Context: 500,000 tokens (`max_position_embeddings`) `[V]`.
- Specialization: coding, agentic editing, tool use. A 2026 Cohere code model.
- GGUF: community. `NANI-Nithin/north-mini-code-gguf` -> `North-Mini-Code-1.0-Q4_K_M.gguf`
  (18.59 GB) `[V]`; also `Fr4nkSt3in/North-Mini-Code-1.0-BF16-GGUF` (61 GB).
- Fit: **fits CPU**. MoE with about 3B active, so decode is fast for a 30B model
  (predicted about 13 t/s at Q4, by the 40 GB/s / active-GB rule). The 18.6 GB
  file does not fit the 8 GB GPU. This is the single best code specialist for
  brys: Apache-2.0, tool use, and a MoE that decodes fast on the CPU.

### `Qwen/Qwen3-Coder-Next` — strongest, but heavy `[V]`

- HF repo: `Qwen/Qwen3-Coder-Next` (Base, FP8, GGUF variants exist).
- Released: 2026-01-30. Params: 80B total, MoE (`Qwen3NextForCausalLM`, 512
  experts, 10 active per token, 48 layers, hidden 2048), about 3B active.
- License: Apache-2.0. Context: 262,144 native.
- Specialization: agentic coding, the flagship open code model of early 2026.
- GGUF: official `Qwen/Qwen3-Coder-Next-GGUF` and `unsloth/Qwen3-Coder-Next-GGUF`.
  `Q4_K_M` is 48.53 GB; `UD-Q3_K_M` is 35.94 GB; `UD-IQ2_M` is 24.96 GB `[V]`.
- Fit: **fits CPU only at a low quant**. At `Q4_K_M` (48.5 GB) it is a slow load
  and about 13 t/s decode (MoE, about 3B active). The 8 GB GPU is far too small.
  `UD-IQ2_M` (25 GB) is the practical brys choice, at a quality cost. Use
  North-Mini-Code for a better size/quality/speed balance.

### `whitecircle/GLM-4.7-Flash-Coder` — GLM coder, community `[V]`

- HF repo: `whitecircle/GLM-4.7-Flash-Coder` (fine-tune of `zai-org/GLM-4.7-Flash`).
- Released: 2026-07-02. Params: about 30B total, MoE (`glm4_moe_lite`), about 3B
  active. License: MIT.
- GGUF: community. `ngquocvinh/GLM-4.7-Flash-Coder-GGUF` -> `GLM-4.7-Flash-Coder-Q4_K_M.gguf`
  (18.13 GB) `[V]`; `Q3_K_M` is 14.41 GB.
- Fit: **fits CPU** (about 13 t/s predicted). Note: there is no official
  Z.ai "GLM-4.7-Coder"; this is a community fine-tune of the official
  GLM-4.7-Flash. Use it only if the North-Mini-Code quality is not enough and a
  GLM tool-use style is wanted.

### DeepSeek coder — no 2026 open fit `[V]`

The 2026 DeepSeek line is `DeepSeek-V4-Flash` (291B) and `DeepSeek-V4.1-Flash`
(763B), both far too large for brys. `DeepSeek-Coder-V2-Lite-Instruct` (16B MoE)
is the last small DeepSeek coder, but it is dated 2024-07, so pre-2026. There is
no `DeepSeek-Coder-V4`. Verdict: **no fit** in this class; use another coder.

### Mistral Devstral `[V]`

`mistralai/Devstral-Small-2-24B-Instruct-2512` (released 2025-11-28, Apache-2.0)
is the current Devstral. It is a dense 24B agentic code model. GGUF:
`unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF` -> `Q4_K_M` is 14.33 GB `[V]`.
Fit: **fits CPU** (about 2.6 t/s, dense). It is pre-2026 (dated `2512`), so it is
noted only as an alternative. Codestral is a hosted API model with no open
weights in the band. There is no `Mistral-Coder-3` in this size.

### Other strong open code models `[V]`

- Moonshot: `Kimi-K2.7-Code` (2026-06-11) and `Kimi-K3` (2026-06-13) are 1T+
  MoE. **No fit.**
- `Qwen3-Coder-30B-A3B-Instruct` (the prior generation, 2025-07-31) is
  superseded by North-Mini-Code and Qwen3-Coder-Next. **Noted, pre-2026.**
- RedNote, Cohere `command-a`: no small open code model in the band.

## 2. Vision / multimodal

### `Qwen/Qwen3-VL-8B-Instruct` / `-4B` — best small VLM `[V]`

- Repos: `Qwen/Qwen3-VL-8B-Instruct`, `Qwen/Qwen3-VL-4B-Instruct`, and `-Thinking`
  variants. Released 2025-10-11 (image-text-to-text).
- Params: 8B and 4B dense. License: Apache-2.0. Context: 256K `[I]`.
- GGUF: official. `Qwen3VL-8B-Instruct-Q4_K_M.gguf` is 5.03 GB plus
  `mmproj-Qwen3VL-8B-Instruct-F16.gguf` (1.16 GB) `[V]`. The 4B file is
  `Qwen3VL-4B-Instruct-Q4_K_M.gguf` (2.50 GB) plus mmproj (0.84 GB) `[V]`.
- Fit: **8B fits the GPU** at Q4 (5.03 GB weights + 1.16 GB mmproj is slightly
  over the 6 GB soft limit, so use `-ngl` to offload most layers). The 4B is a
  clean GPU fit. Both run on the CPU if needed. Note: `Qwen3-VL-30B-A3B` also
  exists (Q4_K_M 18.56 GB, MoE) and **fits CPU** for higher-quality vision.

### `Qwen/Qwen3.8-27B` — already covered `[V]`

Native vision-language, 27B dense, 262K-1M context, Apache-2.0. Unsloth Q4_K_M
is 16.46 GB plus a 0.93 GB mmproj. Fits CPU. See the mid-band survey; noted here
only because it is itself a mid VLM.

### `moondream/moondream3.1-9B-A2B` — small specialized VLM `[V]`

- Released: 2026-06-30. Params: 9.27B total, MoE (about 2B active). License:
  `other` (custom, non-commercial terms). Specialization: compact vision
  (caption, query, detect, point).
- GGUF: official `moondream/moondream3.1-9B-A2B` ships safetensors only;
  community `SkyContact/moondream3.1-9B-A2B-GGUF` -> `moondream3.1-q6k.gguf`
  (8.12 GB) plus `moondream3.1-vision.gguf` (0.90 GB) `[V]`.
- Fit: **fits CPU**; q6k at 8.12 GB is over the 8 GB GPU. The non-commercial
  license is a limit for general use.

### `LiquidAI/LFM2.5-VL-3B` — tiny VLM `[V]`

- Released: 2026-08-11. 3B dense, plus 1.6B and 450M variants. License: LFM
  Open `[I]`. GGUF: official `LiquidAI/LFM2.5-VL-3B-GGUF` `[V]`.
- Fit: **fits the GPU** at Q4 (about 2 GB). Good for edge vision tasks, lower
  quality than Qwen3-VL.

### InternVL `[V]`

`OpenGVLab/InternVL3_5-8B-Flash` (8.8B, released 2025-09-28) is the current
small InternVL. It is pre-2026 and has no first-party llama.cpp GGUF path as
clean as Qwen's. Noted; Qwen3-VL is the better brys pick.

### Gemma vision `[V]`

The Gemma-4 family (`gemma-4-E2B-it`, `-E4B-it`, `-12B-it`, `-31B-it`) is
multimodal (text + vision + audio) and Apache-2.0. Google ships QAT GGUFs, for
example `gemma-4-E4B-it-qat-q4_0-gguf` -> `gemma-4-E4B_q4_0-it.gguf` (5.15 GB)
plus `gemma-4-E4B-it-mmproj.gguf` (0.99 GB) `[V]`. Fit: the E4B is a GPU fit;
the 12B and 31B fit CPU (see the mid-band survey). SmolVLM2 (HuggingFace, 256M
to 2.2B) also exists but is a pre-2026 line.

## 3. Reasoning-specialized

There is **no dedicated, distinct 2026 open *small* reasoning model** that fits
brys and is separate from the general fleet. The situation:

- Reasoning is now a mode, not a separate model: Qwen3.8-27B, the Qwen3-VL
  `-Thinking` variants, GLM-4.7, and Gemma-4 all expose a thinking mode or a
  `-Thinking` build. These are already in the mid-band fleet.
- Dedicated 2026 reasoning models are large: `DeepSeek-V4.1-Flash` (763B) and
  `DeepSeek-Math-V2` (685B, math-specialized) are far too big for brys.
- Small `-thinker` builds exist (`CohereLabs/tiny-aya-en-thinker`, 3.35B, but
  license `cc-by-nc-4.0`) `[V]`. The non-commercial license rules it out for
  general use.

Verdict: **no fit** for a distinct reasoning specialist. Use the thinking mode of
the registered general models.

## 4. Embedding / reranker

### `Qwen/Qwen3-Embedding-4B` — best embedding `[V]`

- Repo: `Qwen/Qwen3-Embedding-4B` (also `-0.6B`, `-8B`, with official GGUF).
- Released: 2025-06-03. Params: 4B dense. Dimensions: 2560 (MRL, truncatable).
  Context: 40,960. License: Apache-2.0.
- GGUF: official `Qwen/Qwen3-Embedding-4B-GGUF` `[V]`.
- Fit: **fits CPU easily** (about 2.5 GB at Q4). The `0.6B` (1024-d, about
  0.4 GB) is a GPU fit if a tiny, fast embedder is wanted.

### `Qwen/Qwen3-Reranker-4B` — best reranker `[V]`

- Repo: `Qwen/Qwen3-Reranker-4B` (also `-0.6B`, `-8B`). Released 2025-06.
  Params: 4B dense, 2560-d backbone. License: Apache-2.0.
- GGUF: community `[V]` (for example W8A8 and oQ8e builds); official
  transformers weights exist.
- Fit: **fits CPU easily**. The `0.6B` reranker (1024-d) is a GPU fit.

**2026 note:** the current Qwen retrieval line is the vision-capable
`Qwen3-VL-Embedding-{2B,8B}` and `Qwen3-VL-Reranker-{2B,8B}` (2026-01-07) `[V]`.
For text-only retrieval, Qwen3-Embedding-4B and Qwen3-Reranker-4B remain the
best simple open pick; they are dated 2025-06 but are still current.

## 5. Speech (note only)

- **ASR:** `Qwen/Qwen3-ASR-0.6B-hf` and `-1.7B-hf` (2026-06-26, Apache-2.0)
  `[V]` are the current small open ASR models. NVIDIA `parakeet-tdt-0.6b-v3`
  is a fast English ASR model with int8/ONNX builds `[V]`. Voxtral
  (`mistralai/Voxtral-Mini-3B-2507`, and `Voxtral-Mini-4B-Realtime-2602`,
  2026-01) covers ASR and, in `Voxtral-4B-TTS-2603`, TTS `[V]`. All are small
  and fit CPU or GPU. Whisper itself is the prior generation; the successors
  above replace it.
- **TTS:** `Qwen3-TTS` (0.6B and 1.7B) and `Kokoro-82M` (82M, very small) are the
  current open TTS options `[V]`.
- Verdict: all fit brys, but TCP/speech serving is out of scope for the current
  fleet; noted only.

## Ranked shortlist for brys (specialized)

1. **`CohereLabs/North-Mini-Code-1.0`** — 30B MoE code, Apache-2.0, Q4_K_M
   18.59 GB, fits CPU at about 13 t/s. The one code model to add.
2. **`Qwen/Qwen3-VL-8B-Instruct`** — 8B VLM, Apache-2.0, Q4 5.03 GB + mmproj;
   fits the GPU. (Or `Qwen3-VL-4B` for a clean GPU fit.)
3. **`Qwen/Qwen3-Embedding-4B` + `Qwen/Qwen3-Reranker-4B`** — retrieval pair,
   2560-d, Apache-2.0, fit CPU.
4. **`Qwen/Qwen3-Coder-Next`** — 80B / 3B MoE, Apache-2.0, but 48.5 GB at Q4;
   only at `UD-IQ2_M` (25 GB) on brys. Heavy.
5. **`Qwen/Qwen3-VL-30B-A3B-Instruct`** — MoE VLM, Q4_K_M 18.56 GB, fits CPU;
   higher-quality vision than the 8B if CPU speed is acceptable.

## Ready GGUFs (repo + file)

- North-Mini-Code-1.0:
  `NANI-Nithin/north-mini-code-gguf` -> `North-Mini-Code-1.0-Q4_K_M.gguf`
  (18.59 GB).
- Qwen3-Coder-Next: `unsloth/Qwen3-Coder-Next-GGUF` ->
  `Qwen3-Coder-Next-UD-Q4_K_M.gguf` (49.30 GB) or
  `Qwen3-Coder-Next-UD-IQ2_M.gguf` (24.96 GB); official
  `Qwen/Qwen3-Coder-Next-GGUF`.
- GLM-4.7-Flash-Coder: `ngquocvinh/GLM-4.7-Flash-Coder-GGUF` ->
  `GLM-4.7-Flash-Coder-Q4_K_M.gguf` (18.13 GB).
- Devstral-Small-2-24B: `unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF` ->
  `Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf` (14.33 GB).
- Qwen3-VL-8B: `Qwen/Qwen3-VL-8B-Instruct-GGUF` ->
  `Qwen3VL-8B-Instruct-Q4_K_M.gguf` (5.03 GB) + `mmproj-Qwen3VL-8B-Instruct-F16.gguf`
  (1.16 GB).
- Qwen3-VL-4B: `Qwen/Qwen3-VL-4B-Instruct-GGUF` ->
  `Qwen3VL-4B-Instruct-Q4_K_M.gguf` (2.50 GB) + mmproj (0.84 GB).
- Qwen3-VL-30B-A3B: `Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF` ->
  `Qwen3VL-30B-A3B-Instruct-Q4_K_M.gguf` (18.56 GB) + mmproj (1.08 GB).
- moondream3.1: `SkyContact/moondream3.1-9B-A2B-GGUF` ->
  `moondream3.1-q6k.gguf` (8.12 GB) + `moondream3.1-vision.gguf` (0.90 GB).
- Gemma-4 vision: `google/gemma-4-E4B-it-qat-q4_0-gguf` ->
  `gemma-4-E4B_q4_0-it.gguf` (5.15 GB) + `gemma-4-E4B-it-mmproj.gguf` (0.99 GB).
- Embedding: `Qwen/Qwen3-Embedding-4B-GGUF` (2560-d).
- Reranker: `Qwen/Qwen3-Reranker-4B` (community GGUF).

## See also

- [mid-band-survey.research.md](mid-band-survey.research.md) — the 10-40B band.
- [definition.md](definition.md) — this task.
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) — the
  registration point.
