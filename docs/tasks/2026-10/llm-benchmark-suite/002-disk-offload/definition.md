---
type: Task
description: Research and measure disk-offload and RAM-reduction levers for the large brys models, standalone (not enabled as served models), extending the Qwen3.8-Flash-Next tweaks.
status: in-progress
authored_by: agent
timestamp: 2026-10-19T18:13:00+02:00
---

# 002 — Disk-offload and RAM-reduction study

## Goal

Find and measure the levers that let a model run with less RAM, by moving weights
or KV to disk, without serving it as an always-on model. The work is
**standalone**: the candidate flags are tested with a one-off `llama-server` or
`llama-bench` invocation, not wired into a boot entry, until a result is good
enough to propose.

## Levers to research and measure

- **`--lazy-mode`** (SSD offload): load the model in mmap mode, read experts from
  disk on demand. Already used for a large Qwen variant; measure the RAM/time
  trade-off for the frontier models.
- **`--load-mode`** (`mmap`, `mlock`, `none`) and mmap control
  (`--no-mmap`, `--no-mmap-prefetch`). The earlier finding: prefetch at load
  warms the page cache and lowers first-request time; `--no-mmap-prefetch`
  shortens load but lengthens the first request. Re-confirm and extend.
- **MoE expert offload / streaming**: `--cpu-moe`, `-ot` (override-tensor), and
  the unmerged MoE-streaming PRs already carried as experimental package rows
  (`llama-cpp-master-moe-stream-vulkan`, `llama-cpp-master-pin-hot-experts-vulkan`).
- **KV cache reduction**: KV type (`--cache-type-k`/`-v`, q8_0/q4_0), `--kv-unified`
  vs per-slot, `--swa-*` and attention-window knobs, `--cache-ram`.
- **Quant choice** at the same RAM budget (`qwen-flash-next-quant` is a prior
  task; reuse its findings).
- **Disk speed floor**: the ZFS direct-read rate, since any disk-offload design
  is bounded by it (2.3-2.5 GB/s cold measured).

## Method

- Every measure is standalone: a one-off server or bench process, then stop it.
- Record RAM (RssFile/RssAnon/VmRSS), disk read volume, major faults, decode and
  prefill tok/s, and load time.
- The main server need not be down, but a measurement that competes with a
  resident frontier model for page cache is invalid; note box state.

## Deliverables

- `offload.research.md` in this directory: the lever inventory, what each does,
  and the measured effect on brys.
- A recommendation: which levers are worth enabling, and for which models.

## Acceptance criteria

- Each lever in the list above has either a measured effect or a documented
  reason it does not apply.
- At least one concrete RAM-reduction result for a frontier model, with the
  speed cost stated.

## References

- [llama-cpp-latest-package](../llama-cpp-latest-package/definition.md)
- [qwen-flash-next-quant](../qwen-flash-next-quant/definition.md)
- [qwen-gpu-offload](../qwen-gpu-offload/done.md)
- [llm-prompt-cache-ram](../llm-prompt-cache-ram/done.md)
- [packages/llama-cpp/README.md](../../../../packages/llama-cpp/README.md)
- [docs/local-llms.md](../../../local-llms.md) (`--lazy-mode` section)
