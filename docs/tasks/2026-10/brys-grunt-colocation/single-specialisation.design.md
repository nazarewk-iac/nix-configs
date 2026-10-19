---
type: Design
description: Collapse the four brys boot specialisations into one llama-swap config by expressing "DS4 runs alone" and "each model family owns its RAM class" as matrix sets and evict costs, not as separate top-level boot entries.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T17:30:00+02:00
---

# Design: one specialisation, many models, DS4 alone

## Problem

brys has four boot specialisations, and the split exists for one reason: the
old llama.cpp router was blind to memory. It evicted by idle-LRU alone. It had
no priority and no pinning. A request for a small model could evict the
orchestrator, and a model with an in-flight request could be evicted (llama.cpp
#28698, #28443). So each RAM class got its own boot entry, and only one class
could be resident:

| Entry | Serves | Why separate |
|---|---|---|
| `llm-ds4` | DeepSeek V4 Flash alone | ~92 GB, needs the whole box |
| `llm-qwen` | Qwen3.8-Flash-Next alone | ~101-116 GB warm, needs the whole box |
| `llms-frontier` | DS4 + Qwen, swap | one router, `--models-max 1`, no reboot to switch |
| `llm-small` | the six-model CPU set | RAM-exclusive with DS4 |
| `default` | DS4 (128K) + Qwen (1M) + grunt | shares the box with the desktop |

The `matrix` engine in llama-swap removes the reason. It has `evict_costs`
(priority) and `sets` (which models may co-reside). That turns each RAM
constraint into a routing rule.

## The rule that replaces the split

A `set` lists the models that may run together. A request for a model evicts
every running model outside that model's set. `evict_costs` sets how hard each
model is to evict: a high cost protects a model, a low cost makes it the first
to go.

The one hard physical fact is the RAM budget (125 GB). DS4 (~92 GB) and Qwen
(~116 GB warm) cannot both be resident. This is arithmetic, not scheduling. A
scheduler cannot fix an overflow. So the design does **not** try to keep both up.
It expresses "DS4 runs alone" as a set:

```yaml
models:
  deepseek-v4-flash:  { evict_cost: 1000 }
  qwen3.8-flash-next: { evict_cost: 1000 }
  qwen3.5-4b:         { evict_cost: 1 }     # GPU grunt
  <surveyed small>:   { evict_cost: 1 }     # CPU/GPU grunts
sets:
  # DS4 may co-run with nothing.
  ds4_alone:      (deepseek-v4-flash)
  # The frontier pair swap among themselves; DS4 keeps its own slot.
  main:           (qwen3.8-flash-next | deepseek-v4-flash)
  # The grunts run ALONGSIDE whichever frontier is resident, and never
  # evict it, because the frontier asks for its own set and the grunt costs 1.
  with_grunt:     (qwen3.5-4b | <surveyed gpu grunts>) & (qwen3.8-flash-next | deepseek-v4-flash)
  with_surveyed:  (<surveyed cpu grunts>) & (qwen3.8-flash-next | deepseek-v4-flash)
```

Outcomes:

- request DS4: every other model is evicted; DS4 alone; fits.
- request Qwen while DS4 is up: DS4 is evicted; Qwen loads; fits.
- request a grunt: it co-resides with Qwen and does not touch DS4's slot.
- request a big CPU grunt: it co-resides with Qwen, but only if the RAM budget
  allows; a request for DS4 evicts it.

The `main` set carries both frontier models so a request for either keeps the
other's slot semantics, exactly as `llms-frontier` does today, without a reboot.

## What collapses

| Today | After |
|---|---|
| `llm-qwen`, `llms-frontier`, `default`, `llm-small` | **one** swap config: frontier pair + grunt + surveyed grunts |
| `llm-ds4` | kept as a *convenience* boot entry (start with DS4 loaded), not a separate topology |

So the design is **4 top-level topologies -> 1 swap config** (plus an optional
DS4-head-start entry). The RAM classes become `sets`, not boot entries.

## Weights placement

Every surveyed model already sits on disk at
`/var/lib/kdn/llms/models/surveyed/<name>.gguf`, inside `modelsDir`. A model
entry reaches it with `hfRepo = "surveyed"`, `hfFile = "<name>.gguf"`, and
`download.enable = false` (no fetch). The weights then map into the swap child
by the same `<modelsDir>/<hfRepo>/<hfFile>` rule the router path uses.

Placement follows the measured table
([coresidency-measured.research.md](coresidency-measured.research.md)):

- **GPU-fit** (file <= ~7 GB at a modest context): the smallest models, with
  `nGpuLayers = 99`, `device = "Vulkan0"`, `parallel = 1`. These decode 37-110
  tok/s and use no CPU bandwidth, so they never slow the orchestrator.
- **CPU** (bigger than the 8 GB card): the rest, on the CPU, evictable.

## Risk and mitigation

- **Reload cost.** A matrix eviction reloads the evicted model from disk
  (67.5 s cold for a large model). The mitigation is `evict_cost`: a grunt costs
  1, so a grunt request never pays this, and the frontier costs 1000, so a
  frontier request never loses its slot to a grunt.
- **Stop-the-world reload.** llama-swap config reload is stop-the-world
  (upstream issue #1202). The design does not reload in place; a config change
  is a restart (see [router-hot-reload.research.md](router-hot-reload.research.md)).
- **Small CPU grunts still halve the orchestrator.** A CPU-resident grunt reads
  the same ~40 GB/s as the orchestrator (measured: idle phi-4 halves DS4). So a
  CPU grunt is a low-priority, opt-in resident, not a default. The GPU grunts
  avoid this cost.
