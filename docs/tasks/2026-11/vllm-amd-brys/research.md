---
type: Research
description: Desk survey of vLLM, SGLang, LMDeploy, Aphrodite/Sonar and TGI on a single Radeon AI PRO R9700 (gfx1201, 32 GB) via ROCm, with measured cross-stack numbers, KV arithmetic, expected gains over llama.cpp for dense models, the 180B-MoE offload question, and the pinned-nixpkgs packaging state.
task: definition.md
authored_by: agent
timestamp: 2026-11-19T05:45:00+01:00
---

# Serving stacks on one R9700: what beats llama.cpp, and what does not

Desk research. No model was loaded, no GPU was touched, and no stack was installed. All `nix`
statements below are `nix eval` / `nix path-info` results from 2026-11-19.

Input thread: Kagi Assistant thread `8ca96912-7dc8-463b-bbc8-866c904eb773`, exported with
`kagi assistant thread export`. It is short and partly wrong; the checks are in
[The input thread](#the-input-thread).

## Answer in one page

For **one user on one R9700**, a vLLM-class stack does **not** beat llama.cpp on decode for a
dense model. It ties at best, and it loses on a bad kernel day. The gains are real but they sit
somewhere else:

| What you want                              | Winner on this card            | Size of the win                                |
| ------------------------------------------ | ------------------------------ | ---------------------------------------------- |
| Single-stream decode, dense model          | **llama.cpp Vulkan**           | vLLM is 0.8-1.0× of llama.cpp (measured range) |
| Single-stream decode, MoE with CPU experts | **llama.cpp** `--n-cpu-moe`    | no other stack can do it at all                |
| Single-stream decode with a **draft head** | **vLLM + MTP/DFlash/DSpark**   | **2-3.5×** over its own non-spec number        |
| Long-prompt prefill (4k+)                  | **vLLM** paged/chunked prefill | **2.5×** at pp4096, measured                   |
| Many concurrent agents on one model        | **vLLM / SGLang**              | 381 t/s at 16 users, measured                  |
| Repeated agent prompts (prefix reuse)      | **vLLM / SGLang** prefix cache | TTFT 9.04 s cold → 0.70 s warm, measured       |
| 180B MoE, experts in RAM                   | **llama.cpp only**             | vLLM is ~100× slower, see below                |

So the honest ranking for brys is: **vLLM with a RDNA4 fork for dense models that have a draft
head**, then **plain vLLM for long-prompt prefill and prefix reuse**, then nothing, then SGLang
and the rest. The 180B MoE stays on llama.cpp.

The one number that changes the decision: with speculative decoding on a 27B dense model, a
tuned vLLM fork reached **173.5 t/s** single-stream against **53.3 t/s** for the same fork
without it (3.25×, two cards, both measured). No llama.cpp configuration on this card has
published anything near that for a dense 27B.

## Target host

| Part       | Value                                                              | Source                                                    |
| ---------- | ------------------------------------------------------------------ | --------------------------------------------------------- |
| GPU        | 1× Radeon AI PRO R9700, 31.86 GiB, 640 GB/s, gfx1201, 300 W        | existing task, read-only                                  |
| CPU / RAM  | Ryzen 9 5950X, 16C/32T, AVX2 only; 125 GiB usable DDR4-3200        | existing task, read-only                                  |
| Link       | PCIe Gen4 **x8** (~16 GB/s theoretical, ~13 GB/s real)             | existing task, read-only                                  |
| Incumbent  | llama.cpp `llama-server` behind llama-swap, **Vulkan**             | existing task, read-only                                  |
| ROCm today | `hsa_init` fails; HIP finds no device; Vulkan is the only GPU path | `docs/tasks/2026-11/brys-r9700-model-fit/measurements.md` |

Every stack below except llama.cpp needs a working `hsa_init`. **None of them can run through
Vulkan.** There is no Vulkan backend in vLLM, SGLang, LMDeploy, Sonar/Aphrodite or TGI; they
issue HIP (or CUDA) kernels and ask the ROCm runtime for a device. Vulkan is a graphics and
compute API with its own memory model, and no Python serving stack implements a backend for it.
So the ROCm track is a hard prerequisite, not a preference.

## What each stack needs from ROCm

| Stack                    | Runs on gfx1201? (2026-11)   | What it needs from ROCm                                                                                                                                             | Practical status on brys                                                                    |
| ------------------------ | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| **vLLM**                 | **yes, officially listed**   | ROCm 6.3+; `gfx1200/gfx1201` in the arch list; rocBLAS, hipBLASLt, MIOpen, comgr, rccl; optional AITER; Triton-ROCm; a Python 3.12 ROCm wheel or the ROCm container | Best-supported option. `hsa_init` must work; AITER RMSNorm must stay off on gfx12           |
| **Radiance (vLLM fork)** | yes, built **for** this card | same as vLLM, plus ROCm 10.0, AMD Torch 2.13, Triton 3.8, AITER 0.1.26, and HIP kernels compiled for `gfx1201`                                                      | Highest measured numbers; container only; qualified topology is **two** cards               |
| **SGLang**               | **no, upstream blocks it**   | `sgl-kernel` HIP build allow-lists only `gfx942/gfx950`; AITER is CDNA-only and imported eagerly; no ROCm wheel for RDNA                                            | Needs a patched source build. Community patches exist and one W7900D user serves on gfx1100 |
| **LMDeploy**             | **not a performance path**   | ROCm PyTorch + `LMDEPLOY_TARGET_DEVICE=rocm` for the **PyTorch** engine; TurboMind is a CUDA C++ engine                                                             | Would run, slowly, with none of TurboMind's value                                           |
| **Aphrodite → Sonar**    | unknown, source build only   | ROCm PyTorch; `SONAR_TARGET_DEVICE=rocm`; supported arches follow `requirements/rocm.txt`                                                                           | Not verified on RDNA. Interesting for DSpark/DFlash draft support                           |
| **TGI**                  | **dead**                     | ROCm container supports MI210/MI250 only                                                                                                                            | Repo archived 2026-03-21, maintenance mode                                                  |

Version anchors: the official vLLM ROCm install page lists "Radeon RX 9000 series
(gfx1200/1201)" under required hardware, ships `rocm100` and `rocm721` wheels and
`vllm/vllm-openai-rocm` images, and sets `VLLM_TARGET_DEVICE=rocm` only for **source** builds —
the wheel or container already contains the ROCm backend, so no environment variable is needed
at run time. `VLLM_TARGET_DEVICE=rocm` is a _build_ switch, not a serve switch.

## What each stack is good at, and what a single user gets

| Feature                  | What it does                                  | Worth it for one interactive user?                                 |
| ------------------------ | --------------------------------------------- | ------------------------------------------------------------------ |
| Continuous batching      | packs many requests into one forward pass     | **No** at c=1. **Yes** for a fleet of agents                       |
| Paged attention          | fixes KV fragmentation, allows many sequences | Neutral at c=1; it is the enabler for batching                     |
| CUDA / HIP graphs        | removes launch overhead per step              | **Yes.** Measured: eager 22 t/s vs 33.6 t/s graphs on a 14B (1.5×) |
| Chunked prefill          | splits a long prompt into chunks              | **Yes** for long prompts: measured 2.5× at pp4096                  |
| Prefix caching           | reuses KV of a repeated prompt prefix         | **Yes** for agent loops: TTFT 9.04 s → 0.70 s                      |
| Speculative decoding     | drafts k tokens, verifies in one pass         | **Yes, the biggest lever.** Measured 3.25× at c=1                  |
| Expert / tensor parallel | splits a model over cards                     | No, one card                                                       |

The pattern is clear: the _batching_ features are wasted on one user, and the _step-cost_
features (graphs, prefill scheduling, prefix cache, speculation) are what pay.

## Measured evidence on R9700-class cards

All rows are a **single** R9700 unless the row says TP2. "MoE" and "dense" are marked because
the two behave very differently on this card.

| #   | Stack / version                 | Model, quant                                 | Decode t/s                          | Prefill t/s                      | Source               |
| --- | ------------------------------- | -------------------------------------------- | ----------------------------------- | -------------------------------- | -------------------- |
| 1   | vLLM 0.16 (ROCm 7.2.1)          | Qwen3-30B-A3B, AWQ-4bit (MoE)                | **49.3**                            | 3,370 @pp512 → **8,326** @pp4096 | field series part 12 |
| 2   | llama.cpp HIP build 764f1e6     | same 30B-A3B, UD-Q4_K_XL                     | **92.0**                            | 3,421 → 4,635 → 4,325            | field series part 12 |
| 3   | llama.cpp Vulkan (RADV coopmat) | same 30B-A3B, same GGUF                      | **167.6**                           | 3,078 → 3,675 → 3,386            | field series part 12 |
| 4   | SGLang 0.5.12 + RDNA4 patches   | Qwen3-Coder-30B-A3B, AWQ-native              | **44.3**                            | — (TTFT 489 ms)                  | field series part 6  |
| 5   | vLLM 0.16                       | dense 14B, AWQ-4bit                          | **7.5**                             | —                                | field series part 2  |
| 6   | vLLM 0.22.1                     | Qwen3-14B-**FP8**, `ROCM_AITER_UNIFIED_ATTN` | **26.5 / 33.6** (bimodal)           | —                                | TheRock #9228        |
| 7   | vLLM 0.23.0                     | gemma-4-12B FP8, `TRITON_ATTN`               | **34.2** (stable)                   | —                                | TheRock #9228        |
| 8   | vLLM 0.20.1                     | gemma-4-26B-A4B FP8 (MoE)                    | **73.9** cold → **44.6** after idle | —                                | TheRock #9228        |
| 9   | vLLM TP2                        | gemma-4-31B dense FP8                        | **13.7 / 25.8** (bimodal)           | —                                | TheRock #9228        |
| 10  | vLLM TP2                        | Qwen3.8-27B-FP8 (GDN hybrid)                 | **13.8 / 30.1** (bimodal)           | —                                | TheRock #9228        |
| 11  | Radiance vLLM 0.33 TP2          | Qwen3.8-27B Quark MXFP4, non-spec            | **53.3**                            | 4,480 @4k                        | Radiance publication |
| 12  | Radiance vLLM 0.33 TP2          | same + DFlash2 K7                            | **173.5**                           | 4,456 @4k                        | Radiance publication |
| 13  | llama.cpp Vulkan                | Qwen3.8-27B Q8_0, 2 cards                    | 28-29.7                             | 1,458                            | blog (dual card)     |
| 14  | vLLM + Radiance MXFP4, 2 cards  | Qwen3.8-27B                                  | **184.9**                           | 3,948                            | blog (dual card)     |
| 15  | llama.cpp Vulkan (brys)         | dense 27B Q4, 16.5 GB                        | **30-32**                           | —                                | brys measurements    |
| 16  | llama.cpp Vulkan (brys)         | gemma-4-31b Q4, 18.3 GB                      | **29.9**                            | **1,030.5**                      | brys measurements    |
| 17  | llama.cpp Vulkan (brys)         | Qwen3.5-35B-A3B                              | 120.7                               | —                                | brys measurements    |
| 18  | llama.cpp Vulkan (brys)         | Gemma-4-26B-A4B                              | 134.0                               | —                                | brys measurements    |
| 19  | llama.cpp Vulkan (brys)         | flash-next IQ1_S, `n-cpu-moe 26`             | 21.9                                | 38.3                             | brys measurements    |

Three things fall out of this table.

1. **On a MoE the runtime ranking reverses.** llama.cpp Vulkan is 3.4× vLLM on the same 30B-A3B
   (row 3 vs row 1) and SGLang is last (row 4). The field series' own conclusion is that vLLM's
   MoE kernels have no tuned config for RDNA4: it prints `Using default MoE kernel config.
Performance might be sub-optimal.` and a borrowed CDNA config made things 4.6× **worse**.
2. **Dense models put vLLM at 55-75 % of the memory roofline.** Qwen3-14B FP8 is ~14 GB, so the
   roofline is 640/14 = 46 t/s; vLLM delivers 26.5-33.6. gemma-4-12B FP8 is ~12 GB → roofline
   53; it delivers 34.2. llama.cpp Vulkan on brys reaches 79 % (27B Q4) and 85 % (gemma-4-31b).
   vLLM is therefore **at or below** llama.cpp on dense decode, not above it.
3. **On a fork with native WMMA kernels and a draft head, the picture changes completely.**
   Rows 11-12 are the same model, same card, same flags, only speculative decoding differs:
   53.3 → 173.5 t/s. Rows 13-14 show the same jump on a different build.

Row 5 is kept for honesty, not as the dense baseline: 7.5 t/s on a dense 14B is far below the
roofline and points at an unoptimized AWQ path in that vLLM version, not at the card. The FP8
rows (6, 7) are the fair dense comparison, and they sit at 55-75 % of the roofline.

## Expected gain versus llama.cpp for a dense 7-14B model

Method: roofline = 640 GB/s ÷ bytes of weights read per token. Then apply the measured
efficiency of each stack. Estimates are marked (E).

### Decode, one user, model fully resident

| Model (4-bit)               |        Weight bytes | Roofline |            llama.cpp Vulkan (measured or 80 % of roofline) | vLLM at 55-75 % of roofline | vLLM + draft head at ×3 |
| --------------------------- | ------------------: | -------: | ---------------------------------------------------------: | --------------------------: | ----------------------: |
| Qwen3.5-9B                  |              5.5 GB |  116 t/s |                                                **~93 (E)** |                       64-87 |        **~190-280 (E)** |
| 14B dense (Qwen3-14B class) |              8.0 GB |   80 t/s | **~64 (E)**; the FP8 build measured 26.5-33.6 at 14 GB (M) |                       44-60 |        **~130-190 (E)** |
| Qwen3.8-27B                 | 14.5 GB (AWQ/MXFP4) |   44 t/s |                               **30.7 on a 16.5 GB Q4 (M)** |                       24-33 |          **72-100 (E)** |
| gemma-4-31b                 |        18.3 GB (Q4) |   35 t/s |                                               **29.9 (M)** |                       19-26 |           **58-88 (E)** |

Read this as: **plain vLLM gives no decode win, and can lose 20-30 %.** A draft head is the only
thing that moves dense decode by a factor. It is not free: it needs a checkpoint with an MTP head
(many Qwen builds have one) or a matching DFlash/DSpark drafter, and Radiance's own docs say the
fast draft lanes fail strict output-equivalence gates (`K7` matched only 1/8 of the non-spec
fixed outputs). Treat ×3 as a _speed_ claim, not a _fidelity_ claim.

### Prefill, long prompt

| Model               |                          llama.cpp |                               vLLM |      Gain |
| ------------------- | ---------------------------------: | ---------------------------------: | --------: |
| gemma-4-31b, pp4096 |              **1,030.5 (M, brys)** | ~2,500 (E, 2.46× from row 1/row 3) | **~2.4×** |
| 30B-A3B MoE, pp4096 | 3,386 (M, Vulkan) / 4,325 (M, HIP) |                      **8,326 (M)** |  1.9-2.5× |

This is the most reliable win, because it comes from scheduling (paged/chunked prefill) rather
than from a kernel that needs per-arch tuning. For a 30k-token agent prompt, 2.4× on prefill is
several seconds of wall clock per turn.

### Throughput, many users

Measured 381 t/s aggregate at 16 users and 450-480 t/s at 23-24 users on a 30B-A3B (rows 1, 2).
llama.cpp on brys runs `parallel=1`; llama-swap swaps models instead of batching. If several
agents hit the _same_ dense model, vLLM's aggregate can pass llama.cpp's by a wide margin even
when its c=1 number is lower, because the weight read is amortised over the batch.

## Fit: what a 32 GB card holds, with KV arithmetic

Budget: **31.86 GiB VRAM**, of which ~29 GiB is usable once graphs, activations and the desktop
are paid for. Weights plus KV must fit; the linear-attention state is a **per-sequence** cost,
not a per-token one, and is easy to forget on these hybrid models.

### Formula

```
KV bytes per token  = 2 (K and V) × n_kv_heads × head_dim × bytes_per_element × n_full_layers
linear state / seq  = n_linear_layers × n_value_heads × key_head_dim × value_head_dim × 4 B
```

Cross-check against a published measurement: Qwen3-30B-A3B has 48 layers, 4 KV heads, head_dim
128, so F16 gives 2×4×128×2×48 = 98,304 B = **96 KiB/token**. The field series measured 7.7 GiB
of KV space serving ~84,000 tokens, i.e. **100 KiB/token**. The formula matches.

### Qwen3.8-27B (dense, hybrid attention)

Config: 64 layers, `full_attention_interval = 4` → **16 full-attention + 48 linear** layers;
24 query heads, **4 KV heads**, **head_dim 256**; 262,144 native context.

- KV per token = 2 × 4 × 256 × 2 B × 16 = **64 KiB/token** at F16
- linear state per sequence = 48 × 48 × 128 × 128 × 4 B = **144 MiB** (+ ~8 MiB conv state)
- weights: 16.5 GB at Q4 (measured on brys), ~14.5 GB at AWQ/MXFP4 4-bit

| Context |  KV (F16) | KV (FP8) |            Weights + KV + state | Fits 29 GiB?                            |
| ------: | --------: | -------: | ------------------------------: | --------------------------------------- |
|     32k |  2.00 GiB | 1.00 GiB | 16.5 + 2.0 + 0.15 = **18.7 GB** | yes, 10 GB spare                        |
|    128k |  8.00 GiB | 4.00 GiB | 16.5 + 8.0 + 0.15 = **24.7 GB** | yes, 4 GB spare                         |
|    262k | 16.00 GiB | 8.00 GiB |       16.5 + 16.0 = **32.7 GB** | **no** at F16; **yes** at FP8 (24.7 GB) |

So: **32k is comfortable, 128k is comfortable, 256k needs FP8 KV.** vLLM supports FP8 KV on
ROCm, and the Radiance capacity table reports exactly this shape (256K context at 2 concurrent
requests on one card's worth of weights with FP8 KV).

### gemma-4-31b (dense)

Config: 60 layers, 10 full + 50 sliding-window (window 1024); full layers use **4 global KV
heads × head_dim 512**; local layers use **16 KV heads × head_dim 256**; `attention_k_eq_v:
true` (V shares K), so only one tensor is stored.

- full layers: 4 × 512 × 2 B × 10 = **40 KiB/token** (80 KiB if the loader ignores `k_eq_v`)
- sliding layers: 16 × 256 × 2 B × 1024 × 50 = **400 MiB fixed per sequence**
- weights: 18.3 GB at Q4 (measured on brys)

| Context |                           KV | Weights + KV | Fits 29 GiB? |
| ------: | ---------------------------: | -----------: | ------------ |
|     32k |   1.25 + 0.40 = **1.65 GiB** |      20.0 GB | yes          |
|    128k |   5.00 + 0.40 = **5.40 GiB** |      23.7 GB | yes          |
|    262k | 10.00 + 0.40 = **10.40 GiB** |      28.7 GB | marginal     |

### Qwen3.5-9B (dense, hybrid attention)

Config: 32 layers, 8 full + 24 linear; 4 KV heads, head_dim 256; 32 value heads in the linear
blocks.

- KV per token = 2 × 4 × 256 × 2 B × 8 = **32 KiB/token** at F16
- linear state per sequence = 24 × 32 × 128 × 128 × 4 B = **50 MiB**
- weights: 5.5 GB at Q4, 9.5 GB at Q8

| Context | KV (F16) | Weights (Q8) + KV | Fits? |
| ------: | -------: | ----------------: | ----- |
|     32k | 1.00 GiB |           10.5 GB | yes   |
|    128k | 4.00 GiB |           13.5 GB | yes   |
|    262k | 8.00 GiB |           17.5 GB | yes   |

**Model classes that fit at a useful context:** every dense model from 4B to 31B at 4-bit, up to
128k context, with the 27B needing FP8 KV to reach 256k. A 70B dense model does not fit: 4-bit is
~40 GB before any KV.

## The 180B MoE with experts in RAM

Short answer: **none of these stacks can do it usefully. Keep llama.cpp.**

### Why vLLM's `--cpu-offload-gb` is not the same thing

`--cpu-offload-gb N` reserves N GiB per GPU in host memory and registers the offloaded weights as
a "virtual GPU" extension. The engine then **copies the offloaded weights to the device on the
forward pass that needs them**. It is layer-granular, it has no expert cache, and it has no
notion of "compute this expert on the CPU". vLLM issue #15196 ("Does vLLM support MoE model use
`--cpu-offload-gb`") was closed as _not planned_, and issue #32653 shows the mechanism still
running out of VRAM with `--cpu-offload-gb 100` on a DeepSeek-R1 MoE. A tiered expert-offload
design exists only as an RFC for Intel XPU (#63666), not for ROCm.

llama.cpp does the opposite thing: `--n-cpu-moe K` **keeps** those experts in RAM and **computes**
them with the CPU. The weights never cross the bus. That is why brys gets 21.9 t/s from a 62 GB
model on a 32 GB card.

### The arithmetic

Qwen3.8-Flash-Next `UD-IQ1_S` is 66.4 GB (measured on brys). Take ~6 GB of shared attention and
embedding weights on the card and ~30 GB of expert weights resident (the llama.cpp layout that
gives 21.9 t/s), so ~30 GB of experts must come from RAM on every token if vLLM streams them.

| Path                                        | Bytes moved per token over PCIe | Per-token time at ~13 GB/s real |                             Decode |
| ------------------------------------------- | ------------------------------: | ------------------------------: | ---------------------------------: |
| vLLM `--cpu-offload-gb`, streamed           |                          ~30 GB |                          ~2.3 s | **~0.4 t/s, and less in practice** |
| llama.cpp `--n-cpu-moe 26`, computed on CPU |         0 GB (only activations) |                          ~46 ms |            **21.9 t/s (measured)** |

That is a **50-100× gap**, in the wrong direction. Two further blockers:

- vLLM would need the model in a format whose kernels it has. vLLM lists GGUF for AMD GPUs, but
  it is a compatibility loader with a measured high time-to-first-token, not a fast quantized
  kernel path. SGLang states plainly that `gguf` is one of the quant methods that does **not**
  work on AMD. The Unsloth `UD-IQ1_S` file is GGUF-only.
- Even a perfect streaming implementation would be bounded by the Gen4 **x8** link: ~13 GB/s,
  about 1/50 of the card's 640 GB/s. Tiering only wins when the tier you stream from is close in
  bandwidth, which is why it works over RAM+CPU and fails over PCIe.

**Recommendation:** do not test a 180B MoE on vLLM. The test would burn hours and produce a
number you cannot use. Spend that time on the dense 27B + draft-head lane instead.

## NixOS packaging reality

Checked on 2026-11-19. The version queries use `nixpkgs#` (registry flake, which agrees with the
pin); the package contents were read in the local patched checkout of the pin at
`.flake.patches/nixpkgs/repo` (26.11; `319e4ceb` in `flake.lock`).

| Question                                             | Result                                                                           |
| ---------------------------------------------------- | -------------------------------------------------------------------------------- |
| `nix eval nixpkgs#vllm.version`                      | **`0.33.0`**                                                                     |
| `nix eval nixpkgs#sglang.version`                    | attribute **does not exist**                                                     |
| `nix eval nixpkgs#lmdeploy.version`                  | attribute **does not exist**                                                     |
| `nix eval nixpkgs#aphrodite-engine.version`          | attribute **does not exist**                                                     |
| `nix eval nixpkgs#text-generation-inference.version` | attribute **does not exist**                                                     |
| ROCm package-set version in the pin                  | `rocmPackages.clr` **7.2.4**                                                     |
| Does the pin build gfx1201 variants of ROCm libs?    | yes: `aotriton`, `hipblaslt`, `miopen`, `rocsolver` all list `gfx1200`/`gfx1201` |

**`nixpkgs#vllm` is a CPU-only build.** The package defaults `rocmSupport ? torch.rocmSupport`,
and `torch.rocmSupport` is false in the default package set, so `cpuSupport` is true and
`VLLM_TARGET_DEVICE=cpu`. Selecting ROCm is a _per-package override_, and the package exposes
exactly the arguments you need:

```nix
python3Packages.vllm.override {
  rocmSupport = true;                 # sets VLLM_TARGET_DEVICE=rocm, PYTORCH_ROCM_ARCH, ROCM_PATH
  gpuTargets = [ "gfx1201" ];         # wins over rocmPackages.clr.gpuTargets
  torch = python3Packages.torch.override { rocmSupport = true; };
}
```

The package file also documents the intent: `rocmOnly` dependencies (`amd-aiter`, `amd-quark`,
`amdsmi`), `makeWrapperArgs` that set `HIP_DEVICE_LIB_PATH`, and `meta.broken = cudaSupport` —
i.e. the ROCm path is the one the maintainers expect to work, and the CUDA path is the marked-broken
one.

**That override does not evaluate today.** On the same nixpkgs (registry flake `nixpkgs`, 0.33.0,
`clr` 7.2.4, identical on the relevant lines to the patched tree), a
`vllm.override { rocmSupport = true; ... }` stops with:

```
error: Refusing to evaluate package 'python3.14-tensorflow-2.21.0' ...
       - broken: This package is broken.
  trace: python3.14-vllm-0.33.0 → python3.14-outlines-1.2.12 → python3.14-tensorflow-2.21.0
```

`outlines` (a structured-output dependency) drags in a broken `tensorflow`. Any Nix route needs a
small fix first: override or drop `outlines`, or allow that broken dependency. This is a packaging
task, not a blocker on the idea.

**Closure size is large and nothing is cache-served.** `nix path-info --store
https://cache.nixos.org -S` reports that the vllm output path **does not exist in the store**, so
Hydra does not build it and every build is local. The ROCm dependencies are already big (sizes
measured from the `nixpkgs` registry closures, same major versions as the pin):

| Package                   |      Closure |
| ------------------------- | -----------: |
| `python3.14-torch` (ROCm) | **14.6 GiB** |
| `miopen-hip` 7.2.4        |      7.5 GiB |
| `rocblas` 7.2.4           |      3.4 GiB |
| `hipblaslt` 7.2.4         |      2.6 GiB |
| `clr` 7.2.4               |      0.9 GiB |

A ROCm vLLM closure is therefore **≥ 30 GiB**, before AITER's JIT cache. For a first experiment
the container is the sane route: `vllm/vllm-openai-rocm` is a published, tested image, and it
costs a pull instead of an hour of local compilation plus a multi-GiB rebuild every bump.

## Field notes and traps

These are all from first-hand reports on this exact card family. They will bite on brys.

1. **The spawn lottery.** Decode throughput on a single R9700 lands on one of two stable values
   per process start: 26.5 or 33.6 t/s on a dense 14B, 42 or 72 on a gemma-4-26B MoE, 13.8 or
   30.1 on a Qwen3.8-27B (TP2). Same image, same flags. Only a restart re-rolls it. **Measure
   each configuration several times and report the cold value before idling anything.**
2. **The idle regression.** With `cudagraph_mode=FULL_AND_PIECEWISE`, gemma-4-26B-A4B drops
   **73.9 → 44.6 t/s (−39.6 %)** after ~90 s idle and stays there until restart. `PIECEWISE` and
   `FULL` do not show it. Pin `PIECEWISE` for a long-lived server.
3. **AITER RMSNorm crashes on gfx12.** Set `VLLM_ROCM_USE_AITER_RMSNORM=0`; keep the rest of
   AITER on.
4. **gfx1201 was not enabled in the v0.22.1 image** — the reporter patched the `amdsmi` import
   and the AITER support gate. Later images and PR #43615 upstream that. Test the plain image
   first; only patch if it refuses the card.
5. **New architectures land in llama.cpp first.** `qwen3_5_moe` (the hybrid linear-attention MoE
   family) loaded in llama.cpp and was **refused** by the ROCm-navi vLLM container, which knew
   `Qwen3Next*` but not `qwen3_5_moe`. The repo's own 27B and 9B are `model_type: qwen3_5`, so
   check the loader before you plan a run.
6. **llama.cpp and vLLM do not share weights.** brys's library is GGUF. vLLM wants AWQ, GPTQ,
   FP8, MXFP4 or compressed-tensors checkpoints. Every dense-model experiment needs a second
   download, and IQ1/IQ2 GGUF has no vLLM equivalent at all.
7. **`--no-mmap` (`-lm none`) is needed for llama.cpp ROCm on this card** — without it a 27B
   loads at 19 t/s or hangs on other models. Only relevant once HIP works.
8. **A vLLM server takes 30-180 s to start** (torch.compile + graph capture). llama.cpp loads a
   27B in a few seconds. For an on-demand llama-swap fleet that is a real regression; the group
   TTL and keep-alive would have to change.

## The input thread

Kagi thread `8ca96912-7dc8-463b-bbc8-866c904eb773`, titled "vllm on a single r9700?". It
recommends Radiance, `vllm-mxfp4` and a bare-setup guide, and gives a small table. What checked
out, and what did not:

| Claim in the thread                                             | Status                                                                                  |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| vLLM runs on a single R9700, stock is slower than forks         | **holds.** Rows 5-10 vs 11-12                                                           |
| `vllm-radiance` is the easy path                                | **holds.** It is the only build with published R9700 numbers                            |
| "~50 tok/s at c=1" for a 27B                                    | **partly.** 53.3 t/s is the _non-spec TP2_ number; single-card dense is lower           |
| "scales to ~450-480 tok/s at 23-concurrency"                    | **holds, different stack.** It is the plain-vLLM 30B-A3B figure, not the 27B            |
| "stock vLLM 19 → 185 tok/s"                                     | **wrong attribution.** 19.2 t/s was _llama.cpp_ with a default build and Q8_0, not vLLM |
| "vLLM 0.23.x / ROCm 7.14 gives a ~50 % regression on one model" | **holds.** The forum thread exists; the same bimodality is in TheRock #9228             |
| `vllm-mxfp4` (GGZ14) and the "bare setup" guide                 | **unverified.** Not fetched; treat as leads                                             |
| "MXFP4 fits 32 GB comfortably"                                  | **holds** for a 27B (14.5 GB), see the KV table                                         |

The thread's real value is the pointer to Radiance and the Level1Techs report. Its numbers should
not be quoted without the model and card count attached.

## Ranked shortlist

| Rank | Stack                         | Why                                                                                 | Needs                                                             |
| ---- | ----------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| 1    | **Radiance (vLLM 0.33 fork)** | only build with measured R9700 kernels and a 3× draft-head lane                     | ROCm 10.0 + `gfx1201` + container; a draft head or DFlash drafter |
| 2    | **vLLM official ROCm image**  | upstream-listed gfx1201; best prefill, prefix cache, batching; the baseline to beat | working `hsa_init`; AWQ/FP8/MXFP4 weights                         |
| 3    | **Sonar (ex-Aphrodite)**      | vLLM-derived, ROCm source build, DSpark/DFlash/MTP drafts                           | an unproven source build on RDNA                                  |
| 4    | **SGLang**                    | good scheduler, but RDNA is blocked upstream                                        | patched `sgl-kernel` build, AITER workarounds                     |
| 5    | **LMDeploy**                  | TurboMind is CUDA; the ROCm path is the slow PyTorch engine                         | nothing to gain                                                   |
| —    | **TGI**                       | archived, MI210/250 only                                                            | do not use                                                        |

## Test plan once ROCm works

Ordered so each step is useful even if the next one fails. Run each step **three to six times**
(see the spawn lottery) and record the cold number first.

### Step 0 — prove the stack sees the card

```sh
rocminfo | grep -m1 gfx          # must print gfx1201
amd-smi version
docker run --rm --device=/dev/kfd --device=/dev/dri --group-add video \
  vllm/vllm-openai-rocm:latest --help | head -3
```

Acceptance: `gfx1201` printed and the image starts. If `hsa_init` still fails, stop; nothing
below can work.

### Step 1 — vLLM, Qwen3.8-27B, 32k context (the honest baseline)

```sh
docker run -d --name vllm-27b --network=host --ipc=host \
  --device=/dev/kfd --device=/dev/dri --group-add video \
  -v /var/lib/kdn/llms/models:/models \
  -v vllm-cache:/root/.cache/vllm \
  -e VLLM_ROCM_USE_AITER=1 \
  -e VLLM_ROCM_USE_AITER_RMSNORM=0 \
  -e ROCBLAS_USE_HIPBLASLT=1 \
  -e PYTORCH_ROCM_ARCH=gfx1201 \
  vllm/vllm-openai-rocm:latest \
  --model /models/Qwen3.8-27B-AWQ \
  --served-model-name qwen3.8-27b \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.90 \
  --kv-cache-dtype fp8 \
  --enable-prefix-caching \
  --compilation-config '{"cudagraph_mode":"PIECEWISE"}'
```

Acceptance: **decode ≥ 25 t/s** at c=1 (llama.cpp does 30-32), **prefill ≥ 1,500 t/s** at 4k
(llama.cpp does ~1,030 on gemma), warm prefix TTFT **< 1 s**. If decode is under 25, plain vLLM
loses and only step 2 is worth keeping.

```sh
# decode, one stream
python benchmarks/benchmark_serving.py --backend openai-chat --model qwen3.8-27b \
  --host 127.0.0.1 --port 8000 --dataset-name random \
  --random-input-len 256 --random-output-len 256 --num-prompts 8 --max-concurrency 1
# prefill, 4k prompt, one token out
python benchmarks/benchmark_serving.py --backend openai-chat --model qwen3.8-27b \
  --host 127.0.0.1 --port 8000 --dataset-name random \
  --random-input-len 4096 --random-output-len 1 --num-prompts 1 --max-concurrency 1
```

### Step 2 — the draft-head lane (the only large win)

Same model with an MTP head, or a matched DFlash/DSpark drafter, on the Radiance image:

```sh
docker run -d --name radiance --network=host --ipc=host \
  --device=/dev/kfd --device=/dev/dri --group-add video \
  -v /var/lib/kdn/llms/models:/models \
  -e GPU_UTIL=0.90 -e KV_MEM=0 \
  -e RADIANCE_FAST_DRAFT=1 \
  -e RADIANCE_SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":8,"attention_backend":"R4D"}' \
  magiccodingman/vllm-radiance:latest
```

Acceptance: **≥ 70 t/s** single-stream (2× the step-1 number) with outputs that still pass the
same prompts. Verify fidelity explicitly: Radiance's K7 lane matched only 1/8 strict non-spec
outputs, so run a fixed-prompt diff, not a vibe check.

### Step 3 — prefix cache, measured on the real workload

Send the same 8k-token agent system prompt twice and compare TTFT. Acceptance: second call
**≥ 5× faster** to first token (the published figure is 9.04 s → 0.70 s).

### Step 4 — only if a second card ever appears

TP2 is where the headline Radiance numbers were qualified. Do not compare a single-card result
with a TP2 table.

### What not to test

- 180B MoE on vLLM: ruled out by arithmetic, not by a missing flag.
- SGLang and LMDeploy on this card today: both need work that is not about brys.
- TGI: archived.

## Sources

1. Kagi Assistant thread `8ca96912-7dc8-463b-bbc8-866c904eb773`, "vllm on a single r9700?",
   exported 2026-11-19 with `kagi assistant thread export --format markdown`.
2. Field series, part 2 — dense 14B vs MoE 30B-A3B, 7.5 vs 51 t/s, concurrency sweep to 381 t/s:
   <https://deepindeepsea.github.io/r9700-vllm-blogs/part2-r9700-moe-and-concurrency.html>
3. Field series, part 3 — vLLM Triton 51 vs llama.cpp Vulkan 108 on the same MoE:
   <https://deepindeepsea.github.io/r9700-vllm-blogs/part3-r9700-the-vulkan-plot-twist.html>
4. Field series, part 6 — SGLang 0.5.12 + RDNA4, 44.3 t/s c=1, 234 t/s at N=8, TTFT cliff at
   N=16, and the three-way verdict:
   <https://deepindeepsea.github.io/r9700-vllm-blogs/part6-r9700-sglang-bench-and-verdict.html>
5. Field series, part 12 — the full sweep: vLLM prefill 3,370/7,089/8,326, HIP 92.0 decode,
   Vulkan 167.6 decode, with exact commands and environment:
   <https://deepindeepsea.github.io/r9700-vllm-blogs/part12-r9700-the-full-sweep.html>
6. Field series, part 13 — `qwen3_5_moe` refused by the ROCm-navi vLLM container; llama.cpp HIP
   78.5 decode / 2,752 prefill:
   <https://deepindeepsea.github.io/r9700-vllm-blogs/part13-r9700-the-35b-only-one-runtime-could-load.html>
7. Alex K. Miller, "From 19 to 185 tokens per second" (2× R9700, Qwen3.8-27B Q8_0 then
   Radiance MXFP4; `-lm none` fix; 184.9 gen / 3,948 prefill):
   <https://alexkmiller.com/blog/2026/09/07/dual-r9700-llama-cpp-and-vllm.html>
8. vLLM installation docs, ROCm section — supported GPU list including gfx1200/1201, ROCm 6.3+,
   `rocm100`/`rocm721` wheels, `VLLM_TARGET_DEVICE=rocm` for source builds:
   <https://docs.vllm.ai/en/latest/getting_started/installation/gpu.html>
9. vLLM optimization docs (2026-11-12) — extensible KV cache, `gpu_memory_utilization` default
   1.0 on ROCm, cudagraph modes, chunked prefill on by default:
   <https://docs.vllm.ai/en/latest/configuration/optimization.html>
10. vLLM engine arguments — `--cpu-offload-gb` "space in GiB to offload to CPU, per GPU":
    <https://docs.vllm.ai/en/stable/configuration/engine_args/>
11. vLLM issue #15196 — "Does vLLM support MoE model use `--cpu-offload-gb`", closed not planned:
    <https://github.com/vllm-project/vllm/issues/15196>
12. vLLM issue #32653 — CPU offload still OOMs on a DeepSeek-R1 MoE with `--cpu-offload-gb 100`:
    <https://github.com/vllm-project/vllm/issues/32653>
13. vLLM RFC #63666 — tiered MoE expert offload, single-GPU **Intel XPU** only:
    <https://github.com/vllm-project/vllm/issues/63666>
14. vLLM quantization docs — per-backend hardware table (GGUF listed for AMD GPUs):
    <https://docs.vllm.ai/en/latest/features/quantization/>
15. ROCm/TheRock issue #9228 — R9700 bimodal decode, 26.5/33.6 t/s on a 14B, 34.2 on
    gemma-4-12B, 73.9→44.6 idle regression on gemma-4-26B-A4B, 13.7/25.8 on gemma-4-31B,
    13.8/30.1 on Qwen3.8-27B TP2, eager 22 t/s, VRAM R/W correlation, AITER RMSNorm crash on
    gfx12, gfx1201 not enabled in v0.22.1:
    <https://github.com/ROCm/TheRock/issues/9228>
16. SGLang issue #30599 — RDNA3/RDNA4 not officially supported, `setup_rocm.py` allow-list,
    CDNA-only AITER, no ROCm wheel, W7900D 22.79 t/s on Qwen3-8B BF16 at c=1:
    <https://github.com/sgl-project/sglang/issues/30599>
17. SGLang AMD install docs — source build with `python[all_hip]`, `sgl-kernel/setup_rocm.py`,
    quantization matrix with `gguf` unsupported on AMD:
    <https://docs.sglang.io/docs/hardware-platforms/amd_gpu.md>
18. TGI repository — archived 2026-03-21, maintenance mode, ROCm container for MI210/MI250:
    <https://github.com/huggingface/text-generation-inference>
19. Sonar (ex-Aphrodite Engine) — vLLM-derived, AGPL-3.0, ROCm source build with
    `SONAR_TARGET_DEVICE=rocm`, DSpark/DFlash/MTP drafts:
    <https://sonar.dphn.ai/getting-started/installation/> and
    <https://github.com/dphnAI/sonar>
20. LMDeploy installation docs — `LMDEPLOY_TARGET_DEVICE=rocm pip install git+...`:
    <https://lmdeploy.readthedocs.io/en/latest/get_started/installation.html>
21. Radiance (R9700 vLLM fork) — vLLM 0.33.0, ROCm 10.0, TP2 qualification, non-spec 53.3 vs
    DFlash2 K7 173.5 t/s at c=1, prefix-cache TTFT 9.04 s → 0.70 s, capacity tables:
    <https://github.com/magiccodingman/vllm-radiance>
22. Level1Techs — "vLLM 0.23.x / ROCm 7.14 upgrade on 4× Radeon AI PRO R9700: ~50 % regression on
    one model … a free +9 % via kernel tuning":
    <https://forum.level1techs.com/t/253460>
23. Hugging Face configs used for the KV arithmetic:
    `Qwen/Qwen3.8-27B`, `google/gemma-4-31b`, `Qwen/Qwen3.5-9B` (raw `config.json`).
24. brys measurements, read-only from
    `docs/tasks/2026-11/brys-r9700-model-fit/measurements.md`: dense 27B 30-32 t/s, gemma-4-31b
    29.9 t/s / 1,030.5 prefill, 35B-A3B 120.7, gemma-4-26B-A4B 134.0, flash-next 21.9 at 64k,
    and the `hsa_init` failure.
25. `nix` checks run 2026-11-19: `nixpkgs#vllm.version` = `0.33.0`; `sglang`, `lmdeploy`,
    `aphrodite-engine`, `text-generation-inference` absent; `rocmPackages.clr` 7.2.4; closure
    sizes for `torch` (ROCm) 14.6 GiB, `miopen-hip` 7.5 GiB, `rocblas` 3.4 GiB, `hipblaslt`
    2.6 GiB, `clr` 0.9 GiB; `vllm` output path absent from `cache.nixos.org`; the
    `outlines` → `tensorflow` broken-package eval error.
26. vLLM quantization guide with measurements — "the GGUF format has significant overhead in
    vLLM" and a high TTFT on a GGUF model:
    <https://jarvislabs.ai/blog/vllm-quantization-complete-guide-benchmarks>
