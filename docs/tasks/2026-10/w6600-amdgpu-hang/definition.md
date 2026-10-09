---
type: Task
description: Investigate why the Radeon Pro W6600 (Vulkan/radv) hard-hangs under the Qwen3.8-Flash-Next MTP workload on brys, and decide whether the GPU draft head can be safely re-enabled.
status: in-progress
authored_by: agent
timestamp: 2026-10-09T07:34:28+02:00
---

# W6600 amdgpu ring timeout under the Qwen MTP draft head

## Context

The `llms-frontier` / `llm-qwen` boot entries ran the Qwen3.8-Flash-Next MTP
draft head on the Radeon Pro W6600 over Vulkan (radv), with the main model and KV
on the CPU. It gave ~18% faster decode (10.82 vs ~9.1 t/s).

On 2026-10-08 22:34:13 the W6600 wedged mid-decode. Kernel log:

```
amdgpu 0000:0d:00.0: amdgpu: ring comp_1.2.0 timeout, signaled seq=114180, emitted seq=114181
amdgpu 0000:0d:00.0: amdgpu: Starting comp_1.2.0 ring reset
amdgpu 0000:0d:00.0: amdgpu: Ring comp_1.2.0 reset succeeded
amdgpu 0000:0d:00.0: [drm] device wedged, but recovered through reset
```

llama-server:

```
ggml_vulkan: device lost on Vulkan0
srv  update_slots: decode() failed: vk::Queue::submit: ErrorDeviceLost
srv    send_error: task id = 844, error: decode() failed: vk::Queue::submit: ErrorDeviceLost
slot      release: id  2 | task 844 | stop processing: n_tokens = 40635, truncated = 0
```

The kernel reset the ring, but the radv Vulkan context was lost for the life of
the llama-server process. Every later decode failed in ~0.4 s
(`ErrorDeviceLost`); the request returned an empty stream, and OpenCode closed
the turn with an empty assistant message ("stops without answering"). It
happened at ~40.6K tokens of context.

The GPU draft head was **disabled** on 2026-10-09: `qwenVulkan = false` in
`hosts/brys/llm-qwen.nix` and `hosts/brys/llms-frontier.nix`, so the MTP draft
runs on the CPU. That is the safe state; this task is to understand the hang and
decide whether the GPU can return.

## Goal

1. Find the root cause of the `comp_1.2.0` ring timeout (driver bug, firmware,
   Mesa/radv bug, or the `qwen4exp` MTP graph on the W6600).
2. Find any fix or mitigation (kernel/driver/firmware upgrade, Mesa update, a
   llama.cpp flag, a different submission path) that removes the hang.
3. Decide whether to re-enable the GPU draft head, and at what context limit.

## Approach

Orchestrated research across the relevant upstream projects and bug trackers,
then a targeted reproduction on brys. Sub-questions:

- Is `ring comp_1.2.0` a known amdgpu hang on Navi/RDNA (W6600 = Navi 23)?
- Known radv `ErrorDeviceLost` / `device wedged, but recovered through reset`
  reports on llama.cpp's Vulkan backend.
- Does the `qwen4exp` MTP graph submit a workload that trips the compute ring
  (large buffers, a fence/wait pattern, `vk::Queue::submit` from multiple
  threads)?
- Is the timeout context-size dependent (only at ~40K+ tokens)?
- Does a newer Mesa (radv), kernel, or firmware change the outcome?

## Acceptance criteria

- A `research.md` with the findings and their sources.
- A clear recommendation: re-enable, re-enable with a cap, or keep disabled.
- If a mitigation exists, a reproduction on brys that shows the hang gone (or a
  documented reason it cannot be reproduced safely).

## References

- [docs/local-llms.md](../../../docs/local-llms.md) — the serving topology and
  the "GPU draft head — DISABLED 2026-10-09" note.
- [hosts/brys/llm.nix](../../../../hosts/brys/llm.nix) — `qwenVulkan` and the
  W6600 note.
- [docs/tasks/2026-10/qwen-gpu-offload/done.md](../qwen-gpu-offload/done.md) —
  the original GPU-draft-head work.
