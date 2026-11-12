---
type: Solution
description: Disable the LiteLLM per-model health probes and move the signal to a host-level llama-swap `GET /health` probe, so a health check returns without loading a model.
task: definition.md
authored_by: agent
timestamp: 2026-11-12T14:00:00+01:00
---

# A health check that never loads a model

## Changes

| File | Change |
| --- | --- |
| `hosts/etra/litellm.nix` | `general_settings.background_health_checks = false` and `enable_health_check_routing = false`. The `health_check_interval` and `health_check_staleness_threshold` settings are gone. |
| `hosts/etra/litellm.nix` | Remove `health_check_timeout` and `health_check_max_tokens` from every deployment and pool entry. They configured the probes that no longer run. |
| `hosts/etra/litellm.nix` | `litellm-host-probe` now runs `curl -fsS -m 3 http://<host>:39704/health` and accepts only the body `OK`, instead of a bare TCP connect. `pkgs.curl` is added to the unit `path`. |

## Why `/health` and not `/v1/models`

llama-swap answers `GET /health` with `200 OK` and the body `OK` without touching a model (measured
on brys and oams). `/v1/models` also avoids a load, but it serialises a large catalog and it
describes the configured set, not liveness. `/health` is the smaller, direct signal.

The probe still connects to the host's NetBird address directly, not through the etra socat relay,
so a blackhole is a real 3 s timeout instead of an accepted-but-hung relay connect.

## Why the host filter still works

`probe.host_probe` is a `CustomLogger.async_filter_deployments` callback. LiteLLM calls every
registered `async_filter_deployments` for each request (`router.py`, `async_callback_filter_deployments`)
regardless of `enable_health_check_routing`, which only controls the separate health-state cache
filter. So a down host is still dropped before any connect with health-check routing off.

## Verification

- Evaluate `etra` and inspect the generated config:

  ```bash
  nix eval --raw .#nixosConfigurations.etra.config.system.build.toplevel.drvPath
  nix eval --json .#nixosConfigurations.etra.config.containers.litellm...   # or read the store file
  ```

- Restart the gateway container on etra, then watch the backends:

  ```bash
  sudo journalctl -M litellm --since '2 min ago' | grep 'chat/completions'
  ssh brys 'sudo journalctl -u llama-swap --since "5 min ago" -o cat | grep "Request " | grep -c AsyncOpenAI'
  ```

  Expected: no `AsyncOpenAI` completions, no new `Executing start command` while the fleet is idle.

- The probe file must stay healthy:

  ```bash
  cat /var/lib/litellm/host-health.json   # {"brys": true, "oams": true}
  ```

- A real completion through the gateway must still work, and a stopped backend must still be
  filtered (stop llama-swap on oams, wait one probe interval, then send a request for an
  oams-only model; it must fail over to brys without a connect timeout).
