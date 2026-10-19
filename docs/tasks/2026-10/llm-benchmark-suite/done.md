---
type: Solution
description: Closed the umbrella. All three sub-tasks are done: the benchmark suite and harness, the disk-offload study with the lazy-mode RAM correction, and the runner evaluation closed as researched-only (Strata not viable on brys).
task: definition.md
authored_by: agent
timestamp: 2026-10-19T21:35:00+02:00
---

# Solution — local-LLM benchmark suite

## Outcome

All three sub-tasks are done.

| Sub-task | Result | Deliverable |
|---|---|---|
| 001 benchmark suite | 31 brys models measured; opencode client cells on oams | [001-benchmark-suite/done.md](001-benchmark-suite/done.md) |
| 002 disk-offload | each lever measured; lazy-mode RAM claim corrected | [002-disk-offload/done.md](002-disk-offload/done.md) |
| 003 runner evaluation | closed researched-only; Strata not viable on brys | [003-runner-eval/done.md](003-runner-eval/done.md) |

## Key results

- One harness, `hack/llm-bench.sh`, measures every model the same way.
- Decode spans 2.4 tok/s (seed-oss-36b) to 208 tok/s (qwen3.5-0.8b).
- DeepSeek V4 Flash cold start 310 s, Qwen3.8-Flash-Next cold start 156 s.
- RAM rule: read system `used`, not process `VmRSS`. With `mmap`, the weights
  stay reclaimable in `buff/cache`; `--lazy-mode off` is a speed knob, not a RAM
  cost. This corrects the earlier `docs/local-llms.md` note.
- Strata cannot run on brys: AMD path is HIP/ROCm-only, `gfx1032` is not
  supported, and there is no CPU-only mode. `ik_llama.cpp` is the future
  candidate.

## Open follow-ups (not blocking)

- Add a GPU-reader step to the harness for `VRAM_MiB`.
- Re-test KV quant and `--cache-ram` at the served 1M context.
- Build a master llama.cpp package to test `--no-mmap-prefetch`,
  `--moe-stream*`, and `--pin-hot-experts*`.
- Package `ik_llama.cpp` if a runner comparison is wanted later.
