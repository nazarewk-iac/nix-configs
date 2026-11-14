---
type: Status
description: oams is a live second llama-swap host serving its small GPU models; the serving toggle has not been exercised end-to-end and the GPU-stability watch is open.
task: definition.md
authored_by: agent
timestamp: 2026-11-14T05:09:42+01:00
---

## Done so far

- **Datasets** `hosts/oams/disko.nix` — `/var/lib/kdn/llms/{models,sessions}` (and
  `/var/lib/llm-stats`), with `systemd.tmpfiles` for the modes disko cannot express.
- **Host wiring** `hosts/oams/llm.nix` — projects `servers.oams`, GPU pinned to the 6800M
  (`1002:73df!`), llama-swap enabled via the `llm` aspect.
- **Serving toggle** `oams-llm on|off|auto|status` + a 30 s timer — `auto` serves only on AC and
  with no `app-steam_app_*` scope; an off auto-trip stops and masks llama-swap.
- **Models served** — the small fast set (gemma-4-e4b, granite-4.2-3b, qwen3.5-0.8b, qwen3.5-2b);
  qwen3.5-35b-a3b dropped (not frontier-quality, not fast enough).
- **Live** — oams was switched (2026-11-13) and llama-swap is serving; oams is registered in
  `data/llm.nix` and in the LiteLLM fleet (5 oams deployments).
- **Sops incident fixed** — oams's SSH host key (age via `ssh-to-age`) is a recipient in the `llms`
  rule; oams decrypts unattended with no touch.

## Remaining

- **Serving toggle not exercised end-to-end**: the `oams-llm` CLI and timer are deployed, but the
  AC-unplug -> serving-off and gaming-scope -> serving-off paths have not been observed on a live
  cycle (a reboot plus an unplug, or a Steam launch).
- **GPU stability watch**: a dense 9 B fully on the 12 GB card faults the GPU; only the
  MoE-with-`n-cpu-moe` path is proven stable. Watch if more models are added.

## Next directions

1. Reboot oams, then exercise the toggle: `oams-llm status` on AC, unplug AC and confirm llama-swap
   stops and masks, and confirm a Steam scope forces it off.
2. Record the observation; if the dense 9 B is to be re-added, verify the `n-cpu-moe` path first.
3. When both are green, flip to `done` with a `done.md` and delete this `status.md`.
