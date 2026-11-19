# LiteLLM hooks for waking a powered-off backend (`brys`)

Research task. No code changes. Sources: official LiteLLM docs and the
`BerriAI/litellm` source at `main` (cloned to `/tmp` for this report).

Every claim is tagged:

- **CONFIRMED** — stated in official docs or read from current source.
- **NOT FOUND / UNVERIFIED** — I searched and could not confirm it exists.

---

## TL;DR for your use case

There is **no** purpose-built "backend is down, wake it up" hook in LiteLLM.
There is also **no** native "cold start / scale to zero / autostart" feature
(**NOT FOUND**). But three generic mechanisms can be combined to approximate it:

1. `CustomLogger.async_pre_call_hook` — runs before routing/backend contact,
   can `await asyncio.sleep(...)`, can probe the backend, and can raise an
   exception or return a `str` that becomes an HTTP error.
2. `CustomLogger.async_pre_call_deployment_hook` — runs after a deployment is
   chosen, immediately before the HTTP call; can also block on a probe.
3. Alerting (`alert_types: ["outage_alerts"]`, `"cooldown_deployment"`) + the
   `webhook` / `generic_api` network callbacks — these REACT to failures, they
   do not pre-empt them, but they can POST to an arbitrary URL (Home Assistant).

The blocking `async_pre_call_hook` is the closest thing to "request arrives →
start power-on → wait → continue". Read §1.4 for the caveats (worker blocking,
timeouts, retries).

---

## 1. Custom callbacks / hooks

### 1.1 The full `CustomLogger` surface (CONFIRMED)

Inherit from `litellm.integrations.custom_logger.CustomLogger`. The complete
set of overridable methods, grouped by when they run
([source: `litellm/integrations/custom_logger.py`](https://github.com/BerriAI/litellm/blob/main/litellm/integrations/custom_logger.py),
[docs: Modify / Reject Incoming Requests](https://docs.litellm.ai/docs/proxy/call_hooks)):

| Method                                                                                                                                            | Fires                                                            | Before backend contact? |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ----------------------- |
| `async_pre_call_hook(user_api_key_dict, cache, data, call_type)`                                                                                  | Before routing / deployment selection, before the LLM call       | **Yes**                 |
| `async_pre_routing_hook(model, request_kwargs, messages, input, specific_deployment)`                                                             | Before the routing decision (auto-router)                        | **Yes**                 |
| `async_filter_deployments(model, healthy_deployments, messages, request_kwargs, parent_otel_span)`                                                | In the router's healthy-deployment filter, before the call       | **Yes**                 |
| `async_pre_call_deployment_hook(kwargs, call_type)`                                                                                               | After a deployment is selected, immediately before the HTTP call | **Yes**                 |
| `async_moderation_hook(data, user_api_key_dict, call_type)`                                                                                       | **In parallel** with the LLM call                                | No (concurrent)         |
| `async_post_call_success_hook(data, user_api_key_dict, response)`                                                                                 | After a successful call (non-streaming)                          | No                      |
| `async_post_call_failure_hook(request_data, original_exception, user_api_key_dict, traceback_str)`                                                | After a failed call                                              | No                      |
| `async_post_call_streaming_hook`, `async_post_call_streaming_iterator_hook`                                                                       | Streaming responses                                              | No                      |
| `async_post_call_response_headers_hook(data, user_api_key_dict, response, request_headers)`                                                       | After call, success **and** failure                              | No                      |
| `async_post_call_success_deployment_hook`, `async_post_call_failure_deployment_hook`                                                              | Per-deployment attempt (per retry / fallback hop)                | No                      |
| `async_filter_listed_models(user_api_key_dict, model_names)`                                                                                      | On `/v1/models`, `/model/info` etc.                              | N/A (listing)           |
| `log_success_event`, `async_log_success_event`, `log_failure_event`, `async_log_failure_event`, `log_pre_api_call`, `async_log_pre_api_call`, ... | Logging callbacks                                                | Mostly after            |

Also confirmed: the general loggers are registered via separate lists
`litellm.input_callback`, `litellm.success_callback`,
`litellm.failure_callback` ([docs: Callbacks](https://docs.litellm.ai/docs/observability/callbacks)).

### 1.2 The two hooks that matter for "wake on request" (CONFIRMED)

Both run **before** the backend is contacted, and both are `async`, so they can
`await` (probe the host, sleep, call Home Assistant, poll until the port opens).

`async_pre_call_hook` — exact signature from source:

```python
async def async_pre_call_hook(
    self,
    user_api_key_dict: UserAPIKeyAuth,
    cache: "DualCache",
    data: dict,
    call_type: CallTypesLiteral,
) -> Exception | str | dict | None:
    ...
```

Return contract, confirmed by
[`process_pre_call_hook_response`](https://github.com/BerriAI/litellm/blob/main/litellm/proxy/utils.py)
in the proxy source:

- return a **`dict`** → it becomes the new request `data` (mutate/normalise).
- return a **`str`** → for chat/completions the proxy raises
  `RejectedRequestError` and returns that string as the model's message;
  for other endpoints it becomes an `HTTPException(status_code=400, detail=...)`.
- return an **`Exception`** instance → the proxy `raise`s it (so a
  `fastapi.HTTPException(status_code=..., detail=...)` you returned or raised
  becomes that exact HTTP status to the client).
- return **`None`** → request proceeds unchanged.
- Raising any exception propagates to the caller (verified: the loop at
  `litellm/proxy/utils.py` around the `async_pre_call_hook` call site has no
  catch that converts it; `fastapi.HTTPException` flows through as its status).

`async_pre_call_deployment_hook` — exact signature from source:

```python
async def async_pre_call_deployment_hook(
    self, kwargs: dict[str, object], call_type: CallTypes | None
) -> dict | None:
    ...
```

Called from `litellm/utils.py::async_pre_call_deployment_hook`, which iterates
`litellm.callbacks` and replaces `kwargs` when a hook returns non-`None`. It
can raise (the source raises `MalformedRequestFieldError` from the same code
path, so raising is supported) and it can `await`. It is the right place to
block on "wait until my backend's port responds" **after** routing has already
chosen this deployment.

**Can they sleep/wait?** Yes — they are `async def`, run inside the request's
coroutine, and the code path does not impose a sub-second deadline on the hook
itself. Practical limit is the client's HTTP timeout and the proxy's
`request_timeout`. A multi-minute sleep (power-on can take minutes) will very
likely exceed default timeouts (**UNVERIFIED** exact interaction between a
client-side OpenAI timeout and this hook; test it). See §1.4.

### 1.3 Registering a custom callback (CONFIRMED)

`config.yaml`:

```yaml
litellm_settings:
  callbacks: my_pkg.wake_handler.instance # dotted path to an INSTANCE
```

The dotted path is resolved by
[`get_instance_fn`](https://github.com/BerriAI/litellm/blob/main/litellm/proxy/types_utils/utils.py):

- splits on `"."`, the last segment is the **instance/attribute** name, the
  rest is the **module**.
- if `<module>.py` exists **next to the config file**, it is loaded from disk
  via `importlib.util.spec_from_file_location` — so you can drop
  `my_pkg/wake_handler.py` beside `config.yaml` with no install.
- otherwise it does `importlib.import_module(module_name)` — so the package
  must be `pip install`-ed (or on `PYTHONPATH`) into the proxy's environment.

The docs are explicit that the file must create the instance
(`proxy_handler_instance = MyCustomHandler()`) and that you point `callbacks`
at the **instance**, not the class
([docs: Quick Start](https://docs.litellm.ai/docs/proxy/call_hooks)).

`litellm_settings.callbacks` sets `litellm.callbacks`; `success_callback` and
`failure_callback` are separate lists for pure loggers
([source: `proxy_server.py` config handling](https://github.com/BerriAI/litellm/blob/main/litellm/proxy/proxy_server.py)).

### 1.4 Caveats of the "block in pre_call_hook" approach (CONFIRMED unless noted)

- **Blocking model**: `async_pre_call_hook` runs in the worker's event loop.
  `await asyncio.sleep()` yields, but if you call a **synchronous** power-on
  script, wrap it in `asyncio.to_thread` / `run_in_executor`, or you stall the
  whole worker. Not documented as a rule, but implied by async semantics.
- **Retries multiply the side effect**: the hook runs **per request**. If the
  client retries, your wake script fires again. Guard with a shared
  "already-waking / cooldown" flag (a module global or the `cache: DualCache`
  passed into the hook is a natural place).
- **Timeouts**: the OpenAI client and proxy `request_timeout` will cut the
  connection before a multi-minute power-on finishes. Expect to need a
  `HTTPException(503, ...)` + `Retry-After` path rather than a true block for a
  cold machine. (**UNVERIFIED** — no doc promises the hook can hold a
  connection open for minutes.)
- **`async_pre_call_hook` runs before deployment selection**, so it does not
  know which `api_base` will serve the request unless you read `data["model"]`
  and look up the deployment yourself.

---

## 2. "Model requested → ensure backend up" / cold start

### 2.1 Native "wake the backend" concept (NOT FOUND)

I searched docs and source for `scale to zero`, `cold start`,
`wake on demand`, `autostart`, and equivalents. **There is no LiteLLM feature
that powers a backend up when a model is requested.** The only `cold_start`
hits in the source are unrelated:
`litellm/router_strategy/adaptive_router/bandit.py` uses "cold-start" as
**Bayesian prior mass** for the bandit router, nothing to do with backends
(**CONFIRMED** by reading the file).

### 2.2 `pre_call_checks` / `enable_pre_call_checks` (CONFIRMED)

The router has an `optional_pre_call_checks` (a.k.a. pre-call checks) system
([docs: Load Balancing](https://docs.litellm.ai/docs/proxy/load_balancing),
source: `litellm/router_utils/pre_call_checks/`). Built-in checks:

- `enforce_model_rate_limits`
- `encrypted_content_affinity`
- `deployment_affinity` / `responses_api_deployment_check`
- `prompt_caching_deployment_check`
- `io_token_rate_limit` / `model_rate_limit_check`

These are **rate-limit and affinity** checks — none of them "wake a server".
They are wired through the `async_filter_deployments` hook (§1.1), which you
_can_ override in your own `CustomLogger` to drop/allow deployments before the
call. That is the supported extension point, but there is **no built-in
"ensure backend up" check**.

### 2.3 Overriding deployment choice (CONFIRMED mechanism, custom code)

The router chooses a deployment internally; there is no documented public
`async_get_available_deployment` override hook on `CustomLogger`
(**NOT FOUND** as a callback). The supported way to influence which deployment
serves a request **before the call** is `async_filter_deployments` (filter the
healthy list) and `async_pre_call_deployment_hook` (act once chosen). To force a
specific backend you would implement that filtering yourself.

### 2.4 llama-swap interaction (NOT FOUND in LiteLLM)

LiteLLM does not know about llama-swap's eviction or its `/v1/models`. If
llama-swap unloads a model, LiteLLM sees a slow/failed completion, not a
"model evicted" event. Your code must translate:
"request for model X arrived" → "probe llama-swap `/v1/models` / the model's
endpoint" → "if 404/timeout, run power-on / model-load" → "wait". This is all
custom logic inside `async_pre_call_hook` / `async_pre_call_deployment_hook`.

---

## 3. Health-check-driven actions and alerting

### 3.1 Custom action on an unhealthy deployment (PARTIAL / NOT FOUND)

- The **background health check** (`general_settings.background_health_checks:
true`, `health_check_interval`, `health_check_details`) is **CONFIRMED**
  ([docs: Health Checks](https://docs.litellm.ai/docs/proxy/health)). It
  populates a cache that `/health` reads and that
  [health-check routing](https://docs.litellm.ai/docs/proxy/health_check_routing)
  can use to route traffic away.
- There is **no documented user hook** that fires "on health check failure"
  or "on cooldown start" where you can run arbitrary Python (**NOT FOUND** as a
  `CustomLogger` method).
- There **is** an internal callback `router_cooldown_event_callback`
  ([source](https://github.com/BerriAI/litellm/blob/main/litellm/router_utils/cooldown_callbacks.py))
  that fires when a deployment enters cooldown, but it only updates Prometheus
  metrics — it is not a public extension point, and it takes no user code.

So: **health-check-driven custom Python action is not a first-class feature.**
For "run power-on when unhealthy" you either (a) do it in
`async_pre_call_hook` per request, or (b) alert out and let an external system
act (see §3.2 / §4).

### 3.2 Webhook alerting that can POST to an arbitrary URL (CONFIRMED)

LiteLLM's alerting can POST to Slack-compatible / Discord / MS Teams webhooks,
and there is a **generic `webhook`** alerting backend and a **`generic_api`**
network callback. These fire on **failure**, after the fact.

Config for the built-in webhook alerting
([docs: Alerting / Webhooks](https://docs.litellm.ai/docs/proxy/alerting)):

```yaml
general_settings:
  alerting: ["webhook"]
  alert_types: ["outage_alerts", "cooldown_deployment", "llm_exceptions"]
```

The `webhook` alerting backend POSTs a fixed JSON event body (budget events
documented; the same `alerting` list carries `outage_alerts`,
`cooldown_deployment`, `llm_exceptions`). URL comes from `WEBHOOK_URL` (or
`SLACK_WEBHOOK_URL` / `ALERTING_WEBHOOK_URL`).

For a **fully generic** "POST a JSON payload anywhere", use the
`generic_api` callback
([docs: Generic API](https://docs.litellm.ai/docs/observability/generic_api)):

```yaml
litellm_settings:
  callbacks: ["ha_hook"]
callback_settings:
  ha_hook:
    callback_type: generic_api
    endpoint: https://homeassistant.example/api/webhook/llm_wake
    headers:
      Authorization: Bearer <token>
    event_types: ["llm_api_failure"]
```

**Can it POST to Home Assistant?** Yes — Home Assistant has a
`/api/webhook/<id>` endpoint that accepts arbitrary `POST` bodies, and
`generic_api`'s `endpoint` accepts any URL. **Caveat (CONFIRMED):**
`generic_api` **batches** (`DEFAULT_BATCH_SIZE`, `DEFAULT_FLUSH_INTERVAL_SECONDS`)
and sends a JSON **array** of `StandardLoggingPayload` records — HA would
receive a batch, not a clean single event. If you need one clean event per
failure, prefer the `webhook` alerting backend (fixed schema) or your own
`failure_callback` that POSTs directly.

Alert types relevant to you (**CONFIRMED** from the alert-types table):
`outage_alerts` (deployment facing an outage), `cooldown_deployment`
(deployment put into cooldown), `llm_exceptions`. `region_outage_alerts` is
Enterprise.

---

## 4. Alternatives outside LiteLLM

**(a) Reverse-proxy / health-probe shim in front.** Put a tiny proxy (nginx,
Caddy, Envoy, or a ~100-line aiohttp app) between clients and LiteLLM. On a
request for a model whose upstream `api_base` is unreachable, the shim runs the
power-on procedure and either holds the connection open (long `proxy_read_timeout`)
or returns `503 + Retry-After`. This keeps all the cold-start logic out of
LiteLLM and out of the Python event loop, and it composes with llama-swap
cleanly.

**(b) Home Assistant automation driven by a Prometheus alert.** Enable
LiteLLM's Prometheus metrics and alerting (`outage_alerts`,
`cooldown_deployment`); point Alertmanager at a webhook that HA consumes, or
have HA poll `/health`. On the alert, HA runs your existing multi-step
power-on. Downside: it fires **after** the first failed request, so the first
request still fails — you get "wake on first failure", not "wake on demand".

**(c) A small custom "wake proxy".** A standalone service that owns the power
state: it exposes an OpenAI-compatible `/v1/chat/completions`, checks
`/v1/models` on the real backend, triggers power-on + waits for readiness, then
streams through. Combined with LiteLLM either in front or behind it, this is the
most controllable option and the one I would pick given your power-on is long
and stateful. This is essentially what `async_pre_call_hook` from §1 would do,
just outside LiteLLM's worker.

---

## Confirmed vs. not found — summary

**CONFIRMED in docs / source**

- `CustomLogger.async_pre_call_hook` (signature, return contract, raises →
  HTTP status) — §1.2
- `CustomLogger.async_pre_call_deployment_hook(kwargs, call_type)` — §1.2
- `async_pre_routing_hook`, `async_filter_deployments` (pre-call, router-level)
  — §1.1
- `async_post_call_failure_hook(request_data, original_exception,
user_api_key_dict, traceback_str)` — §1.1
- Registration via `litellm_settings.callbacks: module.instance`; instance
  required; module loaded from config dir or `importlib` — §1.3
- `optional_pre_call_checks` / `enforce_model_rate_limits`, etc. — §2.2
- Background health checks + `/health` semantics — §3.1
- `alerting: ["webhook"]`, `alert_types: ["outage_alerts",
"cooldown_deployment", "llm_exceptions"]` — §3.2
- `callback_type: generic_api` with arbitrary `endpoint` — §3.2

**NOT FOUND / UNVERIFIED**

- Any native "wake backend / cold start / scale-to-zero / autostart" feature —
  does not exist (§2.1).
- A public `CustomLogger` hook that fires on health-check failure or
  cooldown-start where user code runs — does not exist (only the internal
  Prometheus `router_cooldown_event_callback`) (§3.1).
- A documented `async_get_available_deployment` override callback on
  `CustomLogger` — not found; use `async_filter_deployments` instead (§2.3).
- Whether a multi-minute `await` inside `async_pre_call_hook` survives client
  timeouts and worker settings — no doc promise; must be tested (§1.4).
- Whether llama-swap eviction is surfaced to LiteLLM as any distinct event —
  it is not; only generic failures/timeouts (§2.4).
