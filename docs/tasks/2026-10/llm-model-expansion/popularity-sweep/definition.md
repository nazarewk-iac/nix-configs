---
type: Task
description: Discover candidate models by Hugging Face popularity, then filter by fit for brys. Method-first: query the HF API for the most-downloaded 2026 GGUF-capable models per class, then screen by size, architecture support, license, and hardware fit.
status: in-progress
authored_by: agent
timestamp: 2026-10-20T19:30:00+02:00
---

# Popularity-first model discovery

The earlier surveys ([mid-band-survey.research.md](mid-band-survey.research.md),
[specialized-survey.research.md](specialized-survey.research.md),
[qwen-specialized-survey.research.md](qwen-specialized-survey.research.md)) used
hand-picked candidate lists. This task uses a **data-driven** method: rank the
Hugging Face catalog by popularity, then filter by what actually fits brys.

## Method

1. Query the Hugging Face model API, sorted by `downloads`, with filters:
   - `filter=gguf` (a GGUF must exist for llama.cpp to serve it),
   - `pipeline_tag` per class (`text-generation`, `image-text-to-text`,
     `feature-extraction`, `text-to-speech`, `automatic-speech-recognition`,
     `text-ranking`),
   - `createdSince=2026-01-01` (current generation),
   - paginate (`limit` max 1000, follow with `?cursor=`).
   API shape:
   `https://huggingface.co/api/models?filter=gguf&pipeline_tag=text-generation&sort=downloads&direction=-1&limit=100&createdSince=2026-01-01`
2. Deduplicate by base model (many GGUF repos repackage the same weights).
3. Screen each candidate against the brys fit rules (below).
4. Rank the survivors and hand the top ones to measurement.

## Fit rules (brys)

- **Serving**: llama.cpp / llama-server, CPU-first. The arch must be in
  llama.cpp (`llama-arch.cpp`), or the model is out.
- **Size**: Q4/Q5 GGUF must fit the box. Weights up to ~40 GB load on the CPU
  (slower for dense, faster for MoE). Small models (<= ~6 GB) can use the 8 GB
  W6600.
- **Disk**: about 330 GB free; prefer models <= 25 GB.
- **License**: note it; an unclear license is a caveat, not an immediate reject.
- **Recency**: 2026 generation preferred; a strong older model is noted, not the
  goal.
- **Modality**: text, vision, audio, embedding/rerank, speech; note each.

## Deliverable

`popularity-sweep.research.md`: the query used, the ranked shortlist after
screening, and a table (model | repo | downloads | class | params | GGUF size |
license | fit verdict). Then feed the top new entries to measurement.

## Acceptance criteria

- The sweep lists every 2026 GGUF-capable model above a stated download
  threshold, deduplicated by base model.
- Each entry has a fit verdict against the rules above.
- The top ~10 new candidates that are not already in the fleet are named for
  measurement.

## References

- [definition.md](definition.md)
- Hugging Face model API: `https://huggingface.co/api/models`
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix)
- [llm-benchmark-suite/measurements.research.md](../llm-benchmark-suite/001-benchmark-suite/measurements.research.md)
