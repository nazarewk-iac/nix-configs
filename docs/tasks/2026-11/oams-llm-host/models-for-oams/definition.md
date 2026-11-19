---
type: Task
description: Choose and benchmark the models oams serves on its 12 GB RX 6800M, prioritising quality-per-GB and bounded disk use, with the measured evidence recorded.
status: open
authored_by: agent
timestamp: 2026-11-05T09:49:54+01:00
---

# Models for oams

## Context

oams has 12 GB VRAM, ~45-50 GiB usable RAM headless, and 530 GB free on a fast
NVMe. The goal is a small, high-value model set — not a mirror of brys' 30-model
surveyed set. Disk use matters (it is a laptop, and the repo already carries 464 GB
of GGUFs on brys).

Research (see [research.md](research.md)) ranked candidates by practical
quality-per-GB on this specific card. The shortlist:

| #   | model                         | quant     | on disk | fits 12 GB | use                                |
| --- | ----------------------------- | --------- | ------: | ---------- | ---------------------------------- |
| 1   | `qwen3.5-9b`                  | Q6_K      | 7.46 GB | yes, full  | general worker + vision + long ctx |
| 2   | `glm-4.7-flash` (30B-A3B)     | Q4_K_M    | 18.3 GB | offload    | agentic coding (SWE-bench 59.2)    |
| 3   | `gemma-4-12b`                 | Q6_K      | 9.79 GB | yes, full  | audio + vision + text in one       |
| 4   | `qwen3.5-35b-a3b`             | UD-IQ4_XS | 17.5 GB | offload    | 256K context, near-frontier        |
| 5   | `qwen3-embedding-8b`          | Q4_K_M    | 4.68 GB | yes, full  | RAG                                |
| 6   | `qwen3-vl-8b-instruct`        | Q6_K      | 6.73 GB | yes, full  | OCR / document / UI vision         |
| 7   | `whisper-large-v3-turbo-q5_0` | q5_0      | 0.55 GB | yes, full  | bulk ASR                           |
| 8   | `qwen3-reranker-0.6b`         | Q8        | ~0.6 GB | yes, full  | RAG rerank                         |

Already measured working on oams and not candidates for replacement:
`qwen3.5-0.8b`, `qwen3.5-2b`, `gemma-4-e2b`, `gemma-4-e4b`, `granite-4.2-3b`.

## The MoE question

The highest-value category. A 30B-A3B at Q4 is ~18 GB and does **not** fit 12 GB,
but with `--n-cpu-moe` (attention + shared expert + KV on the GPU, routed experts
in RAM) it runs at usable speed. Published CUDA numbers are 25-64 tok/s on
RTX 3060/4070-class 12 GB cards. **Vulkan/RDNA2 numbers are unpublished** — this
must be measured on oams before committing to a MoE model. The tuning rule from
the literature is to sweep `--n-cpu-moe` in ±2 steps and take the first stable
point above the "expert cliff".

## Proposed approach

1. Benchmark the shortlist's _fits-in-VRAM_ picks (1, 3, 5, 6, 7, 8) with
   `llama-bench` on oams — cheap, already have the harness.
2. Benchmark one MoE (`glm-4.7-flash` Q4_K_M or `qwen3.5-35b-a3b` IQ4_XS) with
   the `--n-cpu-moe` sweep, to find the real RDNA2 number.
3. Decide the served set from the measurements, favouring:
   - coverage of gaps brys cannot fill cheaply (ASR via whisper is 0.55 GB and
     far better value than a 30B omni model);
   - one general worker (`qwen3.5-9b`) and one vision (`qwen3-vl-8b`);
   - optionally one MoE if the measured speed justifies the disk.

## Acceptance

- Every served model has a measured prefill/decode line on oams recorded in
  `docs/local-llms.md`.
- Total disk for the oams model set is stated and considered acceptable.
- Models that do not justify their disk are not added.

## Open questions

- Is `qwen3.5-9b` real and available as a GGUF, or is the research's naming off?
  Verify the exact repo/quant before adding.
- Does a 30B-A3B MoE on Vulkan actually clear the expert cliff, or does the
  RDNA2 prefill regression (seen with the GDN-hybrid flash-next) sink it?
- Do we need a second embedding model, or is the one on brys enough via LiteLLM?
