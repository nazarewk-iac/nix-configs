---
type: Task
description: Follow-ups from the local-LLM benchmark suite: a harness VRAM step, KV-quant/cache-ram measurement at the served 1M context, building and testing the experimental llama.cpp master variants, and packaging ik_llama.cpp for a runner comparison.
status: done
authored_by: agent
timestamp: 2026-10-19T21:45:00+02:00
---

# Benchmark-suite follow-ups

The open follow-ups from
[llm-benchmark-suite/done.md](../llm-benchmark-suite/done.md). Benchmarks run on
brys only.

## Items

| # | Item | Owner | Status |
|---|---|---|---|
| F1 | Harness `VRAM_MiB` step | sub-agent | open |
| F2 | KV quant + `--cache-ram` at the served 1M context | sub-agent | open |
| F3 | Build and test the llama.cpp master variants | sub-agent | open |
| F4 | Package `ik_llama.cpp` for a runner comparison | sub-agent | open |

## Notes

- **F1.** The GPU is the W6600 (`1002:73E3`, `/sys/class/drm/card1/device`).
  VRAM is readable at `/sys/class/drm/card1/device/mem_info_vram_used` (bytes).
  No `amd-smi`/`rocm-smi` on brys. VRAM is only non-zero for GPU-mode grunts.
- **F2.** At 1M context the Qwen F16 KV is about 24 GiB, so this is the regime
  where KV quant and `--cache-ram` matter. The earlier study measured only at
  16K, where both are no-ops.
- **F3.** The three master variants already exist in
  `packages/llama-cpp/default.nix` with patches
  (`29250-no-mmap-prefetch.patch`, `25294-moe-stream.patch`,
  `26414-pin-hot-experts.patch`). No host builds them. The task is to build
  them, confirm the patches still apply, and measure each flag on brys.
- **F4.** `ik_llama.cpp` must be a Nix package under `packages/`, pinned by
  `fetchFromGitHub`, registered in `packages/default.nix`. No ad-hoc build.

## Acceptance criteria

- F1: `hack/llm-bench.sh` gains a `vram` step; a GPU grunt shows non-zero VRAM.
- F2: a measured comparison of F16/q8_0/q4_0 KV and low/high `--cache-ram` at
  1M context, with system `used` and `RssAnon`.
- F3: each master variant either builds and is measured, or has a documented
  reason it does not apply.
- F4: `ik_llama.cpp` builds as a Nix package and starts; a first
  decode/prefill comparison against llama.cpp is recorded.

## References

- [llm-benchmark-suite/](../llm-benchmark-suite/definition.md)
- [hack/llm-bench.sh](../../../../hack/llm-bench.sh)
- [packages/llama-cpp/](../../../../packages/llama-cpp/)
