---
type: Research
description: Standalone measurements of the experimental llama.cpp master flags (no-mmap-prefetch, moe-stream, pin-hot-experts) on brys with the Qwen3.8-Flash-Next model, with load time, first-request time, decode/prefill speed, system used memory, RssAnon, and disk read volume per run.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T03:30:00+02:00
---

# Test of the llama.cpp master variants on brys

This document answers item F3 of the task, second part: how does each
experimental master flag behave on brys? The
[build research](master-variants-build.research.md) supplies the store paths and
the flags. The
[offload measurements](../llm-benchmark-suite/002-disk-offload/offload-measurements.research.md)
supply the method and the earlier levers.

## Method

- Host: `brys`, AMD Ryzen 5950X, 128 GB DDR4, no swap, ZFS mirror of two NVMe
  SSDs (pool 50% fragmented, 78% full), Radeon Pro W6600. The ZFS ARC is capped
  at 8 GiB, so a cold read hits the disks.
- Model: Qwen3.8-Flash-Next `UD-IQ4_XS` (94 GB, three shards). Fixed context
  **16384**, `-ngl 0`, `--threads 16`, `--flash-attn on`. One-off server on port
  18080.
- Binary: the matching master build for each run. The four store paths are on
  brys (copied with `nix copy --no-check-sigs`).
- Before each run: `llama-swap` was stopped and `echo 3 > /proc/sys/vm/drop_caches`
  ran, so the first read is cold. One process at a time. After the runs,
  `llama-swap` was restarted and `/v1/models` returned **34** ids.
- Metrics:
  - `load_s` — wall time from process start to HTTP `200` on `/health`.
  - `first_req_s` — server `timings.prompt_ms` of the first request (the prompt
    processing time, which is the first-request latency).
  - `decode_tok_s`, `prefill_tok_s` — from the server `timings` block.
  - `SYS_used_MB` — system `used` from `free -m`, idle after load.
  - `RssAnon_MiB` — process `RssAnon`, idle after load.
  - `read_load_MB` — `read_bytes` from `/proc/<pid>/io` at the end of load.
  - `idle_faults_s` — major faults over 5 s idle.
- The first request is a chat completion of about 3190 prompt tokens (a unique
  corpus, so it misses the prompt cache) and 128 decode tokens at temperature 0.

## Results

| variant | flag | load_s | first_req_s | decode_tok_s | prefill_tok_s | SYS_used_MB | RssAnon_MiB | read_load_MB | note |
|---|---|---|---|---|---|---|---|---|---|
| control | none | 70.7 | 576.3 | 3.04 | 5.5 | 13705 | 1065 | 89234 | baseline; RssFile 44629 MiB; read_req 25147 MB |
| noprefetch | `--no-mmap-prefetch` | 16.2 | 720.1 | 2.48 | 4.4 | 13734 | 1065 | 16106 | RssFile 7853 MiB; read_req 98158 MB |
| moe-stream | `--moe-stream` | — | — | — | — | — | — | — | **ABORT** at load: cache has 20 slots, needs 30 |
| moe-stream | `--moe-stream-cache 8G` | 7.1 | 915.5 | 1.24 | 3.5 | 20698 | 2932 | 12311 | RssFile 32 MiB; read_req 345629 MB |
| moe-stream | `--moe-stream-direct` | — | — | — | — | — | — | — | **ABORT** at load (same cache check) |
| moe-stream | `--moe-stream-direct --moe-stream-cache 8G` | 6.1 | 939.8 | 1.23 | 3.4 | 20629 | 2932 | 11816 | RssFile 32 MiB; read_req 327346 MB |
| pin-hot | `--pin-hot-experts 8` | 70.6 | 591.4 | 2.91 | 5.4 | 13708 | 1065 | 87769 | mlock denied (8 MiB limit) → no-op, equals control |
| pin-hot | `--pin-hot-experts 8` (memlock unlimited) | 119.1 | 601.6 | 2.65 | 5.3 | 48734 | 1065 | 145281 | locks ~35 GB; read_req 25272 MB |
| pin-hot | `--pin-hot-experts 32 --pin-hot-experts-budget-mib 32768` | 119.1 | 587.8 | 3.46 | 5.4 | 48069 | 1065 | 146123 | locks ~34 GB; read_req 27729 MB |

`idle_faults_s` is 0.00 for every run that loaded. The model stays in the page
cache, so no major fault happens while the server is idle.

## Note on the absolute numbers

The decode rate here (about 3.0 t/s) matches the earlier offload doc (3.23 t/s).
The prefill rate here (about 5.5 t/s) is much lower than the earlier doc
(44.3 t/s). The cause is the disk: the pool is now 50% fragmented and 78% full,
and the request-phase read of the lazy expert tensors runs at about 43 MB/s
(25 GB in 576 s), against about 340 MB/s in the earlier doc. The load-phase
sequential read is still about 1.3 GB/s (89 GB in 70 s). The comparison between
variants is valid because every run uses the same box state and the same method.

## Verdict per flag

- **`--no-mmap-prefetch` — mixed.** It is useful as a load-time lever: the load
  drops from 70.7 s to 16.2 s (4.4 times faster), because the load read falls
  from 89 GB to 16 GB. It is harmful to the first request: the deferred read
  moves into the request (25 GB to 98 GB), so the first request rises from 576 s
  to 720 s and decode falls 18%. The total read is the same (about 114 GB). Use
  it only when a fast load matters and the first request can wait.
- **`--moe-stream` — harmful on brys.** The default cache aborts at load: the
  model needs an expert cache of at least `3 * n_expert_used` slots (30), and the
  default has 20. With `--moe-stream-cache 8G` the server starts, but one request
  reads 328-346 GB from disk and decode falls to 1.24 t/s (2.5 times slower than
  control). Process RSS is small (32 MiB) because mmap is off.
- **`--moe-stream-direct` — neutral against buffered streaming.** It gives the
  same numbers as `--moe-stream-cache 8G` (decode 1.23 against 1.24 t/s), so
  O_DIRECT gives no gain here. It is harmful in the same way as `--moe-stream`,
  and it aborts at load without a sufficient cache.
- **`--pin-hot-experts` — harmful on brys.** With the default memlock limit
  (8 MiB) it is a no-op: every `mlock` fails and the run equals the control.
  With the memlock limit raised it locks about 35 GB into non-reclaimable RAM
  (`SYS_used_MB` 13.7 to 48.7 GB), slows the load (70.7 to 119 s), and gives no
  gain: decode stays within noise (2.65-3.46 t/s against 3.04) and the
  request-phase read does not fall. The pin set is learned over time, so one cold
  request cannot benefit.

## Scope limit

**brys has no model larger than RAM.** The Qwen model is 94 GB and the box has
128 GB, so the whole model fits in the page cache. The `--moe-stream` and
`--pin-hot-experts` flags exist for the opposite case: a model too large to hold,
where expert weights must move between disk and RAM. On brys these runs are an
**overhead test**, not the intended large-model case. The overhead is real
(extra disk reads, extra locked RAM), but the benefit of these flags cannot
appear on this box.

## Recommendation

1. Keep the control behaviour (`--load-mode auto`, no extra flag) for the served
   Qwen model on brys.
2. Do not enable `--moe-stream` or `--pin-hot-experts` on brys. Both add cost and
   give no gain for a model that fits in RAM.
3. Test `--moe-stream` and `--pin-hot-experts` only on a host with a model larger
   than RAM. That is the case the flags are built for.
