---
type: Solution
description: All four benchmark-suite follow-ups are done: harness VRAM step, KV/cache measurement at 1M, the master llama.cpp variants built and tested, and ik_llama.cpp packaged with a first comparison.
task: definition.md
authored_by: agent
timestamp: 2026-10-19T22:10:00+02:00
---

# Solution — benchmark-suite follow-ups

## F1 — harness VRAM step

`hack/llm-bench.sh` gained a `vram` step that reads
`mem_info_vram_used`/`mem_info_vram_total` from the W6600 sysfs over ssh.
Measured: `tmax-2b` holds 1536 MiB VRAM. The harness README is now tracked
(it was caught by `hack/.gitignore`).

## F2 — KV quant and `--cache-ram` at 1M

[kv-cache-1m.research.md](../llm-benchmark-suite/002-disk-offload/kv-cache-1m.research.md).
At ctx 1048576:

| KV type | RssAnon | SYS used | decode | prefill |
|---|---|---|---|---|
| F16 | 31409 MiB | 48685 MB | 3.29 t/s | 39.3 t/s |
| q8_0 | 17010 MiB | 32243 MB | 3.29 t/s | 45.0 t/s |
| q4_0 | 9330 MiB | 24534 MB | 3.43 t/s | 43.4 t/s |

**q8_0 KV saves about 14 GiB of non-reclaimable RAM at no decode cost.** This
is a recommended served-config change (not applied by this task).
`--cache-ram` (8192/36864/131072) made no difference at a 46K-token prompt: it
is a ceiling, and it only bites above about 350K tokens.

## F3 — master variants

[master-variants-build.research.md](master-variants-build.research.md) and
[master-variants-test.research.md](master-variants-test.research.md).
All four variants build; the three manual patches still apply to master
`9c2e0e4`. On brys, all three flags are neutral or harmful, because brys has no
model larger than RAM:

- `--no-mmap-prefetch`: load 4.4x faster (70.7 to 16.2 s) but first request
  +25% and decode -18%. The read moves from load into the request.
- `--moe-stream`: harmful. The default cache aborts (needs 30 slots, has 20);
  with `--moe-stream-cache 8G` a request reads ~345 GB and decode falls to
  1.24 t/s.
- `--pin-hot-experts`: harmful. A no-op under the 8 MiB memlock; raised, it
  locks ~35 GB non-reclaimable and gives no gain.

The intended large-model streaming case is not present on brys.

## F4 — ik_llama.cpp

[ik-llama-cpp.research.md](ik-llama-cpp.research.md) and
`packages/ik-llama-cpp/`. Packaged from a pinned `fetchFromGitHub`, CPU-only.
It builds and **loads the qwen4exp arch**. First comparison at ctx 16384:

| model | engine | decode | prefill |
|---|---|---|---|
| Qwen3.8-Flash-Next | ik_llama.cpp | 6.48 | 66.2 |
| Qwen3.8-Flash-Next | llama-cpp-sessions-vulkan-noblas | 5.31 | 75.1 |
| qwen3.5-9b | ik_llama.cpp | 7.80 | 117.6 |
| qwen3.5-9b | llama-cpp-sessions-vulkan-noblas | 7.31 | 214.6 |

ik_llama.cpp wins decode; llama.cpp wins the large-context prefill. A served
A/B (through llama-swap) is the next step if wanted.

## Open follow-ups

- Serve ik_llama.cpp through llama-swap for a full A/B.
- `q8_0` KV at 1M is **already applied and deployed**: the host files set
  `qwenCacheTypeK/V = "q8_0"` (commit `wzyozlvvxrrr`) and the running
  `llms-frontier` swap config carries `--cache-type-k q8_0 --cache-type-v q8_0`
  at `--ctx-size 1048576`. No further change is needed. The served
  `--cache-ram` is `8192`; the F2 study found `36864` also safe but not
  necessary.
