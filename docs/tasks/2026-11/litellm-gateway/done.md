---
type: Solution
description: Deploy LiteLLM on etra as the single fleet entrypoint — a DB-less NixOS container with build-time config, brys + oams backends, host-level health routing, and Prometheus metrics.
task: definition.md
authored_by: agent
timestamp: 2026-11-14T05:09:42+01:00
---

# LiteLLM gateway on etra — done

## Solution

LiteLLM runs as a NixOS container on etra, the single OpenAI-compatible entrypoint for the local
fleet. No database, no Web UI: a single master key plus model-scoped client keys, and the config is
generated at build time from `data/llm.nix` (one deployment per (host, alias)), so there is no flat
file to keep in sync.

| Where | What |
| --- | --- |
| `hosts/etra/litellm.nix` | the container (private veth, socat ingress `:4000`), the config generated from `data/llm.nix` (local deployments + explicit `requesty/*`), the clamped router timeouts, the brys egress relay, and the Requesty egress path |
| `modules/den/aspects/prometheus-container.nix` | the etra Prometheus that scrapes the gateway's unauthenticated `/metrics` |

Decisions that held:
- **DB-less** over Postgres. `general_settings` reads `os.environ/...` keys; the no-DB premise is
  preserved (no prisma engine).
- **Health via a host-level `/health` probe, not per-model.** The gateway relies on
  `probe.host_probe` (introduced by the sibling task `litellm-health-check-storm`) rather than the
  original 30 s background model probes. `probe.host_probe` is an
  `async_filter_deployments` callback, so a down host is dropped before any connect regardless of
  `enable_health_check_routing`.
- **Requesty egress** through a `tinyproxy` CONNECT (`HTTPS_PROXY`), not the raw socat relay — the
  relay keeps the relay's `Host` header and Requesty 404s; the proxy preserves SNI/Host.
- **Timeouts clamped** (`request_timeout` / `stream_timeout`) so a dead backend returns a fast error
  instead of a 100-minute hang.

## Verification

Observed on the live host (sessions of 2026-11-05 and 2026-11-13):

- etra `switch` (2026-11-13 20:43) — `GET /v1/models` returns the union of backends (31 model groups
  after the frontier retirement: 26 local + 4 `requesty/*` + 1 `chat-fast`).
- A real chat completion through the gateway reaches brys, and a `requesty/*` model serves.
- `/metrics` exposes `litellm_deployment_state` and the etra Prometheus target is `up`.
- A stopped backend is filtered by `probe.host_probe` and fails over without a connect timeout.

Re-check:

```bash
# master key, or a model-scoped client key from /run/configs/litellm-keys
curl -sS -H "Authorization: Bearer <master-key>" http://<etra>:4000/v1/models
```

## Follow-up notes

- **LAN reachability**: the socat ingress binds `0.0.0.0` but etra's firewall trusts only
  `nb-priv`. Opening `4000` on the plain LAN interface for non-NetBird clients is a deliberate
  tightening, not a core deliverable.
- **oams as a second backend** is now live (registered in the fleet, 5 oams deployments) — folded in
  from `oams-llm-host`.
