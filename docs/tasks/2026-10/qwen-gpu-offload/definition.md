---
type: Task
description: Prepare a GPU-offload boot specialisation that puts the Qwen3.8-Flash-Next dense layers on the Radeon Pro W6600 with the Vulkan backend, and prove that the GPU helps at all.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-07T13:19:11+02:00
---

# Qwen3.8-Flash-Next on the W6600: a Vulkan GPU-offload specialisation

> ✅ **Done** — see the solution in [done.md](done.md).

## Goal

Serve Qwen3.8-Flash-Next with a **partial GPU offload** on brys: the dense layers
on the AMD Radeon Pro W6600 (8 GB, Navi 23 / `gfx1032`, ~224 GB/s), the experts
and the KV cache on the CPU. The result is a separate boot specialisation
`llm-qwen-gpu`, beside `llm-qwen`, so the CPU-only path stays the default and the
two can be compared.

Before the specialisation is worth building, the task must **prove that the
Vulkan backend accelerates inference at all** on this host. A separate smoke
test does that with a tiny model.

## Context

### Why the GPU may help this model

Qwen3.8-Flash-Next is a sparse MoE: 512 experts with 10 active per token. Decode
is memory-bandwidth-bound on the activated expert weights. The CPU-only path
moves those weights from DDR4 (~40 GB/s) every token. The W6600 holds ~224 GB/s
of VRAM, but only 8 GB of it, so it cannot hold the expert weights (~80 GB in
`UD-IQ4_XS`).

### The 4.68 GB dense-offload math

The ~125B main model splits into about **120B expert parameters** and about
**5B dense parameters** (attention, GDN, gate, shared expert, embeddings). In
the `UD-IQ4_XS` build the dense tensors are mostly `Q8_0`
(~1.06 bytes/param), so they occupy about **4.68 GB**. That fits in the 8 GB
W6600 with about 3 GB left for the KV cache and activations. The ~120B expert
parameters (mostly `IQ3_S`/`IQ4_NL`) must stay in the CPU's 128 GB. This is the
shape that `-ngl 99 -cmoe` produces: every dense layer on the GPU, every MoE
expert tensor on the CPU.

### ICD and ROCm findings (prior research)

- The W6600 needs the **Mesa RADV** Vulkan driver. ROCm is dead on this host:
  `gfx1032` (Navi 23) is not a ROCm-supported target for this use, and the
  earlier `gpu/amd` module already prefers Mesa over ROCm.
- The system's Vulkan ICD directory is **absent/empty**: `/run/opengl-driver`
  does not exist on brys. The `kdn.hw.gpu.amd` module sets
  `hardware.graphics.extraPackages = [ mesa.opencl ]` but **never enables
  `hardware.graphics`**, and brys does not set `kdn.hw.gpu.enable = true`. So no
  ICD is exposed to the Vulkan loader.
- A second GPU is present: the 4 GB Lexa PRO (`1002:699f`, `card0`,
  `renderD128`). The W6600 is `1002:73e3`, `card1`, `renderD129`. The Lexa must
  **not** be selected.

### The quant-type question

The deployed Unsloth `UD-IQ4_XS` GGUF mixes quant types: dense layers `Q8_0`,
experts `IQ3_S`/`IQ4_NL`/`Q8_0`, n-gram table `IQ4_NL`. A user recollection
holds that a **non-Unsloth** model is needed for partial GPU offload. This task
checks that claim against the Vulkan shader list before it builds anything.

## Findings (2026-10-07)

### Vulkan build

`nix build .#llama-cpp-v0_6_0-vulkan` succeeds on oams in **304 s** (the bulk is
the Vulkan shader compile). The output exposes `libggml-vulkan.so`; on brys
`llama-bench --list-devices` finds the backend and both GPUs.

### The quant-type answer

The Unsloth quant **can** be offloaded; a non-Unsloth quant is **not** needed for
the GPU path. The deployed GGUF headers were parsed directly. The types present
across the three shards are `F32`, `BF16`, `Q8_0`, `Q6_K`, `IQ3_S`, `IQ4_NL`,
`IQ4_XS`. Every one is in the `type_names` list of the Vulkan shader generator
(`ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp` at commit
`d812350`), and the generator emits `mul_mat_vec_id_<type>` and
`get_rows_<type>` for every non-`f32`/`f16` type, including `IQ3_S`, `IQ4_NL`
and `IQ4_XS`. The only known `IQ*`-type correctness issue on Vulkan is on
Imagination PowerVR (llama.cpp issue #28343), not AMD. The recollection about a
non-Unsloth model is not supported by the shader list or the issue tracker.

### Exposing the RADV ICD

Verified on brys, without any config change, with:

```bash
export VK_ICD_FILENAMES=/nix/store/...-mesa-26.2.2/share/vulkan/icd.d/radeon_icd.x86_64.json
export VK_IMPLICIT_LAYER_PATH=/nix/store/...-mesa-26.2.2/share/vulkan/implicit_layer.d
export MESA_VK_DEVICE_SELECT=1002:73e3!   # only the W6600
```

The implicit-layer path is needed because brys has no `/run/opengl-driver`. The
decided NixOS change is `hardware.graphics.enable = true` plus
`hardware.graphics.extraPackages = [ pkgs.mesa ]`; that creates
`/run/opengl-driver` with both the ICD and the implicit layer, so
`MESA_VK_DEVICE_SELECT` works with no extra env. The specialisation must also set
`MESA_VK_DEVICE_SELECT=1002:73e3!` (or `--device Vulkan0`) in the llama-cpp
service environment.

### The exact device

```
Vulkan0: AMD Radeon Pro W6600 (RADV NAVI23)            (8176 MiB, 8128 MiB free)
Vulkan1: AMD Radeon RX 550 / 550 Series (RADV POLARIS12) (4096 MiB, 4089 MiB free)
```

The W6600 is `Vulkan0` / `AMD Radeon Pro W6600 (RADV NAVI23)`; the 4 GB Lexa is
`Vulkan1`. With `MESA_VK_DEVICE_SELECT=1002:73e3!` only the W6600 is visible.

### Smoke test (Qwen2.5-0.5B-Instruct `q4_k_m`, 462.96 MiB, 630 M params)

`llama-bench -p 512 -n 128 -r 3 -t 16`, W6600 via `--device Vulkan0`, llama-cpp
stopped during the run and restarted after:

| test | `-ngl 0` (CPU) | `-ngl 99` (W6600) | speedup |
|---|---|---|---|
| pp512 | 61.87 ± 2.73 t/s | 10113.74 ± 308.34 t/s | ~163× |
| tg128 | 94.47 ± 2.92 t/s | 336.99 ± 3.01 t/s | ~3.6× |

### Verdict

The Vulkan backend works on the W6600 and is dramatically faster for a fully
offloaded dense model, so the GPU is **worth pursuing**. The open question is
the *MoE* case: the smoke test offloads a dense model, while the real target
offloads only the ~4.68 GB of dense layers and keeps the ~80 GB of experts on the
CPU. That is the benchmark the `llm-qwen-gpu` specialisation must run.

## Plan

1. **Vulkan build.** Add `llama-cpp-v0_6_0-vulkan` to
   [packages/llama-cpp/default.nix](../../../../packages/llama-cpp/default.nix):
   the v0.6.0 source with `GGML_VULKAN` on, `shaderc` + the Vulkan headers, and
   `GGML_CPU_ALL_VARIANTS`/`GGML_BACKEND_DL` still true.
2. **Quant-type check.** Read the Vulkan shader generator at the pinned commit
   and confirm that every type in `UD-IQ4_XS` has a `mul_mat`/`mul_mat_id` and
   `get_rows` shader. Search llama.cpp issues for an unsupported `IQ*` gap on
   AMD Vulkan.
3. **Expose the RADV ICD.** Verify with
   `VK_ICD_FILENAMES=<mesa>/share/vulkan/icd.d/radeon_icd.x86_64.json` first.
   Then decide the NixOS change: `hardware.graphics.enable = true` and
   `hardware.graphics.extraPackages = [ pkgs.mesa ]`.
4. **Select the W6600.** List the Vulkan devices and record the exact device id
   string. Exclude the Lexa with `MESA_VK_DEVICE_SELECT=1002:73e3!` (or the
   equivalent `--device Vulkan0`).
5. **Smoke test.** Stop `llama-cpp`, download a tiny GGUF (Qwen2.5-0.5B
   `q4_k_m`, ~0.4 GB), and run `llama-bench` with `-ngl 99` (GPU) and `-ngl 0`
   (CPU). Record pp/tg. Restore `llama-cpp`.
6. **Specialisation.** If the GPU helps, add `llm-qwen-gpu`
   (`hosts/brys/llm-qwen-gpu.nix`) on the `llm-qwen` shape with
   `-ngl 99 -cmoe -nkvo`, the Vulkan package, and the ICD + device selection.
   The slot needs three new `perf.*` keys to emit the flags: `n-gpu-layers`,
   `cpu-moe`, `no-kv-offload` (both the slot and its den counterpart).

## Acceptance criteria

- `llama-cpp-v0_6_0-vulkan` builds and its `llama-server`/`llama-bench` list the
  Vulkan device.
- The exact Vulkan device id string of the W6600 is recorded, and the Lexa is
  provably excluded.
- A `llama-bench` smoke test reports pp/tg for GPU (`-ngl 99`) and CPU
  (`-ngl 0`) on a tiny model, with the GPU clearly faster or clearly not.
- The quant-type claim is answered with a cited source.
- The ICD config change is decided and recorded.
- `llama-cpp` is left serving at the end.
- If the GPU helps, `llm-qwen-gpu` exists and is reachable as a boot entry;
  otherwise the task records the negative result and stops.

## References

- [packages/llama-cpp/default.nix](../../../../packages/llama-cpp/default.nix) —
  the Vulkan derivation.
- [packages/llama-cpp/README.md](../../../../packages/llama-cpp/README.md) —
  how to build the Vulkan variant.
- [hosts/brys/llm.nix](../../../../hosts/brys/llm.nix) and
  [hosts/brys/llm-qwen.nix](../../../../hosts/brys/llm-qwen.nix) — the Qwen
  specialisation this task mirrors.
- [docs/local-llms.md](../../../local-llms.md) — the deployed models and the
  benchmark log.
- [docs/tasks/2026-10/qwen-flash-next-quant/definition.md](../qwen-flash-next-quant/definition.md) —
  the quant choice and the model facts.
- [docs/tasks/2026-10/llama-cpp-latest-package/definition.md](../llama-cpp-latest-package/definition.md) —
  the v0.6.0 build this task extends.
- llama.cpp Vulkan shader generator:
  `ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp` at commit
  `d812350` (the `type_names` list and the `get_rows` generation).
- llama.cpp issues checked: #29811 (MTP assert with `qwen4exp`), #29093
  (Vulkan `qwen4exp` multimodality), #25700 (CPU input layer hurts partial
  offload on AMD).
