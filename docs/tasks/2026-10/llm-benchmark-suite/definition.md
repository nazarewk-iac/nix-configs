---
type: Task
description: Umbrella task for a full local-LLM benchmark suite on brys (tok/s, cold/warm starts, memory, caches), a standalone disk-offload/RAM-reduction study, and an evaluation of Strata and other runners versus llama.cpp.
status: in-progress
authored_by: agent
timestamp: 2026-10-19T18:10:00+02:00
---

# Local-LLM benchmark suite, disk-offload study, and runner evaluation

Three related efforts, tracked as sub-tasks in this directory:

1. **Benchmark suite.** A repeatable set of measurements over every enabled brys
   model: decode and prefill tok/s, cold start (first enable of a model), and
   RAM/VRAM use. Plus client-side starts measured from opencode: cold and warm
   start of opencode, and cold and warm start of opencode in this repository
   (`nix-configs`). Plus context and cache capacity per model.
2. **Disk-offload / RAM-reduction study.** Standalone (without enabling the
   candidate as a served model), research and measure the levers that reduce RAM
   or move weights to disk, the same family of tweaks already applied to
   Qwen3.8-Flash-Next (`--lazy-mode`, `--load-mode`, mmap control, MoE expert
   streaming/offload, KV quant, `--cache-ram`).
3. **Runner evaluation.** Package and evaluate serving Qwen3.8-Flash-Next from
   **Strata** and from other runners (llama.cpp is the incumbent), on the same
   harness, to compare speed, memory, and features.

## Sub-tasks

| # | Sub-task | Directory | Status |
|---|---|---|---|
| 001 | Benchmark suite | [001-benchmark-suite/](001-benchmark-suite/definition.md) | open |
| 002 | Disk-offload / RAM-reduction study | [002-disk-offload/](002-disk-offload/definition.md) | open |
| 003 | Runner evaluation (Strata, others) | [003-runner-eval/](003-runner-eval/definition.md) | open |

## Decisions taken (umbrella)

- **Orchestration.** The primary session is the orchestrator, reviewer, and
  decision maker. Measurement and research go to sub-agents. The need for
  several parallel sub-agents is explicit in the user's brief.
- **Reuse prior work.** One-off benchmarks already exist in
  `docs/tasks/2026-10/llm-warm-start-session/measurements-2026-10-18.research.md`,
  `docs/tasks/2026-10/brys-grunt-colocation/coresidency-measured.research.md`,
  and `docs/local-llms.md`. The suite extends and unifies them; it does not
  redo them.
- **Strata is a Nix package.** Strata is not built ad-hoc from source. It becomes
  a package under `packages/strata/` (or equivalent) with a pinned
  `fetchFromGitHub`, and is selected through the normal host config. It must not
  be run from a hand-built checkout.
- **AVX2.** The Ryzen 5950X has AVX2, F16C and FMA, and no AVX512. This
  repository's llama.cpp builds use `GGML_CPU_ALL_VARIANTS` plus
  `GGML_BACKEND_DL`, so the binary ships every CPU variant and selects one at
  runtime (it should pick AVX2 on this host). Strata advertises an AVX2 build.
  Sub-task 001 confirms which variant each runner actually dispatches, so the
  comparison is apples-to-apples.

## Acceptance criteria (umbrella)

- Each sub-task has a `definition.md` with its own acceptance criteria and a
  sibling results file (`*.research.md` or `measurements*.research.md`).
- All numbers are **measured on brys**, with the box state (warm/cold, resident
  models) recorded, because brys page-cache churn invalidates a bench (see
  `docs/local-llms.md` benchmark-log caveat).
- The Strata and runner comparison uses the same prompt, the same context, and
  the same measurement points as the llama.cpp baseline.

## References

- [docs/local-llms.md](../../../local-llms.md) — the incumbent architecture and
  the append-only benchmark log.
- [docs/tasks/2026-10/llm-warm-start-session/](../llm-warm-start-session/definition.md)
- [docs/tasks/2026-10/brys-grunt-colocation/coresidency-measured.research.md](../brys-grunt-colocation/coresidency-measured.research.md)
- [hosts/brys/performance.md](../../../../hosts/brys/performance.md)
- [packages/llama-cpp/](../../../../packages/llama-cpp/)
