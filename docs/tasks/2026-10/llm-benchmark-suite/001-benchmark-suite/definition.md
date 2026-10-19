---
type: Task
description: Repeatable benchmark suite over every enabled brys model: decode/prefill tok/s, cold start (first enable), RAM/VRAM, context and cache capacity, plus opencode cold/warm start on this repository.
status: done
authored_by: agent
timestamp: 2026-10-19T18:12:00+02:00
---

# 001 — Benchmark suite

## Goal

One repeatable harness that measures every enabled brys model with the same
prompt and the same points, so the numbers are comparable across models and
across runs.

## Measurements (per model)

### Server side (through the compat-proxy or direct to llama-swap)

| measurement | definition | unit |
|---|---|---|
| cold start | wall time from the request that first loads the model to its first token, page cache cold for that model | s |
| warm start | the same, with the model already resident (no load) | s |
| decode tok/s | generation rate at a fixed generation length | tok/s |
| prefill tok/s | prompt-processing rate at a fixed prompt length | tok/s |
| TTFT | time to first token at a fixed prompt | s |
| context (served) | the model's real maximum (`context_length`) | tokens |
| KV cache | KV bytes at the served context, per the model's KV type | MiB |
| prompt/reuse cache | prefix-reuse speed on a repeated prompt (cache_n) | tok/s, x speed-up |
| RssFile | mmap'd weights | MiB |
| RssAnon | KV + compute buffers | MiB |
| VmRSS | total resident | MiB |
| VRAM | GPU memory while served (GPU-mode models) | MiB |
| idle major faults | page-cache thrash detector | faults/s |

### Client side (opencode)

| measurement | definition |
|---|---|
| opencode cold start | start a fresh opencode (no prior process/cache) to first usable prompt |
| opencode warm start | the same with a warm process/cache |
| opencode cold start in nix-configs | a fresh opencode in this repository (project config + MCP + agent rules loaded) |
| opencode warm start in nix-configs | the same, warm |
| first-turn latency | cold, first request to first token, against a model |
| first-turn latency | warm |

The client-side runs use `zellij-llm opencode spawn/send/watch`
(`packages/llm/zellij-llm/`). The prompt is fixed and minimal.

## Method

- **Warm/cold discipline.** Record and control page-cache state. A bench after a
  nix build/copy is invalid (see the `docs/local-llms.md` benchmark-log caveat).
- **Two runs minimum** per cell (cold then warm), so the cold/warm pair is
  visible.
- **One prompt** for decode (a fixed generation length) and one for prefill
  (a fixed prompt length); reuse the warm-start prompt where possible.
- Reuse `coresidency-measured.research.md` rows where they already exist; mark
  them as reused, not re-measured.

## Deliverables

- A harness script (a new file, for example under `hack/` or
  `packages/llm/`), committed, with a fixed invocation.
- `measurements.research.md` in this directory: the unified per-model table plus
  the opencode client table.
- A short summary added to `docs/local-llms.md`'s benchmark log.

## Acceptance criteria

- Every enabled brys model has a decode and prefill row, a cold-start row, and
  RAM rows (or a documented reason it cannot be measured).
- The opencode cold/warm and nix-configs cold/warm cells are filled.
- The harness is repeatable: a second invocation reproduces the same shape.

## Out of scope

- Comparing different runners (that is [003-runner-eval](../003-runner-eval/definition.md)).
- Disk-offload tweaks (that is [002-disk-offload](../002-disk-offload/definition.md)).

## References

- [llm-warm-start-session/measurements-2026-10-18.research.md](../llm-warm-start-session/measurements-2026-10-18.research.md)
- [brys-grunt-colocation/coresidency-measured.research.md](../brys-grunt-colocation/coresidency-measured.research.md)
- [docs/local-llms.md](../../../local-llms.md)
- [packages/llm/zellij-llm/](../../../../packages/llm/zellij-llm/)
