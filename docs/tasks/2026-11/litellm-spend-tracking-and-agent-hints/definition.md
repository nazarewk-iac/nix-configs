---
type: Task
description: Record per-request spend and prefill/decode rates in the LiteLLM gateway, expose truthful cost headers, and give agents a cache-safe budget hint — DB-less first, then on top of the adeci/litellm-nix fork.
status: open
authored_by: agent
timestamp: 2026-11-13T12:11:00+01:00
---

# Spend tracking, budget hints, and prefill metrics in the LiteLLM gateway

## Context

- The gateway is `hosts/etra/litellm.nix`. It runs **DB-less** (`DATABASE_URL` unset), so it has
  no virtual keys, no budgets, no spend logs, no `/key/info` and no admin UI. Auth is the
  `custom_auth` hook `hosts/etra/litellm_auth.py` over a sops key file; model scope is enforced by
  the `pre_call` hook `hosts/etra/litellm_enforce.py`.
- Requesty is **prepaid**. A frontier agent loop can burn $100 in a day. The burn is
  **input tokens × cache misses**, not output: a 30-step turn re-sends ~60k tokens per step.
  At DS4.1 prices ($0.50/M in, $0.05/M cached) one task costs ~$0.99 uncached and ~$0.26 cached.
- The sibling task [litellm-postgres-via-litellm-nix](../litellm-postgres-via-litellm-nix/definition.md)
  forks [adeci/litellm-nix](https://github.com/adeci/litellm-nix/tree/main) to get Prisma 6,
  migrations and the UI. That unblocks the DB path. This task covers tracking and the
  agent-facing feedback, and must work **before and after** that fork lands.

## Goal

1. Every request carries a truthful cost — visible to the client, to Prometheus, and as a
   per-key rolling total.
2. An agent can learn its own budget position and self-throttle, **without destroying the prompt
   cache**.
3. Prefill and decode rates are recorded per request for local models, and TTFT-derived prefill
   for remote ones.

## Verified findings (litellm 1.85.0)

Source: `/nix/store/i2wyv73sq1897a1lxkj0wfp3g2faa5rj-litellm-1.85.0`.

### Cost

- `response._hidden_params["response_cost"]` holds the computed cost of one request.
- `ProxyBaseLLMRequestProcessing.get_custom_headers` emits on every response:
  `x-litellm-response-cost`, `x-litellm-key-spend`, `x-litellm-key-max-budget`,
  `x-litellm-key-rpm-limit`, `x-litellm-key-tpm-limit`, `x-litellm-call-id`, plus timing headers.
- Those headers are **not** gated by `litellm_settings.return_response_headers`; that flag only
  exposes *provider* headers such as `x-remaining-requests`.
- `get_custom_headers` reads `user_api_key_dict.spend` and `.max_budget`. `custom_auth` can
  populate both, so `x-litellm-key-spend` and `x-litellm-key-max-budget` become truthful
  **with no database**.
- **Streaming caveat:** headers are sent before the body, so `x-litellm-response-cost` is empty on
  streamed calls. Agents stream. The cost must reach them another way (final chunk or request hint).
- Prometheus (already scraped) exports `litellm_spend_metric`, `litellm_total_tokens_metric`,
  `litellm_input_tokens_metric`, `litellm_output_tokens_metric`, `litellm_cached_tokens_metric`
  and `litellm_llm_api_time_to_first_token_metric`.
- DB-less gaps: `/spend/logs`, `/key/info`, `/global/spend/report`, virtual-key budgets, admin UI.

### Prefill and decode

- `llama-server` returns `timings` in the response body: `prompt_n`, `prompt_ms`,
  `prompt_per_second`, `predicted_n`, `predicted_ms`, `predicted_per_second`, `cache_n`.
- litellm has **no llama.cpp provider** and no `timings` parsing. Only the fal.ai image transform
  stores `_hidden_params["timings"]`, so the typed response drops it.
- The raw body is **not lost**: `logging.post_call(original_response=...)` stores it at
  `model_call_details["original_response"]` (a JSON string when the body was a dict). A
  `CustomLogger` reads it in `async_logging_hook(kwargs, result, call_type)`.
- Streaming: the final SSE chunk carries `timings`. Capture it in
  `async_post_call_streaming_iterator_hook`.
- Backend-agnostic fallback: `litellm_llm_api_time_to_first_token_metric` gives TTFT, and
  `prompt_tokens / TTFT` approximates the prefill rate. `LITELLM_DETAILED_TIMING` adds
  `x-litellm-timing-llm-api-ms` and friends.
- For local models the number already exists outside litellm: llama-swap's
  `GET /api/metrics/activity` returns `tokens.prompt_per_second` and `tokens.tokens_per_second`
  per request. Do not rebuild that in litellm for brys/oams; join on `x-litellm-call-id` or the
  request timestamp.

### The cache trap

A budget hint that changes on every request breaks the prompt prefix and the cache never hits.
That is a **10× cost increase** — the opposite of the goal. Any in-request hint must change only
at thresholds (50/80/95 %), once per session, or live after the cached prefix.

## Approach

### Phase 1 — no database (works today)

1. **Redis counters.** `INCRBYFLOAT spend:{key}:{YYYY-MM}`, `:{YYYY-MM-DD}`, `:{YYYY-MM-DD-HH}`
   with `EXPIRE`. Redis is already there (`coordination_redis`, `10.233.100.1:6379`).
2. **Truthful headers.** Populate `spend=` and `max_budget=` in `litellm_auth.py` from Redis and
   the keys file, so the built-in `x-litellm-key-*` headers carry real numbers.
3. **Hard throttle.** A `pre_call` reject (HTTP 429) when the hour/day/month cap is exceeded.
   Estimate with `prompt_tokens × in_price + max_tokens × out_price`. This is the actual control;
   never rely on the model obeying a hint.
4. **Threshold-only hint.** When a counter crosses 50/80/95 %, append one system message
   ("budget 82 % used; be concise, do not re-read files"). Emit it once per threshold, not per step.
5. **Prometheus.** Panel for spend/day per key and model; alert on a daily spike.

### Phase 2 — after the fork lands

6. Move to **DB virtual keys** with `max_budget` + `budget_duration` per client, and keep the
   Redis counters as the sub-monthly (hour/day) throttle the DB does not give.
7. Enable `/spend/logs`, `/key/info`, and the admin UI. Reconcile Redis totals with the DB on
   startup so the two do not drift.

### Phase 3 — metrics

8. A `Meter` logger that parses `model_call_details["original_response"]` for `timings`, records
   `prefill_tps`/`decode_tps` per model, and exposes them as Prometheus gauges/histograms.
9. For streaming, capture `timings` from the final chunk in the streaming iterator hook.
10. For remote providers, derive prefill from TTFT and label it as an estimate.

## Acceptance test

1. A non-streaming request returns a non-empty `x-litellm-response-cost`, and
   `x-litellm-key-spend` equals the Redis counter for that key.
2. A streamed request records the same cost in Prometheus (headers alone are not enough).
3. Crossing a threshold injects exactly one hint; a second step in the same session does not
   change the prompt prefix (verify a cache hit on the next request).
4. Exceeding the hourly cap returns 429 before the upstream call.
5. A local `llama-server` request yields `prefill_tps` and `decode_tps` matching
   `/api/metrics/activity` for the same request.
6. After Phase 2: `/spend/logs` returns rows, and a virtual key with `max_budget` blocks at the cap.

## Risks and open questions

- **Do not trust the model with its own budget.** The hint is advisory; small models ignore it.
  The 429 is the enforcement.
- Cache damage from the hint is the main regression risk. Prefer a client-side hint (opencode/pi
  already track token usage) when it avoids touching the prompt.
- `custom_auth` runs on every request; a Redis round-trip per request must be measured, not assumed
  free. Cache the value in-process with a short TTL if needed.
- Reconcile Redis and Postgres totals after the fork, or the numbers will disagree.
- `timings` is llama.cpp-specific. Do not write it into a shared schema as if it were universal;
  mark the source.

## Related docs

- [litellm-postgres-via-litellm-nix](../litellm-postgres-via-litellm-nix/definition.md) — the fork
  that unblocks the DB path.
- [litellm-client-keys-and-requesty](../litellm-client-keys-and-requesty/definition.md) — the
  DB-less key and scope work this builds on.
- `hosts/etra/litellm.nix`, `hosts/etra/litellm_auth.py`, `hosts/etra/litellm_enforce.py`.
- [docs/local-llms.md](../../../local-llms.md) — brys metrics API and measured throughput.
