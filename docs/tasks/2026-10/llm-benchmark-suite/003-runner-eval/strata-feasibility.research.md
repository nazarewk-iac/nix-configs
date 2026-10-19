---
type: Research
description: Desk feasibility study of the Strata inference runner on host brys. Does Strata support Vulkan or only HIP/ROCm, is gfx1032 (Radeon Pro W6600) in its AMD target set, what are the memory and CPU-only rules, its relation to llama.cpp, and whether it builds offline. Verdicts and the fallback options.
task: ../definition.md
authored_by: agent
timestamp: 2026-10-19T20:15:00+02:00
---

# Strata feasibility on brys

Desk research only. No build and no hardware run.

## Target host: brys

| Part | Value |
|---|---|
| GPU | AMD Radeon Pro W6600, 8 GB VRAM, RDNA2, PCI 1002:73e3, LLVM/ROCm target gfx1032 |
| GPU runtime | Mesa RADV Vulkan works; llama.cpp uses it for small models |
| CPU | AMD Ryzen 5950X, 16C/32T, AVX2, F16C, FMA, no AVX-512 |
| RAM | 128 GB DDR4 |
| OS | NixOS |
| Storage | ZFS |

## Answer 1: Vulkan or HIP only

Strata has **no user-facing Vulkan backend for its own model engine**. Its AMD
path is HIP/ROCm only.

- The README support table lists AMD cards under `docs/AMD_HIP.md` only. There is
  no Vulkan option for Qwen3.8-Flash-Next.
- `docs/AMD_HIP.md` line 1 states the AMD backend is "the same engine as on
  NVIDIA compiled for AMD", built with `-DSTRATA_ENABLE_HIP=ON -DSTRATA_ENABLE_CUDA=OFF`.
  There is no `-DSTRATA_ENABLE_VULKAN`.
- The only Vulkan in the tree is a **build-time dependency of the Intel Arc
  engine**: `setup.py` unpacks the LunarG Vulkan SDK into `third_party/` for the
  Intel path (`setup.py` line ~3991). That path does not cover AMD.
- Source: https://github.com/Niko1221/Strata/blob/main/README.md (support table),
  https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md (line 1, Build section).

## Answer 2: AMD GPU targets, and is gfx1032 in the set

Strata's HIP engine builds for a **fixed allow-list**. `setup.py` defines:

```
AMD_ARCHS = ("gfx1100", "gfx1101", "gfx1102", "gfx1200", "gfx1201",
             "gfx1030", "gfx1031", "gfx1151")
```

`docs/AMD_HIP.md` confirms the same in prose: validated cards are gfx1100,
gfx1101, gfx1201 (RX 7900 XT/XTX, RX 7800 XT/7700 XT, RX 9070/9070 XT, R9700);
community-validated are gfx1200, gfx1030, gfx1031 (RX 9060 XT, RX 6800/6900
series, RX 6700 XT).

**gfx1032 is not in this list.** The RDNA2 entries stop at gfx1030 (RX
6800/6900) and gfx1031 (RX 6700 XT). The W6600's gfx1032 (Navi 23) is absent
from the target list, the setup acceptance list, and the community-validated
list.

The reason is in `docs/AMD_HIP.md`: "Other AMD architectures ... are not
supported." Setup accepts a card only when its `gcnArchName` matches a built
architecture, and setup names gfx1030/gfx1031 explicitly from PCI ids (Windows)
or KFD topology (Linux). A gfx1032 card is not recognized.

ROCm 7 on its own does **not** officially support gfx1032 either. AMD's ROCm 7.14
compatibility matrix lists RDNA2 only as gfx1030 (W6800, RX 6800/6900-class).
gfx1032 is a TheRock community-enablement target, not an official ROCm 7 target.

Sources: https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md (RDNA2
gfx1030 section, Build section), `setup.py` line 2832 (`AMD_ARCHS`),
https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html.

## Answer 3: Minimum memory, and 128 GB RAM with 8 GB VRAM

Strata's memory rule counts **RAM + VRAM together**:

- README: "You need at least 32 GB of RAM and graphics memory (VRAM) together."
- `docs/MODELS.md` per-size table (RAM + VRAM):
  - 32 GB -> Gyro-S (27.6 GB need) or the Coder
  - 40 GB -> Swift 1.5 IQ2_XS (39.2 GB), or Gyro-M (35 GB)
  - 48 GB -> IQ3_XXS (47.0 GB)
  - 64 GB -> IQ3_S (54.8 GB)
  - 96 GB+ -> Unsloth UD-IQ4_XS to Q8_0
- `docs/INSTALL.md` "What you need": NVIDIA 12 GB VRAM or more (8 GB runs,
  slowly); AMD 12 GB VRAM or more.

So brys has 128 GB RAM + 8 GB VRAM = 136 GB by the rule. The **smallest** size,
Gyro-S, needs 27.6 GB; the box passes the total-memory test with room to spare.
The VRAM part alone is under the 12 GB recommendation, so setup would use the
low-RAM mode.

But this answer is conditional: **the low-RAM mode still needs a supported GPU
backend to run at all.** An 8 GB card of an unsupported architecture cannot be
the compute device. The memory rule is not the blocker; the architecture is.

Sources: https://github.com/Niko1221/Strata/blob/main/README.md (What you need,
The other sizes), https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md
(Pick by memory), https://github.com/Niko1221/Strata/blob/main/docs/INSTALL.md
(What you need).

## Answer 4: CPU-only mode and the AVX2 path

Strata has **no pure CPU-only mode**. Its engine always uses a GPU: the README
GPU row is mandatory, and every backend is a GPU backend (CUDA, HIP, Metal,
Intel). There is no `--cpu-only` switch.

There **is** an AVX2-only host path, but it is the CPU *side* of a GPU run, not a
GPU-less mode:

- `docs/INSTALL.md` "Older CPUs (experimental)": the ready-made engine needs
  AVX2 (Haswell 2013 / Zen 2017 or newer). brys's Ryzen 5950X has AVX2, so it is
  inside the normal CPU requirement, not the experimental one.
- The experimental path (`STRATA_ISA_FLOOR=avx` or `none`) is for CPUs *older*
  than AVX2 (AVX-only or SSE4.2-only). It is compiled on the PC. brys does not
  need it.
- AVX-512 (Ryzen 7000/9000) is "a bit faster" but not required. brys has no
  AVX-512, which only costs a little speed.
- The GPU part is "unchanged and the CPU part is slower" in the old-CPU build:
  the host kernels run the CPU share of the experts. The GPU still does the
  heavy work.

So the Ryzen 5950X CPU side is fully supported; the question stays the GPU.

Sources: https://github.com/Niko1221/Strata/blob/main/docs/INSTALL.md (What you
need - CPU row, Older CPUs (experimental)).

## Answer 5: Relation to llama.cpp

Strata is not a llama.cpp fork. It **uses parts of llama.cpp / ggml** and pins a
revision:

- README Credits: "Strata uses parts of [llama.cpp / ggml]".
- `docs/AMD_HIP.md` Build note: "CMake fetches the llama.cpp revision pinned by
  this repository. For an offline build, point `STRATA_GGML_DIR` at a checkout of
  that exact revision."
- `setup.py` line 211:
  `LLAMA_CPP_COMMIT = "3cf03257f219afbe7334045ff7c6a06ac68c627d"`, and the zip
  URL `https://github.com/ggml-org/llama.cpp/archive/<commit>.zip`.
- `third_party/llama.cpp` is the unpack location (`setup.py` line 2683:
  `llama = home() / "third_party" / "llama.cpp"`). It supplies ggml, gguf-py and
  mtmd. `ENGINE_SOURCES` includes `third_party/ggml` (line 4797).

So llama.cpp is a **build dependency pinned to one commit**, not an optional
extra. Strata adds its own kernels (MoE expert streaming, GDN, QSA) on top of
ggml.

Sources: https://github.com/Niko1221/Strata/blob/main/README.md (Credits),
https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md (Build), `setup.py`
(lines 211, 212, 2683, 4797).

## Answer 6: Offline build, STRATA_NO_ACQUIRE, and what it fetches

There is **no `STRATA_NO_ACQUIRE` variable in Strata**. That name does not exist
in `setup.py` or the docs. The offline story is different:

- **Build time.** The engine build fetches the pinned llama.cpp revision from
  GitHub (`LLAMA_CPP_ZIP`) unless `STRATA_GGML_DIR` points at a local checkout of
  that exact revision (`docs/AMD_HIP.md`, Build section). ROCm comes from AMD's
  TheRock wheels (about 10 GB, no sudo) or a system ROCm 7 in `/opt/rocm`.
- **Run time.** README: "Starting and serving never download anything. Only the
  install, `strata launch` (when you choose a model) and `strata update` do."
- **Model time.** The model (40-120 GB) and the MTP draft layer (about 6 GB) are
  downloaded from Hugging Face at pinned revisions, with SHA-256 checks. A mirror
  or a hand-placed tree works (`docs/INSTALL.md`, "Where github.com cannot be
  reached" and the ModelScope/mirror notes).

So a fully offline build is possible: place the pinned llama.cpp tree in
`third_party/llama.cpp` (or set `STRATA_GGML_DIR`), supply ROCm, and place the
model files. The flag is `STRATA_GGML_DIR` for the build; there is no general
acquire-off switch.

Sources: `setup.py` (lines 211-212, 216-224), https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md
(Build), https://github.com/Niko1221/Strata/blob/main/docs/INSTALL.md (Where
things are stored - "Where github.com cannot be reached"), https://github.com/Niko1221/Strata/blob/main/README.md (Terminal section).

## Verdict A: can Strata run on brys as-is?

**No.** Strata cannot run on brys as-is with any backend.

- Vulkan is not a Strata backend for its own model, so the working RADV Vulkan
  path is irrelevant.
- The only AMD backend is HIP/ROCm, whose target allow-list does not contain
  gfx1032. gfx1032 is not supported by Strata, not community-validated, and not
  an official ROCm 7 target.
- The CPU-only fallback does not exist; the engine needs a usable GPU.

The 128 GB RAM is not the limit. The 8 GB VRAM is below the 12 GB recommendation
but the total-memory rule is satisfiable; the hard blocker is the GPU
architecture.

## Verdict B: if HIP/gfx1032 is unsupported, the exact options

1. **Unofficial HSA override (`HSA_OVERRIDE_GFX_VERSION=10.3.0`).** This makes
   the runtime report the card as gfx1030. Strata does **not** document or
   support this, and its startup check compares `gcnArchName` to the built list
   and "require[s] wave32" (`docs/AMD_HIP.md`). A gfx1032 card that reports
   gfx1030 would need a gfx1030 build and would run unvalidated, with no
   guarantee of correct kernels. This is a high-risk experiment, not a supported
   configuration.
2. **ROCm version.** A system ROCm 7 in `/opt/rocm`, or the TheRock `gfx103X-all`
   wheels (Strata pins `7.13.0a20260515` for that index, `setup.py`
   `ROCM_FAMILY_PINS`). The `gfx103X-all` index is the closest match; it covers
   gfx1030/gfx1031, not gfx1032, and the gfx1030 wheels are marked unvalidated.
   Note brys is NixOS: Strata's setup expects `/opt/rocm` or its own `.venv`
   wheels, and nixpkgs ROCm is "not an `/opt/rocm` tree" (the `docs/AMD_HIP.md`
   RDNA2 report says the by-hand build was needed for exactly this reason).
3. **Vulkan-via-llama.cpp fork.** Not a Strata option. Use a Vulkan-capable
   llama.cpp build directly (the incumbent path on brys). Strata itself has no
   Vulkan engine to fork.
4. **"Not viable."** For a supported, maintainable setup, this is the honest
   result: Strata on brys needs either a supported AMD card (RDNA2 gfx1030 /
   gfx1031 or newer) or an NVIDIA/Intel/Mac GPU. On the current hardware Strata
   is not viable.

## Alternative: ik_llama.cpp

Repository: https://github.com/ikawrakow/ik_llama.cpp (MIT).

ik_llama.cpp is a llama.cpp fork with optimized CPU kernels. Its README is
explicit about backend support:

- "The only fully functional and performant compute backends are CPU (AVX2 or
  better, ARM_NEON or better) and CUDA." It asks users **not** to file issues for
  ROCm, Vulkan, Metal, old NVIDIA, or AVX CPUs.
- CPU build: `cmake -B build -DGGML_NATIVE=ON`. On brys `GGML_NATIVE=ON` detects
  AVX2/F16C/FMA. brys has no AVX-512, so the AVX2 path applies (the README notes
  a vanilla Release build "silently falls back to the AVX2 path" without the
  AVX-512 flags, which is exactly brys's case).
- It targets MoE CPU/GPU hybrid inference: `--cpu-moe` / `--n-cpu-moe`, tensor
  overrides, "Smart Expert Reduction", and auto-fit of offloaded tensors to VRAM.
  This fits brys: 128 GB RAM holds the experts, the 8 GB card holds a few layers.
- It supports the mainline GGUF quants. Caution from the README: do not use
  Unsloth `_XL` models that contain `f16` tensors, and `-rtr` forces CPU-only
  matmuls for k-quants.
- It has a `flake.nix`.

Assessment: **Yes, ik_llama.cpp is a lower-risk comparison runner than Strata on
brys.** Its CPU path is a first-class, maintained backend (AVX2, no GPU needed),
whereas Strata needs a supported GPU and has none here. ik_llama.cpp's real
weakness on brys is the same as llama.cpp's: the Vulkan/ROCm backends are
unsupported, so the 8 GB card contributes little; the run is CPU-bound. But it
compares cleanly against llama.cpp on the same GGUF models and the same CPU, so
it is the right A/B target for the benchmark suite.

Sources: https://github.com/ikawrakow/ik_llama.cpp (README: TL;DR, backend note,
CPU/GPU build, MoE options, model-support notes).

## Summary

| Question | Result |
|---|---|
| Vulkan backend | No. AMD path is HIP/ROCm only |
| gfx1032 in AMD targets | No. List stops at gfx1030/gfx1031 |
| Min memory | 32 GB RAM+VRAM; brys total passes; 8 GB VRAM under 12 GB rec |
| CPU-only mode | None. AVX2 host path exists, but a GPU is mandatory |
| Relation to llama.cpp | Build dependency pinned at commit `3cf03257...` |
| Offline build | Possible via `STRATA_GGML_DIR`; no `STRATA_NO_ACQUIRE` flag |
| Verdict A: runs on brys as-is | No |
| Verdict B: fallbacks | HSA override (risky), ROCm 7 + TheRock, Vulkan-via-llama.cpp, or not viable |
| ik_llama.cpp | Lower-risk CPU/MoE comparison runner than Strata here |
