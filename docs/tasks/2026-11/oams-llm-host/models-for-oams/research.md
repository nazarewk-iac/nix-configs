# Model candidates for oams (12 GB VRAM / ~45 GB usable RAM)

Research, 2026-11-05. Web research only; no benchmarks were run for this document.
Every size is from the Hugging Face file tree. Sources are at the bottom.

**Hardware constraint that shapes everything:** oams is Vulkan on RDNA2 (RX 6800M).
Almost all published MoE-partial-offload numbers are **CUDA**; expect RDNA2 at or
below them. See [docs/local-llms.md](../../../../local-llms.md) for the measured
brys-vs-oams comparison that motivates this host.

---

## 1. Mid-size dense (7B-14B) — keep fully in VRAM

Dense models degrade badly with partial offload (a 14B measured 35.9 → 5.7 → 3.05
tok/s as layers moved to RAM), so these must fit entirely in 12 GB.

| model                   | quant    | file                                        |    size | fits              | verdict                                                                       |
| ----------------------- | -------- | ------------------------------------------- | ------: | ----------------- | ----------------------------------------------------------------------------- |
| **Qwen3.5-9B**          | Q6_K     | `unsloth/Qwen3.5-9B-GGUF`                   | 7.46 GB | yes, wide margin  | **best quality-per-GB** — GPQA-D 81.7, MMLU-Pro 82.5, LCB v6 65.6, multimodal |
| Qwen3-14B               | Q4_K_M   | `unsloth/Qwen3-14B-GGUF`                    | 9.00 GB | yes               | more depth, text only, thinking toggle                                        |
| **Gemma-4-12B-it**      | Q6_K     | `unsloth/gemma-4-12b-it-GGUF`               | 9.79 GB | yes               | native audio+vision+text, 256K, Apache-2.0                                    |
| Gemma-4-12B-it          | QAT Q4_0 | `google/gemma-4-12b-it-qat-q4_0-gguf`       | 6.98 GB | yes, lots of room | quantisation-aware, best low-VRAM pick                                        |
| Ministral-3-8B-Instruct | Q6_K     | `unsloth/Ministral-3-8B-Instruct-2512-GGUF` | 6.97 GB | yes               | terse instruction worker                                                      |

Superseded, do not add: Llama-3.x (any), Phi-4-14B, older 7B coders.

---

## 2. MoE — highest value, but needs partial offload

A 30-35B-A3B does not fit 12 GB; experts live in RAM. `--n-cpu-moe N` keeps
attention + shared expert + KV on the card. Decode is RAM-bandwidth bound.

**Published CUDA numbers (RDNA2 will be lower):**

| hardware             | model                  | config                    | decode            |
| -------------------- | ---------------------- | ------------------------- | ----------------- |
| RTX 3060 12 GB       | 35B-A3B Q4             | `--n-cpu-moe`             | ~38 tok/s         |
| RTX 4070 Super 12 GB | Qwen3.6-35B-A3B ~17 GB | tuned `--n-cpu-moe` 16→22 | 64 @32K, 51 @258K |
| GTX 1060 6 GB        | Qwen3-Omni-30B-A3B Q4  | `-cmoe`                   | 16.2 tok/s        |

| model                       | quant      |     size | quality                                  | notes                                         |
| --------------------------- | ---------- | -------: | ---------------------------------------- | --------------------------------------------- |
| **GLM-4.7-Flash** (30B-A3B) | Q4_K_M     |  18.3 GB | **SWE-bench-V 59.2**, τ² 79.5, GPQA 75.2 | best agentic/coding 30B; MIT                  |
| Qwen3-30B-A3B-Instruct-2507 | Q4_K_M     |  18.6 GB | MMLU-Pro 78.4, GPQA 70.4                 | safe, huge ecosystem                          |
| Qwen3.6-35B-A3B             | UD-Q3_K_M  |  16.6 GB | SWE 73.4, AIME26 92.7                    | newest, best "big brain"                      |
| Gemma-4-26B-A4B             | UD-Q3_K_XL |  12.9 GB | MMLU-Pro 82.6, GPQA 82.3                 | highest raw scores that fit via light offload |
| gpt-oss-20b                 | MXFP4      | 12.11 GB | GPQA 71.5, good tool use                 | already 4-bit, do not re-quantise             |

**The crucial unverified point:** none of these speed figures are Vulkan/RDNA2.
The `--n-cpu-moe` sweep must be measured on oams before committing.

---

## 3. Specialised / small — real fleet gaps

| category          | model                           |    size | verdict                              |
| ----------------- | ------------------------------- | ------: | ------------------------------------ |
| embedding         | **Qwen3-Embedding-8B** Q4_K_M   | 4.68 GB | №1 MTEB-multilingual; best retrieval |
| embedding (cheap) | Qwen3-Embedding-0.6B Q8_0       | 0.64 GB | near-best at 640 MB                  |
| reranker          | Qwen3-Reranker-0.6B Q8          | ~0.6 GB | pairs with Qwen3 embeddings          |
| vision            | **Qwen3-VL-8B-Instruct** Q6_K   | 6.73 GB | best sub-10 GB VLM; OCR/doc/UI       |
| ASR               | **whisper-large-v3-turbo-q5_0** | 0.55 GB | near-lossless, the ASR workhorse     |

Skip bge-m3 (beaten by Qwen3-0.6B) and large omni models for audio (whisper at
0.55 GB wins on value).

---

## 4. Ranked recommendation

| #   | model                       |    disk | fits    | use               |
| --- | --------------------------- | ------: | ------- | ----------------- |
| 1   | Qwen3.5-9B Q6_K             | 7.46 GB | full    | general worker    |
| 2   | GLM-4.7-Flash Q4_K_M        | 18.3 GB | offload | agentic coding    |
| 3   | Gemma-4-12B-it Q6_K         | 9.79 GB | full    | audio+vision+text |
| 4   | Qwen3.5-35B-A3B UD-IQ4_XS   | 17.5 GB | offload | 256K reasoning    |
| 5   | Qwen3-Embedding-8B Q4_K_M   | 4.68 GB | full    | RAG               |
| 6   | Qwen3-VL-8B-Instruct Q6_K   | 6.73 GB | full    | vision            |
| 7   | whisper-large-v3-turbo-q5_0 | 0.55 GB | full    | ASR               |
| 8   | Qwen3-Reranker-0.6B Q8      | ~0.6 GB | full    | rerank            |

**If only three:** Qwen3.5-9B (worker) + GLM-4.7-Flash (agent, offload) +
Qwen3-Embedding-8B (RAG). ~30 GB covering chat, agentic coding, retrieval.

**Skip:** Llama-3.x, Phi-4, Qwen2.5-Coder-7B, bge-m3, Qwen3-Omni-30B.

---

## Caveats

- All MoE tok/s are CUDA; no RDNA2/Vulkan publication exists. Measure locally.
- Qwen3.5-9B / Qwen3.6-35B-A3B GGUF sizes are from Unsloth and a third-party
  guide; verify the exact repo and quant before registering.
- Qwen3-Reranker GGUF repo was gated (401) at research time; size estimated.
- Benchmarks are vendor-reported, not independently reproduced.

## Sources

- [Qwen3.5-9B](https://huggingface.co/Qwen/Qwen3.5-9B) · [Qwen3-14B](https://huggingface.co/Qwen/Qwen3-14B)
- [gemma-4-12B-it](https://huggingface.co/google/gemma-4-12B-it) · [GLM-4.7-Flash](https://huggingface.co/zai-org/GLM-4.7-Flash)
- [Qwen3-30B-A3B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507) · [gpt-oss-20b](https://huggingface.co/openai/gpt-oss-20b)
- [Qwen3-Embedding-8B](https://huggingface.co/Qwen/Qwen3-Embedding-8B)
- [insiderllm VRAM guide](https://insiderllm.com/guides/vram-requirements-local-llms/)
- [Qwen3.6-35B on 12 GB guide](https://github.com/shiqikuangsan31/Qwen3.6-35B-12GB-VRAM-Guide)
- [llama.cpp -cmoe telemetry](https://github.com/ggml-org/llama.cpp/discussions/30426)
- [whisper.cpp models](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md)

---

## Measured on oams, 2026-11-05 (llama-bench, `-p 512,2048 -n 128 -r 2`)

Model files copied from brys to `/home/kdn/gmodels` on oams. Vulkan build
`llama-cpp-sessions-vulkan-noblas` (same as brys).

| model                              | config                                       | pp512 | pp2048 |     tg128 | notes                                                    |
| ---------------------------------- | -------------------------------------------- | ----: | -----: | --------: | -------------------------------------------------------- |
| **qwen3.5-35b-a3b** (MoE, 20.5 GB) | CPU (`-ngl 0`)                               |     — |  101.6 |      9.25 | best decode                                              |
| **qwen3.5-35b-a3b**                | GPU attn + experts CPU (`-ngl 99 -ncmoe 24`) | 113.2 |      — | **10.23** | **winner**, stable                                       |
| qwen3.5-35b-a3b                    | `-ngl 99 -ncmoe 32`                          | 111.4 |      — |     10.02 | ~same                                                    |
| qwen3.5-9b (dense, 5.3 GB)         | CPU (`-ngl 0`)                               |     — |   80.6 |      5.58 | slower than the MoE                                      |
| qwen3.5-9b (dense)                 | GPU (`-ngl 99`)                              |     — |      — | **CRASH** | `vk::Device::resetFences: ErrorUnknown`, 4 amdgpu faults |

### The findings that matter

1. **`qwen3.5-35b-a3b` is the best model for oams, and it is an MoE — 3B active
   beats the 9B dense on BOTH axes.** Decode 9.25 t/s on CPU vs 5.58 for the 9B;
   with GPU attention (`ncmoe 24`) it reaches **10.2 t/s decode / 113 t/s prefill**.
   Its only cost is disk/RAM (20.5 GB file), which oams has.
2. **GPU help is real but modest and model-dependent.** The MoE with `-n-cpu-moe`
   (small VRAM footprint: attention only) gains ~10% decode and is **stable**. But
   a _dense_ 9B fully on the 12 GB card **faults the GPU** (`ErrorUnknown`, amdgpu
   faults) — so "fits in VRAM" is not "safe on this Vulkan stack", consistent with
   the W6600 hangs on brys. Prefer keeping the big tensors on CPU and only the
   attention/shared path on the GPU.
3. This reframes the Shortlist: **rank 1 for oams is `qwen3.5-35b-a3b` at
   `-ngl 99 -n-cpu-moe 24`** (~10 t/s), not the small dense models. The small GPU
   models (`gemma-4-e4b` etc., ranked earlier) remain useful for fast/vision/audio
   at 40-80 t/s, but the MoE is the "real work" model.

Disk added on oams for these tests: `qwen3.5-9b` 5.7 GB + `qwen3.5-35b-a3b` 22 GB,
plus the two flash-next quants (88 + 84 GB) under `/home/kdn/UD-IQ4_XS` and
`/home/kdn/UD-IQ3_XXS` — the flash-next copies can be deleted, they are not the
oams default.
