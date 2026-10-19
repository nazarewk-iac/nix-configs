---
type: Solution
description: Closed the benchmark suite. Every enabled brys model measured with one harness; opencode client start measured on oams; the harness is committed and repeatable.
task: definition.md
authored_by: agent
timestamp: 2026-10-19T21:30:00+02:00
---

# Solution — benchmark suite

## What was delivered

- `hack/llm-bench.sh` plus `hack/README-llm-bench.md`: a repeatable harness.
  It measures cold start, warm start, TTFT, decode tok/s, prefill tok/s, cache
  reuse, resident memory (RssFile/RssAnon/VmRSS) and idle major faults for one
  served model. It prints TSV or JSON. It was smoke-tested and passes
  `shellcheck`.
- [measurements.research.md](measurements.research.md): 31 brys models measured
  in one pass, with a legend, one unified table, and a caveats section.
- [opencode-client.research.md](opencode-client.research.md): the opencode
  client-start cells, measured on oams and labelled as client-side.

## Results (summary)

- Decode spans 2.4 tok/s (seed-oss-36b) to 208 tok/s (qwen3.5-0.8b).
- The two frontier models are the slow, cold-load ones: DeepSeek V4 Flash cold
  310 s and 1.46 tok/s decode; Qwen3.8-Flash-Next cold 156 s and 2.49 tok/s.
- opcode start is about 3.4-4.0 s in every cell.

## Caveats

- Cold and warm opencode start differ by less than the host-load noise on oams,
  so that pair is not significant. Every run records its own load.
- `VRAM_MiB` is not in the table: the harness does not read the GPU, and no
  prior per-model VRAM set exists.
- A cold-start number is only truly cold when the model was evicted first, and
  the box can hold only one frontier model at a time.

## Follow-ups

- Add a GPU-reader step to the harness for `VRAM_MiB`.
- Re-measure the frontier models on an idle box for tighter cold-start numbers.
