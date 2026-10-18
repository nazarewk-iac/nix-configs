---
type: Task
description: Colocate fast small "grunt" models on brys beside the Qwen3.8 orchestrator, tested on the W6600 GPU, with a measured-profile-driven scheduler.
status: in-progress
authored_by: agent
timestamp: 2026-10-18T06:00:00+02:00
---

# Colocate grunt models on brys beside the Qwen3.8 orchestrator

The orchestrator on brys is a single large, bandwidth-bound model. It serves
well-scoped, high-quality work, but it decodes slowly. Delegation of small,
well-scoped tasks needs a second model that answers fast. A second model that
sits on the CPU path gives back that speed on the orchestrator: the box has one
~40 GB/s memory bandwidth shared by all residents. This task finds, measures,
and wires a fast grunt that stays beside the orchestrator without halving it.
The measured 2026-10-18 result shows the W6600 GPU is the win: a small model
fully on the GPU uses no CPU bandwidth.

## Context

`Qwen3.8-Flash-Next` (93.7 GB on disk, ~9-14 tok/s decode measured) is the
orchestrator. It runs on the CPU, it is sparse MoE, and it is bandwidth-bound.
Delegation to small, well-scoped tasks needs a fast grunt for two reasons:

1. The orchestrator decode is slow for a quick subtask.
2. Any CPU-resident co-tenant halves the orchestrator decode, because both
   models read from the same ~40 GB/s. (Measured for DS4: idle phi-4 halves it.)

The three research files that support this task are:

- [colocation.research.md](colocation.research.md) - the RAM budget, the
  bandwidth arithmetic, the colocation penalty, and the W6600 option.
- [models-2026.research.md](models-2026.research.md) - the 2026-era small-model
  shortlist (Qwen3.5-4B, Qwen3.5-9B, and others).
- [llama-router-scheduler.research.md](llama-router-scheduler.research.md) - the
  router/scheduler survey (llama-swap) and the measured-profile policy.

## Measured results (llama-bench, brys, 2026-10-18)

All rows are Q4_K_M. `-p 512 -n 128 -r 3 -t 16`. The CPU columns are `-ngl 0`;
the W6600 columns are `-ngl 99 --device Vulkan0`. Units are tokens/second.

| model | released | weights | CPU pp512 | CPU tg128 | W6600 pp512 | W6600 tg128 |
|---|---|---|---|---|---|---|
| Qwen3.5-2B | 2026-02 | 1.27 GB | 906 | 28.30 | 2737 | **125.01** |
| Granite-4.2-3B | 2026-08 | 2.24 GB | 825 | 19.89 | 1441 | **86.65** |
| Qwen3-4B-Instruct-2507 | 2025-10 | 2.49 GB | 596 | 14.14 | 1173 | 74.94 |
| Qwen3.5-4B | 2026-02 | 2.73 GB | 452 | 12.03 | 1073 | **62.34** |
| Qwen3-8B | 2025-04 | 5.02 GB | 297 | 8.03 | 644 | 42.77 |
| Qwen3.5-9B | 2026-02 | 5.67 GB | 270 | 7.26 | 594 | **36.99** |
| Qwen2.5-0.5B-Instruct | 2024-09 | 0.46 GB | - | - | 10113 | 337 |

The 0.5B row comes from
[docs/tasks/2026-10/qwen-gpu-offload/definition.md](../qwen-gpu-offload/definition.md).
The `Qwen3-4B-Instruct-2507` and `Qwen3-8B` rows are **2025** models, kept only as
the pre-2026 baseline; the decision uses the 2026 rows.

### LEGEND

- `pp` = prompt processing, also called prefill. The number after `pp` is the
  prompt length in tokens. So `pp512` = the prefill speed in tokens/second for a
  512-token prompt.
- `tg` = token generation, also called decode. The number after `tg` is the
  number of generated tokens. So `tg128` = the decode speed in tokens/second for
  128 generated tokens.
- `-ngl 99` = all model layers on the GPU. `-ngl 0` = all layers on the CPU. The
  CPU columns are `-ngl 0`; the W6600 columns are `-ngl 99` on `Vulkan0`.
- `t/s` = tokens per second. A higher number is faster. `pp512` is normally much
  higher than `tg128` because prefill reuses the weights for many tokens at once.

The target is 20-50 tok/s decode and 100s tok/s prefill.

The W6600 beats the target for every 2026 row on decode and prefill. On the CPU
alone, only the 2B and 3B rows reach the decode target, and no CPU row reaches
100 tok/s. Ranked by W6600 decode: 2B 125.0, Granite-3B 86.7, 4B 62.3, 9B 37.0
tok/s. The 9B is the highest-quality grunt that still fits the 8 GB card at 16K
context; the 4B is the safer default; the 3B is the fastest useful tool-caller.

## Decision

(a) The primary grunt is a 2026-era small model, `Qwen3.5-4B` or `Qwen3.5-9B`
per [models-2026.research.md](models-2026.research.md), fully on the W6600. It
runs on its own `routers.grunt`, colocated with the orchestrator, with
`modelsMax 1`, `parallel 1`, no speculative decoding, and context <= 32K.

(b) The W6600 is the win because it uses no CPU bandwidth. The GPU is idle while
the orchestrator runs on the CPU, so a GPU grunt does not halve the
orchestrator. A CPU co-tenant does: it contends for the same ~40 GB/s and halves
the orchestrator decode.

(c) The CPU `llm-small` boot entry stays for CPU-only grunts and overspill. It
is a separate boot entry, so it does not contend with the orchestrator.

(d) The DS4 option stays available as an alternative frontier model. It is not
removed and not changed by this task.

## Scheduler requirement (user note)

The grunt needs a router/scheduler with:

- priority and pinning, so a grunt request never evicts the orchestrator;
- active-request protection, so a model with a request in flight is never
  swapped out; and
- a measured per-model profile, filled in at model start, used as the input for
  eviction and admission.

The profile holds these fields, measured at real start:

| field | meaning |
|---|---|
| `rss_file` | mmap'd weights at idle (RAM budget; reclaimable) |
| `rss_anon` | KV + compute buffers at served context (RAM budget; not reclaimable) |
| `vram` | GPU VRAM used while served |
| `decode_tok_s`, `prefill_tok_s` | warm llama-bench/server timings |
| `load_time` | spawn to "listening", cold page cache (swap cost) |
| `fault rate` | major faults/s at idle (detect page-cache thrash) |
| `coexist penalty` | orchestrator tok/s with versus without this model resident |

The scheduler decides from measured numbers, not from model names. See
[llama-router-scheduler.research.md](llama-router-scheduler.research.md) sections
3 and 4 for the llama-swap configuration and the measured-profile mechanism.

## Acceptance criteria

- The grunt routes through the compat-proxy without evicting Qwen. A grunt
  request reaches `routers.grunt`, and Qwen stays resident.
- Measured grunt decode is >= 20 tok/s.
- A profile file exists for each served model, with every field in the table
  above filled in.
- The setup is documented in `docs/local-llms.md` and
  `hosts/brys/performance.md`.

## References

- [colocation.research.md](colocation.research.md)
- [models-2026.research.md](models-2026.research.md)
- [llama-router-scheduler.research.md](llama-router-scheduler.research.md)
- [hosts/brys/llm.nix](../../../hosts/brys/llm.nix)
- [hosts/brys/llm-routers.nix](../../../hosts/brys/llm-routers.nix)
- [hosts/brys/llm-qwen.nix](../../../hosts/brys/llm-qwen.nix)
- [modules/den/aspects/llm.nix](../../../modules/den/aspects/llm.nix)
