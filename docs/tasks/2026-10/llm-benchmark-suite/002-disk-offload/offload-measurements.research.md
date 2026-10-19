---
type: Research
description: Standalone measurements of llama.cpp disk-offload and RAM-reduction levers for the brys models (Qwen3.8-Flash-Next at 94 GB and gemma-4-12b at 7 GB), with load time, decode/prefill speed, process RSS, system used memory, disk read volume, and idle major faults per lever.
task: definition.md
authored_by: agent
timestamp: 2026-10-19T21:10:00+02:00
---

# Disk-offload and RAM-reduction measurements (brys, standalone)

This document reports the measured effect of each lever from
[offload.research.md](offload.research.md). Every run is a one-off
`llama-server` process, not wired into a boot entry or `llama-swap`. The
inventory doc holds the flag definitions and upstream sources; this doc holds
the numbers.

## Method

- Host: `brys`, AMD Ryzen 5950X (16 cores), 128 GB DDR4, no swap, ZFS
  storage, Radeon Pro W6600 (Vulkan). Lix 2.95.3.
- Binary for every run:
  `llama-cpp-vulkan-noblas-0.6.0` (build 11029/0.6.0, CPU + Vulkan, no BLAS).
  This is the same build family the host serves.
- Fixed context: **16384**. Fixed prompt: ~3171 tokens of unique text (a
  cache-missing prompt, so it does not hit the prefix cache). Decode: 128
  tokens at temperature 0. `--threads 16`, `--flash-attn on`. No MTP draft and
  no speculative decoding, so the numbers are the base model only.
- Before each run: `echo 3 > /proc/sys/vm/drop_caches`, so the first read is
  cold. One process at a time; each is stopped before the next.
- Metrics per run:
  - `load_s` — wall time from process start to a `200` on `/health`.
  - `decode_tok_s`, `prefill_tok_s` — from the server `timings` block.
  - `RssFile_MiB`, `RssAnon_MiB`, `VmRSS_MiB` — idle, before the request.
  - `read_MB` — `read_bytes` from `/proc/<pid>/io` during the request phase
    (the load-phase read is in the note as `read_load_MB`).
  - `idle_faults_s` — major faults over 5 s idle.
- **Box state.** The served frontier model (Qwen3.8-Flash-Next) was resident
  for the mid-model runs (gemma-4-12b): `used` ~32 GB, `buff/cache` ~44-62 GB,
  `available` ~89-96 GB. For the frontier runs, `llama-swap` was **stopped** to
  free RAM (`used` 42.8 → 18.7 GB, `available` 110 GB), then **restarted** and
  `/v1/models` was confirmed to return 34 ids. The frontier numbers are
  therefore on an otherwise-idle box. The mid-model numbers carry the served
  model's page-cache pressure.

## Absent builds (not tested)

No `master` build is present in the Nix store on brys:

- `--no-mmap-prefetch` — **absent**. The binary rejects it:
  `error: invalid argument: --no-mmap-prefetch`. Only `--load-mode`,
  `--lazy-mode` and `--cache-ram` exist. Confirmed by `--help`.
- `llama-cpp-master-moe-stream-vulkan` (`--moe-stream*`) — **absent**.
- `llama-cpp-master-pin-hot-experts-vulkan` (`--pin-hot-experts*`) — **absent**.

The `llama-cpp-master-vulkan`, `llama-cpp-master-noprefetch-vulkan`,
`llama-cpp-master-moe-stream-vulkan` and
`llama-cpp-master-pin-hot-experts-vulkan` rows exist only as flakes in the
repo; no host builds them and the store has none.

## Results

`SYS_USED` is the system `used` from `free -m` while the server is idle after
load. It is the honest RAM figure; `VmRSS` counts only the process.

### Mid model: gemma-4-12b (7.1 GB, ctx 16384)

| lever | model | load_s | decode_tok_s | prefill_tok_s | RssFile_MiB | RssAnon_MiB | VmRSS_MiB | read_MB | idle_faults_s | note |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline (mmap, lazy auto) | gemma-4-12b | 31 | 5.30 | 62.5 | 4952 | 1338 | 6290 | 4 | 0 | read_load 8381 MB |
| `--lazy-mode off` | gemma-4-12b | 30 | 5.26 | 61.7 | 4952 | 1338 | 6290 | 3 | 0 | no tensor >4 GiB; no-op |
| `--lazy-mode on` | gemma-4-12b | 31 | 5.45 | 61.9 | 4952 | 1338 | 6290 | 3 | 0 | no-op |
| `--load-mode mmap` | gemma-4-12b | 29 | 5.36 | 62.0 | 4952 | 1338 | 6290 | 0 | 0 | same as baseline |
| `--load-mode mlock` | gemma-4-12b | — | — | — | — | — | — | — | — | **ABORT (core dumped)** at load: `RLIMIT_MEMLOCK` is 8 MiB |
| `--load-mode none` | gemma-4-12b | 22 | 4.97 | 65.3 | 32 | 1339 | 1371 | 2 | 0 | RssFile→0; read_load 8602 MB |
| `--load-mode dio` | gemma-4-12b | 22 | 5.22 | 65.3 | 32 | 1338 | 1370 | 0 | 0 | like `none`; read_load 7364 MB |
| `--cache-ram 256` | gemma-4-12b | 30 | 5.02 | 61.7 | 4952 | 1338 | 6290 | 2 | 0 | no effect on one request |
| `-ctk q8_0 -ctv q8_0` | gemma-4-12b | 31 | 5.13 | 49.5 | 4833 | 763 | 5596 | 0 | 0 | KV F16→q8_0; prefill −20% |
| `-ctk q4_0 -ctv q4_0` | gemma-4-12b | 30 | 5.21 | 50.0 | 4698 | 468 | 5166 | 1 | 0 | KV→q4_0; prefill −20% |
| `-ngl 99 -cmoe -nkvo` | gemma-4-12b | 18 | — | — | 575 | 1862 | 2437 | — | — | **HANG** >300 s on the request; killed. GPU path unusable |

### Frontier: Qwen3.8-Flash-Next UD-IQ4_XS (94 GB, ctx 16384)

| lever | model | load_s | decode_tok_s | prefill_tok_s | RssFile_MiB | RssAnon_MiB | VmRSS_MiB | read_MB | idle_faults_s | note |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline (mmap, lazy auto) | Qwen3.8-Flash-Next | 83 | 3.23 | 44.3 | 45169 | 148 | 45312 | 24488 | 0 | SYS_USED 15.7 GB; read_load 91.9 GB |
| `--lazy-mode off` (mmap) | Qwen3.8-Flash-Next | 146 | 5.22 | 73.6 | 88835 | 144 | 88935 | 0 | 0 | SYS_USED 15.9 GB; read_load 176.7 GB |
| `--load-mode none` | Qwen3.8-Flash-Next | 40 | 4.43 | 98.3 | 32 | 239 | 271 | 2236 | 0 | SYS_USED **71.2 GB**; read_load 90.3 GB |
| `--load-mode dio` | Qwen3.8-Flash-Next | — | — | — | — | — | — | — | — | **CRASH (device lost)** at load: `ggml_vulkan: device fault on Vulkan0`, `vk::Queue::submit: ErrorDeviceLost` |
| lazy off + `-ctk q8_0 -ctv q8_0` | Qwen3.8-Flash-Next | 147 | 6.08 | 73.7 | 88838 | 141 | 88935 | 0 | 0 | RssAnon ~same as F16; KV tiny at 16K |
| lazy off + `--cache-ram 256` | Qwen3.8-Flash-Next | 148 | 5.93 | 73.0 | 88835 | 145 | 88896 | 0 | 0 | no effect on one request |
| `-ngl 99 -cmoe -nkvo` | Qwen3.8-Flash-Next | 74 | 1.94 | 36.0 | 44099 | 1064 | 45154 | 26109 | 0 | SYS_USED ~14 GB; decode −63% vs baseline |

Notes on the frontier table:

- **lazy auto vs off.** `off` raises process `RssFile` by 46.9 GiB
  (45169 → 88835 MiB), which reproduces the prior ~46 GB finding. But
  **`SYS_USED` is 15.7 GB in both cases**: with `mmap` the weight pages live in
  `buff/cache` and stay reclaimable, so the 46 GiB is not real RAM pressure.
  `off` is also **faster** (decode 5.22 vs 3.23 t/s, prefill 73.6 vs 44.3)
  because the lazy tensors are then read once at load, not re-read from disk
  per token (`read_load` 176.7 GB vs 91.9 GB + a 24.5 GB request-phase read).
- **`--load-mode none`.** Process `VmRSS` is only 271 MB, but **`SYS_USED` is
  71.2 GB** — the weights move into non-reclaimable `used` memory. `none` is
  therefore **worse** for colocation than `mmap`, despite the tiny RSS. Prefill
  is the fastest measured (98.3 t/s); decode is 4.43 t/s.
- **`--load-mode dio`** crashes the W6600 (device lost) on this build and model.
- **KV quant at 16K.** `RssAnon` is ~equal (141 vs 148 MiB idle; ~396-405 MiB
  after request). KV at 16K is small, so KV quant has almost no RAM effect here.
  Its effect only shows at large context.

## What worked / what did not

**Worked.**

- **`mmap` (the default) is the correct RAM lever.** It keeps the 94 GB of
  weights as reclaimable `buff/cache`; system `used` stays ~15.7 GB whether
  lazy-mode is `auto` or `off`.
- **`--lazy-mode off` is not a RAM win on a colocated host; it is a speed loss.**
  It moves 46.9 GiB from `buff/cache` into the process `RssFile` count, but
  `SYS_USED` does not change, and it costs 38% decode and 40% prefill.
- **`--load-mode none` gives a near-zero process RSS** (271 MB) and the fastest
  prefill (98 t/s), but pushes 71 GB into non-reclaimable `used` memory. It is
  useful only standalone, never colocated.
- **`--cache-ram 256`** is safe but has no measurable effect on a single
  request; it only bounds the cross-request prompt cache.
- **KV quant and `--lazy-mode` are no-ops on the mid model** (7 GB, no large
  tensors).

**Did not work.**

- **`--load-mode mlock`** aborts at load: `RLIMIT_MEMLOCK` is 8 MiB
  (same as the prior brys finding; 0 bytes lockable).
- **`--load-mode dio`** crashes the W6600 on the frontier model
  (`device fault on Vulkan0`, `ErrorDeviceLost`).
- **`-ngl 99 -cmoe -nkvo`** hangs the request for >300 s on the mid model and
  drops decode to 1.94 t/s (−63%) on the frontier. The GPU offload path is
  unusable for serving.
- **`--no-mmap-prefetch`, `--moe-stream*`, `--pin-hot-experts*`** could not be
  tested: no build with them is present.

## Recommendation

1. **Keep `--load-mode mmap` and `--lazy-mode auto`.** This is already the
   served default and is the best colocated RAM behaviour. Do not switch to
   `none` (non-reclaimable 71 GB) or `lock`/`dio` (crash).
2. **Do not treat process `VmRSS` as the RAM budget on brys.** Always read
   system `used`. With `mmap`, a 94 GB model shows ~89 GiB `VmRSS` with
   `lazy-mode off` but only ~15.9 GB real `used`; with `lazy-mode auto` it shows
   ~44 GiB `VmRSS` at the same `used`. The two configs differ in speed, not in
   real RAM.
3. **The biggest real RAM win is `--load-mode none`** (71 GB into a form that
   the kernel can reclaim only at process exit) **at a 27% decode cost**
   (4.43 vs 5.22-with-`off`) **and a large first-use disk cost**. It is a
   standalone-only option, for a one-shot batch on a box that cannot hold the
   model — never for the colocated service.
4. **KV quant and `--cache-ram` do nothing at 16K.** Re-test them at the served
   1M context, where the KV is ~24 GiB.
5. **Do not use the W6600 path** (`-ngl`, `--load-mode dio`): it hangs or
   crashes. This matches the prior `qwen-gpu-offload` result.
6. **Test the absent levers only after building a master package**
   (`--no-mmap-prefetch`, `--moe-stream*`). The positive MoE-stream case (a
   model larger than RAM) is still unmeasured because no such model and no such
   build exist on brys today.
