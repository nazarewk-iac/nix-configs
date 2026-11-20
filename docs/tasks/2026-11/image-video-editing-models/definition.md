---
type: Task
description: Pick the open-weight image and video editing models that fit one 32 GB R9700, decide whether they share the card with QFN or replace it, and build the serving stack that llama-swap can drive.
status: open
authored_by: agent
timestamp: 2026-11-20T15:00:00+01:00
---

# Image and video editing on the R9700

## Context

The fleet serves text, plus `qwen3-omni` for reading images and audio. Nothing edits an image or a
video. The card is one R9700 (31.86 GiB, ROCm via the shim and Vulkan), the host has 125 GiB of RAM,
and llama-swap is the front door, so a new model has to look like a llama-swap entry: a command that
serves a port.

The question this task answers: **which open-weight editors are worth running, and do they fit
beside QFN or must they evict it?**

## Shortlist, measured against this hardware

Licences first, because they eliminate more than VRAM does.

| model                                        | task                                                                             | params                            | licence                                                                | file sizes                                                                                     | verdict                                                                |
| -------------------------------------------- | -------------------------------------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| **Qwen-Image-Edit-2511**                     | instruction image editing, multi-image, text-in-image                            | 20B MMDiT + Qwen2.5-VL-7B encoder | **Apache-2.0**                                                         | Q4_K_M 13.2 GB, Q8_0 21.8 GB, FP8 20.5 GB, BF16 40.9 GB; encoder 9.38 GB (RAM, released after) | **the quality pick**                                                   |
| **LongCat-Image-Edit(-Turbo)**               | instruction editing, bilingual text                                              | 6B                                | **Apache-2.0**                                                         | ~17 GB with CPU offload; Turbo is a 10x distilled variant; ComfyUI-native since 2026-03        | **the efficiency pick**                                                |
| FLUX.1 Kontext [dev]                         | iterative single-edit fidelity                                                   | 12B                               | non-commercial                                                         | 12 GB FP8, 7 GB NF4                                                                            | licence disqualifies it for client work                                |
| FLUX.2 [dev]                                 | multi-reference, 4 MP                                                            | 32B                               | non-commercial                                                         | 4-bit on a 4090-class card                                                                     | same licence problem                                                   |
| FLUX.2 [klein] 4B                            | fast edits                                                                       | 4B                                | Apache-2.0                                                             | 6-8 GB at 4-bit                                                                                | good fallback if latency wins over fidelity                            |
| Step1X-Edit v1.2                             | reasoning-heavy edits                                                            | MLLM + DiT                        | Apache-2.0                                                             | 34 GB FP8, 18 GB with offload                                                                  | too big for the benefit                                                |
| MiniMax-H3-Image                             | 4K generation **and** editing, 16 references, 6 steps                            | 33.1B DiT + Qwen3-VL-32B encoder  | MiniMax community: **excludes the EU, UK, KR and US**, $1M revenue cap | DiT 66 GB BF16 / 13.6 GB UD-Q4; encoder 66.7 GB BF16 / 18.2 GB Q4; ~34 GB download             | **excluded: we are in the EU**, and the encoder alone is a second card |
| Z-Image / Z-Image-Edit                       | fast generation; editing variant                                                 | 6B                                | Apache-2.0                                                             | Turbo fits 16 GB                                                                               | Edit and Omni-Base are announced, **not released** as of 2026-11       |
| ERNIE-Image (8B), GLM-Image, OmniGen2, BAGEL | generation, some editing                                                         | 4-8B                              | Apache-2.0 / MIT                                                       | 9.6-23 GB                                                                                      | viable, none beats the two picks on editing benchmarks                 |
| **Wan2.1 VACE 14B**                          | video editing: subject swap, in-video replacement, outpainting, first/last frame | 14B                               | **Apache-2.0**                                                         | fp16 ~32 GB, fp8/GGUF ~16 GB                                                                   | **the video pick**                                                     |
| Wan2.2 TI2V-5B                               | text/image to video                                                              | 5B                                | Apache-2.0                                                             | 24 GB with offload                                                                             | generation, not editing; a later add                                   |
| LTX-2.5                                      | video + synchronized audio                                                       | 22B                               | LTX community (free under $10M revenue), gated                         | 32 GB minimum, int8/GGUF 13-24 GB                                                              | good, but the licence is not Apache                                    |
| HunyuanVideo-1.5                             | text/image to video                                                              | 8.3B                              | Tencent community, **excludes the EU**                                 | 14 GB with offload                                                                             | excluded: we are in the EU                                             |

Benchmarks, from the vendors' own GEdit-Bench-EN tables (read as vendor claims): LongCat-Image-Edit
reports 7.64 overall, Qwen-Image-Edit 7.56, Step1X-Edit 6.97, FLUX.1 Kontext [dev] 6.00. LongCat is
the smallest of them at 6B, and its Turbo variant claims a 10x speedup, which matters on a batch
workload where each edit already evicts QFN.

Two facts decide the fit:

- Qwen-Image-Edit at Q8_0 is **21.8 GB** plus a 9.4 GB encoder that ComfyUI loads and releases, so
  the card holds it alone. It cannot share with QFN, which wants ~30 GB.
- Wan2.1 VACE 14B at fp8 is ~16 GB; with the text encoder and activations it wants most of the card
  too.

## Decision

Three entries are staged (two image, one video), and the image pair is a choice rather than a
duplicate: Qwen-Image-Edit-2511 for quality and text-in-image work, LongCat-Image-Edit-Turbo for
iteration speed at a third of the parameters. Only one of them is enabled after the spike.

They join the **`main` set** in `data/llm.nix`, which is the frontier's set: llama-swap
evicts `qfn` for them and they for `qfn`. That is the "EITHER that or QFN" the hardware forces, and
it is the honest model: an edit is a minutes-long batch job, not a request interleaved with coding.

`qwen3-omni` stays as it is (the reserve, the gate). It reads images; these models change them.

## The serving stack

llama.cpp cannot run a diffusion model, so the entry is not a llama-server. Two candidates, both in
nixpkgs:

| option                              | why                                                                                         | why not                                                                                                                  |
| ----------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **`stable-diffusion-cpp`** (Vulkan) | no torch, no ROCm stack, same shape as llama.cpp: a GGUF on the card, a small server binary | feature lag: Qwen-Image-Edit support has to be checked against the pinned version; server API is A1111-style, not OpenAI |
| `comfyui` (ROCm torch)              | every workflow and every quant exists; Qwen-Image-Edit and VACE templates are native        | a multi-GB torch/ROCm stack on a host whose ROCm path already needs a shim, plus custom nodes and a workflow JSON to pin |

Start with `stable-diffusion-cpp` on Vulkan: it matches how llama.cpp already reaches this card, it
is one binary, and a failure there is a model-support question rather than a Python dependency
question. Fall back to ComfyUI only if the pinned sd.cpp cannot run Qwen-Image-Edit.

## Work items

1. **Prove the runtime.** Build `stable-diffusion-cpp` with Vulkan on brys, run Qwen-Image-Edit-2511
   Q8_0 (or Q4_K_M if memory is tight) through its server on `:8090`, and time one edit at
   1024×1024 with the 4-step Lightning LoRA. Acceptance: one edited image, under two minutes, card
   stays under 31 GiB.
2. **Add the entry.** `data/llm.nix` gains `qwen-image-edit` with `set = "main"`, a `command` that
   starts the sd.cpp server on `${PORT}`, and `contextSize` set to what the wrapper accepts. The
   model file lives under the persisted tree, so a second machine shares it.
3. **Video, second.** Wan2.1 VACE 14B at fp8, same path. It is a bigger download and a slower job;
   it lands only after the image editor is proven, and it may need the GGUF route.
4. **Re-measure the switch cost.** An edit request evicts QFN: measure the reload for the image model
   the way the text profiles were measured, and record it in the task's `solution.md`.

## Risks

- **ROCm/Vulkan coverage.** sd.cpp on Vulkan is the least-tested path on this card; the first spike
  is a smoke test, not a benchmark.
- **Disk.** Qwen-Image-Edit at Q8_0 plus the encoder is ~31 GB; VACE fp8 is ~16 GB. The LLM dataset
  has ~152 GB free, so both fit, but the download is a long WAN job and `wan-shaping.nix` caps it.
- **Expectation setting.** These are batch tools. A single edit is tens of seconds to minutes, and
  the card cannot serve text while it runs. That is why the entry is exclusive, not colocated.

## Follow-up

The entries are added with `enable = false` until item 1 passes, so the fleet config states the
intent without advertising a model that nothing serves yet.
