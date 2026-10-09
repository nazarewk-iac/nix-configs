---
type: Research
description: Why the W6600 hangs under the Qwen MTP draft head, the upstream reports that match, and the mitigations that could allow re-enabling it.
task: definition.md
authored_by: agent
timestamp: 2026-10-09T08:05:00+02:00
---

# W6600 amdgpu ring timeout — research

## Summary

The hang is a **kernel compute-queue (KCQ) timeout on `comp_1.2.0`** that
escalates to a hard GPU recovery. It matches an **open llama.cpp bug** where the
`--spec-type draft-mtp` speculative draft decode triggers the ring timeout on
RADV. Our exact topology (main model + KV on CPU, only the MTP draft head on the
GPU) has no direct report, but the trigger — the extra draft-context decode after
each target ubatch — is independent of where the target runs.

The kernel recovers the *device*, but the guilty context's GPU state is dropped.
RADV has no device-loss recovery: the first `-ETIME` submit latches
`VK_ERROR_DEVICE_LOST`, so llama-server must restart.

**Recommendation: keep the GPU draft head disabled.** The ~18% decode gain does
not justify a hang that kills the server at ~40K context. The mitigations below
are worth a controlled test later, not a production default.

## What `comp_1.2.0` is

`comp_<me>.<pipe>.<queue>` is the GFX10 compute-ring name. `comp_1.2.0` = MEC0
(`me = mec + 1`), pipe 2, queue 0 — a kernel compute queue, not the graphics ring
and not a userspace/HSA queue. Navi 23 is `CHIP_DIMGREY_CAVEFISH`, GFX10.3, with
4 pipes × 4 queues on MEC0.
Source: `drivers/gpu/drm/amd/amdgpu/gfx_v10_0.c` (`gfx_v10_0_compute_ring_init`,
`reset compute queue (1:2:0)`).

## The matching upstream bug (most likely root cause)

- **llama.cpp #27306** — `--spec-type draft-mtp` dies with `ring comp_1.2.0`
  timeout + `ErrorDeviceLost` on RADV at tens of thousands of tokens. The report
  isolates the extra `llama_decode(ctx_dft)` that `impl_draft_mtp::process` runs
  after **every** target ubatch; turning MTP off survives past 125k tokens.
  <https://github.com/ggml-org/llama.cpp/issues/27306>
- **llama.cpp #27076** — RX 6900 XT (RDNA2), Qwen3.8-27B + `draft-mtp`, ctx
  150016: the same `device lost on Vulkan0` / `ErrorDeviceLost`. Open.
  <https://github.com/ggml-org/llama.cpp/issues/27076>
- **llama.cpp #30010** — RX 7900 XTX (RDNA3), `draft-mtp`, dies at ~70% of a
  104k context (checkpoint path). Open.
  <https://github.com/ggml-org/llama.cpp/issues/30010>
- **llama.cpp #29352** — AMD discrete on Vulkan lost the device with 4 server
  slots; `--parallel 1` fixed it. Relevant because brys runs `parallel = 4`.
- **llama.cpp #24872** (merged) — added `GGML_VK_MAX_NODES_PER_SUBMIT`
  specifically to avoid amdgpu ring-timeout device loss. This is the main lever.
- **llama.cpp #27183** (open, draft) — a lost device escapes as `std::terminate`
  / empty stream instead of a clean error. This is why OpenCode sees an empty
  answer instead of an error.

No report was found for the exact "main on CPU, draft head on GPU" split, so the
link is by mechanism, not confirmed.

## Kernel side

- **"device wedged, but recovered through reset"** means the per-queue reset
  succeeded (`drm_dev_wedged_event(..., DRM_WEDGE_RECOVERY_NONE)`), but the KCQ
  reset marks the timed-out fence `-ETIME` and every other unprocessed fence from
  that context `-ECANCELED`; the owning context is flagged *guilty* and later
  submits return `-ECANCELED`. See `amdgpu_job.c`, `gfx_v10_0.c`
  (`gfx_v10_0_reset_kcq`), `amdgpu_fence.c`, `amdgpu_cs.c`.
- RADV maps `-ECANCELED` / `-ENODATA` / `-ETIME` to `VK_ERROR_DEVICE_LOST` and
  never retries (`radv_amdgpu_cs.c`, `radv_queue.c`). So a queue reset always
  kills the llama.cpp process's GPU context.
- On GFX10.3 there is no `SQ_CMD` to kill a stalled compute wave, so a
  compute-ring queue reset can fail and escalate to a MODE1/MODE2 full reset
  (drm/amd #5476). A full reset loses VRAM and every context.
- Kernel 6.18.50 already contains the current gfx10 KCQ-reset fixes
  (`14b2d71a9a24`, `a4b2ba8f631d`, `f410731d5cdd`, `75ebd4244170`). No 6.18.y
  commit fixes this exact signature.
- Reports of a Navi 23 / RDNA2 reset regression in the 6.16–6.18 range exist:
  drm/amd #4613 (Navi 23, kernels > 6.15.7) and #5166 (Navi 23, SMU
  driver/firmware interface mismatch). These are hypotheses for our hang; neither
  is confirmed as the cause.

Relevant module parameters (`drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c`):

| param | effect | relevance |
|---|---|---|
| `amdgpu.queue_preemption_timeout_ms` | queue preemption timeout (default 9000) | the #27306 workaround sets `60000` |
| `amdgpu.gpu_recovery` | `0` disables all resets (job stalls, scheduler suspends) | preserve state for a dump; not a fix |
| `amdgpu.debug_mask` | `BIT(6)` disables ring reset, `BIT(2)` disables soft recovery | force a full reset for diagnosis |
| `amdgpu.noretry` | disables XNACK retry faults | **not** defaulted on for gfx10.3 (only gfx10.1.x) |
| `amdgpu.lockup_timeout` | `[GFX,Compute,SDMA,Video]` timeouts | detection latency only |
| `amdgpu.num_kcq` | kernel compute queues (default 8) | queue-budget pressure, not a single-process issue |
| `amdgpu.ppfeaturemask=0xfffd3fff` | disables GFXOFF | credible mitigation for a GFXOFF/TLB ring-timeout race (drm/amd #5249) |

## Mesa / radv side

- Mesa 26.2.2 is current and stable. The 26.3 dev branch introduced new compute
  regressions (Mesa #16493, #16488) — avoid mesa-git.
- No 26.2.2-specific regression explains the hang; the kernel-side evidence is
  stronger.
- Mesa #16352 — RADV compute `DeviceLost` on long-context llama.cpp; the report
  workaround is `RADV_DEBUG=syncshaders`.
- Mesa #16158 — disabling the compute queue (`RADV_QUEUE_DISABLE=compute`)
  removed a hang; not usable for llama.cpp (it needs the compute queue).
- Diagnostics: `RADV_DEBUG=hang` dumps to `$HOME/radv_dumps_*`;
  `MESA_VK_ABORT_ON_DEVICE_LOSS=1` aborts on loss for a clean repro.
- Navi 23 firmware (`dimgrey_cavefish_*`) is updated in linux-firmware; the RLC
  blob is stale (2022). drm/amd #5166 ties a Navi 23 hang to an SMU
  driver/firmware interface mismatch. Weak evidence for a compute-specific bug.

## Mitigation catalogue (for a future test)

llama.cpp (env vars; `ggml/src/ggml-vulkan/ggml-vulkan.cpp`):

- `GGML_VK_MAX_NODES_PER_SUBMIT=1` (or 8–32) — the primary anti-timeout lever
  (#24872).
- `GGML_VK_SERIALIZE_SUBMISSIONS=1`, `GGML_VK_DISABLE_ASYNC=1`.
- `GGML_VK_DISABLE_FUSION=1`, `GGML_VK_DISABLE_GRAPH_OPTIMIZE=1`.
- Smaller `-b`/`-ub` (e.g. `-ub 256 -b 512`) — the known timeout lever in
  #27306 / #20515.
- `--spec-draft-type-k/-v f16`; `--load-mode mmap` (avoid GTT over-commit,
  #27360); `--no-kv-offload`, `--no-op-offload`.
- `--parallel 1` for a test (brys runs `parallel 4`).

Mesa: `RADV_DEBUG=syncshaders`, `RADV_DEBUG=hang` (diagnostics).

Kernel: `amdgpu.queue_preemption_timeout_ms=60000`; consider
`amdgpu.ppfeaturemask=0xfffd3fff` (GFXOFF off).

Upstream: llama.cpp master after b11429 has PR #30107 (Oct 8) which touches the
MTP draft-context sampler path. It is not a guaranteed fix for a ring timeout.

## Recommendation

Keep the GPU draft head disabled (`qwenVulkan = false`, the state since
2026-10-09). The root cause matches an **open** upstream bug (#27306) and the
mitigations are untested and cost decode speed. Re-enable only after a controlled
test shows the hang gone.

## Deferred test plan

Do this only when brys can be taken out of service (the test can wedge the GPU):

1. Boot `llm-qwen` with the GPU draft head, but run a **manual** `llama-server`
   (not the system service) so the service stays up.
2. Set `GGML_VK_MAX_NODES_PER_SUBMIT=1`, `GGML_VK_SERIALIZE_SUBMISSIONS=1`,
   `GGML_VK_DISABLE_ASYNC=1`, `RADV_DEBUG=hang`, and a small `-ub`.
3. Drive a request past 40K tokens of context and watch
   `journalctl -u llama-cpp` for `device lost` / `comp_1.2.0`.
4. If it survives, bisect the mitigations and record the minimum set. If it
   hangs, capture the `radv_dumps_*` and file a llama.cpp issue linking #27306.

## Sources

- llama.cpp #27306, #27076, #30010, #29352, #24872, #27183, #28808, #27360,
  #30107.
- Mesa #16352, #16158, #16121, #16076, #16403, #16493, #16488, #15532.
- drm/amd #4613, #5166, #5249, #5476, #5146, #5889.
- Kernel: `gfx_v10_0.c`, `amdgpu_job.c`, `amdgpu_fence.c`, `amdgpu_cs.c`,
  `amdgpu_drv.c`, `drm_drv.c`; commits `14b2d71a9a24`, `a4b2ba8f631d`,
  `f410731d5cdd`, `75ebd4244170`.
- amd-gfx Dec 2025: "[bug 6.18] Failures and Resets on GFX1037".
