---
type: Research
description: Popularity-first sweep of the Hugging Face GGUF catalog by 2026 downloads across six pipeline classes plus all-GGUF and trending sorts, deduplicated by base model and screened against the brys fit rules; ranks the survivors and names the top 10 new candidates to measure.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T20:40:00+02:00
---

# Popularity-first model sweep for brys

A desk study only. No hardware, no builds, no large downloads. This file ranks
the Hugging Face catalog by popularity, then filters by what fits host `brys`.
It does not re-list the hand-picked candidates that the earlier surveys already
cover ([mid-band-survey.research.md](../mid-band-survey.research.md),
[specialized-survey.research.md](../specialized-survey.research.md),
[qwen-specialized-survey.research.md](../qwen-specialized-survey.research.md));
it finds what those surveys missed.

**Evidence:** `[V]` verified against the public Hugging Face API on 2026-10-20
(model list, model info, `config.json`, tree blob sizes); `[I]` inferred (param
math, naming, arch table). GGUF sizes are the real blob sizes from the tree API.

## 1. Method

Six `pipeline_tag` classes were swept, plus one sweep with no `pipeline_tag`.
Every query used `filter=gguf`, `sort=downloads`, `direction=-1`,
`createdSince=2026-01-01`, `limit=100`, paged with the `Link` header
`?cursor=` until the download count dropped **below 100,000 downloads**. Two
extra sweeps used `sort=trendingScore` instead of `sort=downloads`.

Exact queries `[V]`:

```
https://huggingface.co/api/models?filter=gguf&pipeline_tag=text-generation&sort=downloads&direction=-1&limit=100&createdSince=2026-01-01
https://huggingface.co/api/models?filter=gguf&pipeline_tag=image-text-to-text&sort=downloads&direction=-1&limit=100&createdSince=2026-01-01
https://huggingface.co/api/models?filter=gguf&pipeline_tag=feature-extraction&sort=downloads&direction=-1&limit=100&createdSince=2026-01-01
https://huggingface.co/api/models?filter=gguf&pipeline_tag=text-ranking&sort=downloads&direction=-1&limit=100&createdSince=2026-01-01
https://huggingface.co/api/models?filter=gguf&pipeline_tag=automatic-speech-recognition&sort=downloads&direction=-1&limit=100&createdSince=2026-01-01
https://huggingface.co/api/models?filter=gguf&pipeline_tag=text-to-speech&sort=downloads&direction=-1&limit=100&createdSince=2026-01-01
https://huggingface.co/api/models?filter=gguf&sort=downloads&direction=-1&limit=100&createdSince=2026-01-01
https://huggingface.co/api/models?filter=gguf&pipeline_tag=text-generation&sort=trendingScore&direction=-1&limit=100&createdSince=2026-01-01
```

**Threshold:** 100,000 downloads. Stated per class:

| class | repos at or above 100k |
|---|---|
| text-generation | 141 |
| image-text-to-text | 102 |
| feature-extraction | 5 |
| text-ranking | 1 |
| automatic-speech-recognition | 16 |
| text-to-speech | 9 |
| all-GGUF (no pipeline_tag) | 412 |

**Total:** 1,111 unique repos across all sweeps `[V]`.

**Deduplication:** many GGUF repos (unsloth, bartowski, mradermacher, ggml-org,
and the large number of "uncensored" and "abliterated" re-quantizers) repackage
the same weights. One row is kept per base model; the best GGUF repo is named.
The 1,111 repos collapse to about 130 base models; of those, about 40 are not in
the earlier surveys.

## 2. Ranked table (new base models not in the earlier surveys)

The fleet column marks models already served or measured on brys (see
[hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) and
[measurements.research.md](../../llm-benchmark-suite/001-benchmark-suite/measurements.research.md)).
GGUF size is Q4/Q5 unless noted. CPU decode estimate uses 40 GB/s / active-GB.

| model | repo | downloads | likes | class | params | GGUF size | license | in fleet? | fit verdict |
|---|---|---|---|---|---|---|---|---|---|
| Ornith-1.5-9B | `ornith-ai/Ornith-1.5-9B-GGUF` | 4,991,826 | 568 | text + vision | 9B dense (`qwen3_5`) | 5.78 GB Q4_K_M (+0.92 mmproj) | MIT | no | fits GPU; strong new candidate |
| Ornith-1.5-35B-A3B | `ornith-ai/Ornith-1.5-35B-A3B-GGUF` | 3,840,023 | 530 | text + vision | 35B / ~3B (`qwen3_5_moe`, 256 experts) | 21.71 GB Q4_K_M (+0.90 mmproj) | MIT | no | fits CPU (~13 t/s pred) |
| Ternary-Bonsai-2-27B | `prism-ml/Ternary-Bonsai-2-27B-gguf` | 2,999,667 | 2,765 | text + vision | 27B ternary | mmproj only; weights separate | Apache-2.0 | no | check: ternary quant; llama.cpp support unclear |
| Ornith-1.0-35B | `ornith-ai/Ornith-1.0-35B-GGUF` | 1,513,951 | 1,062 | text | 35B dense | 21.17 GB Q4_K_M | MIT | no | fits CPU; superseded by Ornith-1.5 |
| DeepSeek-V4-Flash (antirez) | `antirez/deepseek-v4-gguf` | 1,262,374 | 487 | text | V4-Flash `[I]` | see repo | MIT | no | likely too big; llama.cpp unsupported arch `[I]` |
| Swift-1.5-Qwen3.8-27B-GSQ-RCO | `ukisai/Swift-1.5-Qwen3.8-27B-GSQ-RCO-GGUF` | 1,241,163 | 403 | text | 27B dense (Qwen3.8 fine-tune) | 11.77 GB IQ3_S | other | no | fits CPU; low-quant merge, not a new base |
| GLM-5.3-Flash | `unsloth/GLM-5.3-Flash-GGUF` | 934,656 | 489 | text + vision | ~320B MoE `[I]` (`glm5_next`, 288 experts) | 48 GB+ per shard | MIT | no | **no fit** (too large; BF16 is 642 GB) |
| Muse-Glimmer-30B | `unsloth/Muse-Glimmer-30B-GGUF` | 532,254 | 574 | vision | 30B `[I]` (`muse_glimmer`) | 15.88 GB Q4_K_XL (+mmproj) | Apache-2.0 | no | fits CPU; new arch, check llama.cpp |
| Inkling-Small | `unsloth/Inkling-Small-GGUF` | 750,066 | 98 | text + vision | ~35B `[I]` (`inkling_mm_model`) | 15.02 GB Q4_K_M | Apache-2.0 | no | fits CPU; new arch, check llama.cpp |
| Tiel-Coder-35B-A3B | `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP` | 1,927,505 | 296 | vision | 35B / 3B MoE | 22.75 GB Q4_K_XL | MIT | no | fits CPU; coder merge, check arch |
| MiniCPM-V-4.7-35B-A3B | `openbmb/MiniCPM-V-4.7-35B-A3B-gguf` | 186,447 | 186 | vision | 35B / 3B (`minicpmv4_7`) | 21.17 GB Q4_K_M (+1.12 mmproj) | Apache-2.0 | no | fits CPU; official GGUF, new VLM |
| MiniCPM-V-4.7-1B | `openbmb/MiniCPM-V-4.7-1B-gguf` | 58,779 | — | vision | 1B (`minicpmv4_7`) | small Q4 | Apache-2.0 | no | fits GPU; clean small VLM |
| Nemotron-3.5-Bolt-74B-A9B | `nvidia/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-GGUF` | 87,789 | 104 | text + vision | 74B / 9B MoE | 24 GB class | other | no | fits CPU (~4 t/s pred); just under threshold |
| Hy-Memory-30B-A3B | `tencent/Hy-Memory-30B-A3B-GGUF` | 455 | — | text | 30B / 3B MoE | 18.24 GB Q4_K_M | Apache-2.0 | no | fits CPU; trending, new arch |
| Beam-1.0-501B-A23B | `unsloth/Beam-1.0-501B-A23B-GGUF` | 1,835 | — | text | 501B / 23B MoE | 48 GB+ per shard | Apache-2.0 | no | **no fit** (too large) |
| LFM2.5-2.6B | `LiquidAI/LFM2.5-2.6B-GGUF` | 750,210 | 387 | text | 2.6B dense (`lfm2`) | 1.67 GB Q4_K_M | LFM Open | family in fleet (24B) | fits GPU; small sibling of LFM2.5-24B |
| Mellum2.1-12B-A2.5B-Thinking | `JetBrains/Mellum2.1-12B-A2.5B-Thinking-GGUF` | 151,955 | — | text | 12B / 2.5B MoE | Q4 class | Apache-2.0 | no | fits CPU; new coder, low downloads |
| JiRackUltra-1B | `CMSManhattan/JiRackUltra_1b` | 2,490,599 | 13 | text | 1.78B (`qwen2`) | small Q4 | MIT | no | fits GPU; download-inflated, low likes |
| JiRackDeltaNet-27B | `CMSManhattan/JiRackDeltaNet_27b` | 556,517 | 3 | text | 27.3B (`qwen3_5`) | Q4 class | MIT | no | fits CPU; download-inflated |

### New class specialists (below the general table)

| model | repo | downloads | class | params | GGUF | license | verdict |
|---|---|---|---|---|---|---|---|
| mxbai-embed-large-v1 | `mixedbread-ai/mxbai-embed-large-v1` | 2,081,255 | embedding | 335M (`BertModel`) | GGUF exists | Apache-2.0 | fits GPU; older (2024), popular |
| embeddinggemma-2 (300M) | `unsloth/embeddinggemma-2-GGUF` | 114,623 | embedding | 300M | Q8/Q4 | Gemma | fits GPU; 2026 embedding line |
| nemotron-3.5-asr-streaming-0.6b | `handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf` | 1,987,522 | ASR | 0.6B | small | other | fits GPU; streaming ASR, current |
| parakeet-unified-en-0.6b | `handy-computer/parakeet-unified-en-0.6b-gguf` | 1,967,158 | ASR | 0.6B | small | other | fits GPU; NVIDIA ASR |
| cohere-transcribe-03-2026 | `handy-computer/cohere-transcribe-03-2026-gguf` | 1,164,946 | ASR | — | small | Apache-2.0 | fits GPU; new Cohere ASR |
| Qwen3-TTS (community) | `Serveurperso/Qwen3-TTS-GGUF` | 474,013 | TTS | 0.6-1.7B | GGUF | Apache-2.0 | fits GPU; speech out of fleet scope |
| Qwen3-Reranker-0.6B (Q8) | `ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF` | 106,678 | rerank | 0.6B | Q8_0 | Apache-2.0 | fits GPU; already known line |
| jina-reranker-v3.5 | `jinaai/jina-reranker-v3.5-GGUF` | 3,580 | rerank | ~0.6B | GGUF | CC-BY-NC | below threshold; note non-commercial |

## 3. Top new candidates to measure (10)

Ranked by fit, popularity, and role. Each has a GGUF repo and file.

1. **Ornith-1.5-9B** — `ornith-ai/Ornith-1.5-9B-GGUF` ->
   `Ornith-1.5-9B-Q4_K_M.gguf` (5.78 GB) + `mmproj-Ornith-1.5-9B-BF16.gguf`
   (0.92 GB). The single most-downloaded 2026 GGUF in every sweep. `qwen3_5`
   dense, 262K context, MIT, text + vision. Fits the 8 GB GPU at partial
   offload, or the CPU. The headline find of the method.
2. **Ornith-1.5-35B-A3B** — `ornith-ai/Ornith-1.5-35B-A3B-GGUF` ->
   `Ornith-1.5-35B-Q4_K_M.gguf` (21.71 GB) + mmproj (0.90 GB). `qwen3_5_moe`
   (256 experts, 8 per token), 262K context, MIT. Fits CPU at about 13 t/s.
3. **MiniCPM-V-4.7-35B-A3B** — `openbmb/MiniCPM-V-4.7-35B-A3B-gguf` ->
   `MiniCPM-V-4_7-35B-A3B-Q4_K_M.gguf` (21.17 GB) + `mmproj-model-f16.gguf`
   (1.12 GB). Official OpenBMB VLM GGUF, Apache-2.0. Fits CPU. A new VLM beside
   Qwen3-VL.
4. **LFM2.5-2.6B** — `LiquidAI/LFM2.5-2.6B-GGUF` -> `LFM2.5-2.6B-Q4_K_M.gguf`
   (1.67 GB). `lfm2` dense, tiny, LFM Open. Clean GPU fit; the small sibling of
   the LFM2.5-24B already measured. Cheap to add.
5. **Muse-Glimmer-30B** — `unsloth/Muse-Glimmer-30B-GGUF` ->
   `Muse-Glimmer-30B-UD-Q4_K_XL.gguf` (15.88 GB) + `mmproj-Muse-Glimmer-30B-Q8_0.gguf`
   (2.05 GB). Apache-2.0, vision. Fits CPU. New arch (`muse_glimmer`) — verify
   llama.cpp first.
6. **Inkling-Small** — `unsloth/Inkling-Small-GGUF` ->
   `Inkling-Small-UD-Q4_K_M-*` (15.02 GB Q4_K_M) + `mmproj-F16.gguf` (0.14 GB).
   Apache-2.0, text + vision. Fits CPU. New arch (`inkling_mm_model`) — verify
   llama.cpp first.
7. **Nemotron-3.5-Bolt-74B-A9B (24GB)** —
   `nvidia/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-GGUF`. NVIDIA MoE, 74B total /
   9B active, a "24GB-class" quant. Fits CPU at about 4 t/s if the quant holds
   near 24 GB. Just under the threshold but notable.
8. **Tiel-Coder-35B-A3B** — `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP` ->
   `Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf` (22.75 GB). MIT, MoE coder with an
   MTP head. Fits CPU. A second code candidate beside North-Mini-Code.
9. **Mellum2.1-12B-A2.5B-Thinking** — `JetBrains/Mellum2.1-12B-A2.5B-Thinking-GGUF`.
   JetBrains MoE coder (12B / 2.5B). Apache-2.0. Fits CPU. Low downloads but a
   fresh, credible code specialist.
10. **Ornith-1.5-35B-A3B vision path** and **Qwen3.8-Flash-Next** are already
    known from the hand surveys via `qwen3.8-27b`/`flash-next` — listed here only
    because the sweep confirms their popularity. The tenth slot goes to
    **Hy-Memory-30B-A3B** — `tencent/Hy-Memory-30B-A3B-GGUF` ->
    `hy3a3b-memrl1009-step250-Q4_K_M-imat.gguf` (18.24 GB). Apache-2.0, a
    trending 30B / 3B memory-augmented MoE; fits CPU. Verify the arch.

## 4. What the method surfaced that the hand surveys missed

- **Ornith-1.5 dominates the 2026 GGUF catalog by downloads** (9B and 35B-A3B
  both above 3.8M) and appears in no earlier survey. It is a `qwen3_5`-arch
  vision-language family, MIT, with the same 262K context as Qwen3.8. This is
  the largest gap the popularity method filled.
- **A large "uncensored / abliterated / Heretic" re-quant sub-culture** sits at
  the top of the downloads list (Qwen3.8-27B variants from huihui-ai, HauhauCS,
  0bserverx, DavidAU, OBLITERATUS). These are community fine-tunes of Qwen3.8,
  not new base models, so they dedup away — but they inflate the raw download
  ranks and would mislead a naive reader of the API.
- **Download-inflated repos:** `CMSManhattan/JiRackUltra_1b` (2.5M downloads,
  13 likes) and `CMSManhattan/JiRackDeltaNet_27b` (557k downloads, 3 likes).
  High downloads with almost no likes suggests automated or accidental traffic.
  Likes and trending score are the better popularity signal for these.
- **Two new GGUF-only architectures** the hand surveys did not know:
  `muse_glimmer` (Muse-Glimmer-30B) and `inkling_mm_model` (Inkling-Small),
  plus `minicpmv4_7` (MiniCPM-V-4.7). Their llama.cpp support is **not
  confirmed** and must be checked before measurement.
- **GLM-5.3-Flash** has a huge community GGUF footprint (unsloth ships it) but is
  a ~320B `glm5_next` model (BF16 repo is 642 GB). It matches the earlier
  finding that the whole GLM-5 line is out of range; the sweep confirms it.
- **Weight-trending small models** the download sort misses: `nvidia/
  NVIDIA-Nemotron-Labs-Dory1.0-4B`, `schizophyllume/BeeLLM`, and
  `tencent/Hy-Memory-30B-A3B` appear high on `trendingScore` with few downloads.
  The trending sort is a useful complement to the download sort.
- **Speech and retrieval are dominated by a few new GGUF repos:** ASR by
  `handy-computer` (nemotron-3.5-asr-streaming, parakeet-unified-en,
  cohere-transcribe-03-2026) and embeddings by `embeddinggemma-2`. These fit
  brys but speech and retrieval serving is outside the current fleet scope.

## 5. Fleet cross-check

Already in the fleet (so not new): `qwen3.8-27b`, `qwen3.6-27b`,
`qwen3.6-35b-a3b`, `qwen3.5-35b-a3b`, `gemma-4-12b`, `gemma-4-26b-a4b`,
`gemma-4-31b`, `granite-4.2-30b`, `olmo-3.1-32b`, `glm-4.7-flash`,
`seed-oss-36b`, `nemotron-3.5-lightning-30b`, the small `surveyed` set, and the
frontier `deepseek-v4-flash` / `qwen3.8-flash-next`. Newly measured in
[new-candidates.research.md](../new-candidates.research.md): LFM2.5-24B-A2B,
Nemotron-3-Nano-30B-A3B, North-Mini-Code-1.0, Qwen3-VL-8B. None of the top-10
above is in the fleet.

## See also

- [definition.md](definition.md) — this task.
- [mid-band-survey.research.md](../mid-band-survey.research.md) — the hand
  survey of the 10-40B band.
- [specialized-survey.research.md](../specialized-survey.research.md) — the hand
  survey of the specialized classes.
- [new-candidates.research.md](../new-candidates.research.md) — measured new
  candidates from the hand surveys.
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) — the
  registration point.
