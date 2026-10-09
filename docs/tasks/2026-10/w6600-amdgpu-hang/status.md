---
type: Status
description: Research done; the hang matches open llama.cpp #27306 (MTP draft decode). Re-enable is deferred to a controlled test.
task: definition.md
authored_by: agent
timestamp: 2026-10-09T08:05:00+02:00
---

# Status — W6600 amdgpu hang

## Done so far

- Captured the hang evidence from brys (kernel `comp_1.2.0` ring timeout +
  hard recovery; radv `ErrorDeviceLost`).
- Disabled the GPU draft head (`qwenVulkan = false`); brys runs the CPU MTP path
  with 0 device errors since the 2026-10-09 reboot.
- Orchestrated research across three tracks (amdgpu kernel, llama.cpp Vulkan,
  Mesa radv). Findings in [research.md](research.md).
- Identified the most likely root cause: **llama.cpp #27306** — the
  `--spec-type draft-mtp` draft-context decode triggers the RADV compute-ring
  timeout. Still open upstream.

## Remaining

- A controlled reproduction on brys with the mitigation set
  (`GGML_VK_MAX_NODES_PER_SUBMIT`, serialized/async-off submits, small `-ub`,
  `RADV_DEBUG`), driven past 40K tokens.
- A decision on whether any mitigation is good enough to re-enable the GPU.

## Next directions

1. When brys can be taken out of service, run the test plan in
   [research.md](research.md) with a manual `llama-server` so the system service
   stays up.
2. If the hang persists, file a llama.cpp issue linking #27306 with the
   `radv_dumps_*` capture and this host's topology.
3. Otherwise keep the CPU MTP path (current default).
