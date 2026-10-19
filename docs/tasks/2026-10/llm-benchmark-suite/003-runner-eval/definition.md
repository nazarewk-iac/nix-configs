---
type: Task
description: Package Strata in Nix and evaluate it, and other runners, against llama.cpp for serving Qwen3.8-Flash-Next on brys, with a like-for-like benchmark.
status: in-progress
authored_by: agent
timestamp: 2026-10-19T18:14:00+02:00
---

# 003 — Runner evaluation (Strata, others)

## Goal

Decide whether a runner other than llama.cpp serves Qwen3.8-Flash-Next better on
brys, judged on a like-for-like benchmark. Strata is the first candidate.

## Strata

- Upstream: <https://github.com/Niko1221/Strata>. MIT. Runs
  Qwen3.8-Flash-Next on a gaming PC by keeping hot experts on the GPU, all
  experts in RAM, and a lookup table on the SSD.
- It speaks the OpenAI and Anthropic APIs, so opencode can point at it.
- It advertises an **AVX2** build. The 5950X has AVX2, so this is the relevant
  path. Confirm which CPU variant it dispatches at runtime, and confirm our
  llama.cpp build dispatches AVX2 too (it uses `GGML_CPU_ALL_VARIANTS` +
  `GGML_BACKEND_DL`).
- **Nix requirement (hard):** Strata must be a Nix package in this repository
  (under `packages/`), with a pinned source and a deterministic build. Do not
  build it from a hand-made checkout and run that. If a fully from-source build
  is impractical, document exactly which upstream artifact is wrapped, its hash,
  and why a source build is not used.

## Other candidates to survey (research first)

- **llama.cpp** (incumbent baseline).
- **vLLM** (does it fit a CPU+MIG-like box at this model size?).
- **SGLang**, **ktransformers** (CPU+GPU MoE offload), **exllamav2** (GPU-only),
  **mlx** (not on this host), **ollama** (wrapper over llama.cpp), **LM Studio**
  (not headless-friendly).
- Any runner that does layer/expert offload specifically for large MoE on a
  small GPU.

## Method

- Same prompt, same context, same server-settings (parallel, KV type) where the
  runner supports them.
- Measure: decode tok/s, prefill tok/s, cold start, RAM, VRAM, and API
  compatibility with opencode.
- Use the harness from [001-benchmark-suite](../001-benchmark-suite/definition.md)
  so the numbers line up with the llama.cpp baseline.

## Deliverables

- `packages/strata/` (or equivalent) — the Nix package, registered in
  `packages/default.nix`.
- `runners.research.md` in this directory: the candidate survey, and the measured
  Strata-versus-llama.cpp comparison.
- A recommendation with a go/no-go on adopting Strata.

## Acceptance criteria

- Strata builds as a Nix package and starts with `nix run` (or the host config
  path), with no hand-built checkout.
- The comparison against llama.cpp is measured on the same harness, with the CPU
  variant confirmed on both sides.
- The other candidates have a one-paragraph assessment each.

## References

- <https://github.com/Niko1221/Strata>
- [packages/llama-cpp/default.nix](../../../../packages/llama-cpp/default.nix)
- [docs/local-llms.md](../../../local-llms.md)
