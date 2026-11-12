---
type: Task
description: Identify every client and poller that reaches the llama-swap servers on brys and oams, and stop the LiteLLM background health checks from forcing a model swap every 30 seconds.
status: in-progress
authored_by: agent
timestamp: 2026-11-12T13:20:00+01:00
---

# What reaches the local model servers on brys and oams

## Context

The owner asked what is hitting the local agents on `brys` and `oams`, possibly through `etra`.
The answer must name every path and its volume, because one of them changes the resident model.

The serving hosts bind llama-swap to `127.0.0.1:39700`. Two relays expose it:

- `llm-netbird-relay-swap` listens on `0.0.0.0:39704` and the firewall opens that port only on
  `nb-priv`. It exists for the LiteLLM gateway on etra.
- `llm-metrics-relay-swap` (brys only) listens on `10.233.90.1:39700` for the Prometheus container.

## Findings

Measured 2026-11-12 13:20-13:45. Full evidence in [research.md](research.md).

| Source | Destination | Volume | Cost |
| --- | --- | --- | --- |
| LiteLLM background health checks on etra | `brys:39704` and `oams:39704` | 592 completions / 10 min on brys, 80 / 10 min on oams | **High**: each probe is a real chat completion for a different model, so llama-swap (`--models-max 1`) evicts the resident model to answer it. A probe round queues every model at once. |
| `llm-stats.service` on each host | `127.0.0.1:39700` | 2 GETs every 2 s (86 400 requests/day) | Low: `/api/metrics/activity` and `/v1/models` only; no model load. |
| Prometheus container on brys | `10.233.90.1:39700` (relay) | `/metrics` every 15 s | Low. |
| LiteLLM model discovery | both hosts | `/v1/models` about every 60 s | Low. |
| Real clients on oams (opencode 2.2.5, pi 1.4/1.5, curl) | `litellm.etra...:443` (Caddy) -> gateway -> hosts | 52 chat completions, 1290 `/v1/models` polls in the Caddy log | The intended traffic. |

Every established connection to `:39704` on both hosts comes from `100.79.187.16`, the etra
NetBird address. Nothing else reaches the relays.

## Root cause of the load

`hosts/etra/litellm.nix` sets `general_settings.background_health_checks = true` and
`health_check_interval = 30`. The gateway has 37 deployments on brys, 5 on oams and 3 on Requesty,
and LiteLLM probes **each deployment** with a real completion (`health_check_max_tokens = 1`). That
is about 1.2 probes/s on brys and 0.17/s on oams. With `models-max 1`, a probe for a model that is
not resident forces a swap. The matrix engine also queues every model in the same round, so one
health-check tick becomes a load/unload storm.

The design doc already measured that health-check routing does not protect against a blackholed
host in this deployment, and that the host-side probe (`litellm-host-probe` +
`probe.host_probe`) is the mechanism that does. The per-model probes therefore buy little and cost
a model swap every 30 s.

## Proposed approach

1. Set `general_settings.background_health_checks = false` and
   `enable_health_check_routing = false` in `hosts/etra/litellm.nix`. Keep `num_retries`,
   `cooldown_time` and `allowed_fails`, so a real failed request still cools a deployment, and keep
   the host probe as the pre-selection filter.
2. Do not use `background_health_check_model_groups` as the fix: a single scoped group still probes
   one model per host every 30 s, which still evicts the resident model.
3. Keep `llm-stats` and the Prometheus scrape; they are cheap read-only polls.

## Acceptance

- The `AsyncOpenAI/Python` completions in the brys and oams llama-swap journal drop to zero.
- A model stays resident across a quiet period (no health-check-driven `Executing start command`).
- A stopped host still fails over through `probe.host_probe`, and a stopped model still cools
  after a real failure.

## Solution

Not applied yet. The change is one `general_settings` edit; it needs the gateway restarted and the
two acceptance observations above.
