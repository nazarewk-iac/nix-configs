# LiteLLM routing, timeouts and health — design notes (2026-11-07)

Answers to the open questions for the gateway (`docs/tasks/2026-11/litellm-gateway/`).
Research is source-verified against `BerriAI/litellm` main + docs.litellm.ai.

## #3 Routing: preferences, parallelism, pinning, historical speed, warm models

**Can I prioritise oams over brys for specific models?**
- Yes, **per model group**, with `litellm_params.weight` under `routing_strategy:
  simple-shuffle` (the key is read from `litellm_params`, NOT `model_info`). Give the
  oams deployment a higher weight for the aliases where it is faster. The group is
  the alias, so weighting is per-alias automatically.
- To pin a **specific host** for a specific alias, declare a distinct `model_name`
  per host (`tiny-dumb-fast-oams`, `tiny-dumb-fast-brys`). Declaring the same
  underlying model under several `model_name`s is fully supported. The client then
  chooses `...-oams` / `...-brys` / plain (auto). This is the robust pin; a
  `model: <model_info.id>` request also pins one deployment but is doc-thin.

**Does it track parallelism?** Yes — `routing_strategy: least-busy` uses a live
per-deployment in-flight counter (+ short pick reservations). It counts *requests*,
not GPU slots/KV; llama-swap's real slot state is invisible to it.

**Does load balancing track historical speed / latency?** Yes, with
`routing_strategy: latency-based-routing`. It keeps the last `max_latency_list_size`
(default 10) samples per deployment, averaged over `routing_strategy_args.ttl`
(default 3600 s), keyed **per model group**. For streaming it routes on
**time-to-first-token**, else on `response_seconds / completion_tokens`. In-memory
per worker unless Redis (`DATABASE_URL`/`REDIS_HOST`); we run DB-less, so it is
per-worker and reset on restart. `lowest_latency_buffer` widens the candidate band
so the single fastest host is not always hammered.

**Can it prefer already-loaded models?** No first-class feature (NOT FOUND). LiteLLM
does not know llama-swap's loaded/unloaded state. The clean hook is
`async_filter_deployments` (CustomLogger/plugin): query each backend's llama-swap
`/v1/models` `status` and drop cold deployments before the strategy runs. Not
implemented here — noted as an option.

Recommendation for this fleet: `simple-shuffle` + weights per alias (oams heavier
for the small fast models), keep `enable_weighted_failover: true`. Move to
`latency-based-routing` only if the in-memory-only tracking (no Redis) is acceptable.

## #1 Health checks / blackholed backend (VERIFIED)

`enable_health_check_routing: true` + `background_health_checks: true` makes the
provider a **pre-selection candidate filter**: a deployment that failed its last
probe is dropped **before any connect**, so a client request never pays the connect
timeout. The probe is a real short completion (`max_tokens` 16, timeout
`health_check_timeout`, default 60 s). We set `health_check_interval: 30`,
`health_check_staleness_threshold: 120` (must track the interval; the default 600 s
is fixed at 2×300 and would keep a dead host "unhealthy" far too long).
Caveats: if the blackholed host is the ONLY deployment in a group, `KeepAll` bypasses
the filter and the request still hangs — the shared aliases always have a brys
sibling, so this does not bite. `health_check_ignore_transient_errors` must stay off
so a probe timeout counts as failure.

## #6 Timeouts and long TTFT (VERIFIED)

- `router_settings.timeout` / `litellm_settings.request_timeout` are **per-read
  (idle)**, not wall-clock total, for httpx. A 30-min prefill is only killed by the
  first-token wait.
- For a **streaming** response, `stream_timeout` governs the wait for the FIRST chunk
  and each inter-chunk gap; steady streaming after token 1 is unaffected. So set
  `stream_timeout` ≥ max TTFT (we used 1800 s) and `timeout`/`request_timeout` large
  (3600 s). There is no wall-clock total wrapper.
- **`timeout: 0` is NOT infinite** (it means immediate); `timeout: null` falls back
  to 600 s. Use a large finite value. Never rely on 0/None for infinite.
- Client SDKs add their own timeout: set `timeout=None` on the openai client for the
  slow call so the SDK never aborts before LiteLLM's long limit fires.
- The 600 s `COMPLETION_HTTP_FALLBACK_SECONDS` default is why an unconfigured
  proxy would cut a 30-min prefill — we override it.

## #4 Client registration

- **Pi**: providers `brys`, `oams`, `requesty` existed; the gateway is now a
  **`litellm`** endpoint in `data/llm.nix`, and `mkPiModelsJson` lists every served
  alias under it (a client picks an alias, the gateway picks the host).
- **OpenCode**: only `brys` (oams' devenv) existed; a **`litellm`** upstream is now
  added on oams. It reads the master key from `/run/configs/litellm/master-key`,
  which must be provisioned on the client (same secret as the gateway); this is the
  one manual step.

## #2 Prometheus

A new `prometheus-container` den aspect (extracted from brys' inline container) runs
a confined Prometheus; etra uses it to scrape the gateway. `/metrics` is exposed
without auth via `require_auth_for_metrics_endpoint: false` (public_routes alone is
overridden for `/metrics`), scraped at `/metrics/` (no 307). Verified up;
`litellm_deployment_state` alerting metric ingested (0 = healthy).
