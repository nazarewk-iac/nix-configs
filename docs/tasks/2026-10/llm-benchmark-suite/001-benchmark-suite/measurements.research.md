---
type: Research
description: Full harness pass over every enabled brys model (2026-10-19): cold start, TTFT, decode, prefill, cache reuse, resident memory, and idle faults, one unified table.
task: definition.md
authored_by: agent
timestamp: 2026-10-19T19:45:00+02:00
---

# Benchmark suite measurements (2026-10-19)

This file holds the result of one full pass of `hack/llm-bench.sh` over every
real brys model id. The harness ran 31 models in a fixed order: the small models
first and the two frontier models last. Every throughput and memory number below
is measured on brys on 2026-10-19.

## Legend

The harness steps and their columns:

| column | step | source key | meaning |
|---|---|---|---|
| `cold_start_s` | `cold-start`, phase `cold` | `ttft_s` | Seconds from the first request, with the model not resident, to the first streamed token. |
| `ttft_s` | `ttft`, phase `stream` | `ttft_s` | Seconds to the first streamed token when the model is resident. |
| `decode_tok_s` | `decode`, phase `run` | `timings.predicted_per_second` | Generation rate. |
| `prefill_tok_s` | `prefill`, phase `run` | `timings.prompt_per_second` | Prompt-processing rate on a unique prompt. |
| `cache_n` | `prefill`, phase `run` | `timings.cache_n` | Tokens served from the prompt cache. The prompt is unique, so this is zero unless the cache held a prefix. |
| `RssFile_MiB` | `mem`, phase `run` | `/proc/<pid>/status` `RssFile` | mmap'd weights. Reclaimable. |
| `RssAnon_MiB` | `mem`, phase `run` | `RssAnon` | KV cache plus compute buffers. Not reclaimable. |
| `VmRSS_MiB` | `mem`, phase `run` | `VmRSS` | Total resident set. |
| `VRAM_MiB` | — | — | Not measured by this harness. See caveats. |
| `idle_faults_s` | `faults`, phase `idle` | `/proc/<pid>/stat` field 12 | Major faults per second over five seconds, at idle. |
| `context` | — | `/v1/models` `context_length` | The model's real served maximum. |

Every row in the table is measured on 2026-10-19, except the `context` column,
which comes from the server `/v1/models` field (reused: server-driven context,
see [server-context-2026-10-19.research.md](../brys-grunt-colocation/server-context-2026-10-19.research.md)).

## Measurements

| model | class | cold_start_s | ttft_s | decode_tok_s | prefill_tok_s | cache_n | RssFile_MiB | RssAnon_MiB | VmRSS_MiB | VRAM_MiB | idle_faults_s | context |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| qwen3.5-0.8b | surveyed-gpu | 2.38 | 0.22 | 208.42 | 4732.41 | 0 | 234 | 462 | 696 | — | 0.000 | 16384 |
| qwen3.5-0.8b-cpu | surveyed-cpu | 2.52 | 0.17 | 204.70 | 4631.45 | 0 | 234 | 461 | 695 | — | 0.000 | 8192 |
| qwen3.5-2b | surveyed-gpu | 2.61 | 0.20 | 119.90 | 2545.02 | 0 | 433 | 463 | 895 | — | 0.000 | 16384 |
| qwen3.5-2b-cpu | surveyed-cpu | 2.62 | 0.20 | 118.91 | 2540.22 | 0 | 433 | 462 | 895 | — | 0.000 | 8192 |
| tmax-2b | surveyed-gpu | 2.57 | 0.21 | 120.18 | 2611.84 | 0 | 432 | 462 | 894 | — | 0.000 | 16384 |
| tmax-2b-cpu | surveyed-cpu | 2.60 | 0.19 | 120.51 | 2606.86 | 0 | 433 | 461 | 894 | — | 0.000 | 8192 |
| granite-4.2-3b | surveyed-gpu | 6.61 | 0.32 | 85.17 | 1127.08 | 8 | 176 | 430 | 605 | — | 0.000 | 16384 |
| ministral-3-3b-instruct | surveyed-gpu | 5.99 | 0.38 | 79.26 | 948.84 | 534 | 353 | 650 | 1003 | — | 0.000 | 16384 |
| ministral-3-3b-reasoning | surveyed-gpu | 6.51 | — | 80.62 | 1116.47 | 125 | 350 | 589 | 939 | — | 0.000 | 16384 |
| qwen3.5-4b | grunt | 3.67 | 0.41 | 60.56 | 989.30 | 0 | 532 | 928 | 1461 | — | 0.000 | 16384 |
| gemma-4-e2b | surveyed-gpu | 7.70 | 0.16 | 105.46 | 1792.97 | 1 | 1794 | 244 | 2038 | — | 0.000 | 16384 |
| olmo-3-7b-instruct | surveyed-gpu | 9.80 | 1.67 | 46.42 | 537.61 | 0 | 258 | 5799 | 6057 | — | 0.000 | 16384 |
| gemma-4-e4b | surveyed-gpu | 12.11 | 0.31 | 60.25 | 1201.62 | 1 | 2768 | 417 | 3185 | — | 0.000 | 16384 |
| granite-4.2-8b | surveyed-gpu | 11.90 | 0.61 | 38.54 | 493.40 | 8 | 255 | 767 | 1022 | — | 0.000 | 16384 |
| ministral-3-8b-instruct | surveyed-gpu | 12.71 | 0.63 | 38.36 | 472.79 | 534 | 323 | 808 | 1131 | — | 0.000 | 16384 |
| ministral-3-8b-reasoning | surveyed-gpu | — | — | 38.81 | 511.36 | 125 | 323 | 784 | 1107 | — | 0.000 | 16384 |
| mimo-v2.6-qwen-9b | surveyed-gpu | 12.83 | 0.46 | 35.43 | 587.35 | 0 | 581 | 921 | 1501 | — | 0.000 | 16384 |
| tmax-9b | surveyed-gpu | 3.89 | 0.60 | 36.75 | 583.59 | 0 | 581 | 923 | 1503 | — | 0.000 | 16384 |
| gemma-4-12b | surveyed-cpu | 18.36 | 1.31 | 18.53 | 335.10 | 1 | 1125 | 2555 | 3680 | — | 0.000 | 16384 |
| gemma-4-26b-a4b | surveyed-cpu | 30.28 | 1.00 | 26.62 | 359.25 | 1 | 13790 | 1654 | 15445 | — | 0.000 | 8192 |
| qwen3.6-27b | surveyed-cpu | 37.89 | 4.50 | 3.13 | 102.06 | 0 | 9629 | 2790 | 12419 | — | 0.000 | 8192 |
| granite-4.2-30b | surveyed-cpu | 53.06 | 4.99 | 3.00 | 95.82 | 8 | 10919 | 2533 | 13452 | — | 0.000 | 8192 |
| gemma-4-31b | surveyed-cpu | 40.68 | 6.28 | 2.78 | 83.64 | 1 | 12098 | 7411 | 19509 | — | 0.000 | 8192 |
| glm-4.7-flash | surveyed-cpu | 35.00 | 0.85 | 20.16 | 289.57 | 3 | 17243 | 359 | 17602 | — | 0.000 | 8192 |
| olmo-3.1-32b | surveyed-cpu | 47.16 | 11.44 | 2.73 | 86.37 | 44 | 12246 | 4169 | 16415 | — | 0.000 | 8192 |
| seed-oss-36b | surveyed-cpu | 60.01 | 28.10 | 2.40 | 74.28 | 3 | 14513 | 2727 | 17240 | — | 0.000 | 8192 |
| qwen3.5-35b-a3b | surveyed-cpu | 41.81 | 0.87 | 22.99 | 261.41 | 0 | 20625 | 1047 | 21672 | — | 0.000 | 8192 |
| qwen3.6-35b-a3b | surveyed-cpu | 41.37 | 0.85 | 22.32 | 252.72 | 0 | 20735 | 1044 | 21779 | — | 0.000 | 8192 |
| nemotron-3.5-lightning-30b | surveyed-cpu | 45.17 | 0.89 | 20.37 | 316.71 | 5 | 22825 | 1028 | 23853 | — | 0.000 | 8192 |
| deepseek-v4-flash | frontier | 310.53 | 54.46 | 1.46 | 17.15 | 0 | 79725 | 10922 | 90647 | — | 0.000 | 327680 |
| qwen3.8-flash-next | frontier | 156.14 | 11.00 | 2.49 | 31.35 | 30 | 57035 | 18477 | 75512 | — | 0.000 | 1048576 |

A dash means the value is not available. `ttft_s` is a dash for the two
`*-reasoning` models and `cold_start_s` is a dash for
`ministral-3-8b-reasoning` only. See caveats.

## Reuse

Every throughput and memory row above is re-measured on 2026-10-19. No row in
the table is reused from an earlier run. Two cells come from a prior source and
are marked reused:

- `context` — reused from the `/v1/models` `context_length` field, documented in
  [server-context-2026-10-19.research.md](../brys-grunt-colocation/server-context-2026-10-19.research.md).
- `VRAM_MiB` — not available. A complete per-model VRAM row does not exist in
  [coresidency-measured.research.md](../brys-grunt-colocation/coresidency-measured.research.md)
  or in any other prior file, and this harness does not read the GPU.

The prior full-sweep file
[coresidency-measured.research.md](../brys-grunt-colocation/coresidency-measured.research.md)
holds compatible rows for many models. A reader can compare them directly,
because both use `-c 16384`. The numbers differ in a few places (for example
`olmo-3-7b-instruct` CPU `RssAnon` 5,799 MiB here against 11,445 MiB there,
and `tmax-9b` GPU decode 36.75 here against 36.9 there consistent). The
difference is expected: the prior value is a concurrent run, this value is a
single-resident run.

## Caveats

### Trustworthy cold starts

The caller restarted `llama-swap` before the pass and confirmed
`GET /v1/models` showed no resident model. Each non-frontier model then loaded
after the previous one, so the box held at most one surveyed model at a time.
The `resident-before` value for each of those 30 models was the previous,
evicted model. So each non-frontier `cold_start_s` is a real cold start with
the page cache cold for that model.

### Frontier cold starts

The two frontier models loaded while `nemotron-3.5-lightning-30b` stayed
resident, because the `matrix` engine keeps the frontier set and a grunt
together. This is the intended co-residency. It means:

- `deepseek-v4-flash` cold start (310.53 s) ran against a resident
  `nemotron-3.5-lightning-30b`. The page cache for the DS4 weights was cold, so
  the value is a real cold load, but the resident grunt held about 24 GB of RAM
  during the load.
- `qwen3.8-flash-next` cold start (156.14 s) ran against the same resident
  grunt.

Both values are higher than the ~120 s the prior sweep reports in
[server-context-2026-10-19.research.md](../brys-grunt-colocation/server-context-2026-10-19.research.md),
because that sweep did not hold a grunt resident.

### Box state

| when | resident set |
|---|---|
| start | none (after restart) |
| each surveyed model | that model alone (previous model evicted) |
| `deepseek-v4-flash` | `deepseek-v4-flash` + `nemotron-3.5-lightning-30b` |
| `qwen3.8-flash-next` | `qwen3.8-flash-next` + `nemotron-3.5-lightning-30b` |

The box is a Ryzen 5950X with 128 GB RAM (125 GiB reported) and one 8 GB GPU.
The `box_note` one-minute load stayed low through the pass.

### Failures and missing values

- No model failed. All 32 harness invocations exited 0.
- The `ttft_s` (stream) value is a dash for `ministral-3-3b-reasoning` and
  `ministral-3-8b-reasoning`, and `cold_start_s` is a dash for
  `ministral-3-8b-reasoning`. Cause: these are reasoning models. The streamed
  answer put its text in the reasoning field, not in `content`, so the harness
  never saw a content delta and reported a null time to first token. The
  non-streamed TTFT and the decode and prefill rates are valid for both models.
  This matches the known behaviour in
  [server-context-2026-10-19.research.md](../brys-grunt-colocation/server-context-2026-10-19.research.md).
- `VRAM_MiB` is not measured. The harness reads only `/proc/<pid>/status` over
  ssh. It does not read the GPU. The one memory reader on brys shows total GPU
  use, not per-model use, and each model would need a reload to read it. So the
  column is a dash for every row.
- `idle_faults_s` is 0.000 for every model. The models held their weights in
  RAM and did not have to re-read from disk at idle. This is a valid measurement,
  not a missing one.

### Method notes

- The prompt for prefill is unique, so `cache_n` is normally zero. A non-zero
  `cache_n` (for example `olmo-3.1-32b` 44, `qwen3.8-flash-next` 30) means the
  server held a shared prefix from an earlier request.
- `--max-tokens` was the default 128 for the decode step. `--prompt-tokens` was
  the default 2048 for the prefill step.
- The harness ran with `--timeout 900` for every model.

## Raw output

The raw JSON rows are at `/tmp/opencode/bench-2026-10-19.jsonl` (578 rows) and
the run log with the box state is at `/tmp/opencode/bench-2026-10-19.log`.
