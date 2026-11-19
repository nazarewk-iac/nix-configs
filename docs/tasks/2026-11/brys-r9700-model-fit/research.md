---
type: Research
description: Desk survey of model families and inference engines that fit one Radeon AI PRO R9700 (32 GB) plus 128 GB DDR4 on host brys, with fit arithmetic, single-card speed estimates and sources.
task: ../definition.md
authored_by: agent
timestamp: 2026-11-18T12:00:00+01:00
---

# What fits on brys with one R9700

Desk research only. No model was loaded on brys; another session owns the host.

## Target host

| Part | Value |
| --- | --- |
| CPU | Ryzen 9 5950X, 16C/32T, AVX2, no AVX-512 |
| RAM | 128 GB DDR4-3200 ECC (125 GiB usable); COPY 39.8 GB/s, TRIAD 27.9 GB/s measured |
| GPU | 1× Radeon AI PRO R9700, 31.86 GiB, 640 GB/s, 300 W, gfx1201 |
| Link | PCIe Gen4 **x8** (~16 GB/s), half of the x16 the published test rigs use |
| Disk | ZFS mirror, ~793 GB free on the model dataset |
| Incumbent | llama.cpp `llama-server` behind llama-swap, Vulkan, pinned to `1002:7551` |

**No second card is planned.** Every published two-card number is out of scope; it is a ceiling,
not a target.

## Memory arithmetic

> **Corrected 2026-11-18 by measurement.** The model is **125B parameters plus a 51B n-gram table** (48 layers, 512
> experts, top-10, 262k native context), not the ~125B the first draft assumed. The real Unsloth
> sizes are UD-IQ1_S 66.4 GB, UD-IQ2_XS 75.8, UD-IQ3_XXS 83.6, UD-IQ4_XS 104.6, UD-Q4_K_XL 111.3,
> Q8_0 188.2 GB. The earlier "IQ2_XS 39.2 GB / IQ3_XXS 47 GB" numbers came from a different quant
> family and are wrong for this repo. See [measurements.md](measurements.md) for the measured
> throughput.

- Combined budget: **31.86 GiB VRAM + 125 GiB RAM ≈ 157 GB**.
- Strata sizes the resident arena from available RAM and needs `experts + ~10 GB`. With 125 GiB
  usable, the Unsloth sizes up to `UD-Q4_K_XL` (111 GB) fit in RAM and `Q8_0` (188 GB) does not.
- With 32 GB of VRAM, llama.cpp holds about **4-5 GB of dense weights plus ~28 GB of expert cache**.
  On a 125B model with 512 experts per layer, that is roughly 40 of 48 layers' experts. On oams
  (12 GB) the same model ran 40.6 t/s with a much smaller cache; the larger cache is the main reason
  the R9700 is faster.
- Maya tiers experts across VRAM, RAM and NVMe. With 157 GB combined it can hold the whole
  `Maya-S` set (96.5 GB) in memory, so the SSD tier is not used.

## Engine survey

| Engine | License | Models | AMD / R9700 | Fit for brys | Note |
| --- | --- | --- | --- | --- | --- |
| **Strata** | MIT | Qwen3.8-Flash-Next (ISTA/Unsloth/Gyro/Swift/Coder) | **native**, `rx9070` package covers gfx1200/1201 | **best** | expert cache + CPU compute + SSD n-gram table; MTP decoding |
| **Project Maya** | MIT | GLM-5.3-Flash 321B, GLM-5.3 744B, DeepSeek-V4.1-Flash 748B, MiniMax-M3.1-Flash 428B | experimental (R9700 listed) | **strong second** | fork of the Strata lineage; own quants Maya-XS/S/S24/M/L |
| **BigMoeOnEdge** | Apache-2.0 | **any MoE GGUF**, any quant | **HIP + Vulkan**, tested on a 192 GB AMD card | **new candidate** | tiers VRAM → RAM → flash, `--auto` planner, OpenAI + Anthropic API. 24 GB + 96 GB RAM measured **70 t/s** on flash-next; 2×16 GB + 60 GB → 41–48 t/s |
| **llama.cpp / ik_llama.cpp** | MIT | any GGUF | Vulkan works today | **baseline** | `--n-cpu-moe`, `-ot`; dense models fit VRAM fully |
| **tandem.cpp** | MIT (patch) | GGUF MoE | Linux, AMD with caveats | experiment | CPU computes some misses while others upload; no CUDA-style VRAM borrowing on ROCm |
| **DwarfStar 4 (ds4)** | source-available | DS4Flash, GLM 5, Qwen3.8 (own GGUFs only) | **Strix Halo ROCm only** listed | watch | antirez's C engine; 128 GB runs DS4Flash Q2 81 GiB, Qwen3.8 Q4; 34 t/s on an M5 Max |
| **Xolotl** | MIT | DS4.1, GLM-5.3-Flash, Qwen3.8, LFM3-Omni | CUDA-first (RTX 4090 reference) | unlikely | 33 t/s on a 4090 + 110 GB RAM; AMD path not documented |
| **FreeToken** | research | large MoE | NVIDIA-first | no evidence | bandwidth-adaptive CPU/GPU co-execution; v0.2.1 |
| **MoE-Infinity** | Apache-2.0 | MoE, HF format | CUDA | no | PyTorch serving stack, expert cache + SSD |
| **KTransformers** | Apache-2.0 | 671B-class MoE | CUDA + CPU | weak | needs AMX or AVX-512; the 5950X has neither |
| **fiddler** | research | Mixtral-class | PyTorch CUDA | no | "slow if your CPU does not support AVX-512" |
| **Ostinato** | research | DS4 / Qwen3-235B | CUDA test rigs | watch | resident experts; folds into llama.cpp |
| **vLLM / SGLang** | Apache-2.0 | any | ROCm is first-class on Instinct, experimental on Radeon | poor | GPU-resident; 32 GB caps the model size |
| **ExLlamaV2/V3** | MIT | EXL2 | NVIDIA only | no | — |
| **AirLLM / Promethevs** | mixed | huge models | varies | capacity-only | "runs" is not "usable"; no matched benchmarks |
| **halogen-flash-server / gufo / strixite / CIRU / EngramHalo / q38rocm** | various | flash-next | **Strix Halo (gfx1151) only** | no | one model, one silicon; excellent numbers on that APU, no RDNA4 path |
| **ninfer** | — | closed Qwen list | one 5090 | no | no offload |

The lineage matters: llama.cpp → Strata (hybrid fork, flash-next only) → **Maya** (fork of that
lineage, different model families and its own quants). Maya is the only engine besides Strata that
is built for a single consumer card with tiered experts, and it is the only realistic route to a
321B model on this box.

## Model fit, ranked

> **Superseded by measurement on 2026-11-18.** The table below is the desk estimate, kept for the
> reasoning. [measurements.md](measurements.md) has the measured numbers; several entries here are
> wrong for this model: Flash-Next is **125B + 51B n-gram**, its real `UD-IQ1_S` is 66 GB, and llama.cpp (not
> Strata) is the harness that was actually measured. The measured shortlist is
> **`UD-IQ1_S` at `--n-cpu-moe 26`, 64k context, 22 t/s, plus `qwen3.5-4b` co-resident**.

Estimates were extrapolated from the measured oams run (12 GB card, 40.6 t/s on IQ2_XS) and the
published single-card DS4.1 number (1× R9700, 251 GB RAM, 21–25 t/s).

| # | Model | Engine | Need | Decode estimate | Measured |
| --- | --- | --- | --- | --- | --- |
| 1 | Flash-Next **IQ2_XS** | Strata | 39.2 GB | 50–80 t/s | **not measured**: the quant family is not the Unsloth one; `UD-IQ1_S` did **21.9 t/s** |
| 2 | Flash-Next **Coder IQ1_M** | Strata | 32 GB | 50–80 t/s | not measured on brys |
| 3 | Flash-Next **IQ3_XXS** | Strata | 47.0 GB | 35–55 t/s | not downloaded on brys |
| 4 | **GLM-5.3-Flash 321B Maya-S** | Maya | 96.5 GB | 20–30 t/s | `UD-IQ2_XXS` on llama.cpp: **8.9 t/s** (CPU-bound) |
| 5 | Flash-Next **UD-Q4_K_XL** | Strata | 111 GB RAM | 20–35 t/s | not measured |
| 6 | Dense **27–35B Q4** | llama.cpp Vulkan | 17–23 GB VRAM | 25–40 t/s | **27–32 t/s** |
| 7 | **Qwen3.6-35B-A3B Q4** | llama.cpp Vulkan | 20.6 GB VRAM | 100+ t/s | **121.9 t/s** |
| 8 | **DeepSeek-V4.1-Flash 1.75 bpw** | Maya / Strata | 233 GB | 3–10 t/s | **no**: exceeds 157 GB combined |
| 9 | Flash-Next **Q8_0** | Strata | 188 GB RAM | — | **no**: exceeds RAM |

### What the measurement changed

- llama.cpp with `--n-cpu-moe` is the harness that was measured, not Strata. It is already pinned
  to `1002:7551`, it serves through llama-swap today, and it needed no new package.
- The VRAM expert cache is the lever, and it works: `n-cpu-moe 26` at 64k holds 19.8 GiB and gives
  **22 t/s**. Going below 6 overcommits the card and the decode collapses.
- Strata remains untested on brys: it is an AppImage/Terminal install, and its `rx9070` engine
  package was never fetched here. Treat its oams numbers (40.6 t/s on a 12 GB card) as the target
  to beat, not a result.

### Why Maya is the interesting unknown

- GLM-5.3-Flash is **321B with about 18B active** and a 1M context. That is a class above
  flash-next, and `Maya-S` fits entirely in 157 GB of memory.
- All published R9700 numbers are **two cards** (44 t/s at 256K). **Measured on one card: 8.9 t/s
  decode, 14.3 t/s prefill** (llama.cpp, `UD-IQ2_XXS`, `n-cpu-moe 36`, 16 threads). The estimate of
  20–30 t/s was wrong by 2-3x: GLM-5.3-Flash is bound by the CPU computing the RAM-resident
  experts, not by VRAM or the link.
- AMD is **experimental**. Expect setup friction and check the AMD doc before the run.

### BigMoeOnEdge: the generic alternative

Strata and Maya each serve a fixed model list. **BigMoeOnEdge** does not: it streams any MoE GGUF,
in any quantization, and it uses llama.cpp's public API for formats, tokenizers and chat templates.

- **Tiers:** VRAM holds the always-read weights and the hot experts; RAM caches the rest; flash holds
  the whole model. An expert missing from VRAM is copied from RAM; one missing from RAM is read from
  disk.
- **Planner:** `--auto` measures the machine, then picks cache size, threads and which device does
  prefill versus decode. It re-measures after the first answer and keeps the faster plan.
- **Backends:** CPU, Metal, CUDA, **HIP**, **Vulkan**, OpenCL, Hexagon NPU. Linux is listed with
  Vulkan, CUDA and HIP; tested on 12–24 GB NVIDIA cards and a 192 GB AMD card.
- **Measured flash-next:** 24 GB + 96 GB RAM → **70 t/s**; 8 GB + 31 GB → 16 t/s; 2×16 GB + 60 GB
  → 41–48 t/s. A 32 GB + 128 GB box sits above the best measured row.
- **API:** OpenAI and Anthropic compatible, plus `service install` for systemd.

Why it matters here: one engine could serve flash-next, Qwen3.6-35B-A3B, a dense 27B and the
DeepSeek/GLM GGUFs, instead of one engine per model family. Risk: young project, and no RDNA4
report — "tested on AMD" means a 192 GB card, not a R9700.

### What to skip

- **DeepSeek V4.1-Flash** on this box: 191–239 GB of weights against 157 GB of memory means SSD
  streaming on every miss, and the only published single-card number assumes 251 GB of RAM.
- **Xolotl** until its AMD path is documented; the reference is CUDA.
- **KTransformers** on a 5950X: the AMX/AVX-512 kernels that make it win do not run here.
- **vLLM/SGLang** for a 100B+ model on 32 GB: they want the model resident.

## The link is the other half of the story

The card sits in a **Gen4 x8** slot (~16 GB/s). Strata and Maya both move expert rows over PCIe
when the cache misses. The published R9700 rigs use x16. Expect the brys numbers to trail those
rigs by more than the card alone would suggest, especially on prefill and on long prompts.

## Measurement tags

Use these in every table row so old and new numbers never mix:

- `gpu-w6600` — Radeon Pro W6600, 8 GB, gfx1032, all rows before 2026-11-17.
- `gpu-r9700` — Radeon AI PRO R9700, 32 GB, gfx1201, new rows.
- `gpu-rx6800m` — RX 6800M, 12 GB, gfx1031, oams.
- `cpu` — no GPU.
- `engine=llamacpp|strata|maya|ik-llamacpp|tandem` — engine tag.

## Two cards: what a second R9700 would unlock

The user has one card and does not plan a second. This section records what changes if one is
added later, so the decision is documented rather than re-derived.

**Hardware effect:** 2 × 31.86 GiB = **63.7 GiB VRAM**, with the same 125 GiB RAM → **~189 GB
combined**. The second card replaces the Lexa in `PCIEX16_2`, so both cards get Gen4 **x8**. Power
rises to ~600 W for the cards, and a 850–1000 W PSU is then required.

**What changes:** the expert cache doubles from ~28 GB to ~60 GB, which holds almost every expert
of flash-next. Decode then runs mostly from VRAM and the DDR4 floor matters only for the tail. The
same effect lets much larger quants stay resident, and lets the 700B-class Maya models keep their
whole set in memory instead of streaming from the SSD.

`M` = measured (Maya community runs, 2× R9700), `E` = estimate. Single-card estimates are the
same ranges as the ranked table above.

| Model / quant | Weights | Engine | 1× R9700 (32 GB) | 2× R9700 (64 GB) | Limiter |
| --- | ---: | --- | --- | --- | --- |
| Qwen3.6-35B-A3B Q4 | 22.9 GB | llama.cpp / Strata | 100+ t/s | 100+ t/s | card only |
| Dense 27–35B Q4 | 17–23 GB | llama.cpp Vulkan | 25–40 (E) | 25–40 (E) | card only |
| Flash-Next Gyro-S | 27.6 GB | Strata | 50–80 (E) | 80–120 (E) | DDR4 tail |
| Flash-Next Coder IQ1_M | 32 GB | Strata | 50–80 (E) | 80–120 (E) | DDR4 tail |
| Flash-Next Q2_0 | 37.6 GB | Strata | 55–85 (E) | 85–125 (E) | DDR4 tail |
| Flash-Next IQ2_XS | 39.2 GB | Strata | 50–80 (E) | 80–120 (E) | DDR4 tail |
| Flash-Next IQ3_XXS / Swift | 47.0 GB | Strata | 35–55 (E) | 60–90 (E) | DDR4 |
| Flash-Next IQ3_S | 54.8 GB | Strata | 30–45 (E) | 50–75 (E) | DDR4 |
| Gyro-M | 35 GB | Strata | 35–55 (E) | 60–90 (E) | DDR4 |
| GLM-5.3-Flash **Maya-XS** | 73.4 GB | Maya | 25–35 (E) | 50–60 (E) | DDR4 |
| Unsloth **UD-IQ4_XS** | 72 GB | Strata | 30–50 (E) | 50–75 (E) | DDR4 |
| Unsloth **UD-Q4_K_XL** | 88 GB | Strata | 20–35 (E) | 40–60 (E) | DDR4 |
| GLM-5.3-Flash **Maya-S24** | 94.7 GB | Maya | 20–30 (E) | **44.1 (M)** | DDR4 |
| GLM-5.3-Flash **Maya-S** | 96.5 GB | Maya | 20–30 (E) | **45.2 (M)** | DDR4 |
| Unsloth **UD-Q5_K_XL** | 108 GB | Strata | 15–25 (E) | 30–45 (E) | DDR4 |
| GLM-5.3-Flash **Maya-M** | 116 GB | Maya | 15–25 (E) | **44.4 (M)** | DDR4 |
| Unsloth **UD-Q6_K_XL** | 118 GB | Strata | 12–20 (E) | 25–40 (E) | RAM |
| Flash-Next **Q8_0** | 136 GB | Strata | **no** | 20–35 (E) | RAM |
| GLM-5.3-Flash **Maya-L** | 156.3 GB | Maya | **no** | 20–35 (E) | RAM |
| GLM-5.3 (744B), max Maya-XS | ~150–250 GB | Maya | **no** | SSD at best | SSD |
| DeepSeek-V4.1-Flash 1.75 bpw | 239 GB | Maya / Strata | SSD, 3–10 (E) | SSD, 30–50 (E) | SSD |
| DeepSeek-V4.1-Flash 2.25 bpw | 274 GB | Maya | **no** | SSD, 25–40 (E) | SSD |

**The one-card vs two-card line in one sentence:** a second card does not make the current models
faster by 2×, because DDR4 still feeds the misses; it mainly **raises the quality ceiling** — Q8_0
flash-next, `Maya-L`, and the 744B GLM-5.3 become resident instead of impossible — and it removes
the SSD tier from the 190–240 GB DeepSeek sets.

## Sources

- Strata: <https://github.com/Niko1221/Strata> — README support matrix, `docs/AMD_HIP.md`,
  `docs/MODELS.md` (RAM+VRAM per size), `docs/DOCKER.md` (image flavours).
- Project Maya: <https://github.com/mw00/project-maya> — README hardware table, `docs/AMD_MAYA.md`,
  `docs/MODELS.md` (Maya-XS/S/S24/M/L sizes), community results for 2× R9700.
- Xolotl: <https://github.com/Indras-Mirror/Xolotl> — RTX 4090 + 110 GB RAM reference.
- tandem.cpp, FreeToken, MoE-Infinity, AirLLM, Promethevs, ninfer: engine roundups at
  <https://www.reddit.com/r/LocalLLM/comments/1xm7z5u/> and
  <https://carteakey.dev/blog/local-inference/the-rise-of-overfit-inference-engines>.
- KTransformers limits on AVX2-only CPUs: `docs/tasks/2026-10/llm-benchmark-suite/003-runner-eval/runners.research.md`.
- oams measurements (12 GB, Strata, 40.6 t/s): this repository's session worklog, 2026-11-15.
