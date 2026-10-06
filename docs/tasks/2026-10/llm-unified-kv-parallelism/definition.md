---
type: Task
description: Give brys' DeepSeek router unified KV plus a parallel-slot mode, and stop the small-model router from competing with DS4 for the box.
status: in-progress
authored_by: agent
timestamp: 2026-10-06T00:29:35+02:00
---

# Unified KV cache + parallelism for brys, and evict the small-model router

> **Status:** in-progress. The configuration is implemented and evaluates; the
> on-box measurement (throughput, residency, concurrency) is still pending.
> See [status.md](status.md).

## Context

The `llm-minimal` specialisation on brys serves `deepseek-v4-flash` (DS4) from one
`llama-server` router (`:39703`). Current relevant settings, in the shared
`hosts/brys/llm.nix` and the slot `modules/slots/llm/default.nix`:

- `parallel = 1` (the slot always emits `perf.parallel`, default 1).
- `ctx-size = 327680` (320K).
- No CPU affinity (pinning stalled prefill on this llama-cpp build).
- `batch-size`/`ubatch-size = 4096` (the prefill fix).
- Draft model on (`spec-type = draft-dspark`).

Two structural limits follow:

1. **`--parallel 1` serialises every request.** A sub-agent, or any second client,
   queues behind the in-flight request. A long prefill (measured ~15 t/s, so a
   20K-token prompt is ~20 min) blocks everything behind it — the original
   symptom. There is no concurrency.
2. **`kv_unified` is `false`** — not because DS4 needs it off, but because the
   slot explicitly passes `--parallel 1`. llama.cpp only auto-enables unified KV
   when the slot count is left at its auto default (`n_parallel = -1`): see
   `common/common.h` (`kv_unified = false`), `common/arg.cpp` (server default
   `n_parallel = -1`) and `tools/server/server.cpp` (`if (n_parallel < 0) {
   n_parallel = 4; kv_unified = true; }`). With one slot this is a no-op
   (`n_ctx_slot == ctx-size`), but it is the switch that decides whether raising
   `--parallel` divides or shares the context.

Separately, the specialisation also runs a second router,
`llama-cpp-router-small` (`:39704`, `kdn.llm.local.routers.small`, `modelsMax 2`,
`sleep-idle-seconds -1`). It is only meant for the small models
(`qwen3-30b-a3b`, `phi-4`, `qwen3-coder-next`, `qwen3-next-80b`, `qwen3-235b`,
`gpt-oss-120b`). But:

- `sleep-idle-seconds -1` pins whatever small model was last loaded, so once the
  small router is touched, its resident set competes with DS4's ~101 GB of
  `mmap`'d weights for the last few GB of RAM. DS4's headroom is already ~1 GB
  free / ~101 GB reclaimable on a 125 GB box.
- Any co-resident small model (or a nix build) forces the kernel to evict weight
  file pages, which drops DS4 to disk-bound prefill/decode — the exact failure
  mode the ZFS ARC cap removed.

## Goal

1. Decide and enable a **concurrency mode**: unified KV (`--kv-unified`) plus a
   modest `--parallel N` (candidate: 2–4) with a context budget that keeps each
   slot useful, OR a documented decision to stay at 1.
2. **Turn off the small-model router on this host, or split it out** (separate
   host, or a router that unloads and never steals DS4's headroom), so DS4 has
   the whole box.

## Proposed approach

The explored candidate is `--parallel 4 --kv-unified --ctx-size 327680` (one
shared 320K pool, each slot free to use it; see [`research.md`](research.md)).
Small-context sub-agents need no server change — a shared pool is
usage-proportional, so a small request is automatically small — but a
*guarantee* needs a preconfigured client model entry (smaller `limit.context`) or
a uniform server cap.

- Add a `perf.kvUnified` (and keep `perf.parallel`) option to the slot and the
  den `llm` aspect; emit `--kv-unified`/`--no-kv-unified`. See `perf.batchSize`
  for the pattern just added.
- With unified KV, size `--ctx-size` as the *shared* pool. Decide the target:
  e.g. `parallel 4`, unified, `ctx-size ~131072–196608` shared. Confirm memory:
  DS4 weights are ~101 GB resident; total KV must fit beside it and the 8 GiB ARC
  cap.
- Remove `kdn.llm.local.routers.small` from the specialisation (set
  `cpuPinned`-style host data rather than the shared default), or add
  `sleep-idle-seconds`/unload so it cannot pin a resident small model. Consider
  moving the small models to another host entirely.
- Keep the decode/prefill tuning already landed (no affinity, ubatch 4096).

## Acceptance criteria

- Two concurrent requests (e.g. two `curl`s, or an opencode sub-agent fan-out)
  both make progress; neither waits for the other's full prefill.
- Aggregate and per-request throughput recorded against the `parallel 1` baseline.
- DS4 weights stay resident under the chosen mode: `RssFile` stays near ~101 GB,
  idle major faults ~0, no OOM, `MemAvailable` healthy.
- With the small router off/split, no small model is pinned next to DS4; a
  co-residency test does not evict DS4.
- Documented in [`docs/local-llms.md`](../../../docs/local-llms.md).

## Open questions

- Best `parallel` × `ctx-size` trade for interactive single requests vs
  sub-agent fan-out.
- Whether unified KV interacts with the DSpark draft (`--spec-type draft-dspark`)
  on this build.
- Where the small models should live if they leave brys, or whether a small
  router with a real idle-unload policy is enough.
- Memory headroom: is 2 slots (shared) safe, or does the compute buffer +
  weights already fill the box?

## References

- [`research.md`](research.md) — the theoretical exploration: 320K ctx with
  `--parallel 4` under unified KV, and how to allow smaller-context sub-agents
  (client vs server, on-demand vs preconfigured).
- [`docs/local-llms.md`](../../../docs/local-llms.md) — deployment, the ZFS ARC
  quirk, and the prefill tuning (affinity stall, ubatch).
- `modules/slots/llm/default.nix` — `perf.*` options and preset rendering.
- `hosts/brys/llm.nix` — shared brys LLM config (router + specialisation).
- `hosts/oams/devenv.nix` — the `kdn.llm.client` provider entries (where a
  smaller-context sub-agent model entry would be added).
- Source for the `kv_unified` default logic: llama.cpp `common/common.h`,
  `common/arg.cpp`, `tools/server/server.cpp`, `src/llama-context.cpp`.
