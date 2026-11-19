---
type: Research
description: Measured throughput of every model on the R9700, the fit curves for Qwen3.8-Flash-Next and GLM-5.3-Flash, and the harness comparison on host brys, 2026-11-18.
task: ../definition.md
authored_by: agent
timestamp: 2026-11-18T23:30:00+01:00
---

# Measured on brys with the R9700

Every number is from host `brys` on 2026-11-18, GPU `gpu-r9700`
(Radeon AI PRO R9700, 31.86 GiB, gfx1201), CPU 5950X (AVX2, no AVX-512), 125 GiB usable RAM.
The GPU sits in a PCIe 4.0 **x8** slot.

## Method

- **Sweep of the downloaded models**: `llama-bench` from the served build
  (`llama-cpp-sessions-vulkan-noblas-0.6.0-unstable-2026-10-09`), `-ngl 99 -fa on -p 512
-n 128 -r 2`, `MESA_VK_DEVICE_SELECT=1002:7551!`. So _prefill_ is 512 tokens and _decode_ is
  128 tokens, at an empty context. Every model fit fully in VRAM.
- **Fit curves**: the same `llama-bench` with `--n-cpu-moe N`, then `llama-server` for the
  end-to-end check (`/v1/chat/completions` `timings`).
- **Served numbers**: through `llama-swap` on port 39700, with the preset from `data/llm.nix`.
- `decode` = generation rate, `prefill` = prompt processing. A real chat at long context is
  bounded by prefill for the prompt and by decode for the answer.
- **Check `mem_info_vram_used` is near zero before every run.** A stray `llama-server` left from an
  earlier test keeps its buffers, and the next server then places fewer layers on the card without
  failing: the same served preset read **22.3 t/s at 19.8 GiB** on a clean card and **7.4 t/s at
  12.8 GiB** when a forgotten server held the rest. Restart `llama-swap` after any hand-run server.

## Configuration short names

Each table row names its **harness**, and a **config** short name. The short name is expanded here;
edit the expansion, not the row.

| harness    | config                 | what it means                                                                                                              |
| ---------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `llamacpp` | `vk-full`              | `llama-bench -ngl 99 -fa on -p 512 -n 128 -r 2`. Every tensor in VRAM. Prefill is 512 tokens, decode 128, empty context.   |
| `llamacpp` | `vk-moe6` … `vk-moe40` | the same bench with `--n-cpu-moe N`: the expert tensors of the first N of 48 layers stay in RAM.                           |
| `llamacpp` | `vk-srv32k/N`          | `llama-server --fit off -fa on -c 32768 --n-cpu-moe N`, `-t 8`, mmap load. Measured from `/v1/chat/completions` `timings`. |
| `llamacpp` | `vk-srv32k/N+small`    | the same, with a second `llama-server` holding `qwen3.5-4b` (`-ngl 99`, `-c 16384`) at the same time.                      |
| `llamacpp` | `vk-srv8k/N-t16`       | `llama-server --fit off -fa on -c 8192 --n-cpu-moe N -t 16 --threads-batch 16`.                                            |
| `llamacpp` | `cpu`                  | no GPU offload. Kept only as a reference point; not a served configuration.                                                |
| `bmoe`     | `bmoe-auto`            | `bmoe-cli --auto --no-probe-io -c 2048`. The planner measures the machine, then places tensors.                            |
| `bmoe`     | `bmoe-stream`          | the same with `--moe-stream --auto`: experts stay in RAM and VRAM acts as an expert cache.                                 |
| `llamacpp` | `vk-srv2k/6`           | `llama-server --fit off -fa on -c 2048 --n-cpu-moe 6 -t 16`. The same-context twin of `bmoe-stream`.                       |
| `llamacpp` | `vk-srv64k/26`         | `llama-server --fit off -fa on -c 65536 --n-cpu-moe 26 --cache-type-k/v q8_0 -t 16`. The served preset.                    |

Both harnesses read the **same GGUF files**. A model is downloaded once; `llamacpp` and `bmoe` are
two ways to run it.

## Every downloaded model, GPU-resident

`file GB` is what `llama-bench` reports as the loaded model size.

| model                         | harness  | config  | file GB | decode t/s | prefill t/s |
| ----------------------------- | -------- | ------- | ------: | ---------: | ----------: |
| qwen3.5-0.8b                  | llamacpp | vk-full |     0.5 |  **324.1** |     15266.6 |
| qwen3.5-2b                    | llamacpp | vk-full |     1.2 |  **236.7** |      9915.6 |
| tmax-2b                       | llamacpp | vk-full |     1.2 |      236.1 |      9936.0 |
| mellum-2.1-12b-a2.5b-thinking | llamacpp | vk-full |     7.5 |  **233.6** |      5691.6 |
| gemma-4-e2b                   | llamacpp | vk-full |     2.9 |      211.2 |      8018.9 |
| lfm2.5-24b-a2b                | llamacpp | vk-full |    13.5 |  **211.1** |      5279.6 |
| granite-4.2-3b                | llamacpp | vk-full |     2.1 |      174.4 |      6188.6 |
| qwen3-omni-30b-a3b            | llamacpp | vk-full |    17.3 |      171.4 |      4207.3 |
| qwen3-vl-30b-a3b              | llamacpp | vk-full |    17.3 |      169.7 |      4173.1 |
| ministral-3-3b-instruct       | llamacpp | vk-full |     2.0 |      164.2 |      6650.2 |
| ministral-3-3b-reasoning      | llamacpp | vk-full |     2.0 |      164.0 |      6755.1 |
| nemotron-3-nano-30b-a3b       | llamacpp | vk-full |    22.9 |      144.7 |      4171.1 |
| qwen3.5-4b                    | llamacpp | vk-full |     2.5 |      137.6 |      5069.5 |
| gemma-4-26b-a4b               | llamacpp | vk-full |    13.4 |      134.0 |      3501.6 |
| nemotron-3.5-lightning-30b    | llamacpp | vk-full |    23.5 |      133.9 |      4279.0 |
| ornith-1.5-35b-a3b            | llamacpp | vk-full |    20.2 |      131.9 |      4048.2 |
| gemma-4-e4b                   | llamacpp | vk-full |     4.8 |      127.8 |      4847.1 |
| glm-4.7-flash                 | llamacpp | vk-full |    17.0 |      126.7 |      3768.7 |
| qwen3.6-35b-a3b               | llamacpp | vk-full |    20.6 |      121.9 |      3938.1 |
| qwen3.5-35b-a3b               | llamacpp | vk-full |    20.5 |      120.7 |      3936.5 |
| olmo-3-7b-instruct            | llamacpp | vk-full |     4.2 |      115.6 |      4336.3 |
| qwen3-vl-8b-instruct          | llamacpp | vk-full |     4.7 |      105.2 |      3616.2 |
| granite-4.2-8b                | llamacpp | vk-full |     5.0 |       94.9 |      3617.7 |
| ministral-3-8b-reasoning      | llamacpp | vk-full |     4.8 |       91.5 |      3813.9 |
| ministral-3-8b-instruct       | llamacpp | vk-full |     4.8 |       90.8 |      3842.2 |
| tmax-9b                       | llamacpp | vk-full |     5.2 |       90.4 |      3734.4 |
| qwen3.5-9b                    | llamacpp | vk-full |     5.3 |       90.0 |      3755.2 |
| mimo-v2.6-qwen-9b             | llamacpp | vk-full |     5.4 |       87.6 |      3580.9 |
| gemma-4-12b                   | llamacpp | vk-full |     6.6 |       67.0 |      2161.7 |
| qwen3.8-27b                   | llamacpp | vk-full |    15.3 |       32.4 |      1194.1 |
| qwen3.6-27b                   | llamacpp | vk-full |    15.7 |       31.4 |      1160.1 |
| granite-4.2-30b               | llamacpp | vk-full |    16.5 |       31.3 |      1081.6 |
| gemma-4-31b                   | llamacpp | vk-full |    17.1 |       29.9 |      1030.5 |
| olmo-3.1-32b                  | llamacpp | vk-full |    18.1 |       29.4 |       984.1 |
| seed-oss-36b                  | llamacpp | vk-full |    20.3 |       26.9 |       871.9 |

Also present, not generative: `qwen3-embedding-4b`, `qwen3-reranker-4b`.

**Reading of the table.** Every model up to 23.5 GB runs fully in VRAM. The MoE models win:
13-23 GB of weights with 2-5B active parameters give **120-211 t/s**, while dense 27-36B models sit
at **27-32 t/s** and dense 8-12B at 67-95 t/s. The card is not the limit for any of them; the 5950X
never ran.

## Qwen3.8-Flash-Next: 125B + a 51B n-gram table in 32 GB

The model is **125B with 6B active**, plus a **51B n-gram embedding** and a **4B MTP head** (180B total by safetensors), 48 layers, 512 experts, top-10, 262k native context
(`Qwen4ExpForConditionalGeneration`). `UD-IQ1_S` is 62 GB in 3 shards.

| harness  | config                                    | ctx |     VRAM |           decode t/s |         prefill t/s |
| -------- | ----------------------------------------- | --: | -------: | -------------------: | ------------------: |
| llamacpp | vk-moe6                                   |   0 |        — |             **30.9** |           **481.1** |
| llamacpp | vk-moe8                                   |   0 |        — |                 29.8 |               454.7 |
| llamacpp | vk-moe10                                  |   0 |        — |                 28.0 |               373.9 |
| llamacpp | vk-moe12                                  |   0 |        — |                 27.2 |               393.0 |
| llamacpp | vk-moe14                                  |   0 |        — |                 26.5 |               377.9 |
| llamacpp | vk-moe16                                  |   0 |        — |                 24.3 |               349.8 |
| llamacpp | vk-moe22                                  |   0 |        — |                 22.0 |               280.5 |
| llamacpp | vk-moe28                                  |   0 |        — |                 19.6 |               219.2 |
| llamacpp | vk-moe34                                  |   0 |        — |                 18.1 |               208.4 |
| llamacpp | vk-moe40                                  |   0 |        — |                 16.2 |               162.9 |
| llamacpp | vk-moe2 / 3 / 4                           |   0 |        — |   12.8 / 31.0 / 12.3 |     131 / 129 / 125 |
| llamacpp | `-ngl 99` untuned                         |   0 |        — |                  3.9 |                89.4 |
| llamacpp | vk-srv32k/6                               | 32k | 31.7 GiB |                 14.6 |                38.1 |
| llamacpp | vk-srv32k/24                              | 32k | 21.0 GiB |             **20.4** |                52.5 |
| llamacpp | vk-srv32k/24+small                        | 32k | 24.2 GiB |                 20.1 |                19.1 |
| llamacpp | **vk-srv64k/26 + small**                  | 64k | 23.0 GiB | **21.9** + **125.4** |                   — |
| llamacpp | `qwen3.5-4b` beside it                    | 16k |        — |                119.1 |               185.9 |
| llamacpp | vk-srv64k/26                              | 64k | 19.8 GiB |             **20.9** |                32.3 |
| llamacpp | **llama-swap `chat-deep-slow`**           | 64k | 19.8 GiB |             **21.9** | 255-289 (sustained) |
| llamacpp | **llama-swap `chat-deep-slow` + `grunt`** | 64k | 23.0 GiB | **21.9** + **125.4** |                   — |

The last two rows are the **served** path, not a hand-run server: the preset in `data/llm.nix`
(`nGpuLayers 99`, `nCpuMoe 26`, `loadMode mmap`, `extraFlags ["--fit" "off"]`, `parallel 1`,
`cacheTypeK/V q8_0`, `--threads 16` from the host default, served at 64k). Two llama-servers stay up
together with 23.0 GiB of VRAM in total, and neither loses throughput when the other runs.

**Prefill, measured properly.** A 16-token prompt reports ~50 t/s because the fixed per-request
cost dominates. Four real prompt lengths at the served preset:

| prompt tokens | prefill t/s |   wall |
| ------------: | ----------: | -----: |
|          2572 |       257.3 | 10.0 s |
|          8496 |       288.9 | 29.4 s |
|         11016 |       272.4 | 40.5 s |
|         21516 |       255.1 | 84.4 s |

So the sustained rate is **255-289 t/s**, roughly flat to 21.5k tokens. A 64k prompt would take
about 4-5 minutes. This is the number the fleet must use for `rates.prefill`: it derives the first
token timeout from `contextSize / prefill`.

**64k is the right served window, not 32k.** At `n-cpu-moe 26` the 64k KV cache costs the same VRAM
as the 32k tune at `n-cpu-moe 24` (19.8 vs 21.0 GiB) and decodes the same or slightly faster
(20.9 vs 20.4 t/s). Doubling the window is free.

The prefill collapse below `n-cpu-moe 6` is the signal that the expert tensors no longer fit: VRAM
is overcommitted and the driver starts evicting. `n-cpu-moe 3` is an artifact (decode fine,
prefill collapsed) and should not be used.

**At a real context the tune moves.** The KV cache at 32k eats the VRAM the experts had at an empty
context, so `n-cpu-moe 6` (best at context 0) is overcommitted for a chat: 31.7 GiB and 14.6 t/s.
`n-cpu-moe 24` with `--load-mode none` uses 21 GiB and gives 20.4 t/s / 52.5 prefill. **A served
frontier model must be tuned at the context it serves, not at an empty one.**

## Co-residency: the frontier plus a small model

| harness  | config                            |     VRAM | decode t/s | prefill t/s |
| -------- | --------------------------------- | -------: | ---------: | ----------: |
| llamacpp | vk-srv32k/24 (flash-next alone)   | 21.0 GiB |       20.4 |        52.5 |
| llamacpp | vk-srv32k/24+small (flash-next)   | 24.2 GiB |       20.1 |        19.1 |
| llamacpp | vk-srv32k/24+small (`qwen3.5-4b`) |        — |  **119.1** |       185.9 |

**62 GB of frontier model coexists with a 2.5 GB model in 24.2 GiB of VRAM and ~95 GiB of free
RAM**, and the frontier loses nothing (20.4 → 20.1 t/s). A 9B model (5.3 GB) fits the same
headroom. This is the shape to serve: frontier at `n-cpu-moe 24`, a small model fully offloaded,
both resident.

## GLM-5.3-Flash: 321B in 157 GB of memory

321B, 45 layers, 288 experts, top-8, 1M context. `UD-IQ2_XXS` is 102 GB in 4 shards, and it fits in
125 GiB of RAM with room for the KV cache.

| harness  | config          | ctx |     VRAM | decode t/s | prefill t/s |
| -------- | --------------- | --: | -------: | ---------: | ----------: |
| llamacpp | vk-srv8k/40     |  8k | 18.7 GiB |        8.1 |         9.3 |
| llamacpp | vk-srv8k/38     |  8k | 22.9 GiB |        8.3 |        11.0 |
| llamacpp | vk-srv8k/36     |  8k | 27.0 GiB |        8.5 |        12.2 |
| llamacpp | vk-srv8k/36-t16 |  8k | 28.9 GiB |    **8.9** |    **14.3** |

**GLM-5.3-Flash is CPU-bound here.** Pushing 5 → 9 layers of experts into VRAM (18.7 → 27 GiB) buys
0.4 t/s. The 5950X computes the RAM-resident experts, and it is the wall. 16 threads add a little
over 8 (8.5 → 8.9 decode, 12.2 → 14.3 prefill).

**A load-mode trap.** `--load-mode none` on this 102 GB model makes RADV fail with
`Not enough memory for command submission` → `device lost on Vulkan0` at load. mmap works. One
attempt with `--load-mode none` also left a task in uninterruptible sleep holding all 32 GiB and
required a host reset; the mmap path has not repeated it.

## Harness comparison on the same file

Qwen3.8-Flash-Next `UD-IQ1_S`, same GGUF, same card, 2k context for the apples-to-apples pair:

| harness  | config        | ctx | decode t/s | prefill t/s | note                                                   |
| -------- | ------------- | --: | ---------: | ----------: | ------------------------------------------------------ |
| llamacpp | vk-moe6       |   0 |   **30.9** |   **481.1** | llama-bench                                            |
| llamacpp | `vk-srv2k/6`  |  2k |   **30.7** |        38.3 | llama-server, `-t 16`, whole card (31.4 GiB)           |
| bmoe     | `bmoe-stream` |  2k |   **29.5** |    **60.6** | `--moe-stream --auto`, 26.6 GB expert cache, load 13 s |
| llamacpp | vk-srv32k/24  | 32k |   **20.4** |        52.5 | llama-server                                           |
| bmoe     | bmoe-auto     |  2k |        8.2 |         2.4 | `--auto` chose a host-expert placement                 |

**Decode is a tie; BigMoeOnEdge is 58 % faster on prefill** (60.6 vs 38.3) and leaves VRAM headroom
because its cache is a budget it controls rather than "fill the card". Its failure mode is the
default: without `--moe-stream` the planner runs a host-expert placement and drops to 8.2 t/s while
still printing a 45 t/s projection for the placement it did not choose.

BigMoeOnEdge's planner is the interesting part: it probes the machine, prices every device's expert
and dense bandwidth on the model's own quantized blocks, and prints the plan with a reason per knob.
That is useful for a machine whose VRAM/RAM split is not obvious; llama.cpp gives no such reasoning
and needs the `n-cpu-moe` value found by trial.

## ROCm / HIP

`llama-cpp` with `rocmSupport = true` installs from cache (`llama-cpp-0.9.0`, ROCm 7.2.4), but on
this host **HIP finds no device**: `ggml_cuda_init: failed to initialize ROCm: no ROCm-capable
device is detected`. The kernel side is healthy — KFD exposes the card as `gfx_target_version
120001` (gfx1201, 128 SIMDs) and `rocm-smi` lists both GPUs — but `rocminfo` fails `hsa_init` with
`HSA_STATUS_ERROR` even as root. Until that is solved, the GPU path on brys is Vulkan only.

## WAN shaping

Unconstrained, a Hugging Face download from this host reaches **105 MB/s (845 Mbit/s)** on a
1 Gbit/s WAN. `hosts-den/brys/wan-shaping.nix` caps inbound TCP/443 at 600 Mbit/s (68-70 MB/s)
with an `ifb` + `tbf` pair, so a 100 GB quant takes ~25 minutes and 400 Mbit/s stay free for
everyone else. Measured alternatives: `trickle` under-delivers 3x; the `drek` border router shapes
but its DSA counters cannot be trusted to tune the rate (a 200 Mbit setting delivered 446 Mbit/s).

## Disk

The model dataset (`/var/lib/kdn/llms/models`, `brys-main/brys/impermanence/usr/data`) held **745 GB
free** before this run. `UD-IQ1_S` costs 62 GB and `GLM-5.3-Flash UD-IQ2_XXS` 102 GB; 581 GB remain.

## Strata on the same card — the harness that wins

Strata Terminal 0.2.16 with the signed **HIP `rx9070` engine 0.1.62**, serving the **GSQ-RCO
`IQ2_XS` pack** (63 GiB, copied from oams over the LAN, no download). The engine's own ROCm
runtime hits the Lexa doorbell bug; the shim in `hack/rocm-skip-legacy-gpu.c` hides the gfx803
node from the KFD topology, and then it starts unmodified.

|  ctx |     VRAM | decode t/s | prefill t/s (10.5k prompt) |
| ---: | -------: | ---------: | -------------------------: |
|  32k | 31.0 GiB |   **66.9** |                       2822 |
|  64k | 31.0 GiB |   **67.0** |                       2817 |
| 128k | 31.0 GiB |   **68.6** |                       2799 |
| 256k | 31.0 GiB |   **66.7** |                       2779 |

Two quants, both at 256k:

| pack                |   size | decode t/s | prefill t/s (10.5k) |     VRAM |
| ------------------- | -----: | ---------: | ------------------: | -------: |
| GSQ-RCO **IQ2_XS**  | 63 GiB |   **66.7** |                2779 | 31.0 GiB |
| GSQ-RCO **IQ3_XXS** | 70 GiB |   **63.0** |                2844 | 31.1 GiB |

The better quant costs 5 % decode and buys a quality tier; both fill the card.

Decode is flat from 32k to the model's **native 256k**, and prefill is ~2.8k t/s. MTP on/off made no
difference (67.2 vs 66.9). The engine reports an expert cache of 24.9 GiB and ~864 MiB of VRAM free.

**Against llama.cpp on this box:** 66.9 vs 22.3 t/s decode (3.0x) and 2822 vs 255 t/s prefill
(11x), at four times the context. The comparison is not quant-for-quant — llama.cpp cannot read the
GSQ-RCO pack at all (it rejects `UD-IQ1_S` as "a GGUF Strata cannot run" in the other direction; the
two engines use different quant families). It is a harness comparison: best Strata config against
best llama.cpp config.

| harness             | model                           |  ctx |   decode |  prefill |
| ------------------- | ------------------------------- | ---: | -------: | -------: |
| Strata + HIP        | GSQ-RCO IQ2_XS, 63 GiB          | 256k | **66.7** | **2779** |
| llama.cpp Vulkan    | UD-IQ1_S, 62 GB, `n-cpu-moe 26` |  64k |     22.3 |      255 |
| BigMoeOnEdge Vulkan | UD-IQ1_S, `--moe-stream`        |   2k |     29.5 |     60.6 |

Strata is the engine to serve on this host. The cost is that its packs are its own format: a
llama.cpp GGUF cannot be reused, and the reverse.

## Maya: blocked on packaging, not on the card

Maya (the GLM-5.3-Flash / DS4.1-Flash engine) recognises the R9700 as `gfx1201, 32 GB, can be used`
once `hack/rocm-skip-legacy-gpu.c` hides the Lexa, and its prerequisites check passes with a ROCm 7
prefix assembled from nixpkgs (`rocmPackages.clr`, `hipblas`, `rocblas`, `rocwmma`,
`rocm-device-libs`, `hipcc`). The **build** then fails in CMake: nixpkgs ships each ROCm package in
its own store path, while Maya's `hip-lang-config.cmake` expects the `/opt/rocm` layout
(`lib/x86_64-unknown-linux-gnu/cmake/hip-lang/hip-lang-targets.cmake` references files that a
symlink farm does not satisfy).

That is a packaging job, not a measurement: the fix is an FHS environment like the one
`packages/strata/` already uses, with ROCm 7 and the compiler inside it and `ROCM_PATH=/opt/rocm`.
Until then, GLM-5.3-Flash stays on llama.cpp at 8.9 t/s and the 321B tier is untested on Maya.

What was spent: the repo clone, the Python venv, the llama.cpp source fetch, and about 30 minutes of
fighting the CMake prefix. The model (96.5 GB) was never downloaded.

## What was tried and did not pay off

| idea                                            | result                                                                                                                                                                                                                                                                      |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| llama.cpp **0.9.0** instead of the served 0.6.0 | the nixpkgs build has **no Vulkan backend** (`libggml-vulkan.so` absent) and falls back to BLAS/CPU: 11.8 t/s against 137.7 on the same 4B model. Not a fair comparison until someone packages a Vulkan 0.9.0; the repo's own package is the only Vulkan build on the host. |
| **Speculative decoding** with a small draft     | `qwen3.5-9b` + `qwen3.5-0.8b` draft: 87.0 t/s plain vs 86.7 with the draft, and `draft_n` stayed `None`, so no drafting happened. There is no matched drafter on disk for any dense model we serve.                                                                         |
| **Maya** for GLM-5.3-Flash                      | blocked on packaging (see above), not on the card.                                                                                                                                                                                                                          |
| **ik_llama.cpp**                                | not in nixpkgs; a source build with its own Vulkan flags. Left as a task.                                                                                                                                                                                                   |
| deeper power caps (175/150 W)                   | the driver floor is 210 W on this card; anything lower is refused.                                                                                                                                                                                                          |

## PCIe: the card is at x16, and the link is not the limit

Measured 2026-11-19 from sysfs and `lspci -vv`:

| device                           | current                         | max     |
| -------------------------------- | ------------------------------- | ------- |
| R9700 `0000:0d:00.0`             | **x16**, LnkSta reports 32 GT/s | x16     |
| Lexa `0000:0e:00.0`              | x8, 2.5 GT/s (downgraded)       | x8 Gen3 |
| root ports `0b:00.0` / `0c:00.0` | x16                             | x16     |

So the "Gen4 x8" line in the older host notes is stale, and **moving the RX 550 to another slot
cannot help**: the R9700 already has all 16 lanes and the Lexa sits on its own CPU root port
(`00:03.2`), not on a shared bifurcated slot. The `0b`/`0c` bridges in the R9700's path are the
card's own PCIe switch, not a motherboard splitter.

The measured rates agree: Strata streams cache misses over that link and still reaches 66.7 t/s
decode and 2.8k t/s prefill, and llama.cpp with `--n-cpu-moe` sends **nothing** over PCIe per token
(the experts it does not hold in VRAM are computed by the CPU in RAM). A 16 GB/s x8 link would have
been enough for both; at x16 it is not a candidate for any slowdown seen here.

## Strata configuration sweep: drafting, KV format, context, colocation

All on the R9700, one card, 125 GiB RAM. `--tune skip` unless stated, IQ3_S unless stated.

### DFlash2 drafting is the single biggest lever

| config                                |  ctx | decode t/s | prefill t/s |
| ------------------------------------- | ---: | ---------: | ----------: |
| IQ2_XS, `--mtp off`                   | 256k |       66.7 |        2779 |
| IQ2_XS, `--mtp on --drafting dflash2` | 256k |   **84.9** |        2834 |
| IQ2_XS, dflash2 + `--kv q4_0`         | 256k |   **89.2** |        2150 |

DFlash2 adds **+27 %** decode. My earlier "MTP does nothing" reading was wrong because `--mtp off`
disabled the drafter entirely. The draft acceptance is 120-125 of 175-260 guesses.

### KV format trades decode against prefill

| KV               |  ctx | decode | prefill | note                                                                 |
| ---------------- | ---: | -----: | ------: | -------------------------------------------------------------------- |
| `int8` (default) | 256k |   84.9 |    2834 | the safe default                                                     |
| `q4_0`           | 256k |   89.2 |    2150 | +5 % decode, **-24 % prefill**; perplexity +8-12 % per Strata's docs |
| `k8v4`           |   1M |   81.0 |    1904 | between the two, more precise than q4_0                              |

`k8v4` is the better choice for agent work: it keeps most of the prefill.

### Context: 1M works, with rope scaling

`--context 512k` and `--context 1m` are accepted. Strata warns: _"more than the model was trained on
(256K). Setup adds rope scaling for it (experimental); answers may get less reliable."_

| model     | ctx |   decode | prefill 10.5k |
| --------- | --: | -------: | ------------: |
| IQ2_XS    |  1M | **94.2** |          2103 |
| IQ3_S     |  1M | **81.0** |          1132 |
| UD-IQ4_XS |  1M | **73.1** |          1885 |

Context length costs nothing in decode here: IQ2_XS is as fast at 1M as at 256k.

### The quality ladder, measured

Top-token agreement with Q8_0 is Strata's own yardstick (`docs/QUANTS.md`); speed is ours at 1M.

| pack       |     size | top-token vs Q8_0 |                 decode | prefill |
| ---------- | -------: | ----------------: | ---------------------: | ------: |
| IQ2_XS     |  39.2 GB |  lower than IQ3_S |               **94.2** |    2103 |
| IQ3_XXS    |  47.0 GB |                 — | 63.0 (256k, no dflash) |    2844 |
| **IQ3_S**  |  54.8 GB |        **87.7 %** |               **81.0** |    1132 |
| UD-IQ4_XS  |  93.7 GB |        **88.9 %** |               **73.1** |    1885 |
| UD-Q4_K_XL | 111.3 GB |        **93.1 %** |              see below |         |

Strata calls IQ3_S the size that "matches the full model on the published tests"; the per-token
yardstick is stricter and puts UD-Q4_K_XL 5 points higher. Everything down to UD-Q4_K_XL clears
**40 t/s**, so quality, not speed, is the binding constraint.

### Colocation: yes, with a static VRAM reserve

The lever is `--set vram-reserve-mib=N`: the engine deducts it before sizing the expert cache.
(The elastic `POST /v1/vram` is NVIDIA-only; the static reserve is not.)

| Strata reserve | Strata alone | + qwen3.5-4b on llama.cpp |     total VRAM |
| -------------- | -----------: | ------------------------: | -------------: |
| 0 (whole card) |         81.0 |              not possible |         31 GiB |
| 6000 MiB       |         68.4 |          **77.6 + 126.4** |         29 GiB |
| 4000 MiB       |        73-76 |              76.5 + 130.7 | 31 GiB (tight) |

**6 GB is the recommended reserve**: it fits a 4B (2.5 GB) or a 9B (5.3 GB) with headroom, and costs
Strata about 15 % (81 → 68-78 t/s, run-to-run variance is real). The co-resident model runs fully
offloaded at 126 t/s — no CPU fallback.

### Small extras

- `--draft-vocab latin` adds Polish/German/French/Spanish drafts; English is unchanged (77.5 vs
  81.0 t/s here, within noise). For a Polish user it is free quality on Polish prompts (Strata
  measured 188.4 → 203.2 t/s on Polish).
- `--kv k8v4` is better than `q4_0` for agent work (prefill 1904 vs 1132 at 1M).

### The full ladder, all at 1M with DFlash2 + k8v4

| pack            |     size | quality                            |   decode | prefill 10.5k | verdict                                              |
| --------------- | -------: | ---------------------------------- | -------: | ------------: | ---------------------------------------------------- |
| IQ2_XS          |  39.2 GB | below IQ3_S                        | **94.2** |          2103 | fastest, lowest quality                              |
| IQ3_S           |  54.8 GB | 87.7 % top-token                   | **81.0** |          1132 | Strata's "matches the full model on published tests" |
| **Coder IQ1_M** |   ~32 GB | 91 % SWE-bench, 99 % LiveCodeBench | **86.2** |          2250 | the coding pick; weaker outside code                 |
| Swift IQ3_XXS   |   ~47 GB | ≈ IQ3_XXS                          |     63.0 |           947 | fewer thinking tokens, not more t/s                  |
| UD-IQ4_XS       |  93.7 GB | 88.9 % top-token                   | **73.1** |          1885 | no download needed, already on disk                  |
| **UD-Q4_K_XL**  | 111.3 GB | **93.1 % top-token**               | **56.6** |          1626 | the highest quality that still clears 40 t/s         |

Every one of them clears 40 t/s at the model's 1M window, so quality is the only real choice. The
two picks: **Coder IQ1_M** for code and agent loops, **UD-Q4_K_XL** for general work where the
answer quality matters most.

### Colocation with the top tier

`UD-Q4_K_XL` at 1M with a 6 GB reserve, plus `qwen3.5-9b` fully offloaded on the same card:

| round | Strata decode | 9B decode |             VRAM |
| ----: | ------------: | --------: | ---------------: |
|     1 |          53.1 |      87.3 | 31.0 of 31.8 GiB |
|     2 |          60.4 |      87.9 | 31.0 of 31.8 GiB |

So the **93.1 %-quality primary at 53-60 t/s runs beside a 9B at 88 t/s**. A 4B needs 6 GB of
reserve; a 9B wants 7 GB to keep the same headroom (6 GB was tight at 31.0 of 31.8 GiB).

### What the engine's own tuner said

`--tune quick` on the winning config returned **"already fastest"**: the shipped defaults are the
optimum on this host. No configuration was changed. That is a useful negative result — there is no
hidden tuning gain left in the engine settings.

### Variants that exist but are not a drop-in

- **Abliterated / uncensored**: Strata can serve OrcaRouter's `Flash-Next Uncensored IQ3_XXS`, but
  only through a manual pack conversion (`docs/ORCA.md`), not the installer menu. The llama.cpp
  GGUFs of the abliterated variants cannot reach these speeds on this card.
- **Swift 1.5** is the only fine-tune in the feed (shorter thinking). Its own 5.2 GB draft head is
  required for DFlash2 and is downloaded once.

## Companions for the frontier: what fits in the reserve, and how fast

Every one of these beats the frontier's own 56-86 t/s for its own modality, because they are smaller
and run fully offloaded.

| companion                                    |    size | standalone (sweep) | beside Strata at a 17 GB reserve |
| -------------------------------------------- | ------: | -----------------: | -------------------------------: |
| `qwen3-omni-30b-a3b` (audio, video, text)    | 17.3 GB |          171.4 t/s |                     **84.1 t/s** |
| `qwen3-vl-30b-a3b` (images, video frames)    | 17.3 GB |          169.7 t/s |                   — (same class) |
| `ornith-1.5-35b-a3b` (vision + reasoning)    | 20.2 GB |          131.9 t/s |                     needs ~20 GB |
| `qwen3-vl-8b-instruct` (images)              |  4.7 GB |          105.2 t/s |            fits the 6 GB reserve |
| `gemma-4-e4b` (images, audio-capable family) |  4.8 GB |          127.8 t/s |            fits the 6 GB reserve |

Cost to the frontier, measured: a 6-7 GB reserve leaves Strata at 68-78 t/s; a **17 GB** reserve (a
30B multimodal) drops IQ3_S at 1M to **56.1 t/s**. So the useful tiers are:
_small multimodal in 6 GB_ (8B class, 105-128 t/s), or _one big multimodal in 17-20 GB_
(30-35B class, 84-132 t/s) at a ~30 % frontier cost.

## KV cache: size, placement, and multi-agent

Measured on IQ3_S with `--kv k8v4` at 1M, `free -g` after a clean load:

| context | RAM used |   VRAM |
| ------- | -------: | -----: |
| 32k     |   86 GiB | 31 GiB |
| 256k    |   88 GiB | 31 GiB |
| 1M      |   95 GiB | 31 GiB |

So the KV costs **about 10 KB per token** and lives in **RAM**, not VRAM: 9 GiB for the 992k tokens
between 32k and 1M. Strata streams the KV from 64k upward and keeps only the attention window in
VRAM (`--kv-resident`, default 32k tokens). The numbers match Strata's own 13.7 KB/token for
`int8`; `k8v4` is 23 % smaller, hence ~10 KB.

Multi-agent: `--parallel 4` at 256k costs **+5 GiB of RAM** and leaves single-request speed unchanged
(79.4 t/s against 81.0 at `--parallel 1`). Slots are cheap in RAM and free in VRAM, so the practical
budget for concurrent agents is RAM, not the card: four 256k slots still fit in 125 GiB beside a
55 GB pack.

## A second card: the W6600 would not pay for itself

The W6600 (8 GB, ~224 GB/s, ~100 W) would run a 4-8B at roughly the speeds the W6600 era recorded
here: 4B at ~61 t/s, 9B at ~6-30 t/s. The R9700 today runs a 4B at **126 t/s** inside a 6 GB
reserve, a 9B at **88 t/s** inside 7 GB, and a 30B multimodal at **84 t/s** inside 17 GB — while
also serving the frontier.

So a second card adds ~100 W, a slot and a driver target for strictly less throughput than the
reserve already buys. The only case where it wins is a workload that must keep all 32 GB of the
R9700 untouched _and_ needs a second model at the same time; nothing measured here does. It would
also take the second x16 slot, and although the R9700 currently holds x16 on its own root port, a
second card can only add failure modes to a host with a known power-on fault.

## Mode audit: everything QFN can do is reachable in Strata

Qwen3.8-Flash-Next is text + images, 1M context, thinking, and an MTP head. Strata exposes all of it;
each row below was exercised on brys.

| QFN mode           | Strata switch                                                                        | proved                                                                        |
| ------------------ | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| text               | default                                                                              | every measurement here                                                        |
| **images**         | `--vision gpu` (the 0.9 GB `strata-vision-hip` reader)                               | a 256x256 red PNG answered **"red"**, 89 prompt tokens, 220 t/s prefill       |
| 1M context         | `--context 1m` (rope scaling above 256k)                                             | 94.2 / 81.0 / 73.1 / 56.6 t/s by pack                                         |
| thinking           | `reasoning_effort`, `chat_template_kwargs.enable_thinking`                           | a 16-token cap is consumed by thinking and returns empty content, as expected |
| MTP / speculation  | `--mtp on --drafting dflash2`                                                        | +27 % decode                                                                  |
| concurrency        | `--parallel N`                                                                       | 4 slots at 256k, +5 GiB RAM, 79.4 t/s single request                          |
| KV formats         | `--kv int8 / q4_0 / k8v4`                                                            | measured above                                                                |
| prompt reuse       | `--prompt-cache N`, `--prompt-cache-every`, `--prompt-cache-spread`, `strata_prefix` | documented; one pinned prefix per engine                                      |
| conversation reuse | `--conversation-cache-mib`, `--conversation-cache-slots`                             | parks the K/V of alternating conversations in host RAM                        |
| disk persistence   | `slot_save_path` + `POST /slots/0?action=save\|restore`                              | session files                                                                 |
| API surface        | OpenAI **and** Anthropic, `/metrics` in vLLM names, MCP servers                      | documented                                                                    |

Audio and video are **not** QFN modes; they need the companion model below.

## KV, context reuse and what can be parked

Measured: **about 10 KB per token** with `k8v4` (13.7 KB for `int8`), held in **host RAM**, with a
32k attention window in VRAM. That makes context a RAM question, not a card question.

| budget                            | tokens of context it buys |
| --------------------------------- | ------------------------: |
| 2.6 GiB                           |                      256k |
| 5.2 GiB                           |                      512k |
| 10.4 GiB                          |                        1M |
| 25 GiB (the headroom at 1M today) |                     ~2.5M |

Reuse, three levels:

1. **Checkpoints inside one conversation** — `--prompt-cache N` keeps N marks, `--prompt-cache-every`
   sets the interval, `--prompt-cache-spread` thins them geometrically so an agent that rewrites a
   few thousand tokens back resumes near the edit. `strata_prefix` pins one document boundary, so
   20 questions about one document cost one read.
2. **Parked conversations** — `--conversation-cache-mib` keeps whole K/V images of idle conversations
   in host RAM. The default is 40 % of the RAM left above the floor, **capped at 8 GiB**, which is
   about **800k tokens** of parked context; raising the cap to 25-40 GiB parks 2.5-4M tokens.
3. **Disk** — session files (`slot_save_path`, `POST /slots/0?action=save|restore`) move a conversation
   out of RAM entirely and bring it back later. That is the way to keep many long threads without
   paying RAM for all of them.

## Fine-tuning QFN locally: not a lever

The model is 125B (180B with the n-gram table and MTP head). A LoRA still needs the frozen weights in
compute precision plus activations: bf16 is ~360 GB, and even a 4-bit QLoRA needs the full forward pass
through every expert it touches. On 32 GB of VRAM + 125 GiB of RAM there is no configuration that
trains it in useful time; a single epoch over a modest dataset would run for weeks at the throughput
measured here.

What does work, and costs nothing:

- **Retrieval over the transcripts** instead of weight updates — an index beside the model gives the
  same "knows my sessions" effect without touching 125B parameters.
- The engine-side levers already measured: DFlash2 (+27 %), `k8v4`, `--draft-vocab latin`,
  `--tune` (already optimal), and `STRATA_KVA=1` for long prompts (+28 % prompt on this card,
  measured by Strata on an R9700 with IQ3_S, at -11 % decode).
- `STRATA_CACHE_MESSAGE_BOUNDARY=1` for agent loops that edit the last user message.

## Companion for audio and video

|                     | qwen3-omni-30b-a3b                                                                               | gemma-4-e4b                                  |
| ------------------- | ------------------------------------------------------------------------------------------------ | -------------------------------------------- |
| size                | 17.3 GB                                                                                          | 4.8 GB                                       |
| modalities          | **audio + video + text**                                                                         | audio + images + text                        |
| speed alone         | 171 t/s                                                                                          | 128 t/s                                      |
| speed beside Strata | **84 t/s** at a 17 GB reserve                                                                    | 128 t/s at a 6 GB reserve                    |
| accuracy            | SOTA among open audio models (32 benchmarks, ~Gemini-2.5-Pro; 19 ASR languages, 40-min sessions) | best in its size class, but a 4B-class model |
| video               | **yes**                                                                                          | no                                           |

**For video, the answer is `qwen3-omni-30b-a3b`**: it is the only one of the two that reads video with
its audio track. It costs the frontier ~30 % (81 → 56 t/s at a 17 GB reserve) and returns 84 t/s on
the companion. `qwen3-vl-30b-a3b` (170 t/s) is the alternative when only frames matter and the audio
track does not.

## The chosen stack: QFN + omni, and why UD-IQ4_XS is the pack

`qwen3-omni-30b-a3b` is the only local model that reads **video with its audio track**. Its real
footprint with the projector at an 8k context is **20 GiB of VRAM** (17.3 GB of weights plus the
mmproj, KV and buffers), not 17. That reserve is the number the frontier has to live with.

| QFN pack      | top-token vs Q8_0 |          frontier at a 20 GB reserve |           RAM after both load | verdict                                                        |
| ------------- | ----------------: | -----------------------------------: | ----------------------------: | -------------------------------------------------------------- |
| UD-Q4_K_XL    |            93.1 % |                        40.4-41.4 t/s |  118 GiB used, **7 GiB free** | fits, but leaves nothing for a cache or the desktop            |
| **UD-IQ4_XS** |        **88.9 %** |                    **49.8-54.8 t/s** | 104 GiB used, **21 GiB free** | **the pick**: quality, speed and 1.5M tokens of parked context |
| IQ3_S         |            87.7 % | ~56 t/s (est. from 81 at no reserve) |                  ~90 GiB used | more headroom, a lower quality tier                            |

Settings that produced those numbers, all measured on this card:

| knob                                 | value     | effect                                       |
| ------------------------------------ | --------- | -------------------------------------------- |
| `--drafting dflash2` + `--mtp on`    | on        | +27 % decode                                 |
| `--kv k8v4`                          | on        | 23 % less KV, better prefill than `q4_0`     |
| `--set kv-resident=4096`             | 4k tokens | +10-15 % decode (older K/V is read from RAM) |
| `--set vram-reserve-mib=20000`       | 20 GB     | room for omni at full offload                |
| `--set conversation-cache-mib=15000` | 15 GB     | ~1.5M tokens of parked conversations         |
| `--set memory-limit-mib=112000`      | 112 GB    | keeps a margin for the desktop               |
| `--set pcie-frac=0.6`                | —         | **worse** (39 → 31 t/s); do not use          |
| `--draft-vocab latin`                | on        | free for English, +8 % on Polish per Strata  |

`hack/brys-frontier.sh up` starts exactly that configuration.

**oams cannot run omni usefully.** The same file on the 12 GB RX 6800M: 13.6 t/s at `ncmoe 40`,
14.7 at 32, **17.5 t/s at 24** (12 GiB of VRAM, the rest of the experts on the laptop CPU). brys
gives 157-160 t/s for the same model. The 9x gap is the card plus DDR4 on a full desktop CPU; the
companion belongs on brys.

### Final tuned stack, measured end to end

`hack/brys-frontier.sh up` on brys, then `qwen3-omni-30b-a3b` through llama-swap
(`audio-std-mid`, now served at 16k on the GPU):

| process           | model                             | settings                                                                        |              decode |
| ----------------- | --------------------------------- | ------------------------------------------------------------------------------- | ------------------: |
| Strata :8080      | QFN `UD-IQ4_XS` 1M                | DFlash2, k8v4, latin, reserve 21.5 GB, kv-resident 4k, 15 GB conversation cache |   **41.3-46.6 t/s** |
| llama-swap :39700 | `qwen3-omni-30b-a3b` 16k + mmproj | full offload                                                                    | **100.8-102.8 t/s** |

Together: 31 GiB of 31.8 GiB of VRAM, 84 GiB of RAM used and **41 GiB free**. Omni at 16k is twice
as fast as at 32k (101 vs 57 t/s) because 32k no longer fits the reserve and llama.cpp had to keep
layers on the CPU. That is why the served context moved: `data/llm.nix` now serves omni at 16384 and
marks it `operation = "gpu"` (it still said `cpu` from the W6600 era).

### A regression the formatter pass caused, and the fix

`nix build` of the brys toplevel failed after the formatter-convergence commit:
`kdn-sops-secrets` stopped with `E203 whitespace before ':'`. `ruff format` had re-spaced a complex
slice (`line[start : end]`) in the den twin of `kdn-sops-secrets.py`, and the den aspect did **not**
carry the `flakeIgnore = [ "E203" "E501" ]` that the universal twin already had. Added there; the
build is green again. The general lesson: a formatter and a lint gate must be converged together,
which is exactly what `docs/formatter-convergence.md` asks for.

### Why the frontier drops to 42 t/s with omni resident, and the pack ladder

Decode is set by how much of each token's expert bytes the card holds. With the 21.5 GB reserve, omni
takes 20 GiB and Strata keeps about **5 GiB of expert cache**. Measured with omni loaded:

| pack        | expert bytes | experts in RAM | cache share |       decode | RAM used |
| ----------- | -----------: | -------------: | ----------: | -----------: | -------: |
| **IQ2_XS**  |     35.5 GiB |   61 GiB total |       ~14 % | **71.6 t/s** |   61 GiB |
| Coder IQ1_M |       23 GiB |   52 GiB total |       ~22 % | **54.0 t/s** |   52 GiB |
| IQ3_S       |       50 GiB |   75 GiB total |       ~10 % |     49.2 t/s |   75 GiB |
| UD-IQ4_XS   |     55.4 GiB |   84 GiB total |        ~9 % |     42.3 t/s |   84 GiB |

**RAM cannot replace the expert cache.** It already holds every expert the card does not: Strata keeps
them in an arena and _computes_ the misses on the CPU (it does not upload them, which is why
`pcie-frac` hurt). At 0.8-1.2 GB of expert reads per token, DDR4 at ~28 GB/s is 23x slower than the
card at 640 GB/s, so moving cache from VRAM to RAM lowers decode rather than raising it. The _context_
cache is the opposite case and does live in RAM: the KV is ~10 KB/token, streamed from host memory,
which is why 1M tokens cost 10 GB of RAM and not 10 GB of VRAM.

Three ways to recover the lost decode, in order of cost:

1. **Run omni on demand** instead of always: QFN alone reaches 73.1 t/s at 1M. The price is a ~60 s
   reload of whichever model is swapped.
2. **A smaller companion quant**: omni at Q3 is ~14 GB, so a 17 GB reserve returns ~4.5 GiB of cache
   to Strata (roughly +8-10 t/s). It costs companion quality, which matters for video.
3. **A smaller frontend pack**: IQ2_XS gives 71.6 t/s beside omni, at a lower quality tier.

### Omni at 16k: images and short video, measured

| input                               | prompt tokens | answer                     |
| ----------------------------------- | ------------: | -------------------------- |
| one 256x256 frame                   |            84 | "Red"                      |
| four frames (red/green/blue/yellow) |           286 | "Red, Green, Blue, Yellow" |
| sixteen frames                      |          1076 | "16"                       |

So a frame costs about **67 tokens**. A 16k window therefore holds **~230 frames** (plus the prompt),
which is a few minutes of video at a 1 fps sample or about 30 s at 8 fps. A single image costs 84
tokens, so images are never the limit. 16k is a deliberate trade: at 32k omni needs 22 GiB, no longer
fits the reserve, and llama.cpp keeps layers on the CPU (57 t/s instead of 101).

## Parallelism: how many sessions the QFN profile carries

Strata serves N concurrent engine slots with `--parallel N` (1-8); a request beyond that queues.
Measured on the QFN-only profile (UD-IQ4_XS, 1M, `kv-resident 4096`), 192-token answers:

| parallel |  wall |    aggregate | per session |
| -------: | ----: | -----------: | ----------- |
|        1 | 2.2 s | **87.7 t/s** | 89.8        |
|        4 | 7.9 s | **97.5 t/s** | 25.0-27.2   |

**Four sessions run comfortably, each at ~26 t/s, and together they buy only +11 % aggregate**
(97.5 against 87.7). Decode is memory-bandwidth bound, so concurrent sessions share the same
expert-cache bandwidth instead of adding any; the engine does not make more tokens per second with
more callers, it only interleaves them. That is the honest ceiling: one session is the fast path,
four sessions are the comfortable "several agents, none of them in a hurry" mode, and eight would
divide the same throughput eight ways.

Session _count_ is a different number from live slots:

- **Live** — `--parallel`, up to 8 slots, each holding its own conversation K/V.
- **Remembered** — the conversation cache (`--conversation-cache-mib`, 15 GB here = ~1.5M tokens)
  keeps idle conversations' K/V whole, so a returning thread resumes without a re-read. At 10 KB per
  token that is ~5 threads of 256k or ~1 of 1M, resident.
- **Archived** — session files (`slot_save_path` + `POST /slots/0?action=save|restore`) put a thread
  on disk, so the number of retained threads has no memory ceiling.

RAM is what bounds the middle tier, not the card: the card holds one expert cache shared by every
slot.

## Registering the profiles in llama-swap: works

The three profiles are llama-swap models. A request for the alias starts the engine, and a request
for another profile evicts it and starts that one, exactly like every other model in the fleet:

| model           | alias                                                                     | profile                     | resident need |
| --------------- | ------------------------------------------------------------------------- | --------------------------- | ------------- |
| `qfn-max`       | `chat-deep-slow`, `code-deep-slow`, `tools-deep-slow`, `reason-deep-slow` | UD-IQ4_XS, whole card       | 55 GiB + KV   |
| `qfn-omni-max`  | `chat-deep-slow-omni`                                                     | UD-IQ4_XS + 21.5 GB reserve | 55 GiB + KV   |
| `qfn-omni-fast` | `chat-deep-slow-fast`                                                     | IQ2_XS + 21.5 GB reserve    | 35 GiB + KV   |

Measured switch costs, all through the fleet:

| from → to                          | what changes              |      time |
| ---------------------------------- | ------------------------- | --------: |
| cold start, pack not in page cache | everything                | 601-837 s |
| `qfn-omni-fast` → a warm pack      | different pack            |      47 s |
| `qfn-max` ↔ `qfn-omni-max`         | **only the VRAM reserve** | **180 s** |

**Any switch restarts the engine, even between `qfn-max` and `qfn-omni-max`.** The two share the
same UD-IQ4_XS pack and differ only in `--vram-reserve-mib`, but that is a start-up argument: llama-swap
sees two model ids, evicts one ("matrix: starting swap for model qfn-omni-max, evicting" followed by
`[strata] stopping`), and the next start reloads the whole 55 GiB. There is no runtime reserve
change on HIP: the `POST /v1/vram` elastic call is NVIDIA-only.

So the profiles are three operating points, not three sliders: pick one for a session. If the media
companion is used at all regularly, `qfn-omni-max` is the one to stay on (42 t/s with omni always
ready); if it is rare, stay on `qfn-max` (73 t/s) and pay one reload when a video arrives.

Three walls had to come down, found by an independent bisection with `systemd-run` (one property
flipped per probe):

1. **`ProtectHome=true`.** Strata keeps its per-user state in `$HOME/.local/state/strata` and
   refuses a folder it does not own (`posix_owner.owner_only_wrong`, `runtime.py:79`). Under
   `ProtectHome` the home is a root-owned read-only tmpfs, so the first `mkdir` fails and the CLI
   prints "Strata is not allowed to open one of its own files" (exit 5). `strata repair-access` is a
   Windows-ACL tool and correctly reports 0 entries on POSIX.
2. **A real bug in the shared aspect.** `modules/den/aspects/llm.nix` listed `modelsDir` in **both**
   `ReadOnlyPaths` and `ReadWritePaths`; systemd resolves that as read-only, so on every swap host
   the model dataset was silently mounted RO. The duplicate line is removed.
3. **`/var` is read-only under `ProtectSystem=strict`.** The account's home needs its own
   `ReadWritePaths` entry, and the wrapper must point `ROCM_SHIM` at the dataset copy of the shim
   because `/home` is hidden.

The unit now runs as `llm-server` (owner of the data tree), with `ReadWritePaths` for `models`,
`home` and `sessions`, and `ROCM_SHIM` pointing at `.bench/rocm-skip.so`. The standalone
`strata-frontier` service stays as a manual fallback and no longer starts at boot, so nothing fights
llama-swap for the card.

## The service account and the layout

The LLM stack on brys runs as a dedicated account, not as a human login:

| item        | value                                                                                                 |
| ----------- | ----------------------------------------------------------------------------------------------------- |
| account     | `llm-server`, uid/gid **67890** (out of every dynamic pool, so it means the same on a second machine) |
| description | "Generic LLMs runner account"                                                                         |
| shell       | `nologin`, no password, `home-manager.users` never instantiates it (only `kdn` and `root` do)         |
| HOME        | `/var/lib/kdn/llms/home`                                                                              |

One parent for everything, so a second machine shares it by mounting the same datasets:

| path                              | dataset   | holds                                                  |
| --------------------------------- | --------- | ------------------------------------------------------ |
| `/var/lib/kdn/llms/models`        | usr/data  | GGUFs and the Strata packs                             |
| `/var/lib/kdn/llms/models/.bench` | usr/data  | the Terminal, engine components, configs, the KMS shim |
| `/var/lib/kdn/llms/home`          | usr/data  | the account's HOME                                     |
| `/var/lib/kdn/llms/sessions`      | usr/cache | llama-server session files                             |

`.` is deliberate: the engine tree keeps its path because the Terminal's venv hardcodes it, and it
lives inside `models` so it inherits that dataset's persistence.

Services:

- `strata-frontier` — a **system** service, `User = llm-server`, `LimitMEMLOCK = infinity`,
  `MemoryMax = 112G`, restart on failure, `ExecStart = strata-serve max --port 8080`. Ready in
  ~85 s, serving `qwen3.8-flash-next-unsloth-ud-iq4_xs` at 1M.
- `llama-swap` — the same account, so a model process and the engine share one identity and no
  file-ownership mismatch can exist.

The ROCm shim is built from `hack/rocm-skip-legacy-gpu.c` as a Nix derivation (so it cannot drift
from the source) and copied to `.bench/rocm-skip.so` for hand-run servers; the service uses the
store path.

## A profile manager: switching without a reload when nothing changed

llama-swap restarts a model on every switch because each entry owns a process. For Strata that is
mostly wasted: two of the three profiles differ only in a start-up argument. So brys now runs
**`strata-manager`** (:8181), which owns the single engine and answers:

```
POST /select {"profile": "max"|"omni-max"|"omni-fast"|"none"}
GET  /status
```

`/select` diffs the request against what is already running: the same profile returns
`{"changed": false}` in under a millisecond and touches nothing; a different profile drains the
engine and starts the new one; `none` stops it and frees the card.

The llama-swap entries do not own the engine any more. Each one calls `strata-select <profile>
--port ${PORT}`, which asks the manager and then runs a dual-stack TCP proxy from llama-swap's port
to the engine on 8080. llama-swap therefore pays a proxy per switch, and a model reload only when
the profile really changed.

Measured end to end:

| action                                               | result                               |         time |
| ---------------------------------------------------- | ------------------------------------ | -----------: |
| `POST /select max` (engine cold)                     | engine started                       |         84 s |
| `POST /select max` again                             | `changed: false`, nothing touched    | **0.0009 s** |
| llama-swap `chat-deep-slow` while `max` is current   | served by the running engine         |      **0 s** |
| llama-swap `chat-deep-slow-fast` (different profile) | drained and switched to omni-fast    |         50 s |
| `POST /select none`                                  | engine stopped, VRAM 33 GiB → 74 MiB |          3 s |

Two details that cost an hour:

- **llama-swap health-checks `localhost`, which is `::1` here.** A proxy bound to `127.0.0.1` looks
  dead; the proxy is one IPv6 socket with `IPV6_V6ONLY=0` so it accepts both families.
- **`strata runtime start` takes a saved _preset_ name, not a config path**, so the manager
  supervises `strata serve --profile <config>` as its own child instead.

### A live reserve change is not possible on this card

The obvious way out of the `max` ↔ `omni-max` reload would be to move the reserve on a running
engine, so `max` and `omni` become one engine with an elastic split. Two measurements close it:

- `POST /v1/vram {"reserve_mib": 12000}` answers
  `VRAM needs an engine started with --vram-elastic (one NVIDIA GPU, --serve)`.
- Restarting with `--vram-elastic` adds the flag but the engine still refuses: the check is on the
  backend, not the flag, and `strata generate` reports `--vram-elastic is off: %s` for HIP.

So a reserve change costs a real reload (47–50 s warm, 601–837 s cold). Keep the reserve a start-up
argument.

### A timed loan, reverted outside the manager

A profile selection is easy to forget: a mixed-mode session can hold the smaller reserve for the
rest of the day. The first implementation put the revert in the manager itself — an `expires_at`
field and a thread that called `select(default)` when the deadline passed. It worked once and then
wedged the manager: the revert runs through the same lock and the same drain as a client request, so
a slow or failing revert blocked `/status` and every later `/select`. Test run: `expires_at` stuck
in the state file, `/status` silent, no revert, engine gone.

The revert therefore lives **outside** the process that it can block:

```bash
hack/brys-frontier.sh up --profile omni-fast --ttl 30m
```

`up` posts `/select`, then arms a transient unit:

```
systemd-run --unit=strata-revert --on-active=30m --collect \
  -- curl -sS -m 900 -X POST http://127.0.0.1:8181/select -d '{"profile":"max"}'
```

Properties that follow from that placement:

| property            | why                                                                             |
| ------------------- | ------------------------------------------------------------------------------- |
| crash-safe          | the timer is systemd state, not a thread, so a manager restart keeps the deadline |
| non-blocking        | a failing revert cannot hold the manager lock, because it is a separate process   |
| idempotent          | the default profile is `changed: false` when it is already current (0.0009 s)     |
| visible             | `journalctl -u strata-revert` holds the request and the reply                    |

Verified: `--ttl 0.3m` selected `omni-fast`, `strata-revert.service` fired 18 s later and posted
`max`, and `/status` answered `{"profile": "max"}` throughout.

## What a live omni request does to a loaded QFN (2026-11-19, measured)

The manager settles the profile question, and llama-swap settles the model question, and they
disagree about what "activate omni" means. `hack/probe-omni-swap.sh` reproduces the whole sequence.
Measured on a healthy host with `max` loaded:

| step                                                    | result                                                        |
| ------------------------------------------------------- | ------------------------------------------------------------- |
| QFN served `chat-deep-slow` with no proxy running yet    | 0.9 s, engine already up from the boot restore                |
| `audio-std-mid` requested while `max` holds the card     | **200 in 48.9 s**, omni answered; VRAM 30 → 31 GiB            |
| `chat-deep-slow` requested again, omni still resident    | **0.84 s** — QFN never moved                                  |

So **no reconfiguration happens at all**. `audio-std-mid` sits in its own matrix set
(`with_surveyed = <surveyed> & (<frontier>)`), so llama-swap co-loads it beside the frontier
instead of evicting it. QFN keeps its engine, its conversation cache and its 73 t/s.

The companion is the loser: `max` reserves no VRAM, so omni got about 1 GiB of the card and
llama.cpp pushed nearly every layer back to the CPU. It answers, and it is nowhere near the 101
t/s it reaches inside a 17 GB reserve. Co-residence without a reserve is a working answer, not a
fast one.

A real reconfiguration is only the profile switch, and that is the part that does not survive:

| step                                     | result                                                                     |
| ---------------------------------------- | -------------------------------------------------------------------------- |
| `POST /select omni-max` under load       | 74 s, engine reloaded with the reserve, llama-swap's models dropped        |
| `audio-std-mid` again, now with a reserve | 52 s, full offload                                                         |
| `POST /select max`                       | 83 s, then a frontier request returned **500**                              |
| after it                                 | the kernel OOM-killed the new engine: `anon 58 GB + file 28 GB + shmem 12 GB = 98 GB` |

### The switch is memory-bound, not engine-bound

Every failing switch ended the same way: the incoming engine reached 88-98 GiB RSS with `free` at
zero, the kernel killed it, `OOMPolicy=stop` stopped the manager, the manager restored the previous
profile, and the cycle repeated (restart counter 3). Raising `vm.min_free_kbytes` to 2 GiB and
`vm.watermark_scale_factor` to 200 changed nothing: the burst still reached 93 GiB and still died.

What *did* work was a reboot. With a fresh page cache and a cold ZFS ARC the same `max` profile
loaded and served (30 GiB VRAM, 30 GiB RSS, ready in about 90 s). The load is a ~95 GiB transient on
a 125 GiB host with **no swap**, and the warm state (40-48 GiB of page cache, 7 GiB of ARC, mlocked
KV) leaves no room for it.

Consequences to design around:

- A profile switch on brys is only reliable while the host memory state is fresh. Treat `max` as the
  operating point you boot into, not one you flip to and from during a session.
- Freeing page cache before a load should be the first thing tried (`sync; echo 3 >
  /proc/sys/vm/drop_caches`); it needs root, so the manager cannot do it as `llm-server`.
- The alternative levers are a smaller resident footprint (a lower `--kv-resident` or an explicit
  `--expert-cache` cap, at a decode cost) or a small zram cushion, which is the opposite of the
  current "no swap" default.
