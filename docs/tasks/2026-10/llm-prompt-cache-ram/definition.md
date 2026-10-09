---
type: Task
description: Let the Qwen specialisation grow llama-server's prompt cache past the 8 GiB default, so the frequent "making room for prompt cache entry" evictions stop, while keeping ~8 GiB MemAvailable.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-09T18:19:26+02:00
---

# Size the Qwen prompt cache (`--cache-ram`) to stop evictions

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

While serving `qwen3.8-flash-next` on the `llms-frontier` boot entry (the same
Qwen wiring as `llm-qwen`), the llama-server log shows repeated:

```
W srv alloc:  - making room for prompt cache entry, removing oldest entry (size = 5758.261 MiB)
```

This message comes from llama.cpp's **prompt cache** (`server_prompt_cache`),
not the KV cache. The prompt cache stores KV states of processed prompts for
prefix reuse across requests. Its size is bounded by `--cache-ram` / `-cram`,
whose default is **8192 MiB** (`llama-server --help`). When full it evicts the
oldest entry to admit a new one. On this model one long prompt is ~5.7 GiB, so
the default holds barely one entry and evicts constantly.

The KV cache is a different structure: with `kv-unified = on` and
`ctx-size = 1048576` it is one preallocated pool, not what is being evicted.

## Measured state (brys, `llms-frontier`, Qwen resident, 2026-10-09)

`free -m`: `MemTotal` 125.7 GiB, `MemFree` **1.8 GiB**, `MemAvailable` **45 GiB**,
`Cached` 45 GiB, no swap.

`/proc/<child>/status`: `VmRSS` 113.8 GiB, `RssAnon` **69 GiB**, `RssFile`
44 GiB. One anonymous mapping is ~55 GiB: the unified 1M KV/state pool. The
rest of the anon is compute buffers plus the 8 GiB prompt cache.

So the 45 GiB "available" is almost entirely the **reclaimable mmap'd weight
working set**, not free RAM. `--cache-ram` grows on demand: a high cap is a
ceiling, not an allocation. It only costs RAM when the workload actually fills
the cache; if it fills, the kernel evicts clean weight pages and decode re-reads
them from disk.

## Goal

Raise the Qwen prompt-cache cap so a filled cache still leaves ~8 GiB
`MemAvailable`, i.e. `cache-ram ≈ 36864 MiB` (37 GiB). This holds ~6 of the
~5.7 GiB entries, enough for four concurrent slots plus history.

## Proposed approach

1. Add `perf.cacheRam` (MiB, `null` default) to `modules/slots/llm/default.nix`
   and emit `cache-ram = <N>`; mirror it in `modules/den/aspects/llm.nix`.
2. Add a `qwenCacheRam` argument to `hosts/brys/llm.nix` and fold it into
   `qwenPerf`, so `llm-qwen` and `llms-frontier` share it and cannot drift.
3. Set `qwenCacheRam = 36864` on both Qwen specialisations.
4. Document the lever in `docs/local-llms.md` and the slot README.

## Acceptance criteria

- The rendered `models-preset.ini` for `qwen3.8-flash-next` contains
  `cache-ram = 36864`; the DeepSeek section is unchanged.
- `llms-frontier` (and `llm-qwen`) rebuild and evaluate.
- After activation, the eviction warnings stop under the normal workload and
  `MemAvailable` stays at or above ~8 GiB.
- Weights stay usable: no sustained `RssFile` collapse / disk-bound decode.

## References

- `modules/slots/llm/default.nix` — `perf.*` options and preset rendering.
- `hosts/brys/llm.nix` — shared brys LLM wiring.
- `hosts/brys/llm-qwen.nix`, `hosts/brys/llms-frontier.nix` — the Qwen entries.
- [docs/local-llms.md](../../../docs/local-llms.md) — RAM levers, ZFS ARC quirk.
- llama.cpp PR #16391 (`--cache-ram`).
