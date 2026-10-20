---
type: Task
description: Broaden the brys model fleet: survey and measure missing mid-size (10-40B) and specialized (code, etc.) 2026 models, starting with Qwen3.8-27B, then register and benchmark the ones that fit.
status: in-progress
authored_by: agent
timestamp: 2026-10-20T18:45:00+02:00
---

# Broaden the brys model fleet

The current fleet has a hole in the mid band and lacks specialized models. The
2026-10 model survey
([models-2026-mid-large.research.md](../brys-grunt-colocation/models-2026-mid-large.research.md))
picked one 27B model (`Qwen3.6-27B`) and then jumped to models that do not fit
(~122B and larger). Between about 9B and 27B there are almost no candidates, and
there is no dedicated code or other specialized model.

This task fixes that: a proper survey of the missing band and the specialized
classes, then measurement, then registration of the winners.

## Why this matters

- **`Qwen/Qwen3.8-27B` exists** and is current: 27B dense, native
  vision-language, 262K to 1M context, Apache-2.0, thinking by default with
  `reasoning_effort` (xhigh/medium/low). It is the natural mid-size orchestrator
  or strong grunt and it is absent from the fleet.
- The fleet has no code-specialized model (for example a Qwen3-Coder or a
  GLM-Coder generation) and no small vision-language model.

## Scope

### Mid band (10-40B), current generation

Survey the 2026 models in this band that fit the box (<= ~40 GB at a usable
quant, on the CPU at served context). Include at least: `Qwen3.8-27B`,
`Qwen3.8-*` siblings, `Qwen3.7-*`, `Gemma-4` mid sizes, `Ministral-3` mid sizes,
`GLM-*` small/mid, `Mistral-Small-4`, `OLMo-3`, any other 2026 10-40B.

### Specialized classes

- **Code**: a code-specialized model (Qwen3-Coder generation, GLM-Coder, or
  similar) in a size that fits.
- **Vision / multimodal**: a small-to-mid VLM (Qwen3.8-27B is itself VL;
  consider also smaller VL models).
- **Reasoning**: a dedicated reasoning model, if distinct from the others.
- **Tool-calling / agentic**: note tool-calling strength in the survey.

## Method

- Desk survey first (Hugging Face, model cards, one per candidate): name, repo,
  release date, params (total/active), license, GGUF availability, file size at
  a recommended quant, context, modalities, tool-calling, and a one-line fit
  verdict.
- Measure the top candidates on brys with `hack/llm-bench.sh` (or a one-off
  `llama-server`): decode/prefill tok/s, cold start, RAM, and load success.
  Download the GGUF first (the download service does this; `hfRepo`/`hfFile`).
- Register the winners in `hosts/brys/llm-routers.nix` (the `surveyed` pattern:
  `mkCpu`/`mkGpu`), then benchmark the served ids.

## Acceptance criteria

- A survey document lists every 10-40B and specialized candidate with the fields
  above.
- `Qwen3.8-27B` is surveyed, measured, and (if it fits) registered and served.
- At least one code-specialized model is surveyed; measured and registered if it
  fits.
- Each measured model has decode/prefill/cold-start/RAM rows (or a documented
  load failure).

## References

- [brys-grunt-colocation/models-2026-mid-large.research.md](../brys-grunt-colocation/models-2026-mid-large.research.md)
- [brys-grunt-colocation/models-2026.research.md](../brys-grunt-colocation/models-2026.research.md)
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix)
- [hack/llm-bench.sh](../../../../hack/llm-bench.sh)
- [llm-benchmark-suite/measurements.research.md](../llm-benchmark-suite/001-benchmark-suite/measurements.research.md)
