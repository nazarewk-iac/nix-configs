---
type: Research
description: Standalone measurement on brys of KV-cache quantisation (F16, q8_0, q4_0) and --cache-ram (8192, 36864, 131072 MiB) for Qwen3.8-Flash-Next UD-IQ4_XS at the served 1M context, with idle system and process memory, decode and prefill speed, and prompt-cache reuse.
task: ../definition.md
authored_by: agent
timestamp: 2026-10-20T01:15:00+02:00
---

# KV-cache quantisation and `--cache-ram` at the served 1M context (brys)

This document reports the measured effect of KV quantisation and `--cache-ram`
for Qwen3.8-Flash-Next at ctx 1048576. The earlier study measured the same
levers at ctx 16384, where the KV is small and they are no-ops. See
[offload-measurements.research.md](offload-measurements.research.md). At 1M the
F16 KV is about 24 GiB, so this is where the levers matter. Every run is a
one-off `llama-server` process, not wired into a boot entry or `llama-swap`.

## Method

- Host: `brys`, AMD Ryzen 9 5950X (16 cores, 32 threads), 128 GB DDR4, no
  swap, ZFS storage. Lix. The W6600 is not used (`-ngl 0`).
- Binary: `llama-cpp-sessions-vulkan-noblas-0.6.0-unstable-2026-10-09`
  (`/nix/store/z77bfs2b63wfzlzfczcaq6apsigwd0qw-.../bin/llama-server`). This is
  the served build.
- Model:
  `/var/lib/kdn/llms/models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf`
  (3 shards, ~94 GB).
- Fixed flags: `--host 127.0.0.1 --port 18080 -ngl 0 --threads 16
  --ctx-size 1048576 --parallel 4 --kv-unified --flash-attn on`, `--load-mode`
  default (`mmap`).
- Prompt: one long unique prompt of **45986 tokens** (built from 1000 unique
  lines). The target was about 30K tokens; the generator produced about 46K.
  The prompt misses the prefix cache on the first request. Decode: 128 tokens,
  temperature 0. Each run sends the prompt twice.
- Per run: `echo 3 > /proc/sys/vm/drop_caches`, then one cold load. Idle
  metrics are read after the load and before the first request. The process is
  stopped before the next run.
- Metrics: `SYS_used` and `SYS_avail` from `free -m` (MiB) at idle after load;
  `RssAnon` and `VmRSS` from `/proc/<pid>/status` (MiB); `decode` and `prefill`
  (tok/s) from the server `timings`; `cache_n` from the repeat request.
- Box state: `llama-swap` was **stopped** before the runs (`used` 42.8 → 12.5
  GB, `available` ~116 GB), then **restarted**; `curl :39700/v1/models` returns
  **34 ids** again. One process at a time.

## Results

`SYS_used` is the system `used` from `free -m` at idle after load. `RssAnon` is
the process anonymous memory (this holds the KV cache). `VmRSS` is the full
process RSS.

| config | KV type | cache-ram | SYS_used_MB | SYS_avail_MB | RssAnon_MiB | VmRSS_MiB | decode_tok_s | prefill_tok_s | cache_n | note |
|---|---|---|---|---|---|---|---|---|---|---|
| kv-f16-cr8192 | f16 | 8192 | 48685 | 80033 | 31409 | 76036 | 3.29 | 39.30 | 45982 | baseline; KV F16 |
| kv-q8-cr8192 | q8_0 | 8192 | 32243 | 96475 | 17010 | 61635 | 3.29 | 44.99 | 45982 | KV halved; no decode cost |
| kv-q4-cr8192 | q4_0 | 8192 | 24534 | 104184 | 9330 | 53953 | 3.43 | 43.40 | 45982 | KV quartered; no decode cost |
| kv-f16-cr36864 | f16 | 36864 | 48720 | 79998 | 31406 | 76033 | 3.56 | 39.31 | 45982 | served value; no idle change |
| kv-f16-cr131072 | f16 | 131072 | 48690 | 80028 | 31409 | 76036 | 3.56 | 39.29 | 45982 | 128 GiB ceiling; no preallocation, no OOM |

Notes on the table:

- No run failed. No run OOMs. The KV always allocates. No run logs a
  prompt-cache eviction (`making room for prompt cache entry`): `evict=no` for
  every run.
- The first request of every run reports `cache_n=0` (a cold, cache-missing
  prompt). The repeat request reports `cache_n=45982` of `prompt_n=45986`: the
  prompt cache holds the whole prompt, so only 4 tokens are re-evaluated.
- `decode` varies by about 0.3 tok/s between identical configs (3.29 to 3.56).
  Treat the KV-quant decode numbers as equal within this noise.

## Effect of KV quant

KV quantisation is the large RAM lever at 1M. It works as expected.

- **F16 → q8_0.** `RssAnon` drops from 31409 to 17010 MiB (a saving of
  **14399 MiB, about 14.1 GiB**). System `used` drops from 48685 to 32243 MB (a
  saving of **16442 MB, about 16.1 GiB**).
- **F16 → q4_0.** `RssAnon` drops from 31409 to 9330 MiB (a saving of
  **22079 MiB, about 21.6 GiB**). System `used` drops from 48685 to 24534 MB (a
  saving of **24151 MB, about 23.6 GiB**).
- **Speed cost is zero.** Decode is 3.29 (F16), 3.29 (q8_0) and 3.43 (q4_0)
  tok/s. The spread is the run-to-run noise. Prefill is not slower: 39.30
  (F16), 44.99 (q8_0) and 43.40 (q4_0) tok/s. The quantised runs are equal or
  slightly faster. The quantised KV write is cheaper during prefill.

## Effect of `--cache-ram`

`--cache-ram` has **no measurable effect at this prompt size**. The three F16
runs (8192, 36864, 131072 MiB) give the same idle memory (RssAnon 31406 to
31409 MiB), the same decode (3.29 to 3.56 tok/s), and the same prefill (39.29 to
39.31 tok/s). All three hold the whole prompt (`cache_n=45982`).

- `--cache-ram` is a **ceiling, not an allocation**. A large value does not
  reserve RAM: `131072` (128 GiB) loads and runs with the same idle footprint
  as `8192`, and it does not OOM.
- One F16 prompt of 45986 tokens is about **1.05 GiB** of cache
  (45986 tokens x 24 KiB/token). So `8192` MiB holds about **7** such entries.
  Two requests never fill it, so no eviction occurs and the value cannot show an
  effect. The lever only matters for a prompt larger than about **350K tokens**,
  or for many concurrent long entries.

## Recommendation

1. **Enable `q8_0` KV on the served Qwen at 1M.** It frees about **14 GiB** of
   process RAM (about 16 GiB of system `used`) and costs **no** decode speed. It
   is the largest safe RAM win at the served context.
2. **Use `q4_0` KV when RAM is tight.** It frees about **22 GiB** (about 24 GiB
   of system `used`) at no measured decode cost. Check output quality before
   you adopt it, because q4_0 is a coarse quantisation.
3. **Keep `--cache-ram 36864` as it is.** It is safe, but it does nothing for a
   normal long prompt. Do not raise it to `131072`: it adds no benefit and no
   risk. Lower it only if a smaller cross-request cache is wanted.
4. **The saved RAM stays reclaimable.** The runs use `mmap`, so the 94 GB of
   weights stay in `buff/cache`. The KV saving is in `used` (non-reclaimable)
   memory, so it is a real win for colocation.
