---
type: Decision
description: Prune the model fleet after the 27B drop — remove the slow 8B vision model and the five dense 27-36B models, lift the CPU-variant context to native, and record the long-context routing rule.
status: done
authored_by: agent
timestamp: 2026-11-04T09:20:00+01:00
---

# Fleet prune, 2026-11-04

Follows [the 27B decision](decision-drop-qwen3.8-27b.md). Every number below is from the measured
table in [docs/local-llms.md](../../../local-llms.md) (decode tok/s on brys); nothing was
re-measured for this change.

## 1. `qwen3-vl-8b-instruct` removed; `vision-quick-fast` repointed

The 8B vision model measured **8.4 tok/s**, slower than the 30B VL MoE next to it at **15.7**.
A "quick" tier that is slower than the standard tier is a lie, so the model is gone and
`vision-quick-fast` now resolves to `qwen3-vl-30b-a3b`. Vision still works: that model ships an
`mmproj` and `vision = true`.

Consequence: `vision-quick-fast` and `vision-std-fast` resolve to the same model. That is the
same honest collapse as the deep tiers — there is one capable VL model on this host.

## 2. Dense 27-36B models removed (all below 10 tok/s)

| model             | measured decode |
| ----------------- | --------------- |
| `qwen3.6-27b`     | 1.8 t/s         |
| `gemma-4-31b`     | 1.7 t/s         |
| `granite-4.2-30b` | 2.1 t/s         |
| `olmo-3.1-32b`    | 2.3 t/s         |
| `seed-oss-36b`    | 2.0 t/s         |

None had an alias, so nothing routed to them, and every one is slower than the 1M-context
`qwen3.8-flash-next` (2.36). They are the same class as the 27B dropped earlier: dense, CPU-only,
no speed advantage, smaller windows.

Rule applied: alias-less models stay **unless** a recorded speed is below 10 tok/s. The remaining
alias-less entries have no published measurement and are kept pending a benchmark.

## 3. CPU variants lifted to native context (`8192 → 16384`)

`qwen3.5-0.8b-cpu`, `qwen3.5-2b-cpu`, `tmax-2b-cpu` now serve 16384, matching their GPU siblings
and the models' `max_position_embeddings`. Going beyond native needs rope scaling, which is a
quality risk, not a free flag.

These entries cost nothing extra: each `-cpu` model points at the **same GGUF file** as its GPU
sibling (`download.enable = false`, same `hfFile`), so there is no second download and no extra
disk — only different flags (`ngl 0`, `threads 8`).

Measured CPU-vs-GPU penalty for the same weights, same 16k context:

| model        | GPU decode | CPU decode | penalty |
| ------------ | ---------- | ---------- | ------- |
| qwen3.5-0.8b | 163.4      | 55.8       | 2.9x    |
| qwen3.5-2b   | 116.8      | 20.1       | 5.8x    |
| tmax-2b      | 110.7      | 28.6       | 3.9x    |
| qwen3.5-4b   | 60.8       | 13.0       | 4.7x    |
| tmax-9b      | 36.9       | 7.18       | 5.1x    |

## 4. Long-context routing rule

`qwen3.8-flash-next` is **already** CPU-bound (nothing large fits the 8 GB GPU), so "use a CPU
model instead" is not the real trade. The real trade is per-context tier:

| context needed                    | use                                | why                                                      |
| --------------------------------- | ---------------------------------- | -------------------------------------------------------- |
| up to 262k                        | `chat-std-mid` = `qwen3.5-35b-a3b` | 23 t/s, 262k native — about ten times flash-next's speed |
| beyond 262k, or hardest reasoning | `qwen3.8-flash-next`               | the only 1M window on the host, 2.4 t/s                  |

Small CPU models cannot cover high context: their native window is 16k.

## Open item (not done here)

`code-std-fast` resolves to `qwen3.5-4b` in `data/llm.nix` but to `north-mini-code-1.0` in
`SKILL.md` and the live catalog, and `north-mini-code-1.0` is absent from the data. One of the two
is stale; needs a separate decision.
