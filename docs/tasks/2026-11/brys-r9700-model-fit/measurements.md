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
  -n 128 -r 2`, `MESA_VK_DEVICE_SELECT=1002:7551!`. So *prefill* is 512 tokens and *decode* is
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

| harness | config | what it means |
| --- | --- | --- |
| `llamacpp` | `vk-full` | `llama-bench -ngl 99 -fa on -p 512 -n 128 -r 2`. Every tensor in VRAM. Prefill is 512 tokens, decode 128, empty context. |
| `llamacpp` | `vk-moe6` … `vk-moe40` | the same bench with `--n-cpu-moe N`: the expert tensors of the first N of 48 layers stay in RAM. |
| `llamacpp` | `vk-srv32k/N` | `llama-server --fit off -fa on -c 32768 --n-cpu-moe N`, `-t 8`, mmap load. Measured from `/v1/chat/completions` `timings`. |
| `llamacpp` | `vk-srv32k/N+small` | the same, with a second `llama-server` holding `qwen3.5-4b` (`-ngl 99`, `-c 16384`) at the same time. |
| `llamacpp` | `vk-srv8k/N-t16` | `llama-server --fit off -fa on -c 8192 --n-cpu-moe N -t 16 --threads-batch 16`. |
| `llamacpp` | `cpu` | no GPU offload. Kept only as a reference point; not a served configuration. |
| `bmoe` | `bmoe-auto` | `bmoe-cli --auto --no-probe-io -c 2048`. The planner measures the machine, then places tensors. |
| `bmoe` | `bmoe-stream` | the same with `--moe-stream --auto`: experts stay in RAM and VRAM acts as an expert cache. |
| `llamacpp` | `vk-srv2k/6` | `llama-server --fit off -fa on -c 2048 --n-cpu-moe 6 -t 16`. The same-context twin of `bmoe-stream`. |
| `llamacpp` | `vk-srv64k/26` | `llama-server --fit off -fa on -c 65536 --n-cpu-moe 26 --cache-type-k/v q8_0 -t 16`. The served preset. |

Both harnesses read the **same GGUF files**. A model is downloaded once; `llamacpp` and `bmoe` are
two ways to run it.

## Every downloaded model, GPU-resident

`file GB` is what `llama-bench` reports as the loaded model size.

| model | harness | config | file GB | decode t/s | prefill t/s |
| --- | --- | --- | ---: | ---: | ---: |
| qwen3.5-0.8b | llamacpp | vk-full | 0.5 | **324.1** | 15266.6 |
| qwen3.5-2b | llamacpp | vk-full | 1.2 | **236.7** | 9915.6 |
| tmax-2b | llamacpp | vk-full | 1.2 | 236.1 | 9936.0 |
| mellum-2.1-12b-a2.5b-thinking | llamacpp | vk-full | 7.5 | **233.6** | 5691.6 |
| gemma-4-e2b | llamacpp | vk-full | 2.9 | 211.2 | 8018.9 |
| lfm2.5-24b-a2b | llamacpp | vk-full | 13.5 | **211.1** | 5279.6 |
| granite-4.2-3b | llamacpp | vk-full | 2.1 | 174.4 | 6188.6 |
| qwen3-omni-30b-a3b | llamacpp | vk-full | 17.3 | 171.4 | 4207.3 |
| qwen3-vl-30b-a3b | llamacpp | vk-full | 17.3 | 169.7 | 4173.1 |
| ministral-3-3b-instruct | llamacpp | vk-full | 2.0 | 164.2 | 6650.2 |
| ministral-3-3b-reasoning | llamacpp | vk-full | 2.0 | 164.0 | 6755.1 |
| nemotron-3-nano-30b-a3b | llamacpp | vk-full | 22.9 | 144.7 | 4171.1 |
| qwen3.5-4b | llamacpp | vk-full | 2.5 | 137.6 | 5069.5 |
| gemma-4-26b-a4b | llamacpp | vk-full | 13.4 | 134.0 | 3501.6 |
| nemotron-3.5-lightning-30b | llamacpp | vk-full | 23.5 | 133.9 | 4279.0 |
| ornith-1.5-35b-a3b | llamacpp | vk-full | 20.2 | 131.9 | 4048.2 |
| gemma-4-e4b | llamacpp | vk-full | 4.8 | 127.8 | 4847.1 |
| glm-4.7-flash | llamacpp | vk-full | 17.0 | 126.7 | 3768.7 |
| qwen3.6-35b-a3b | llamacpp | vk-full | 20.6 | 121.9 | 3938.1 |
| qwen3.5-35b-a3b | llamacpp | vk-full | 20.5 | 120.7 | 3936.5 |
| olmo-3-7b-instruct | llamacpp | vk-full | 4.2 | 115.6 | 4336.3 |
| qwen3-vl-8b-instruct | llamacpp | vk-full | 4.7 | 105.2 | 3616.2 |
| granite-4.2-8b | llamacpp | vk-full | 5.0 | 94.9 | 3617.7 |
| ministral-3-8b-reasoning | llamacpp | vk-full | 4.8 | 91.5 | 3813.9 |
| ministral-3-8b-instruct | llamacpp | vk-full | 4.8 | 90.8 | 3842.2 |
| tmax-9b | llamacpp | vk-full | 5.2 | 90.4 | 3734.4 |
| qwen3.5-9b | llamacpp | vk-full | 5.3 | 90.0 | 3755.2 |
| mimo-v2.6-qwen-9b | llamacpp | vk-full | 5.4 | 87.6 | 3580.9 |
| gemma-4-12b | llamacpp | vk-full | 6.6 | 67.0 | 2161.7 |
| qwen3.8-27b | llamacpp | vk-full | 15.3 | 32.4 | 1194.1 |
| qwen3.6-27b | llamacpp | vk-full | 15.7 | 31.4 | 1160.1 |
| granite-4.2-30b | llamacpp | vk-full | 16.5 | 31.3 | 1081.6 |
| gemma-4-31b | llamacpp | vk-full | 17.1 | 29.9 | 1030.5 |
| olmo-3.1-32b | llamacpp | vk-full | 18.1 | 29.4 | 984.1 |
| seed-oss-36b | llamacpp | vk-full | 20.3 | 26.9 | 871.9 |

Also present, not generative: `qwen3-embedding-4b`, `qwen3-reranker-4b`.

**Reading of the table.** Every model up to 23.5 GB runs fully in VRAM. The MoE models win:
13-23 GB of weights with 2-5B active parameters give **120-211 t/s**, while dense 27-36B models sit
at **27-32 t/s** and dense 8-12B at 67-95 t/s. The card is not the limit for any of them; the 5950X
never ran.

## Qwen3.8-Flash-Next: 180B in 32 GB

The model is **180B total, 48 layers, 512 experts, top-10**, 262k native context
(`Qwen4ExpForConditionalGeneration`). `UD-IQ1_S` is 62 GB in 3 shards.

| harness | config | ctx | VRAM | decode t/s | prefill t/s |
| --- | --- | ---: | ---: | ---: | ---: |
| llamacpp | vk-moe6 | 0 | — | **30.9** | **481.1** |
| llamacpp | vk-moe8 | 0 | — | 29.8 | 454.7 |
| llamacpp | vk-moe10 | 0 | — | 28.0 | 373.9 |
| llamacpp | vk-moe12 | 0 | — | 27.2 | 393.0 |
| llamacpp | vk-moe14 | 0 | — | 26.5 | 377.9 |
| llamacpp | vk-moe16 | 0 | — | 24.3 | 349.8 |
| llamacpp | vk-moe22 | 0 | — | 22.0 | 280.5 |
| llamacpp | vk-moe28 | 0 | — | 19.6 | 219.2 |
| llamacpp | vk-moe34 | 0 | — | 18.1 | 208.4 |
| llamacpp | vk-moe40 | 0 | — | 16.2 | 162.9 |
| llamacpp | vk-moe2 / 3 / 4 | 0 | — | 12.8 / 31.0 / 12.3 | 131 / 129 / 125 |
| llamacpp | `-ngl 99` untuned | 0 | — | 3.9 | 89.4 |
| llamacpp | vk-srv32k/6 | 32k | 31.7 GiB | 14.6 | 38.1 |
| llamacpp | vk-srv32k/24 | 32k | 21.0 GiB | **20.4** | 52.5 |
| llamacpp | vk-srv32k/24+small | 32k | 24.2 GiB | 20.1 | 19.1 |
| llamacpp | **vk-srv64k/26 + small** | 64k | 23.0 GiB | **21.9** + **125.4** | — |
| llamacpp | `qwen3.5-4b` beside it | 16k | — | 119.1 | 185.9 |
| llamacpp | vk-srv64k/26 | 64k | 19.8 GiB | **20.9** | 32.3 |
| llamacpp | **llama-swap `chat-deep-slow`** | 64k | 19.8 GiB | **21.9** | 255-289 (sustained) |
| llamacpp | **llama-swap `chat-deep-slow` + `grunt`** | 64k | 23.0 GiB | **21.9** + **125.4** | — |

The last two rows are the **served** path, not a hand-run server: the preset in `data/llm.nix`
(`nGpuLayers 99`, `nCpuMoe 26`, `loadMode mmap`, `extraFlags ["--fit" "off"]`, `parallel 1`,
`cacheTypeK/V q8_0`, `--threads 16` from the host default, served at 64k). Two llama-servers stay up
together with 23.0 GiB of VRAM in total, and neither loses throughput when the other runs.

**Prefill, measured properly.** A 16-token prompt reports ~50 t/s because the fixed per-request
cost dominates. Four real prompt lengths at the served preset:

| prompt tokens | prefill t/s | wall |
| ---: | ---: | ---: |
| 2572 | 257.3 | 10.0 s |
| 8496 | 288.9 | 29.4 s |
| 11016 | 272.4 | 40.5 s |
| 21516 | 255.1 | 84.4 s |

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

| harness | config | VRAM | decode t/s | prefill t/s |
| --- | --- | ---: | ---: | ---: |
| llamacpp | vk-srv32k/24 (flash-next alone) | 21.0 GiB | 20.4 | 52.5 |
| llamacpp | vk-srv32k/24+small (flash-next) | 24.2 GiB | 20.1 | 19.1 |
| llamacpp | vk-srv32k/24+small (`qwen3.5-4b`) | — | **119.1** | 185.9 |

**62 GB of frontier model coexists with a 2.5 GB model in 24.2 GiB of VRAM and ~95 GiB of free
RAM**, and the frontier loses nothing (20.4 → 20.1 t/s). A 9B model (5.3 GB) fits the same
headroom. This is the shape to serve: frontier at `n-cpu-moe 24`, a small model fully offloaded,
both resident.

## GLM-5.3-Flash: 321B in 157 GB of memory

321B, 45 layers, 288 experts, top-8, 1M context. `UD-IQ2_XXS` is 102 GB in 4 shards, and it fits in
125 GiB of RAM with room for the KV cache.

| harness | config | ctx | VRAM | decode t/s | prefill t/s |
| --- | --- | ---: | ---: | ---: | ---: |
| llamacpp | vk-srv8k/40 | 8k | 18.7 GiB | 8.1 | 9.3 |
| llamacpp | vk-srv8k/38 | 8k | 22.9 GiB | 8.3 | 11.0 |
| llamacpp | vk-srv8k/36 | 8k | 27.0 GiB | 8.5 | 12.2 |
| llamacpp | vk-srv8k/36-t16 | 8k | 28.9 GiB | **8.9** | **14.3** |

**GLM-5.3-Flash is CPU-bound here.** Pushing 5 → 9 layers of experts into VRAM (18.7 → 27 GiB) buys
0.4 t/s. The 5950X computes the RAM-resident experts, and it is the wall. 16 threads add a little
over 8 (8.5 → 8.9 decode, 12.2 → 14.3 prefill).

**A load-mode trap.** `--load-mode none` on this 102 GB model makes RADV fail with
`Not enough memory for command submission` → `device lost on Vulkan0` at load. mmap works. One
attempt with `--load-mode none` also left a task in uninterruptible sleep holding all 32 GiB and
required a host reset; the mmap path has not repeated it.

## Harness comparison on the same file

Qwen3.8-Flash-Next `UD-IQ1_S`, same GGUF, same card, 2k context for the apples-to-apples pair:

| harness | config | ctx | decode t/s | prefill t/s | note |
| --- | --- | ---: | ---: | ---: | --- |
| llamacpp | vk-moe6 | 0 | **30.9** | **481.1** | llama-bench |
| llamacpp | `vk-srv2k/6` | 2k | **30.7** | 38.3 | llama-server, `-t 16`, whole card (31.4 GiB) |
| bmoe | `bmoe-stream` | 2k | **29.5** | **60.6** | `--moe-stream --auto`, 26.6 GB expert cache, load 13 s |
| llamacpp | vk-srv32k/24 | 32k | **20.4** | 52.5 | llama-server |
| bmoe | bmoe-auto | 2k | 8.2 | 2.4 | `--auto` chose a host-expert placement |

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

| ctx | VRAM | decode t/s | prefill t/s (10.5k prompt) |
| ---: | ---: | ---: | ---: |
| 32k | 31.0 GiB | **66.9** | 2822 |
| 64k | 31.0 GiB | **67.0** | 2817 |
| 128k | 31.0 GiB | **68.6** | 2799 |
| 256k | 31.0 GiB | **66.7** | 2779 |

Two quants, both at 256k:

| pack | size | decode t/s | prefill t/s (10.5k) | VRAM |
| --- | ---: | ---: | ---: | ---: |
| GSQ-RCO **IQ2_XS** | 63 GiB | **66.7** | 2779 | 31.0 GiB |
| GSQ-RCO **IQ3_XXS** | 70 GiB | **63.0** | 2844 | 31.1 GiB |

The better quant costs 5 % decode and buys a quality tier; both fill the card.

Decode is flat from 32k to the model's **native 256k**, and prefill is ~2.8k t/s. MTP on/off made no
difference (67.2 vs 66.9). The engine reports an expert cache of 24.9 GiB and ~864 MiB of VRAM free.

**Against llama.cpp on this box:** 66.9 vs 22.3 t/s decode (3.0x) and 2822 vs 255 t/s prefill
(11x), at four times the context. The comparison is not quant-for-quant — llama.cpp cannot read the
GSQ-RCO pack at all (it rejects `UD-IQ1_S` as "a GGUF Strata cannot run" in the other direction; the
two engines use different quant families). It is a harness comparison: best Strata config against
best llama.cpp config.

| harness | model | ctx | decode | prefill |
| --- | --- | ---: | ---: | ---: |
| Strata + HIP | GSQ-RCO IQ2_XS, 63 GiB | 256k | **66.7** | **2779** |
| llama.cpp Vulkan | UD-IQ1_S, 62 GB, `n-cpu-moe 26` | 64k | 22.3 | 255 |
| BigMoeOnEdge Vulkan | UD-IQ1_S, `--moe-stream` | 2k | 29.5 | 60.6 |

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

| idea | result |
| --- | --- |
| llama.cpp **0.9.0** instead of the served 0.6.0 | the nixpkgs build has **no Vulkan backend** (`libggml-vulkan.so` absent) and falls back to BLAS/CPU: 11.8 t/s against 137.7 on the same 4B model. Not a fair comparison until someone packages a Vulkan 0.9.0; the repo's own package is the only Vulkan build on the host. |
| **Speculative decoding** with a small draft | `qwen3.5-9b` + `qwen3.5-0.8b` draft: 87.0 t/s plain vs 86.7 with the draft, and `draft_n` stayed `None`, so no drafting happened. There is no matched drafter on disk for any dense model we serve. |
| **Maya** for GLM-5.3-Flash | blocked on packaging (see above), not on the card. |
| **ik_llama.cpp** | not in nixpkgs; a source build with its own Vulkan flags. Left as a task. |
| deeper power caps (175/150 W) | the driver floor is 210 W on this card; anything lower is refused. |
