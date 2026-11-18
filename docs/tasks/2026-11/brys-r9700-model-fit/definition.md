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

Full analysis and sources: [research.md](research.md).

| # | Model | Engine | Resident need | Fits? | Expected decode (single R9700) |
|---|---|---|---|---:|---|
| 1 | Qwen3.8-Flash-Next IQ2_XS | Strata | 39.2 GB | yes | 45–70 t/s (estimate) |
| 2 | Qwen3.8-Flash-Next IQ3_XXS | Strata | 47.0 GB | yes | 35–55 t/s (estimate) |
| 3 | Qwen3.8-Flash-Next Coder IQ1_M | Strata | 32 GB | yes | 50–80 t/s (estimate) |
| 3b | Flash-Next IQ3_XXS | **BigMoeOnEdge** | 47 GB | yes | 50–70 t/s (70 measured at 24 GB + 96 GB RAM) |
| 4 | Qwen3.8-Flash-Next UD-Q4_K_XL | Strata | 88 GB RAM | yes | 20–35 t/s (estimate) |
| 5 | GLM-5.3-Flash 321B Maya-S | Maya | 96.5 GB | yes | 20–30 t/s (unverified; 2 cards = 44 t/s) |
| 6 | Dense 27–35B, Q4 | llama.cpp Vulkan | 17–23 GB VRAM | yes | 25–40 t/s |
| 7 | Qwen3.6-35B-A3B Q4 | llama.cpp Vulkan | 22.9 GB VRAM | yes | 100 t/s or more |
| 8 | DeepSeek V4.1-Flash 1.75 bpw | Maya / Strata | 191–239 GB | SSD-streamed | low, 3–10 t/s |
| 9 | Qwen3.8-Flash-Next Q8_0 | Strata | 136 GB RAM | **no** | — |

Rows 1–3 are the natural first runs: the R9700 is a tested Strata target, the expert cache grows
from 12 GB on oams to 32 GB here, and the existing llama-swap wiring already pins the card.
Row 3b is the same model under a **model-agnostic** engine (BigMoeOnEdge) so one server could later
cover flash-next, Qwen3.6-35B-A3B, dense models and the DeepSeek/GLM GGUFs. Row 5 is the only route
to a 321B model on this box. See [research.md](research.md) for the full engine survey, including
the engines rejected because they are CUDA-, AVX-512- or Strix-Halo-only.

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
