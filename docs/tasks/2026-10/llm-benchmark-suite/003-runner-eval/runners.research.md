---
type: Research
description: Desk survey of inference runners that could serve a large MoE model (Qwen3.8-Flash-Next, ~94-104 GB GGUF) on host brys (Ryzen 5950X, 128 GB RAM, 8 GB Radeon Pro W6600, ZFS). Candidate list, license, build, offload, API, nixpkgs status, and fit.
task: ../definition.md
authored_by: agent
timestamp: 2026-10-19T18:30:00+02:00
---

# Runner evaluation for Qwen3.8-Flash-Next on brys

Desk research only. No build and no measurement on any host.

## Target host: brys

| Part | Value |
|---|---|
| CPU | AMD Ryzen 5950X, 16 cores / 32 threads, AVX2, no AVX-512 |
| RAM | 128 GB DDR4 |
| GPU | 1x AMD Radeon Pro W6600, 8 GB VRAM, Vulkan capable, RDNA2 (gfx1032 / Navi 23) |
| Storage | ZFS |
| Incumbent | llama.cpp `llama-server` behind llama-swap |
| Model | Qwen3.8-Flash-Next MoE, ~94-104 GB GGUF (model is 125 B parameters in the reference articles) |

Consequence: the box has a large RAM pool and a small, non-CUDA GPU. A runner
fits here only when it does CPU inference and expert or layer offload well. A
GPU-first runner does not fit: 8 GB VRAM cannot hold a 94-104 GB model.

## Summary table

| Runner | License | Lang / build | CPU MoE offload | Small-GPU offload | OpenAI API | In nixpkgs | Fit for brys |
|---|---|---|---|---|---|---|---|
| llama.cpp / llama-server | MIT | C/C++, CMake | yes (expert offload) | yes (expert + layer, Vulkan) | yes | yes (`llama-cpp`) | best (incumbent) |
| Strata | MIT | C/C++ engine + Python control, CMake | yes (all experts in RAM) | yes, but HIP only and 12 GB+ validated | yes (+Anthropic) | no | conditional |
| ktransformers | Apache-2.0 | C++/Python, CMake + PyTorch | yes (CPU expert kernel) | yes (CUDA + CPU) | yes | no | weak |
| SGLang | Apache-2.0 | Python, pip | partial (no CPU MoE path) | CUDA only | yes | no | poor |
| vLLM | Apache-2.0 | Python, pip | partial (CPU exec) | CUDA/ROCm, not 8 GB | yes | yes (`vllm`) | poor |
| exllamav2 / exllamav3 | MIT | C++/Python, CUDA | no (GPU only) | no (VRAM floor too high) | yes | exllamav3 in nixpkgs only | no |
| ollama | MIT | Go, wraps llama.cpp | yes (via llama.cpp) | yes (via llama.cpp, Vulkan) | yes | yes (`ollama`) | no gain |
| LM Studio | proprietary | Electron app | via llama.cpp | via llama.cpp | yes | yes (`lmstudio`) | no (not headless-first) |
| llamafile | Apache-2.0 | C/C++, Cosmopolitan | via llama.cpp | via llama.cpp | yes | no | no gain |

Exact `nix search nixpkgs` / `nix eval` results on this machine:
`llama-cpp-0.6.0`, `llama-swap-249`, `ollama-0.40.2`, `vllm-0.29.0`,
`lmstudio-0.4.26-4`, `python3Packages.exllamav3-1.5.4`. Absent:
`ktransformers`, `sglang`, `exllamav2`, `llamafile`.

## 1. llama.cpp / llama-server (incumbent baseline)

llama.cpp is an MIT C/C++ inference engine built with CMake. It is the incumbent
here: `llama-server` speaks the OpenAI API and llama-swap fronts it. On CPU it
uses GGML. A build with `GGML_CPU_ALL_VARIANTS=ON` produces many CPU backends at
once, and `GGML_BACKEND_DL=ON` loads them as separate shared libraries. At
startup the loader reads the CPU's feature flags and loads the best variant: on
the 5950X (AVX2, no AVX-512) it picks the AVX2 build at runtime. This is the
CPU-variant dispatch the task names. This matters because the F16/BF16 default
build can be slower, and because a build without all-variants pins one ISA for
all x86 machines.

MoE offload flags: `--n-cpu-moe N` / `-ot` offload the first N layers' experts
to the CPU, `--cpu-moe` puts all experts on CPU, `--n-gpu-layers N` offloads
whole layers to the GPU. With an 8 GB Vulkan card, llama.cpp can keep attention
and a few layers on the GPU and run experts on the CPU. This is the baseline the
other runners must beat.

Assessment: the correct baseline. It runs the 94-104 GB GGUF from the 128 GB RAM
pool, uses AVX2, uses the small GPU for a slice, and opencode already talks to
it. Any candidate must win on decode speed, prefill speed, or start time to
justify a switch.

## 2. Strata

### What it is

Strata is an MIT inference engine for Qwen3.8-Flash-Next, a 125 B MoE model. It
comes from <https://github.com/Niko1221/Strata> (28.1k stars). It builds with
CMake (`CMakeLists.txt`, `cmake/`). It is not a full fork of llama.cpp: it uses
parts of llama.cpp / ggml (`third_party/ggml`, pinned by `LLAMA_CPP_COMMIT` in
`setup.py`) plus its own kernels and serving code (`src/`, `serve/`,
`strata_control/`, `strata_cli/`, Python `strata.py`, `setup.py`).

### How it works

- **GPU (VRAM):** attention and DeltaNet mixers, gated-residual weights,
  routers, shared experts, output head, the MTP draft layer, the KV cache, and
  an **expert cache**. The cache holds the most-used experts and adapts to the
  conversation. More VRAM holds more experts (about 700 experts per GB).
- **RAM:** all 24,576 experts, pinned. The CPU computes the experts the GPU does
  not hold, in place and at the same time as the GPU. Kernels are AVX-512 or
  **AVX2** (plus ggml's i-quant kernels).
- **SSD:** a ~28.8 GB n-gram (lookup) table, read a few rows per token through
  the OS cache.
- **Speculative decoding:** the model's own MTP layer drafts tokens; one pass
  verifies them. Reported 1.6-1.8x faster answers.

Low-RAM modes exist for a PC whose RAM cannot hold every expert: `--mmap-experts`
maps `experts.bin` from disk, and the resident variant copies only the experts
the GPU does not hold. On a small card most experts then come from the SSD and
it is much slower.

### CPU / AVX2 build

The ready-made engine needs AVX2 (AMD Zen 2017 or newer). AVX-512 (Ryzen
7000/9000) is faster, not required. An older-CPU build exists but is
experimental and slow; it is built with `-DSTRATA_ISA_FLOOR=avx` or `none`. The
5950X is AVX2, so it uses the normal path. Note: the fast **Q2_0** CPU kernel
writes a one-time ~40 GB pack, but only on an AVX-512 CPU. On this AVX2 box the
Q2_0 pack is not used, which pushes the sensible choice to an i-quant size.

### API

- OpenAI Chat Completions: `POST /v1/chat/completions` (stream, tools).
- Anthropic Messages: `POST /v1/messages` (stream, tools).
- OpenAI Responses: `POST /v1/responses` (Codex CLI).
- Metadata: `GET /v1/models`, `GET /models`, `GET /health`, `GET /props`,
  `GET /slots`, `GET /metrics` (Prometheus, vLLM metric names).
- Base URL for opencode: `http://127.0.0.1:8080/v1`.
- `strata connect opencode --write` writes the opencode config.

This is a superset of what opencode needs.

### Distribution

- The app: a Tauri desktop bundle (AppImage on Linux, `.exe` on Windows, `.dmg`
  on Mac). The engine is inside the installer.
- The Terminal: `install.sh` / `install.ps1` download a signed archive and
  unpack it into `~/.local/share/strata/terminal`. `strata launch` then fetches
  the engine for the card from a signed update feed. Nothing is compiled on a
  normal install.
- From source: `./setup.sh` (Linux) or `START-HERE.bat` (Windows). This makes a
  `.venv`, runs `setup.py`, fetches the engine or compiles one, and downloads
  the model. `setup.py` downloads llama.cpp's source (ggml, gguf-py) at
  `LLAMA_CPP_COMMIT` from GitHub unless `third_party/llama.cpp` already holds
  that tree. `requirements-build.txt` pins `cmake==4.4.3` and `ninja==1.13.2`.
- Upstream ships a flake, but it is only a `devShell` for CUDA: it gives
  `python3`, the CUDA toolkit, `cmake`, `ninja`, and sets `CUDA_HOME` and
  `LD_LIBRARY_PATH`. It does **not** package Strata and it does not cover the
  AMD/HIP or AVX2-only path. There is no `packages.` output.

### In nixpkgs

No. `nix eval nixpkgs#strata` fails. Strata is not in nixpkgs.

### AMD / W6600 reality check

Strata's AMD path is **HIP/ROCm only**. Validated AMD cards are RX 7900 XT/XTX
(gfx1100), RX 7800 XT / 7700 XT (gfx1101), RX 9060 XT (gfx1200), RX 9070 /
9070 XT and Radeon AI PRO R9700 (gfx1201), and RX 6800/6900 (gfx1030). The
W6600 is gfx1032 (Navi 23), which is **not in that list and not validated**. The
engines are NVIDIA `nvidia-smi`, AMD `rocminfo`, or Intel `sycl-ls`; there is no
Vulkan engine. So on brys the AMD engine would have to be compiled for gfx1032
from source, and it is untested there. The docs also treat a 12 GB card as the
practical floor (8 GB "runs, slowly"). This is the central fit risk.

### Fit assessment

Strata is the only candidate built specifically for "big MoE on a small GPU plus
lots of RAM", which is exactly brys. Its API is a superset of llama.cpp's, so
opencode works. The risks are: (a) AMD support is HIP-only and the W6600's
gfx1032 is unvalidated, so a from-source gfx1032 build of the engine is needed
and may fail or be slow; (b) an 8 GB card is below the soft 12 GB floor; (c) it
is not in nixpkgs, so this repository must carry the package. Fit is
**conditional**: worth a like-for-like benchmark, but only after a Nix build
exists and the gfx1032 HIP engine compiles. If the HIP path fails, Strata has no
fallback on this GPU (no Vulkan), and it does not fit.

### What a Nix package must contain

The upstream flake is a CUDA `devShell` only, so a real package is new work. A
`packages/strata/default.nix` must:

1. **Pin the source.** Fetch the Strata tree at a fixed commit (source build),
   or wrap a released artifact with a recorded hash. A source build is
   preferred, per the task's hard requirement.
2. **Pin llama.cpp.** Provide `third_party/llama.cpp` at the commit that
   `setup.py` names in `LLAMA_CPP_COMMIT`, so `setup.py` does not fetch from
   GitHub at build time.
3. **Build tools.** `cmake` and `ninja` (upstream pins 4.4.3 / 1.13.2) plus a
   C++17 compiler. `stdenv` gives the compiler.
4. **Python.** CPython 3.12 and the pinned wheels from `requirements.txt`
   (numpy, pillow, and the rest), installed offline with the hash lock.
5. **GPU backend.** For brys: ROCm/HIP 7 for **gfx1032**, plus the engine
   compiled with that target. This is the open question. A CUDA backend is a
   separate output. No Vulkan backend exists to fall back on.
6. **CPU ISA.** Keep the AVX2 kernel path, not an `ISA_FLOOR` build.
7. **Runtime libs.** Set `LD_LIBRARY_PATH` for ROCm and zlib, as the upstream
   flake does for CUDA.
8. **Python packages.** Build and install `strata_control` and `strata_cli`
   into the wrapper environment, or install them into a venv inside the store.
9. **Wrapper.** A `strata` binary in `bin/`, with `STRATA_COMPONENTS_DIR` and
   the component layout (`components/engine/<version>-<platform>-<backend>/`)
   understood. Decide how models and the data dir are handled (they are large
   and belong outside the store; pass `--data-dir`).
10. **No run-time acquisition.** Set `STRATA_NO_ACQUIRE=1` so `strata` never
    runs pip, downloads an engine, or compiles during a start.
11. **The model.** Ship no model. Document that `strata launch --gguf-dir` or
    `--data-dir` points at the GGUF on ZFS.

A fully-from-source Nix build is practical if and only if the gfx1032 HIP engine
compiles inside the Nix sandbox with nixpkgs ROCm. If it does not, the package
must wrap the released AppImage or Terminal archive instead, with its hash
recorded and the reason written down, as the task requires.

## 3. vLLM

vLLM is an Apache-2.0 Python engine, installed with pip, and present in nixpkgs
as `vllm-0.29.0`. It is GPU-first: its PagedAttention and continuous batching
assume CUDA or a full ROCm GPU with enough VRAM for the weights. It has a CPU
executor, but a 94-104 GB MoE on CPU with an 8 GB GPU is not its target and its
CPU path is slow and lightly supported. It has no expert-offload-to-CPU story
comparable to llama.cpp. It speaks the OpenAI API. Fit for brys: **poor**. The
box cannot give vLLM the VRAM it wants, and the CPU fallback loses to llama.cpp.

## 4. SGLang

SGLang is an Apache-2.0 Python engine (pip), not in nixpkgs. Like vLLM it is
GPU-first, with RadixAttention and a CUDA/ROCm device path; it does not have a
CPU MoE offload path. It speaks the OpenAI API. On an 8 GB card it cannot hold
the model, and it has no CPU expert offload. Fit for brys: **poor**.

## 5. ktransformers

ktransformers (Apache-2.0, C++/Python, CMake plus PyTorch) is built for exactly
this shape of problem: large MoE with CPU-resident experts and a GPU that holds
the attention and the hot experts. It uses Intel AMX or AVX2/AVX-512 CPU kernels
and a CUDA GPU, and it speaks the OpenAI API. Two problems for brys: its fast
CPU kernels target Intel AMX (Sapphire Rapids) or AVX-512, and the 5950X has
only AVX2; and its GPU path is CUDA, not Vulkan/ROCm for a Radeon Pro W6600. It
is not in nixpkgs, and its Python/PyTorch build is heavy to package. Fit for
brys: **weak**. The CPU+GPU idea is right, but the hardware match is wrong.

## 6. exllamav2 / exllamav3

exllamav2 and exllamav3 are MIT GPU-only engines (C++/Python, CUDA). They have
no CPU inference path and no expert offload. They need the model in VRAM. For a
94-104 GB model that is impossible on an 8 GB card. There is no small-GPU "big
MoE plus lots of RAM" story here. `python3Packages.exllamav3-1.5.4` is in
nixpkgs; exllamav2 is absent. Fit for brys: **no**. The VRAM floor alone
disqualifies both.

## 7. ollama

ollama (MIT, Go, `ollama-0.40.2` in nixpkgs) is a wrapper and manager over
llama.cpp. It gives a model registry, an OpenAI-compatible API, and simple
model loading, but no inference logic of its own. For brys it adds management
features the incumbent already gets from llama-swap, and it hides the ggml
flags (`--n-cpu-moe`, expert offload) that matter for this model. Fit for brys:
**no gain** over llama.cpp plus llama-swap.

## 8. LM Studio / llamafile

LM Studio (`lmstudio-0.4.26-4` in nixpkgs) is a proprietary Electron desktop
app with llama.cpp inside. It has a headless server mode and an OpenAI API, but
it is not built for unattended servers and the GUI is the normal entry point.
llamafile (Apache-2.0, Cosmopolitan C/C++) packages llama.cpp as a single
executable; it is not in nixpkgs and adds nothing over llama.cpp for this
server use. Fit for brys: **no** for both. Neither wins on server fit or
offload control.

## 9. Other runners with a "big MoE on small GPU + lots of RAM" story

- **ik_llama.cpp**: a llama.cpp fork with faster CPU kernels (including better
  AVX2 quant paths) and extra MoE flags. Same interface and OpenAI API. It is
  not in nixpkgs and is a fork to track, not a first pick.
- **llama.cpp with an RPC backend**: llama.cpp can spread work across nodes with
  `rpc-server` over the network. On one host this does not help, but it is the
  same codebase and adds no new dependency.
- **SGLang / vLLM forks for CPU**: none are mature for an 8 GB Radeon.
- **Ninfer / Splash / HyperQwen**: named by Strata's docs as idea sources for
  MoE expert caching; none is a packaged, general runner to adopt today.

No runner other than Strata advertises this exact story for the brys hardware.

## Ranked shortlist (best to worst fit for brys)

1. **llama.cpp (`llama-server`)** - the incumbent. Runs now, AVX2 at runtime,
   Vulkan expert and layer offload for the 8 GB card, OpenAI API, in nixpkgs.
   The bar to beat.
2. **Strata** - conditional. Best conceptual match (all experts in RAM, hot
   experts on GPU, lookup table on SSD) and a richer API, but AMD is HIP-only,
   the W6600 (gfx1032) is unvalidated, 8 GB is below its soft floor, and it is
   not in nixpkgs. Adopt only if a Nix build works and the gfx1032 engine runs
   fast enough to beat llama.cpp.
3. **ik_llama.cpp** - a fork of the baseline with faster CPU kernels; low risk,
   same interface, worth a look, not packaged.
4. **ktransformers** - the right idea, wrong hardware (Intel AMX / AVX-512, CUDA).
5. **ollama** - a llama.cpp wrapper; adds no inference value here.
6. **LM Studio / llamafile** - llama.cpp inside an app or one binary; no server
   benefit here.
7. **vLLM** - GPU-first; the box cannot feed it.
8. **SGLang** - GPU-first; same problem.
9. **exllamav2 / exllamav3** - GPU-only; the 8 GB VRAM floor disqualifies both.
