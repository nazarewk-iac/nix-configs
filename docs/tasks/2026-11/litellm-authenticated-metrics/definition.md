---
type: Task
description: Put the LiteLLM gateway's Prometheus /metrics behind authentication (it is currently an unauthenticated public route on the litellm.etra subdomain), and have the scrape authenticate, so model names / latency are not readable by any nb-priv client.
status: open
authored_by: agent
timestamp: 2026-11-08T18:20:00+01:00
---

# Authenticated metrics for the LiteLLM gateway

## Context

In `hosts/etra/litellm.nix`, `litellm_settings.require_auth_for_metrics_endpoint
= false` (and `general_settings.public_routes = [ "/metrics" ]`) make `/metrics`
unauthenticated. Caddy exposes the gateway at `https://litellm.etra.priv…/metrics`
on the `nb-priv` mesh, so **any peer on the mesh can read** the counters/latency
(they carry no secrets, but they leak model names, usage shape, and latency).

Meanwhile the confined Prometheus (`kdn.prometheus-container`) scrapes that
endpoint. The `prometheus-container` aspect already supports scrape
`authorizationFile` (a bearer token file) — so both sides can authenticate
without code.

## Proposed approach (to confirm in research)

1. **Turn auth back on**: `require_auth_for_metrics_endpoint = true`; drop
   `/metrics` from `public_routes`. `/metrics` then needs a valid key (master, or
   a dedicated metrics key via custom_auth).
2. **Let the scrape authenticate**: give the Prometheus scrape job an
   `authorizationFile` pointing at a bearer token (a dedicated non-admin key, or
   the master key), read from a sops file mounted into the prometheus container.
   The aspect's existing `authorization` (`credentials_file`) wiring is the hook.
3. **Verify** the Prometheus target stays `up` (it now authenticates) and an
   unauthenticated `curl https://litellm.etra…/metrics` returns 401/403.

## Research questions

- Does LiteLLM's `/metrics` accept the same bearer auth as `/v1` under
  `require_auth_for_metrics_endpoint = true` (which key roles are allowed)?
- Is a dedicated metrics key (custom_auth, no model access) preferable to
  reusing master? Prefer a scoped, non-admin metrics key.
- Does the `prometheus-container` aspect surface `authorizationFile` on the
  gateway scrape target, and can it read a sops-mounted token inside the guest
  (owner/permissions)?
- Any metric that carries sensitive data (client IPs, keys) to scrub regardless.

## Acceptance criteria

- `GET https://litellm.etra…/metrics` without auth → 401/403.
- Prometheus `up{job="litellm"}` = 1 (scrape authenticates).
- The metrics key is non-admin and scoped to no inference models.

## Related

- [../litellm-gateway/definition.md](../litellm-gateway/definition.md),
  [../litellm-client-keys-and-requesty/definition.md](../litellm-client-keys-and-requesty/definition.md)
  (the custom_auth key model this reuses).
- `modules/den/aspects/prometheus-container.nix` (`authorizationFile`).
