---
type: Research
description: Measured co-residency profile of 25 models on brys (2026-10-18, llama-server, -c 16384) with per-model RssFile/RssAnon/VmRSS and decode/prefill throughput, plus the co-residency analysis against the Qwen3.8-Flash-Next and DeepSeek V4 Flash orchestrator budgets.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T15:00:00+02:00
---

# Measured co-residency results on brys

> **Scope.** Every number below is **measured** on brys on 2026-10-18 with
> `llama-server` at `-c 16384`. Memory is in MiB. Throughput is in tok/s. No value
> here is an estimate.

## Legend

| symbol | meaning |
|---|---|
| RssFile | mmap'd weights. Reclaimable: the page cache drops it under pressure. |
| RssAnon | KV cache plus compute buffers. NOT reclaimable: it stays resident. |
| VmRSS | total resident set (RssFile + RssAnon). |
| decode t/s | generation rate. |
| prefill t/s | prompt-processing rate. |

## Measurements

| model | file GB | mode | RssFile | RssAnon | VmRSS | decode t/s | prefill t/s |
|---|---|---|---|---|---|---|---|
| qwen3.5-0.8b | 0.5 | CPU | 508 | 535 | 1043 | 55.8 | 43.0 |
| qwen3.5-0.8b | 0.5 | GPU | 234 | 114 | 348 | 163.4 | 63.8 |
| qwen3.5-2b | 1.2 | CPU | 1222 | 864 | 2085 | 20.1 | 118.5 |
| qwen3.5-2b | 1.2 | GPU | 430 | 114 | 544 | 116.8 | 273.5 |
| qwen3.5-4b | 2.6 | CPU | 2614 | 2118 | 4733 | 13.0 | 68.7 |
| qwen3.5-4b | 2.6 | GPU | 529 | 114 | 643 | 60.8 | 158.0 |
| granite-4.2-3b | 2.1 | CPU | 2136 | 2770 | 4906 | 19.8 | 174.0 |
| granite-4.2-3b | 2.1 | GPU | 172 | 59 | 232 | 83.9 | 223.6 |
| granite-4.2-8b | 5.0 | CPU | 5079 | 6270 | 11349 | 8.2 | 71.1 |
| granite-4.2-8b | 5.0 | GPU | 253 | 46 | 298 | 38.6 | 146.0 |
| gemma-4-e4b | 4.8 | CPU | 4912 | 2600 | 7512 | 9.6 | 50.5 |
| gemma-4-e4b | 4.8 | GPU | 2766 | 170 | 2936 | 56.6 | 46.6 |
| mimo-v2.6-qwen-9b | 5.5 | CPU | 5571 | 3754 | 9325 | 5.7 | 28.1 |
| qwen3.5-9b | 5.3 | CPU | 5418 | 3437 | 8855 | 5.6 | 40.8 |
| gemma-4-26b-a4b | 14 | CPU | 13766 | 14482 | 28248 | 14.5 | 67.7 |
| qwen3.6-27b | 16 | CPU | 16039 | 11759 | 27798 | 1.8 | 10.1 |
| gemma-4-31b | 18 | CPU | 17471 | 19319 | 36790 | 1.7 | 9.3 |
| granite-4.2-30b | 17 | CPU | 16836 | 17029 | 33865 | 2.1 | 17.1 |
| glm-4.7-flash | 18 | CPU | 17466 | 13886 | 31352 | 11.5 | 46.5 |
| qwen3.5-35b-a3b | 21 | CPU | 20996 | 12210 | 33206 | 9.2 | 45.9 |
| qwen3.6-35b-a3b | 21 | CPU | 21109 | 12210 | 33320 | 10.9 | 49.7 |
| seed-oss-36b | 20 | CPU | 20759 | 20178 | 40937 | 2.0 | 12.0 |
| olmo-3.1-32b | 19 | CPU | 18587 | 18361 | 36951 | 2.3 | 17.6 |
| nemotron-3.5-lightning-30b | 24 | CPU | 23164 | 363 | 23527 | 12.9 | 44.0 |
| nemotron-3.5-bolt-74b | 21 | — | — | — | — | — | will not load (tensor shape error) |

## Co-residency analysis

### The two orchestrator budgets

- **Qwen3.8-Flash-Next**: idle ~65 GB, warm ~101-116 GB.
- **DeepSeek V4 Flash**: ~92 GB.
- **Budget**: 125 GB total.

### Against a WARM Qwen (~108 GB)

Only models with `VmRSS <= ~12 GB` leave `>=5 GB` headroom. These are:

- qwen3.5-0.8b, qwen3.5-2b, qwen3.5-4b, qwen3.5-9b
- granite-4.2-3b, granite-4.2-8b
- gemma-4-e4b
- mimo-v2.6-qwen-9b

### Against an IDLE Qwen (~65 GB) or DeepSeek (~92 GB)

One big model can co-reside. The memory-efficient heavyweights are:

- the 3B-active MoEs, qwen3.5-35b-a3b and qwen3.6-35b-a3b: ~12 GB anon, ~33 GB VmRSS;
- nemotron-3.5-lightning-30b: ~0.4 GB anon, 23.5 GB;
- gemma-4-26b-a4b.

The dense 27-36B models cost the most (17-20 GB anon) and are the slowest
(1.7-2.3 tok/s), so they are poor co-residents:

- qwen3.6-27b, gemma-4-31b, granite-4.2-30b, seed-oss-36b, olmo-3.1-32b.

### Key insight

`RssAnon` is the binding constraint, because it is not reclaimable. The
`nemotron-3.5-lightning-30b` model (RssAnon 363 MiB) is the cheapest big model to
keep resident. The dense 27-36B models are the most expensive.

### Corrupt artifact

The `nemotron-3.5-bolt-74b` GGUF is corrupt or incompatible. It fails to load on
every build with a tensor shape error.

## llama-swap expression

llama-swap `matrix` `evict_costs` plus `sets` expresses this co-residency:

- The small GPU-fit grunts can share a set with the orchestrator.
- The big CPU MoEs belong in an "orchestrator idle" set.

## Concurrent small-dense benchmark (added 2026-10-18)

The nine small dense models downloaded later were measured **concurrently** on
brys: each batch starts several `llama-server` processes on distinct ports with
4 threads each, and every server answers `/health` before measurement starts.
Only the 8 GB W6600 limits the GPU runs, so those stay one at a time. All values
are measured, same method as the table above.

| model | file size | RssFile | RssAnon | VmRSS | decode t/s | prefill t/s | mode |
|---|---|---|---|---|---|---|---|
| ministral-3-3b-instruct | 2.15 G | 2,119 MiB | 1,778 MiB | 3,898 MiB | 17.4 | 480 | CPU |
| ministral-3-3b-instruct | 2.15 G | 355 MiB | 74 MiB | 429 MiB | 79.3 | 1369 | GPU |
| ministral-3-3b-reasoning | 2.15 G | 2,119 MiB | 1,778 MiB | 3,898 MiB | 18.9 | 202 | CPU |
| ministral-3-3b-reasoning | 2.15 G | 355 MiB | 74 MiB | 429 MiB | 80.9 | 933 | GPU |
| ministral-3-8b-instruct | 5.2 G | 5,100 MiB | 2,303 MiB | 7,403 MiB | 8.1 | 244 | CPU |
| ministral-3-8b-instruct | 5.2 G | 328 MiB | 74 MiB | 402 MiB | 38.4 | 576 | GPU |
| ministral-3-8b-reasoning | 5.2 G | 5,100 MiB | 2,303 MiB | 7,403 MiB | 8.5 | 56 | CPU |
| ministral-3-8b-reasoning | 5.2 G | 328 MiB | 74 MiB | 402 MiB | 38.9 | 458 | GPU |
| gemma-4-e2b | 3.11 G | 3,052 MiB | 263 MiB | 3,315 MiB | 23.8 | 37.8 | CPU |
| gemma-4-e2b | 3.11 G | 1,833 MiB | 133 MiB | 1,967 MiB | 83.5 | 38.8 | GPU |
| gemma-4-12b | 7.12 G | 6,971 MiB | 1,871 MiB | 8,842 MiB | 5.76 | 10.4 | CPU |
| tmax-2b | 1.27 G | 1,265 MiB | 385 MiB | 1,650 MiB | 28.6 | 79.7 | CPU |
| tmax-2b | 1.27 G | 440 MiB | 117 MiB | 557 MiB | 110.7 | 311 | GPU |
| tmax-9b | 5.63 G | 5,518 MiB | 839 MiB | 6,358 MiB | 7.18 | 20.7 | CPU |
| tmax-9b | 5.63 G | 591 MiB | 117 MiB | 708 MiB | 36.9 | 121 | GPU |
| olmo-3-7b-instruct | 4.47 G | 4,374 MiB | 11,445 MiB | 15,819 MiB | 9.83 | 25.9 | CPU |
| olmo-3-7b-instruct | 4.47 G | 261 MiB | 62 MiB | 323 MiB | 40.4 | 136 | GPU |

Batches: CPU-1 = the six models up to gemma-4-e2b (resident sum ~22 GB);
CPU-2 = gemma-4-12b, tmax-9b, olmo-3-7b (resident sum ~17 GB). Both stay well
under the ~100 GB cap, so the concurrency does not disturb the live orchestrator.
GPU runs are serial (single 8 GB W6600).

Findings:

- **GPU fit is the fast lane.** Every model that fits the 8 GB card decodes at
  37-110 tok/s on Vulkan0, while the same model on CPU is 6-14 tok/s. The best
  grunts by speed are `tmax-2b` (110.7) and `gemma-4-e2b` (83.5).
- **`olmo-3-7b-instruct` is an outlier.** CPU `RssAnon` is 11,445 MiB for a
  4.47 G file: its chat template needs a fallback. It only loads with
  `--no-jinja --chat-template chatml`, otherwise it fails with
  `Unable to generate parser for this template ... filter 'tojson'`. Its CPU VmRSS
  (15.8 GB) makes it a poor co-resident; on GPU it is fine (323 MiB).
  This is a llama.cpp template-compatibility gap, not a brys issue.
- **`gemma-4-12b` prefill is slow** (10.4 tok/s CPU) even though its decode is
  acceptable, so it is a weak interactive model.
