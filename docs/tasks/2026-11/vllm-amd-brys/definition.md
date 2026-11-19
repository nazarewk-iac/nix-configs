---
type: Task
description: Decide whether a vLLM-class serving stack (vLLM, SGLang, LMDeploy, Aphrodite/Sonar, TGI or a RDNA4 fork) beats llama.cpp on one R9700 for dense models, and whether any of them can serve the 180B MoE with experts in RAM.
status: open
authored_by: agent
timestamp: 2026-11-19T05:50:00+01:00
---

# vLLM-class serving on one R9700: is it worth it

## Context

- **brys** has one Radeon AI PRO R9700 (gfx1201, 31.86 GiB, 640 GB/s, PCIe Gen4 **x8**) and
  125 GiB of RAM. llama.cpp Vulkan serves a 180B MoE at 22 t/s (`--n-cpu-moe 26`, 64k) and small
  dense models at 90-324 t/s.
- The owner asked two questions:
  1. Does a stack with better batching and attention kernels beat llama.cpp on this card,
     **especially for smaller non-MoE models that fit fully in 32 GB**?
  2. Can any of them serve a large MoE with experts in RAM?
- `hsa_init` fails on brys today, so **no HIP stack can run yet**. That is a separate track. This
  task is desk research plus `nix eval` checks; no model was loaded and the GPU was not touched.
- Every published R9700 number used here is a single card unless it says TP2. Published dual-card
  numbers are a ceiling, not a target.

## Goal

1. State which of these stacks work on gfx1201 through ROCm in late 2026, and what each needs.
2. Say what a single interactive user actually gains, with numbers and sources.
3. Give the fit arithmetic for 32 GB, including the KV cost of at least one concrete model.
4. Settle the 180B-MoE-with-RAM-experts question.
5. Record the pinned-nixpkgs state and the closure cost.
6. Rank what to test on brys once ROCm works, with exact commands.

## Findings

Full analysis, comparison table, KV arithmetic and sources: [research.md](research.md).
Input thread: Kagi Assistant `8ca96912-7dc8-463b-bbc8-866c904eb773`, exported 2026-11-19.

### Ranked shortlist

| Rank | Stack                          | Works on gfx1201?            | What it needs from ROCm                                                      | Expected gain, dense single user                                            |
| ---- | ------------------------------ | ---------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 1    | **Radiance (vLLM 0.33 fork)**  | yes, built for this card     | ROCm 10.0 + `gfx1201` kernels, AITER, HIP graphs; container only             | **2-3.5× with a draft head** (measured 53.3 → 173.5 t/s, TP2); 1.0× without |
| 2    | **vLLM (official ROCm image)** | yes, officially listed       | working `hsa_init`; rocBLAS/hipBLASLt/MIOpen; Python 3.12 wheel or container | **0.8-1.0× decode**, **2.4× prefill**, prefix TTFT 9 s → 0.7 s              |
| 3    | **Sonar (ex-Aphrodite)**       | unverified, source build     | ROCm PyTorch, `SONAR_TARGET_DEVICE=rocm`, `gfx1201` build                    | unknown; its DSpark/DFlash drafts are the interesting part                  |
| 4    | **SGLang**                     | **no**, upstream blocks RDNA | patched `sgl-kernel` build for the arch; AITER is CDNA-only                  | −10 % on MoE today (44.3 vs 49.3 vLLM, 108 llama.cpp)                       |
| 5    | **LMDeploy**                   | PyTorch engine only          | ROCm PyTorch; TurboMind is CUDA                                              | nothing — the fast engine does not exist here                               |
| —    | **TGI**                        | no                           | ROCm container is MI210/MI250 only                                           | archived 2026-03-21, do not use                                             |

### The four numbers that decide it

- **Dense decode does not improve.** vLLM reaches 55-75 % of the 640 GB/s roofline on this card;
  llama.cpp Vulkan reaches 79-85 %. For Qwen3.8-27B that is 24-33 t/s versus a measured 30-32 t/s.
  Plain vLLM ties or loses.
- **Speculative decoding is the only large win.** The same fork, same model, same flags: 53.3 t/s
  non-spec versus 173.5 t/s with DFlash2 K7. It needs a checkpoint with an MTP head or a matched
  drafter, and the fast lanes do not pass strict output-equivalence gates.
- **Prefill and prefix reuse are real.** 8,326 t/s against 3,386 t/s at pp4096 (2.5×), and
  9.04 s → 0.70 s TTFT on a repeated 32k prefix.
- **The 180B MoE stays on llama.cpp.** `--cpu-offload-gb` _copies_ offloaded weights over PCIe on
  every step (~0.3 t/s); `--n-cpu-moe` _computes_ them on the CPU (21.9 t/s measured). A 50-100×
  gap, and it does not close.

### Fit on 32 GB, with KV arithmetic

| Model (4-bit) |            Weights |                      KV at F16 | Context that fits                     | Note                                         |
| ------------- | -----------------: | -----------------------------: | ------------------------------------- | -------------------------------------------- |
| Qwen3.8-27B   |            16.5 GB | **64 KiB/token** + 152 MiB/seq | 128k (24.7 GB); 256k only with FP8 KV | 16 full + 48 linear layers, 4 KV heads × 256 |
| gemma-4-31b   |            18.3 GB |     40 KiB/token + 400 MiB/seq | 128k (23.7 GB)                        | 10 full + 50 sliding (1024) layers, `k_eq_v` |
| Qwen3.5-9B    | 5.5 GB Q4 / 9.5 Q8 |      32 KiB/token + 50 MiB/seq | 256k (17.5 GB at Q8)                  | 8 full + 24 linear layers                    |

So 4B-31B dense models fit at 4-bit up to 128k context. A 70B dense model does not fit at all.
The linear-attention state is a **per-sequence** cost, not per-token, and must be counted for
concurrency.

### NixOS packaging

- `nixpkgs#vllm.version` = **0.33.0**; `sglang`, `lmdeploy`, `aphrodite-engine` and
  `text-generation-inference` are **absent** from the pin.
- `nixpkgs#vllm` is a **CPU-only** build. ROCm needs a per-package override, which the package
  supports (`rocmSupport`, `gpuTargets = [ "gfx1201" ]`, a ROCm `torch`).
- That override **does not evaluate today**: `outlines` pulls
  `python3.14-tensorflow-2.21.0`, which is marked broken. A small override fixes it.
- The closure is **≥ 30 GiB** (ROCm torch alone is 14.6 GiB) and the vllm path is **not in
  `cache.nixos.org`**, so every build is local. For the first experiment, use the container.

## Proposed approach

1. Wait for the ROCm track to fix `hsa_init`. Nothing here can run before that.
2. Run the container experiments in the order given in [research.md](research.md#test-plan-once-rocm-works):
   vLLM baseline on Qwen3.8-27B, then the Radiance draft-head lane, then prefix-cache timing.
3. Only if steps 1-2 justify it, package vLLM for brys: override `rocmSupport`, `gpuTargets` and
   the broken `outlines` dependency, and measure the real closure with `nix path-info -Sh`.
4. Keep the 180B MoE on llama.cpp. Do not spend a run on vLLM offload.

## Acceptance test

1. Three cold measurements per configuration, because decode on this card is bimodal per process
   start (26.5 or 33.6 t/s on a 14B). Report the cold value before any idle period.
2. Step 1 passes only if decode is **≥ 25 t/s**, prefill **≥ 1,500 t/s** at 4k, and a warm prefix
   gives TTFT **< 1 s** on Qwen3.8-27B at 32k.
3. Step 2 passes only if single-stream decode is **≥ 70 t/s** _and_ a fixed-prompt diff against
   the step-1 output shows no quality collapse.
4. Every row carries the card count. A single-card result is never compared with a TP2 table.

## Risks and open questions

- **`hsa_init` is unsolved.** The whole task is blocked on it. HIP found no device even as root.
- **The spawn lottery and the idle regression** make single measurements meaningless: one
  configuration lost 40 % after 90 s idle and only a restart recovered it. Pin
  `cudagraph_mode=PIECEWISE`.
- **Weights are not shared.** brys's library is GGUF; vLLM wants AWQ/FP8/MXFP4 checkpoints. Each
  dense experiment needs a second download, and the 1-bit MoE quants have no vLLM equivalent.
- **New architectures land in llama.cpp first.** `qwen3_5_moe` loaded in llama.cpp and was refused
  by the ROCm vLLM container. The repo's 27B and 9B are both `model_type: qwen3_5`.
- **Draft-head fidelity is unproven.** The fastest Radiance lane matched only 1/8 strict
  non-spec outputs. Speed without a fidelity gate is not a result.
- **PCIe Gen4 x8** halves the link that published R9700 rigs use. Anything that streams weights
  will look worse on brys than in the sources.
- **Startup cost.** A vLLM server needs 30-180 s to compile and capture graphs. For an on-demand
  llama-swap fleet that changes the keep-alive and TTL design.

## Related

- [research.md](research.md) — the survey, comparison table, KV math, field notes, sources.
- `docs/tasks/2026-11/brys-r9700-model-fit/` — measured llama.cpp numbers on the same card, the
  ROCm `hsa_init` failure, and the model-fit frontier. Read-only for this task.
- `docs/tasks/2026-10/llm-benchmark-suite/003-runner-eval/` — the earlier engine survey for the
  8 GB card.
