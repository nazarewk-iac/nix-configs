---
type: Decision
description: Drop qwen3.8-27b from the fleet because it is slower than the 1M-context flash-next on CPU and offers a smaller window; its deep aliases move to flash-next.
status: done
authored_by: agent
timestamp: 2026-11-04T08:10:00+01:00
---

# Drop `qwen3.8-27b`

## Decision

Remove the `qwen3.8-27b` model from `data/llm.nix` and point its five aliases
(`chat-deep-slow`, `code-deep-slow`, `vision-deep-slow`, `reason-deep-slow`, `tools-deep-slow`)
at `qwen3.8-flash-next`.

## Why

Measured on 2026-11-04 on brys with the same prompt ("write about 150 words about rain"), through
`pi` in print mode, reading `usage.output` against `durationMs`:

| model                | serving              | output        | speed          |
| -------------------- | -------------------- | ------------- | -------------- |
| `qwen3.8-27b`        | CPU, 8 threads, 128k | 195 tok/244 s | **0.80 tok/s** |
| `qwen3.8-flash-next` | CPU, 16 threads, 1M  | 230 tok/97 s  | **2.36 tok/s** |

The dense 27B is **three times slower** and its window is **eight times smaller**. It was
therefore never the right answer for a "deep" tier: the tier exists to buy capability, and the
27B bought neither speed nor context. Only the small 4B model gets GPU layers
(`--n-gpu-layers 99`); every other model is CPU-bound, so thread count dominates and 27B cannot
use as many threads as flash-next without starving the co-resident frontier.

Second reason: it occupied a co-residence slot. Dropping it frees 23.3 GiB, so the frontier and
the 35B MoE now fit with room (79.2 GiB of 106 GiB) instead of being at 102.5 GiB.

## Consequences

- `vision-deep-slow` still works: flash-next ships an `mmproj`, so `vision = true` now.
- Deep tiers collapse onto one model. That is honest: there is exactly one capable large model
  on this host, and the alias should not pretend a slower second one exists.
- `docs/local-llms.md` and `.agents/skills/kdn-llms/SKILL.md` carry the measurement.
- Nothing else changes: aliases keep their names, so every agent file and skill still resolves.

## Reverting

Restore the `qwen3.8-27b` entry and its `coResidentTiers` group, remove the five aliases from
flash-next, and move the aliases back. Only worth it if the model is given GPU layers.
