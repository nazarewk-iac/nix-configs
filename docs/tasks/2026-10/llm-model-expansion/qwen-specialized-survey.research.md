---
type: Research
description: Desk survey of the Qwen SPECIALIZED model lines on Hugging Face (org Qwen) for host brys (Ryzen 5950X, 128 GB, 8 GB W6600, CPU-first, llama.cpp). It separates the models that run on llama.cpp from the models that need vLLM/SGLang/Transformers. No hardware and no builds.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T20:10:00+02:00
---

# Qwen specialized-model survey for brys

A desk survey only. No hardware and no builds. This file goes deeper and wider
than [specialized-survey.research.md](specialized-survey.research.md) and
[mid-band-survey.research.md](mid-band-survey.research.md): it covers the Qwen
org specialized lines one by one. The prior surveys already know
Qwen3-Coder-Next, Qwen3-VL-8B, Qwen3-Embedding-4B, Qwen3-Reranker-4B, and
Qwen3-ASR; this file confirms those and adds the rest of the org.

Target host `brys`: AMD Ryzen 5950X (AVX2, no AVX512), 128 GB DDR4, one 8 GB AMD
W6600 GPU, about 330 GB free disk. CPU-first. A model that fits the 8 GB card
(<= ~6 GB of weights) can use the GPU. A larger model runs on the CPU and is
memory-bandwidth bound. The runner is **llama.cpp / llama-server**.

**The key filter is llama.cpp support.** A model whose architecture llama.cpp
does not implement cannot run on brys, even if a GGUF file exists. The
`llama-arch.cpp` architecture table (llama.cpp master, read 2026-10-20) contains
these Qwen entries: `qwen`, `qwen2`, `qwen2moe`, `qwen2vl`, `qwen3`, `qwen3moe`,
`qwen3next`, `qwen3vl`, `qwen3vlmoe`, `qwen35`, `qwen35moe`, `qwen4exp`,
`rwkv6qwen2`, `qwen3tts` `[V]`.

**Evidence:** `[V]` verified against the Hugging Face API (createdAt, config
`architectures`/`model_type`, license tag, GGUF blob size) at 2026-10-20; `[I]`
inferred. GGUF sizes are the real blob sizes from the tree API. Predicted CPU
decode uses 40 GB/s / active-GB-per-token.

## Master table

The `arch` column gives the GGUF `general.architecture` and whether llama.cpp
implements it. `runs?` = runnable on brys with llama.cpp.

| family | model (HF repo) | released | params | license | HF arch / llama.cpp | runs? | GGUF (repo + file + size) | ctx | fit verdict |
|---|---|---|---|---|---|---|---|---|---|
| Guard | `Qwen/Qwen3Guard-Gen-0.6B` | 2025-09-23 | 0.6B dense | Apache-2.0 | `qwen3` / yes `[V]` | yes | community `mradermacher/Qwen3Guard-Gen-0.6B-GGUF` Q4_K_M 0.48 GB `[V]` | 32K `[I]` | GPU fit; pure classifier head, not a chat model |
| Guard | `Qwen/Qwen3Guard-Gen-4B` | 2025-09-23 | 4B dense | Apache-2.0 | `qwen3` / yes `[V]` | yes | community `mradermacher/Qwen3Guard-Gen-4B-GGUF` Q4_K_M 2.72 GB `[V]` | 32K `[I]` | GPU fit; moderation only |
| Guard | `Qwen/Qwen3Guard-Gen-8B` | 2025-09-23 | 8B dense | Apache-2.0 | `qwen3` / yes `[V]` | yes | community `mradermacher/Qwen3Guard-Gen-8B-GGUF` Q4_K_M 5.03 GB `[V]` | 32K `[I]` | GPU-marginal or CPU; moderation only |
| Guard | `Qwen/Qwen3Guard-Stream-0.6B` | 2025-09-23 | 0.6B dense | Apache-2.0 | `Qwen3ForGuardModel` / **no** `[V]` | **no** | community IQ4_NL exists but arch unsupported `[V]` | 32K `[I]` | needs Transformers; not for llama.cpp |
| Guard | `Qwen/Qwen3Guard-Stream-4B` | 2025-09-23 | 4B dense | Apache-2.0 | `Qwen3ForGuardModel` / **no** `[V]` | **no** | — | 32K `[I]` | needs Transformers |
| Guard | `Qwen/Qwen3Guard-Stream-8B` | 2025-09-23 | 8B dense | Apache-2.0 | `Qwen3ForGuardModel` / **no** `[V]` | **no** | — | 32K `[I]` | needs Transformers |
| Coder | `Qwen/Qwen3-Coder-30B-A3B-Instruct` | 2025-07-31 | 30B / 3B MoE | Apache-2.0 | `qwen3moe` / yes `[V]` | yes | official GGUF + `unsloth/...-GGUF` Q4_K_M 18.56 GB `[V]` | 256K `[I]` | fits CPU (~13 t/s predicted) |
| Coder | `Qwen/Qwen3-Coder-Next` | 2026-01-30 | 80B / 3B MoE | Apache-2.0 | `qwen3next` / yes `[V]` | yes | official `Qwen/Qwen3-Coder-Next-GGUF` Q4_K_M 48.40 GB total `[V]` | 262K | fits CPU only at low quant |
| Coder | `Qwen/Qwen3-Coder-480B-A35B-Instruct` | 2025-07-22 | 480B / 35B MoE | Apache-2.0 | `qwen3moe` / yes `[V]` | yes | community only; huge | 256K `[I]` | **no fit** (too large) |
| Coder | `Qwen/Qwen3.8-Flash-Next` | 2026 `[I]` | MoE `[I]` | Apache-2.0 | `qwen35moe` `[I]` | maybe `[I]` | none found `[V]` | — | no GGUF yet; no fit now |
| VL | `Qwen/Qwen3-VL-2B-Instruct` / `-Thinking` | 2025-10-11 | 2B dense | Apache-2.0 | `qwen3vl` / yes `[V]` | yes | official `Qwen/Qwen3-VL-2B-Instruct-GGUF` Q4_K_M 1.11 GB + mmproj 0.82 GB `[V]` | 256K `[I]` | clean GPU fit |
| VL | `Qwen/Qwen3-VL-4B-Instruct` / `-Thinking` | 2025-10-11 | 4B dense | Apache-2.0 | `qwen3vl` / yes `[V]` | yes | official `Qwen/Qwen3-VL-4B-Instruct-GGUF` Q4_K_M 2.50 GB + mmproj 0.84 GB `[V]` | 256K `[I]` | clean GPU fit |
| VL | `Qwen/Qwen3-VL-8B-Instruct` / `-Thinking` | 2025-10-11 | 8B dense | Apache-2.0 | `qwen3vl` / yes `[V]` | yes | official `Qwen/Qwen3-VL-8B-Instruct-GGUF` Q4_K_M 5.03 GB + mmproj 1.16 GB `[V]` | 256K `[I]` | GPU-marginal; CPU fits |
| VL | `Qwen/Qwen3-VL-32B-Instruct` / `-Thinking` | 2025-10-11 | 32B dense | Apache-2.0 | `qwen3vl` / yes `[V]` | yes | official `Qwen/Qwen3-VL-32B-Instruct-GGUF` Q4_K_M 19.76 GB + mmproj 1.20 GB `[V]` | 256K `[I]` | fits CPU (~2 t/s predicted) |
| VL | `Qwen/Qwen3-VL-30B-A3B-Instruct` / `-Thinking` | 2025-10-11 | 30B / 3B MoE | Apache-2.0 | `qwen3vlmoe` / yes `[V]` | yes | official `Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF` Q4_K_M 18.56 GB + mmproj 1.08 GB `[V]` | 256K `[I]` | fits CPU (~13 t/s predicted) |
| VL | `Qwen/Qwen3-VL-235B-A22B-Instruct` / `-Thinking` | 2025-10-11 | 235B / 22B MoE | Apache-2.0 | `qwen3vlmoe` / yes `[V]` | yes | official GGUF exists `[V]` | 256K `[I]` | **no fit** (too large) |
| Omni | `Qwen/Qwen3-Omni-30B-A3B-Instruct` | 2025-09-20 | 30B / 3B MoE | `other` `[V]` | `qwen3_omni_moe` / yes `[V]` | yes | official `ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF` Q4_K_M 18.56 GB + mmproj 1.33 GB `[V]` | 32K `[I]` | fits CPU; audio+vision+text |
| Omni | `Qwen/Qwen3-Omni-30B-A3B-Thinking` | 2025-09-15 | 30B / 3B MoE | `other` `[V]` | `qwen3_omni_moe` / yes `[V]` | yes | official `ggml-org/Qwen3-Omni-30B-A3B-Thinking-GGUF` Q4_K_M 18.56 GB + mmproj 1.33 GB `[V]` | 32K `[I]` | fits CPU |
| Omni | `Qwen/Qwen3-Omni-30B-A3B-Captioner` | 2025-09-15 | 30B / 3B MoE | `other` `[V]` | `qwen3_omni_moe` / yes `[V]` | yes | community `presencesw/...-Captioner-GGUF` `[V]` | 32K `[I]` | fits CPU; audio captioning |
| Math | `Qwen/QwQ-32B` | 2025-03-05 | 32B dense | Apache-2.0 | `qwen2` / yes `[V]` | yes | official `Qwen/QwQ-32B-GGUF` Q4_K_M 19.85 GB `[V]` | 128K `[I]` | fits CPU (~2 t/s predicted) |
| Math | `Qwen/QwQ-32B-Preview` | 2024-11 | 32B dense | Apache-2.0 | `qwen2` / yes `[V]` | yes | many community GGUFs `[V]` | 32K `[I]` | fits CPU; pre-2026 |
| Math | `Qwen/Qwen2.5-Math-7B-Instruct` | 2024-09 | 7B dense | Apache-2.0 | `qwen2` / yes `[V]` | yes | community GGUFs `[V]` | 4K `[I]` | GPU or CPU; old line |
| Image | `Qwen/Qwen-Image-2.1` | 2026-09-14 | diffusion | `other` `[V]` | `QwenImagePipeline` (diffusers) / **no** `[V]` | **no** | none | — | needs Diffusers; not llama.cpp |
| Image | `Qwen/Qwen-Image-2512` | 2025-12-30 | diffusion | Apache-2.0 | `QwenImagePipeline` / **no** `[V]` | **no** | none | — | needs Diffusers |
| Image | `Qwen/Qwen-Image-Edit-2511` | 2025-12-17 | diffusion | Apache-2.0 | `QwenImageEditPlusPipeline` / **no** `[V]` | **no** | none | — | needs Diffusers |
| TTS | `Qwen/Qwen3-TTS-12Hz-0.6B-Base` | 2026-01-21 | 0.6B | Apache-2.0 | `qwen3tts` / yes `[V]` | yes | official converter + community `[I]` | — | fits GPU; speech out of fleet scope |
| TTS | `Qwen/Qwen3-TTS-12Hz-1.7B-Base` | 2026-01-21 | 1.7B | Apache-2.0 | `qwen3tts` / yes `[V]` | yes | official converter + community `[I]` | — | fits GPU/CPU |
| TTS | `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` | 2026-01-21 | 1.7B | Apache-2.0 | `qwen3tts` / yes `[V]` | yes | official converter + community `[I]` | — | fits GPU/CPU |
| ASR | `Qwen/Qwen3-ASR-0.6B` | 2026-06-26 | 0.6B | Apache-2.0 | audio / yes `[V]` | yes | official `ggml-org/Qwen3-ASR-0.6B-GGUF` Q8_0 0.80 GB + mmproj 0.21 GB `[V]` | — | GPU fit; tiny |
| ASR | `Qwen/Qwen3-ASR-1.7B` | 2026-06-26 | 1.7B | Apache-2.0 | audio / yes `[V]` | yes | official `ggml-org/Qwen3-ASR-1.7B-GGUF` Q8_0 2.17 GB + mmproj 0.36 GB `[V]` | — | GPU fit |
| Align | `Qwen/Qwen3-ForcedAligner-0.6B` | 2026-06-26 | 0.6B | Apache-2.0 | audio aligner / `[I]` | maybe `[I]` | none found `[V]` | — | needs Transformers alignment pipeline |
| Embed | `Qwen/Qwen3-Embedding-4B` | 2025-06-03 | 4B dense | Apache-2.0 | `qwen3` / yes `[V]` | yes | official `Qwen/Qwen3-Embedding-4B-GGUF` Q4_K_M 2.50 GB `[V]` | 40,960 | fits CPU easily |
| Embed | `Qwen/Qwen3-Embedding-8B` | 2025-06-03 | 8B dense (4096-d) | Apache-2.0 | `qwen3` / yes `[V]` | yes | official `Qwen/Qwen3-Embedding-8B-GGUF` Q4_K_M 4.68 GB `[V]` | 40,960 | GPU-marginal; CPU fits |
| Embed | `Qwen/Qwen3-Embedding-0.6B` | 2025-06-03 | 0.6B | Apache-2.0 | `qwen3` / yes `[V]` | yes | official `Qwen/Qwen3-Embedding-0.6B-GGUF` Q8_0 0.64 GB `[V]` | 32K `[I]` | GPU fit; fastest |
| Rerank | `Qwen/Qwen3-Reranker-4B` | 2025-05-29 | 4B dense | Apache-2.0 | `qwen3` + score head / yes `[V]` | yes | community `Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp` `[V]` | 32K `[I]` | fits CPU easily |
| Rerank | `Qwen/Qwen3-Reranker-8B` | 2025-05-29 | 8B dense | Apache-2.0 | `qwen3` + score head / yes `[V]` | yes | community `ggml-org`/`Voodisss` GGUF `[V]` | 32K `[I]` | GPU-marginal; CPU fits |
| VL-Embed | `Qwen/Qwen3-VL-Embedding-2B` | 2026-01-07 | 2B dense | Apache-2.0 | `qwen3vl` / yes `[V]` | yes | community `mradermacher/Qwen3-VL-Embedding-2B-GGUF` Q4_K_M 1.11 GB `[V]` | 32K `[I]` | GPU fit; multimodal retrieval |
| VL-Embed | `Qwen/Qwen3-VL-Embedding-8B` | 2026-01-07 | 8B dense | Apache-2.0 | `qwen3vl` / yes `[V]` | yes | community `mradermacher/Qwen3-VL-Embedding-8B-GGUF` Q4_K_M 4.68 GB `[V]` | 32K `[I]` | GPU-marginal; CPU fits |
| VL-Rerank | `Qwen/Qwen3-VL-Reranker-2B` | 2026-01-07 | 2B dense | Apache-2.0 | `qwen3vl` + head / yes `[V]` | yes | community `mradermacher/Qwen3-VL-Reranker-2B-GGUF` `[V]` | 32K `[I]` | GPU fit |
| VL-Rerank | `Qwen/Qwen3-VL-Reranker-8B` | 2026-01-07 | 8B dense | Apache-2.0 | `qwen3vl` + head / yes `[V]` | yes | community `mradermacher/Qwen3-VL-Reranker-8B-GGUF` `[V]` | 32K `[I]` | GPU-marginal; CPU fits |
| Drive | `Qwen/Qwen-Drive-1.0-4B` | 2026-08-27 | 4B dense | Apache-2.0 | `qwen_drive` / **no** `[V]` | **no** | none | — | needs Transformers; driving planning |
| Agent | `Qwen/Qwen-AgentWorld-35B-A3B` | 2026-06-22 | 35B / 3B MoE | Apache-2.0 | `transformers` / `[I]` | maybe `[I]` | none `[V]` | — | no GGUF; world model, not chat |
| Web | `Qwen/WebWorld-8B` / `-14B` / `-32B` | 2026-02-13 | 8/14/32B | Apache-2.0 | `transformers` / `[I]` | no `[I]` | none `[V]` | — | research world models; no GGUF |
| Reward | `Qwen/WorldPM-72B` | 2025-05-16 | 72B dense | Apache-2.0 | reward model / no `[I]` | no `[I]` | none `[V]` | — | reward model, not for serving |
| FP8 | `Qwen/Qwen3.8-27B-FP8` | 2026-08-13 | 27B dense | Apache-2.0 | `Qwen3_5ForConditionalGeneration` | **no** (FP8) `[V]` | none | 262K | FP8 weights; vLLM/SGLang only |
| FP8 | `Qwen/Qwen3-Coder-Next-FP8` | 2026-02-01 | 80B / 3B | Apache-2.0 | FP8 | **no** (FP8) `[V]` | use the GGUF instead | 262K | FP8 weights; use GGUF |
| FP8 | `Qwen/Qwen3-VL-*-FP8` (all sizes) | 2025-10-11 | varies | Apache-2.0 | FP8 | **no** (FP8) `[V]` | use the GGUF instead | — | FP8 weights; use GGUF |
| FP8 | `Qwen/Qwen3-VL-235B-A22B-*-FP8` | 2025-10-11 | 235B / 22B | Apache-2.0 | FP8 | **no** (FP8) `[V]` | — | 256K | FP8; too large anyway |

## Notes

### 1. Qwen3Guard (safety / moderation)

Two sub-lines, both released 2025-09-23, Apache-2.0, sizes 0.6B / 4B / 8B.

- **`Qwen3Guard-Gen-*`** uses architecture `Qwen3ForCausalLM`, `model_type
  qwen3` `[V]`. This is the plain Qwen3 causal-LM architecture. llama.cpp
  implements `qwen3`, so these GGUFs load and run `[V]`. They are classifiers:
  the model emits a safe/unsafe label and a category, it is not a chat model.
  Community GGUFs exist (`mradermacher`, `QuantFactory`, `geoffmunn`,
  `abnormalmapstudio`). Sizes: 0.6B Q4_K_M 0.48 GB, 4B Q4_K_M 2.72 GB, 8B
  Q4_K_M 5.03 GB `[V]`. The 0.6B and 4B are GPU fits; the 8B is
  GPU-marginal.
- **`Qwen3Guard-Stream-*`** uses architecture `Qwen3ForGuardModel`, `model_type
  qwen3` `[V]`. This is a **different** class with extra input embeddings and a
  streaming guard head. `Qwen3ForGuardModel` is **not** in the llama.cpp
  architecture table `[V]`. A community GGUF exists
  (`abnormalmapstudio/Qwen3Guard-Stream-8B-iq4-nl-gguf` `[V]`), but the arch is
  unsupported, so it cannot run on brys. Use the Stream line only under
  Transformers or vLLM.

Verdict: only the `-Gen` guard models run on brys, and only if a moderation
classifier is wanted. They are a niche; the fleet's general models already
refuse bad requests.

### 2. Qwen3-Coder line

- `Qwen/Qwen3-Coder-30B-A3B-Instruct` (2025-07-31, Apache-2.0): the prior
  generation, MoE 30B total / about 3B active, `qwen3moe` `[V]`. Official GGUF
  plus `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF`; Q4_K_M is 18.56 GB `[V]`.
  Fits CPU (about 13 t/s predicted). The prior specialized survey noted it as
  superseded by North-Mini-Code and Qwen3-Coder-Next, but for a **pure Qwen**
  coder it is the best CPU fit.
- `Qwen/Qwen3-Coder-Next` (2026-01-30, Apache-2.0): MoE 80B / about 3B active,
  `qwen3next` `[V]`. Official GGUF `Qwen/Qwen3-Coder-Next-GGUF`; `Q4_K_M` is
  48.40 GB in 4 split files `[V]`. Fits CPU only at a low quant (community
  `UD-IQ2_M` about 25 GB). Heavy load.
- `Qwen/Qwen3-Coder-480B-A35B-Instruct` (2025-07-22, Apache-2.0): `qwen3moe`,
  but 480B total. **No fit.**
- There is **no** `Qwen3.8-Coder` and **no** `Qwen3-Coder-32B`. The Coder line
  is only the three sizes above; `Qwen3.8-Flash-Next` is a general MoE with no
  GGUF yet `[V]`.

### 3. Qwen3-VL line

The full line, all released 2025-10-11, all Apache-2.0, all with official GGUF
plus an `mmproj` vision projector. Sizes: 2B, 4B, 8B, 32B (dense; `qwen3vl`) and
30B-A3B, 235B-A22B (MoE; `qwen3vlmoe`). Every size has an `-Instruct` and a
`-Thinking` build, and llama.cpp implements both archs `[V]`.

GGUF sizes (Q4_K_M, weights + mmproj) `[V]`:

- 2B: 1.11 GB + 0.82 GB mmproj. Clean GPU fit.
- 4B: 2.50 GB + 0.84 GB mmproj. Clean GPU fit.
- 8B: 5.03 GB + 1.16 GB mmproj. GPU-marginal; CPU fits. (Already in the prior
  survey.)
- 32B: 19.76 GB + 1.20 GB mmproj. CPU only (about 2 t/s predicted).
- 30B-A3B: 18.56 GB + 1.08 GB mmproj. CPU (about 13 t/s predicted).
- 235B-A22B: official GGUF exists, **no fit**.

Verdict: the 2B and 4B are the clean GPU choices; the 30B-A3B is the best
CPU MoE for higher-quality vision.

### 4. Qwen3-Omni (audio + vision + text)

- `Qwen/Qwen3-Omni-30B-A3B-Instruct` (2025-09-20) and `-Thinking` (2025-09-15),
  plus `-Captioner`. MoE 30B total / about 3B active, arch `qwen3_omni_moe`
  `[V]`. License `other` (Qwen custom), not Apache `[V]`.
- llama.cpp **does** support this: the official `ggml-org/Qwen3-Omni-30B-A3B-**
  Instruct-GGUF` and `-Thinking-GGUF` exist, and the llama.cpp multimodal docs
  list both under "Mixed modalities: audio input, vision input" `[V]`. Q4_K_M
  is 18.56 GB plus a 1.33 GB `mmproj` `[V]`.
- Fit: fits CPU (about 13 t/s predicted). The 8 GB GPU is too small. This is the
  only Qwen omni line; there is no smaller or larger omni size. TCP/speech
  serving is out of scope for the current fleet, so this is a note only.

### 5. Qwen3-Math / QwQ (reasoning and math)

- `Qwen/QwQ-32B` (2025-03-05, Apache-2.0): 32B dense reasoning model, 128K
  context `[I]`. Official `Qwen/QwQ-32B-GGUF`; Q4_K_M is 19.85 GB `[V]`. Fits
  CPU (about 2 t/s predicted). `QwQ-32B-Preview` (2024-11) is the earlier
  release; pre-2026.
- The Qwen3 line has **no** separate `Qwen3-Math`; math is now a mode inside the
  general Qwen3 thinking models. `Qwen2.5-Math-*` (2024) is the last dedicated
  open math line and is pre-2026.
- Verdict: **fits CPU** if a distinct reasoning specialist is wanted, but the
  earlier specialized survey found no dedicated 2026 open reasoning model that
  fits. QwQ-32B is the best runnable Qwen reasoning model on brys.

### 6. Qwen-Image / Qwen-Image-Edit (image generation and editing)

These are **diffusion** models, not language models. `Qwen-Image-2.1`
(2026-09-14, license `other`) uses `QwenImagePipeline`; `Qwen-Image-2512`
(2025-12-30, Apache-2.0) uses `QwenImagePipeline`; `Qwen-Image-Edit-2511`
(2025-12-17, Apache-2.0) uses `QwenImageEditPlusPipeline` `[V]`. They load
through **Diffusers** / ComfyUI, not llama.cpp. There is **no** GGUF and no
llama.cpp arch. **Not runnable on brys via llama.cpp.** (They could run on the
CPU through Diffusers, but that is a different runner and outside this survey.)

### 7. Qwen3-TTS and speech models

- `Qwen/Qwen3-TTS-12Hz-{0.6B,1.7B}-Base`, `-1.7B-CustomVoice`,
  `-1.7B-VoiceDesign` (2026-01-21, Apache-2.0): arch `qwen3tts` `[V]`, which is
  in the llama.cpp table `[V]`. So Qwen3-TTS is runnable, but it is small
  (0.6B / 1.7B) and speech serving is out of the fleet scope. Note only.
- `Qwen/Qwen3-ASR-0.6B` and `-1.7B` (2026-06-26, Apache-2.0): the current open
  ASR line. llama.cpp supports them; official `ggml-org` GGUFs exist —
  0.6B Q8_0 0.80 GB, 1.7B Q8_0 2.17 GB, each with a small `mmproj` `[V]`. Both
  are GPU fits.
- `Qwen/Qwen3-ForcedAligner-0.6B` (2026-06-26, Apache-2.0): an audio
  forced-alignment model. No GGUF found `[V]`; needs the Transformers alignment
  pipeline `[I]`. Not runnable on brys now.

### 8. Embedding and reranker

Text line (2025-06, Apache-2.0, arch `qwen3`, runnable):

- `Qwen3-Embedding-0.6B` (Q8_0 0.64 GB), `-4B` (Q4_K_M 2.50 GB, 2560-d),
  `-8B` (Q4_K_M 4.68 GB, 4096-d) `[V]`. Official GGUF for all three.
- `Qwen3-Reranker-0.6B`, `-4B`, `-8B` `[V]`, with a scoring head. Community
  GGUF (for example `Voodisss/...-GGUF-llama_cpp`, `ggml-org`) `[V]`.

Vision line (2026-01-07, Apache-2.0, arch `qwen3vl`, runnable):

- `Qwen3-VL-Embedding-2B` (Q4_K_M 1.11 GB) and `-8B` (Q4_K_M 4.68 GB) `[V]`.
- `Qwen3-VL-Reranker-2B` and `-8B` `[V]`.
- Community GGUF only (`mradermacher`, `mradermacher`, `gorse-io`).

Verdict: all fit; the text pair (Embedding-4B + Reranker-4B) is the best simple
retrieval choice and is already in the prior survey. The VL pair adds
image+text retrieval for the 2B case on the GPU.

### 9. Qwen-Drive and other niche specialists

- `Qwen/Qwen-Drive-1.0-4B` (2026-08-27, Apache-2.0): arch `QwenDriveForPlanning`,
  `model_type qwen_drive` `[V]`. A driving/perception/planning model. **Not** in
  the llama.cpp table; no GGUF. Needs Transformers. **Not runnable** on brys.
- `Qwen/Qwen-AgentWorld-35B-A3B` (2026-06-22, Apache-2.0): a 35B / 3B MoE
  agent world model `[V]`. No GGUF found. Not a chat model. Not runnable now.
- `Qwen/WebWorld-8B`, `-14B`, `-32B` (2026-02-13, Apache-2.0): web-navigation
  world models `[V]`. No GGUF. Research models, not for serving.
- `Qwen/WorldPM-72B` (2025-05-16, Apache-2.0) and the `SAE-Res-*` sparse
  autoencoder releases (2026) `[V]`: reward model and interpretability
  artifacts. Not for serving.

### 10. FP8 and quant variants

Qwen publishes `-FP8` builds for many models (for example
`Qwen3.8-27B-FP8` 2026-08-13, `Qwen3-Coder-Next-FP8` 2026-02-01, and an `-FP8`
for every Qwen3-VL size) `[V]`.

**FP8 is not usable by llama.cpp.** The `-FP8` repos hold 8-bit floating-point
safetensors for **vLLM / SGLang** (and Transformers with an FP8 runtime). They
carry no GGUF. On brys, use the GGUF form of the same model instead — for
example the plain `Qwen/Qwen3-Coder-Next` GGUF, not `-FP8`. There is no
llama.cpp path for `-FP8` weights.

## Runnable on brys (llama.cpp)

These have a llama.cpp-supported architecture **and** a GGUF, grouped by fit.

**GPU fit (weights <= ~6 GB):**

- `Qwen3-VL-2B-Instruct` / `-Thinking` — official GGUF, Q4_K_M 1.11 GB + mmproj.
- `Qwen3-VL-4B-Instruct` / `-Thinking` — official GGUF, Q4_K_M 2.50 GB + mmproj.
- `Qwen3Guard-Gen-0.6B` and `-4B` — community GGUF (moderation classifier).
- `Qwen3-Embedding-0.6B` — official GGUF, Q8_0 0.64 GB.
- `Qwen3-ASR-0.6B` and `-1.7B` — official `ggml-org` GGUF (speech).
- `Qwen3-TTS-12Hz-0.6B` / `-1.7B` — arch supported (speech).

**CPU fit (loads on the CPU; MoE decodes faster):**

- `Qwen3-Coder-30B-A3B-Instruct` — best pure-Qwen CPU coder, Q4_K_M 18.56 GB.
- `Qwen3-VL-30B-A3B-Instruct` / `-Thinking` — MoE VLM, Q4_K_M 18.56 GB.
- `Qwen3-VL-8B-Instruct` / `-Thinking` — Q4_K_M 5.03 GB.
- `Qwen3-VL-32B-Instruct` / `-Thinking` — Q4_K_M 19.76 GB.
- `Qwen3-Omni-30B-A3B-Instruct` / `-Thinking` — audio+vision+text, Q4_K_M
  18.56 GB.
- `Qwen3Guard-Gen-8B` — Q4_K_M 5.03 GB.
- `Qwen3-Embedding-4B` / `-8B` — Q4_K_M 2.50 / 4.68 GB.
- `Qwen3-Reranker-4B` / `-8B` — community GGUF.
- `Qwen3-VL-Embedding-2B` / `-8B` and `Qwen3-VL-Reranker-2B` / `-8B` —
  community GGUF.
- `QwQ-32B` — Q4_K_M 19.85 GB (reasoning).
- `Qwen3-Coder-Next` — Q4_K_M 48.40 GB; only practical at a low quant.

**No fit (too large):** `Qwen3-Coder-480B-A35B-Instruct`,
`Qwen3-VL-235B-A22B-*`.

## Needs vLLM / SGLang / Transformers (not runnable here)

- `Qwen3Guard-Stream-0.6B` / `-4B` / `-8B` — arch `Qwen3ForGuardModel`, not in
  llama.cpp.
- `Qwen-Drive-1.0-4B` — arch `QwenDriveForPlanning`.
- `Qwen-Image-2.1`, `Qwen-Image-2512`, `Qwen-Image-Edit-2511`, and the rest of
  the `Qwen-Image*` line — diffusion pipelines for Diffusers/ComfyUI.
- All `-FP8` repos (`Qwen3.8-27B-FP8`, `Qwen3-Coder-Next-FP8`, every
  `Qwen3-VL-*-FP8`) — FP8 safetensors for vLLM/SGLang; use the GGUF form
  instead.
- `Qwen3-ForcedAligner-0.6B` — alignment pipeline; no GGUF.
- `Qwen-AgentWorld-35B-A3B`, `WebWorld-8B/14B/32B`, `WorldPM-72B`,
  `SAE-Res-*` — research artifacts with no GGUF and no chat serving path.

## Ready GGUFs (repo + file)

- Qwen3-Coder-30B-A3B-Instruct: `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF` ->
  `Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf` (18.56 GB).
- Qwen3-Coder-Next: `Qwen/Qwen3-Coder-Next-GGUF` ->
  `Qwen3-Coder-Next-Q4_K_M/Qwen3-Coder-Next-Q4_K_M-0000{1..4}-of-00004.gguf`
  (48.40 GB total).
- Qwen3-VL-2B: `Qwen/Qwen3-VL-2B-Instruct-GGUF` ->
  `Qwen3VL-2B-Instruct-Q4_K_M.gguf` (1.11 GB) + `mmproj-...-F16.gguf`
  (0.82 GB).
- Qwen3-VL-4B: `Qwen/Qwen3-VL-4B-Instruct-GGUF` ->
  `Qwen3VL-4B-Instruct-Q4_K_M.gguf` (2.50 GB) + mmproj (0.84 GB).
- Qwen3-VL-8B: `Qwen/Qwen3-VL-8B-Instruct-GGUF` ->
  `Qwen3VL-8B-Instruct-Q4_K_M.gguf` (5.03 GB) + mmproj (1.16 GB).
- Qwen3-VL-32B: `Qwen/Qwen3-VL-32B-Instruct-GGUF` ->
  `Qwen3VL-32B-Instruct-Q4_K_M.gguf` (19.76 GB) + mmproj (1.20 GB).
- Qwen3-VL-30B-A3B: `Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF` ->
  `Qwen3VL-30B-A3B-Instruct-Q4_K_M.gguf` (18.56 GB) + mmproj (1.08 GB).
- Qwen3-Omni: `ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF` ->
  `Qwen3-Omni-30B-A3B-Instruct-Q4_K_M.gguf` (18.56 GB) + mmproj (1.33 GB);
  same for the `-Thinking` repo.
- Qwen3Guard-Gen: `mradermacher/Qwen3Guard-Gen-0.6B-GGUF` (Q4_K_M 0.48 GB),
  `-4B-GGUF` (2.72 GB), `-8B-GGUF` (5.03 GB).
- QwQ-32B: `Qwen/QwQ-32B-GGUF` -> `qwq-32b-q4_k_m.gguf` (19.85 GB).
- Qwen3-Embedding: `Qwen/Qwen3-Embedding-4B-GGUF` (Q4_K_M 2.50 GB),
  `-8B-GGUF` (4.68 GB), `-0.6B-GGUF` (Q8_0 0.64 GB).
- Qwen3-Reranker: `Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp` (community).
- Qwen3-VL-Embedding/Reranker: `mradermacher/Qwen3-VL-Embedding-2B-GGUF`
  (Q4_K_M 1.11 GB) and `-8B-GGUF` (4.68 GB); matching reranker repos.
- Qwen3-ASR: `ggml-org/Qwen3-ASR-0.6B-GGUF` (Q8_0 0.80 GB) and
  `-1.7B-GGUF` (2.17 GB), each with mmproj.

## Verdict for brys

The one Qwen specialized **addition** with clear value is
`Qwen3-Coder-30B-A3B-Instruct` (pure-Qwen CPU coder, Q4_K_M 18.56 GB), if a
Qwen-only coder is wanted next to North-Mini-Code. The Qwen3-VL line (2B/4B on
the GPU, 30B-A3B on the CPU) and the text retrieval pair are already known from
the earlier surveys. `Qwen3-Omni-30B-A3B` is the only runnable omni model and is
an optional CPU addition. The Guard `-Gen` models run but are a niche. The
Coder-480B, VL-235B, all `-FP8` builds, the Guard `-Stream` line, Qwen-Image,
Qwen-Drive, and the research world/reward models are **not runnable** on brys.

## See also

- [specialized-survey.research.md](specialized-survey.research.md) — the
  specialized classes survey.
- [mid-band-survey.research.md](mid-band-survey.research.md) — the 10-40B band.
- [definition.md](definition.md) — this task.
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) — the
  registration point.
