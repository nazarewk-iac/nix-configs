---
type: Research
description: The ik_llama.cpp Nix package (packages/ik-llama-cpp): its pinned revision, hash and build flags, the build result, whether it loads the qwen4exp target model, and a first decode/prefill comparison against the in-repo llama.cpp build on brys.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T05:00:56+02:00
---

# The ik_llama.cpp package and the first benchmark

This document answers item F4 of the task. It records the new Nix package, the
build result, and a first decode/prefill comparison on brys. The comparison
uses `llama-bench`, which both engines ship.

## The package

The package is `packages/ik-llama-cpp/default.nix`, registered in
`packages/default.nix` as `ik-llama-cpp`. It builds from a pinned
`fetchFromGitHub`. It does not use `builtins.fetchGit` of a moving branch.

| Field | Value |
|---|---|
| Source | `ikawrakow/ik_llama.cpp` |
| Revision | `35e72560fac6eb4e0bedc99976d3a12040749230` |
| Hash | `sha256-FGBbmLThxMK8PFr3VaoXa4k2yPMCBne+QtR0fUrGw9w=` |
| Date of the revision | 2026-10-19 |
| Version | `0.0.0-unstable-2026-10-19` |
| Build number | `2761` |
| Build commit | `35e72560` |
| Backend | CPU only |
| Store path | `/nix/store/jwk7cw77lgidifyj1zbxyfrr5y2mxfcp-ik-llama-cpp-0.0.0-unstable-2026-10-19` |

The fork has no release tags, so the version is date-based.

### Build flags

The package sets these CMake flags:

| Flag | Value | Reason |
|---|---|---|
| `GGML_NATIVE` | `OFF` | `-march=native` makes the build non-deterministic. The fork then enables AVX/AVX2/FMA/F16C by default, which is the brys baseline (a Zen3 Ryzen 5950X). |
| `LLAMA_BUILD_EXAMPLES` | `ON` | Builds `llama-bench`, the benchmark tool. |
| `LLAMA_BUILD_SERVER` | `ON` | Builds `llama-server`. |
| `LLAMA_BUILD_TESTS` | `OFF` | Skips the upstream test suite. |
| `BUILD_SHARED_LIBS` | `ON` | Shared libraries, as the in-repo llama.cpp builds. |
| `LLAMA_CURL` | `OFF` | No libcurl. |
| `GGML_CUDA` | `OFF` | CPU only. |
| `GGML_HIPBLAS` | `OFF` | CPU only. |
| `GGML_METAL` | `OFF` | CPU only. |
| `GGML_RPC` | `OFF` | No RPC. |
| `GGML_VULKAN` | `OFF` | CPU only. |

The fork diverges from ggml-org llama.cpp. These flags of
`packages/llama-cpp/default.nix` do **not** exist in the fork and are omitted:

- `GGML_CPU_ALL_VARIANTS` and `GGML_BACKEND_DL` are absent. The fork compiles
  for one ISA baseline. The `GGML_NATIVE=OFF` build enables AVX2/FMA/F16C, so
  the binary runs on the brys CPU.
- There is no `LLAMA_BUILD_UI` or `LLAMA_USE_PREBUILT_UI` switch. The server
  always embeds the prebuilt `.gz` assets from the source tree, so the build
  needs no npm tree and no `npmDepsHash`.
- There is no `GGML_BLAS` option. The fork's fast CPU path is the IQK quantized
  GEMM kernels (`GGML_IQK_MUL_MAT`, on by default).

### Build result

The package builds. The build command was:

```bash
nix build --no-write-lock-file --impure --no-link --print-out-paths --expr \
  'let f=builtins.getFlake (toString ./.);
       p=f.inputs.nixpkgs.legacyPackages.x86_64-linux.extend f.overlays.default;
   in p.kdn.ik-llama-cpp'
```

The build finished with exit code 0 and printed the store path in the table
above. The binary reports the pinned version:

```
$ $out/bin/llama-server --version
version: 2761 (35e72560)
built with gcc (GCC) 16.2.0 for x86_64-unknown-linux-gnu
```

The fork reads the build number and the commit from `git` in the source tree.
`fetchFromGitHub` does not keep `.git`, and the `LLAMA_BUILD_NUMBER` /
`LLAMA_BUILD_COMMIT` cache variables do not reach `build-info.cmake`. The
package therefore uses a `postPatch` to write the pinned values into
`cmake/build-info.cmake`. Without that step the version string is
`0 (unknown)`.

## Method

- Host: `brys`. AMD Ryzen 5950X (Zen3, 16 physical cores, AVX2 and no
  AVX-512), 128 GB DDR4, Radeon Pro W6600.
- Tool: `llama-bench`, one build per engine. The prefill test is `pp16384` and
  the decode test is `tg128`.
- Fixed parameters: context 16384, `-ngl 0`, `--threads 16`, `--flash-attn 1`.
- Baseline: the in-repo `llama-cpp-sessions-vulkan-noblas` build (build 11539,
  commit `6beadd4d6`), the build the brys llama-swap serves. The `--ngl 0`
  setting keeps every layer on the CPU, so the run is a CPU comparison.
- `llama-swap` was stopped for the runs. One process at a time. After the runs,
  `llama-swap` was restarted and `GET /v1/models` returned **34** ids again.

The benchmark ran on a build of the same source and the same flags. The only
later change to the package removed a shell-completion step: the fork's
`llama-server` has no `--completion-bash` flag, so that step wrote the usage
text as a completion file. The inference binaries are unchanged.

## Results

The target model is Qwen3.8-Flash-Next (`qwen4exp`). The fork **loads it**: the
`llama-bench` run reported `arch = qwen4exp` and a full result line. The
comparison model is `qwen3.5-9b` (a common architecture), as the task asks.

| model | engine | decode tok/s | prefill tok/s | note |
|---|---|---|---|---|
| qwen3.5-9b Q4_K_M | ik_llama.cpp | 7.80 | 117.56 | `-rtr 0`; 3 runs; decode std 0.76 |
| qwen3.5-9b Q4_K_M | ik_llama.cpp (`-rtr 1`) | 8.28 | 98.34 | run-time repack; 3 runs |
| qwen3.5-9b Q4_K_M | llama-cpp-sessions-vulkan-noblas | 7.31 | 214.64 | CPU backend (`libggml-cpu-haswell.so`); 3 runs; prefill std 1.89 |
| Qwen3.8-Flash-Next UD-IQ4_XS (`qwen4exp`) | ik_llama.cpp | 6.48 | 66.20 | target model; 1 run |
| Qwen3.8-Flash-Next UD-IQ4_XS (`qwen4exp`) | llama-cpp-sessions-vulkan-noblas | 5.31 | 75.07 | target model; 1 run |

A short-prompt smoke test (qwen3.5-9b, `pp64`/`tg16`, 1 run) gave ik_llama.cpp
92.60/7.29 tok/s against the baseline 61.18/4.72 tok/s.

### Reading of the results

- **Decode.** ik_llama.cpp is faster on decode in every pair: 7.80 against
  7.31 tok/s on qwen3.5-9b (about 7 percent), and 6.48 against 5.31 tok/s on
  the qwen4exp target model (about 22 percent). Run-time repack (`-rtr 1`)
  raises the ik decode to 8.28 tok/s, but lowers the prefill.
- **Prefill.** The baseline is much faster on the large 16384-token prefill:
  214.64 against 117.56 tok/s on qwen3.5-9b, and 75.07 against 66.20 tok/s on
  the target model. The baseline build repacks CPU tensors by default; the ik
  default (`-rtr 0`) does not. `-rtr 1` does not close the gap on this run.
- **Small prompt.** On the 64-token prompt ik_llama.cpp is faster on both
  phases (92.60 against 61.18 tok/s prefill). The baseline advantage appears
  only at the large prefill.

## Limits

- The comparison is one box (brys) and one model family per row. The numbers
  are a first look, not a full study.
- The two engines use different defaults (`-rtr`, repack, flash-attention
  kernel set). A matched-flag study is a later task.
- The `llama-cpp-sessions-vulkan-noblas` build carries the Vulkan backend. At
  `-ngl 0` it runs on the CPU, so the comparison is CPU against CPU.
- The qwen4exp rows are one run each. Treat them as an indication, not a
  precise figure.

## Verdict

The package builds and starts. The fork supports the `qwen4exp` target model,
so the "the fork may not support it" risk did not hold. On brys, ik_llama.cpp
wins on decode and on small-prompt prefill, and loses on the large 16384-token
prefill to the in-repo llama.cpp build.
