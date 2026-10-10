---
type: Task
description: Split the tangled Qwen llama-server knobs in hosts/brys/llm.nix into an explicit CPU-only config and an explicit GPU-offload config, so the W6600 choice is one named switch.
status: open
authored_by: agent
timestamp: 2026-10-11T11:05:00+02:00
---

# Split the Qwen CPU-only and GPU configs on `brys`

## Context

- `qwen-gpu-offload` (done, 2026-10-07) folded `llm-qwen-gpu` into the canonical `llm-qwen`
  entry. The fold left a confusing flag combination in `hosts/brys/llm-qwen.nix`:
  `qwenGpu = true` (which once selected the Vulkan build) together with `qwenVulkan = false`
  and a `llamaPackage` override, and the comment has to explain that the GPU is *not* used.
- The reason the W6600 is off for Qwen is measured: at ~40.6K tokens of context the amdgpu
  ring times out under the Vulkan workload and the context is lost
  (`docs/tasks/2026-10/w6600-amdgpu-hang/`, note in `hosts/brys/llm.nix`).
- The GPU path still has value: the draft-only offload measured +15% decode on the W6600, and
  smaller contexts may stay under the hang threshold.

## Goal

Express the two shapes — CPU-only Qwen, and Qwen with the MTP draft head (or dense layers)
on the W6600 — as two clearly named configurations in `hosts/brys/llm.nix`, so
`hosts/brys/llm-qwen.nix` picks one by name instead of juggling `qwenGpu`, `qwenVulkan`,
`qwenNGpuLayers`, and `llamaPackage` by hand.

## Steps

1. Read the current flag plumbing in `hosts/brys/llm.nix`.
2. Define two named shapes (for example `qwenCpu` and `qwenGpuDraft`), each setting every
   llama-server knob it owns.
3. Make `llm-qwen.nix` pick the CPU shape with no leftover GPU flags.
4. Keep the GPU shape selectable (a comment or an option), documented as hang-prone above
   ~40K context.

## Acceptance test

1. `llm-qwen` boots and serves exactly as today (same model, 1M context, MTP on CPU).
2. No combination of flags in `llm.nix` says "Vulkan" while the effective config is CPU-only.
3. `docs/local-llms.md` names both shapes.

## Related docs

- `docs/tasks/2026-10/qwen-gpu-offload/done.md` — the measurement that motivated the fold.
- `docs/tasks/2026-10/w6600-amdgpu-hang/definition.md` — the hang.
- `hosts/brys/llm-qwen.nix`, `hosts/brys/llm.nix` — the code.
