---
type: Task
description: Decide which model families and inference engines to run on host brys after the W6600 to single R9700 (32 GB) upgrade, and tag measurements with gpu-w6600 / gpu-r9700 aliases.
status: open
authored_by: agent
timestamp: 2026-11-18T12:00:00+01:00
---

# Single R9700 on brys: what can we fit

## Context

- **brys** is a Ryzen 9 5950X workstation with **128 GB DDR4-3200 ECC**. Measured memory
  throughput is COPY 39.8 GB/s and TRIAD 27.9 GB/s (`hosts/brys/performance.md`). The CPU has
  AVX2 but no AVX-512.
- The GPU is now **one Radeon AI PRO R9700**: 32 GB (31.86 GiB), 640 GB/s, 300 W, gfx1201,
  in a **PCIe Gen4 x8** slot (~16 GB/s). The W6600 (8 GB, gfx1032) is gone.
- **No second card is planned.** Every target must fit one 32 GB card; multi-GPU published
  numbers do not apply.
- Another session is working heavily on brys. This task is **desk research** until that session
  releases the host.
- The measurement tables in `docs/local-llms.md` mix rows taken on the W6600, on oams, and on
  CPU. They need a hardware tag so the R9700 rows are not compared with 8 GB rows.

## Goal

1. A shortlist of **model × engine** combinations that fit 32 GB VRAM + 128 GB RAM, and which
   of them are worth a real run.
2. A **measurement tag scheme** that keeps old and new rows comparable:
   `gpu-w6600`, `gpu-r9700`, `gpu-rx6800m`, `cpu` for hardware, plus an engine tag.
3. A ranked plan for the first runs on brys, with an acceptance number for each.

## Findings

Full analysis and sources: [research.md](research.md). Measured numbers, harness configs and the
fit curves: [measurements.md](measurements.md).

**Status 2026-11-18: measured, not estimated.** The R9700 ran every downloaded model, the frontier
fits, and the numbers are in `measurements.md`.

| # | Model | Harness | Resident need | Fits? | Measured decode |
|---|---|---|---|---:|---|
| 1 | Qwen3.8-Flash-Next GSQ-RCO `IQ2_XS` | **Strata (HIP)** | 63 GiB | yes | **66.7 t/s** at 256k, prefill 2779 t/s |
| 1b | Qwen3.8-Flash-Next `UD-IQ1_S` | llama.cpp Vulkan, `n-cpu-moe 26` @ 64k | 62 GB | yes | **30.9 t/s** empty context, **21.9 t/s** served at 64k |
| 2 | Qwen3.8-Flash-Next + `qwen3.5-4b` | llama.cpp Vulkan, both resident | 23.0 GiB VRAM | yes | **21.9 t/s** frontier + **125.4 t/s** small |
| 3 | GLM-5.3-Flash 321B `UD-IQ2_XXS` | llama.cpp Vulkan, `n-cpu-moe 36`, 16 threads | 102 GB | yes | **8.9 t/s** (CPU-bound) |
| 4 | Qwen3.5-35B-A3B | llama.cpp Vulkan, all layers on GPU | 20.5 GB VRAM | yes | **120.7 t/s** |
| 5 | Gemma-4-26B-A4B | llama.cpp Vulkan, all layers on GPU | 13.4 GB VRAM | yes | **134.0 t/s** |
| 6 | Dense 27–31B (qwen3.8-27b, gemma-4-31b) | llama.cpp Vulkan, all layers on GPU | 15–17 GB VRAM | yes | **30–32 t/s** |
| 7 | Qwen3.8-Flash-Next `UD-IQ1_S` | BigMoeOnEdge `--auto` | 62 GB | yes | 8.2 t/s (worse than llama.cpp) |
| 8 | DeepSeek V4.1-Flash `UD-IQ1_S` 233 GB | any | 233 GB+ | **no** | exceeds 157 GB combined |
| 9 | Qwen3.8-Flash-Next `Q8_0` 188 GB | any | 188 GB | **no** | exceeds RAM |

**Strata wins outright** on this card: 66.7 t/s decode and 2779 t/s prefill at the native 256k,
against 21.9 / 255 for llama.cpp at 64k. The price is that Strata reads only its own GSQ-RCO packs,
so the llama.cpp GGUF we already have cannot feed it, and the reverse.

The llama.cpp configuration stays useful as the co-residency path: `UD-IQ1_S` at `n-cpu-moe 26`,
64k, plus a small model beside it in 23 GiB of VRAM. GLM-5.3-Flash works but is CPU-bound at 8.9 t/s; keep it only if a 321B model is
needed at any price.

Rows 1–3 are the natural first runs: the R9700 is a tested Strata target, the expert cache grows
from 12 GB on oams to 32 GB here, and the existing llama-swap wiring already pins the card.
Row 7 is the model-agnostic harness (BigMoeOnEdge) on the same GGUF; its planner predicted 45 t/s
but its executed default delivered 8.2. Row 8 is out of reach. See [research.md](research.md) for the
full engine survey, including the engines rejected because they are CUDA-, AVX-512- or
Strix-Halo-only.

## Measurement aliases

Add a hardware tag to every row, and an engine tag to every new row:

| Tag | Meaning |
| --- | --- |
| `gpu-w6600` | Radeon Pro W6600, 8 GB, RDNA2, gfx1032 — all rows before 2026-11-17 |
| `gpu-r9700` | Radeon AI PRO R9700, 32 GB, RDNA4, gfx1201 — new rows |
| `gpu-rx6800m` | RX 6800M, 12 GB, RDNA2, gfx1031 — oams |
| `cpu` | no GPU used |
| `engine=llamacpp` / `strata` / `maya` / `ik-llamacpp` / `tandem` | engine used for the row |

Proposed column change for the measured-model table in `docs/local-llms.md`:

```
| model | host | gpu | engine | class | params (active) | file GB | ctx | decode t/s | prefill t/s | ...
```

Do not edit that table from this task while the other brys session owns the file. Land the column
change after that session finishes.

## Acceptance test

1. Three rows on brys, tagged `gpu-r9700`, with decode and prefill from `llama-server` or Strata
   timings, not wall-clock estimates: IQ2_XS, IQ3_XXS, and one dense 27–35B under
   llama.cpp Vulkan.
2. The Strata rows must beat the oams numbers (40.6 t/s at 12 GB) or the reason is recorded.
3. `docs/local-llms.md` carries the `gpu` and `engine` columns, and every existing row has a tag.

## Risks and open questions

- **The other session owns brys.** Do not stop llama-swap or load a model until it is done.
- **PCIe Gen4 x8** is half the link the R9700 test rigs use. Expert streaming and prefill are the
  first things it will hurt.
- **Maya AMD is experimental.** Its published R9700 numbers are all two cards. Single-card numbers
  must be measured, not inferred.
- **DDR4 is the floor.** At ~28–40 GB/s, every SSD-free tier is bounded by system RAM, not by the
  card. More VRAM raises the cache hit rate; it does not raise RAM bandwidth.
- **Measured numbers are stale.** Every existing brys row was taken on the W6600 and is a lower
  bound at best.

## Related

- [research.md](research.md) — engine survey, fit arithmetic, sources.
- `hosts/brys/performance.md` — hardware inventory, R9700 slot and id.
- `docs/tasks/2026-10/llm-benchmark-suite/003-runner-eval/` — the earlier runner survey for the
  8 GB card.
- `docs/tasks/2026-11/oams-llm-host/` — the measured Strata numbers on 12 GB.
