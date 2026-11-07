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

## Blackholed-host caveat (measured 2026-11-07, IMPORTANT)

Health-check routing does **not** reliably protect against a *blackholed* host in
this deployment, for two measured reasons:

1. **The egress relay hides the blackhole.** LiteLLM probes `10.233.100.1:8444` (the
   etra-side socat relay). The relay's local accept always succeeds; only its
   *upstream* connect to the blackholed oams hangs. So the probe sits in the
   relay until its timeout, not until a fast TCP refusal.
2. **The health cycle ran at 60 s, not the 5 s `health_check_timeout`.** Logs show
   `background_health_check_cycle_duration_exceeded_interval duration_ms=60045
   interval_seconds=30`. `health_check_timeout` IS read (`health_check.py:530`) but
   the cycle still took 60 s — the probe's residual socket read is not bounded by
   that timeout, so a cycle exceeds the interval. `deployment_state` stayed 0 for the
   blackholed oams throughout, and real requests still hung ~120-200 s.

`socat connect-timeout=5` did **not** fix it (a SYN blackhole is bounded by the
kernel TCP timeout, not socat's inactivity timer).

**What actually works today:** a *stopped* host (connection refused) fails over in
~30 ms with no config help. A *blackholed* host is the hard case. Options, in order
of robustness, if this must be solved:
- Put the health check on the **host** side (probe `100.79.80.79:39704` directly
  from etra, where a blackhole is a real connect timeout) and feed the result via a
  custom `async_filter_deployments` — bypasses the relay-hides-it problem.
- Or make each backend's relay die fast on a blackhole (e.g. a connect watchdog),
  so a refused/hung upstream both surface as a fast error.
- Or accept it: the shared aliases always have a brys sibling, so a client only
  pays the hang while oams is cooling, then brys serves.

The `health_check_timeout: 5` and interval settings are kept (correct per the code
path and cheap); the limitation is documented, not claimed fixed.

## #2 measured token rates (2026-11-07)

Every served model now carries `capabilities.rates = { decode; prefill; mode; }`
in `data/llm.nix`, from the measured `docs/local-llms.md` table. The gateway turns
them into `litellm_params.tpm` (decode×60) and `model_info.tokens_per_second` /
`prefill_tokens_per_second` (visible via `/model/info`). 23 deployments carry rates
after adding flash-next (decode 2.36, prefill 30 t/s).

## #4 blackhole + long-prefill timeouts (revised)

Policy adopted: **never START a request above ~100k context** (a session may grow
past it via the disk session cache / prefix reuse), and **cap the first-token wait
at 2 h**. So per-deployment `stream_timeout = min(7200, 120 + 100k/prefill)`:
fast models ~230 s, frontier/deep ~3533 s (~59 min). This bounds both a
slow-but-alive prefill (allowed to finish within the cap) and a dead backend.

The **blackhole caveat stands** (see above): a host that is blackholed behind the
egress relay still isn't skipped cheaply by health routing. The 2 h cap limits the
damage; the robust fix (host-side probe + `async_filter_deployments`) is still the
documented path.

## Checkpoints: what they restore (answering the "arbitrary past prefixes" question)

The disk session cache (`ctx-checkpoints`, `slot-save-path`, `slot-save-sessions =
x-session-id`) does **not** give arbitrary restore of any past prefix. It saves, per
**client session id**, the KV state at a few checkpoints (recurrent-state snapshots,
`ctx-checkpoints 32`, `checkpoint-min-step`), so a request carrying the SAME
`x-session-id` resumes from that session's nearest saved state instead of
re-prefilling — and it survives a server restart. It is **not** a content-addressed
prefix cache you can point at any older prefix; it is "this conversation, resume
where it was". The llama.cpp **prompt/prefix cache** (`--cache-ram`, in memory) does
reuse any identical prompt prefix, but only while resident (evictable). So: yes to
"resume my session cheaply, across restarts", no to "restore an arbitrary older
prefix from the past".

## #3 LiteLLM database — blocker recorded

`dbEnabled` scaffolding exists (DATABASE_URL + prisma-engines paths + password) but
is off. Blocker: nixpkgs `prisma` (python 0.15.0, what litellm 1.102.1 pins) needs
an engine built at its own commit (~5.x); nixpkgs ships prisma-engines 6.19.3 and
7.10.0, neither matching, and no NixOS prebuilt exists. Routing needs no DB, so
this stays a scaffold until a matching `prisma-engines` is packaged.

## Corrected facts, verified against the installed closure (2026-11-07)

### #1 What actually needs a DB
The proxy has **44 `prisma_client is None` guards**. A DB is required for:
virtual keys (`/key/*`), users/teams (`/user/new`, `/team/new`), **budgets**
(spend counters), **spend logs** (`/spend/logs`, `disable_spend_logs` controls
it), and **config-managed models** (`store_model_in_db`, `/model/new`,
`/model/delete`). **Routing, load-balancing, health checks, cooldowns, tag
routing and the complexity router do NOT need a DB** — they are config/in-memory
(Redis only for cross-worker sharing). So a DB buys key/budget/spend accounting
and DB-stored models, none of which this fleet uses.

### #2 Does /metrics expose tok/s and prefill (TTFT) so we can tune later?
Yes — per deployment:
- `litellm_deployment_latency_per_output_token` (histogram) = seconds per output
  token, i.e. **inverse decode tok/s** per deployment.
- `litellm_llm_api_time_to_first_token_metric` (histogram) = **TTFT** per
  deployment/model, the prefill proxy.
- plus success/failure counters and `litellm_deployment_state`.
So real-world decode/prefill are observable per host+model from Prometheus, and
the measured `rates` in `data/llm.nix` can be refined from those (a periodic
export → data file is a future nicety; not automated yet).

### #3 Is config `tpm` the only source of truth, or are real measurements used?
Both, for **different** strategies:
- `simple-shuffle`: `weight`/`rpm`/`tpm` from config are **the only** input
  (static weighting).
- `usage-based-routing(-v2)`: uses **live** tpm/rpm counters (Redis) against the
  configured `tpm`/`rpm` as the **limit**.
- `latency-based-routing`: uses **measured** history — per-deployment
  `time_to_first_token_seconds` and `latency_normalized` sample lists (last 10,
  averaged over TTL) — config `tpm`/`rpm` are only ceilings. **This is the one
  that self-tunes to real speed**, in-memory per worker (Redis to share).
So config `tpm` is a ceiling/weight, not a claim the router trusts over reality
when you pick latency-based routing.

### #4 Where can `tpm` be used?
1. **Rate limiting** per deployment (usage-based-routing: refuse/queue past tpm).
2. **Weight** for `simple-shuffle` (when `weight` is unset, tpm/rpm stand in).
3. **`max_parallel_requests` derivation** (`rpm` > `tpm/1000*6` when unset).
4. As a **ceiling** for usage-based and latency-based routing.
It is NOT a throughput predictor the router uses for latency (that comes from
measurements under latency-based routing).

### #5 The real DB blocker (corrected — my earlier reason was wrong)
`prisma` 0.15.0 and `psycopg` ARE in the litellm closure — so the version is not
the problem. The actual gaps:
- **No engine binary** packaged: prisma 0.15 needs engine commit `393aa359…`
  (prisma-engines **5.17.0**); nixpkgs ships only 6.19.3 / 7.10.0, and prisma on
  `linux-nixos` has no prebuilt (the CLI hits `binaries.prisma.sh .../linux-nixos/
  ...404`).
- **No generated prisma client** and **`litellm_proxy_extras` is not installed**
  in the nixpkgs package — litellm's DB path needs `prisma generate` (schema-engine
  + node) to produce the Python client, which the package does not bake.
Therefore enabling `DATABASE_URL` fails at `prisma generate` / query-engine load,
not at a version check. Fixing it is a packaging job: ship a matching
`prisma-engines` 5.17.0 built for NixOS, bake the generated client, and add
`litellm_proxy_extras`. That is out of scope for a config change and is why the DB
stays an off-by-default scaffold. (A `prisma-engines_6` `query-engine` exists and
could be tried with `PRISMA_QUERY_ENGINE_BINARY`, but without a generated client it
is moot.)

## Q&A round 2 (verified in the installed closure, 2026-11-07)

### Q1 How do routing strategies work without a DB? Memory or Redis? Is Redis persisted?
- Routing state is **never** in the DB. The router builds `self.cache =
  DualCache(redis_cache=…, in_memory_cache=InMemoryCache())` (`router.py:904`).
  - **No Redis configured → in-memory only** (`InMemoryCache` = an in-process
    dict, no disk). State is per-worker and **lost on restart**.
  - **Redis configured → shared and durable** across workers/pods; `InMemory`
    remains the fast local tier.
- **`DiskCache` exists but is NOT used for router state.** `litellm.cache` /
  `cache_params` `type: disk` only backs **response caching**; the router's
  cooldown/usage/latency counters still use the DualCache. There is no built-in
  "persist routing state to disk without Redis".
- **Making it durable = add Redis with disk persistence.** Redis/valkey is in
  nixpkgs (valkey 9.x). Configure AOF (`appendonly yes`) or RDB snapshots so the
  data survives restart; point LiteLLM at it with `REDIS_HOST`/`REDIS_PORT`/
  `REDIS_PASSWORD` (or `REDIS_URL`), or `litellm_settings.cache_params`
  (`type: redis`, host/port/password/db, `default_redis_ttl`). Without this the
  latency/usage history resets on every restart (acceptable today: it rebuilds in
  a few requests; a deliberate choice, not a requirement).
- **Not from Prometheus.** Metrics are export-only; the router never reads them
  back. (So "adjust config after real usage" is a human/cron step over
  `/metrics`, not something the router does itself.)

### Q2 Is prefill tok/s available, or only TTFT? Is TTFT biased for follow-ups?
- There is **no direct prefill-tokens/sec metric**. Available per deployment:
  `litellm_llm_api_time_to_first_token_metric` (TTFT), and input-token counters
  (`litellm_input_tokens_metric`, `litellm_cached_tokens_metric`,
  `litellm_provider_cache_read_input_tokens_metric`).
- **Prefill rate must be derived**: `newly_prefilled_tokens / TTFT`. You get the
  honest denominator only by subtracting cached tokens
  (`prompt_tokens − cached_tokens`), which the metrics expose.
- **Yes, raw TTFT is biased for follow-ups**: a follow-up whose prefix is already
  cached has a tiny TTFT for a large `prompt_tokens`, inflating an apparent
  prefill rate. Correct: use `(prompt − cached)/TTFT` and ignore requests with a
  high cache-hit ratio. That double-count is exactly why the derived-from-single-
  request numbers in `data/llm.nix` are a starting estimate, not ground truth.

### Q3 Cold start / which models are loaded on the target?
- **No cold-start or loaded-state awareness in routing.** No `cold_start` /
  `load_seconds` / `is_loaded` signal exists in the router strategies (grep: none).
  LiteLLM cannot see llama-swap's loaded/evicted state.
- The only hooks to add it: `async_filter_deployments` (per-request plugin) or a
  custom `get_available_deployment`, both of which can query each backend's
  llama-swap `/v1/models` `status`. Same mechanism the host-side healthcheck would
  use (Q4). Not implemented.

### Q4 Host-side healthcheck — did I implement it? Why not?
- **No.** Only LiteLLM's built-in `background_health_checks` +
  `enable_health_check_routing` are enabled; measured (see the blackhole section)
  they do not skip a blackholed host behind the etra relay, because the relay
  accepts the TCP connect and the probe sits on the relay's hung upstream.
- The doc's recommended fix is a **host-side probe** (check `100.79.80.79:39704`
  directly from etra, where a blackhole is a real connect timeout) feeding
  `async_filter_deployments`. It is **not built** — it needs a small LiteLLM plugin
  (Python module loaded via `litellm_settings.callbacks`) and a cron/loop writing
  per-host reachability, which is a real (small) feature, not a config line.
  Deferred, not done.
