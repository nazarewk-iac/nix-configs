# LiteLLM: declarative config and unreachable-backend behaviour

Research, 2026-11-05. Sources: official LiteLLM docs and the `BerriAI/litellm`
source. Every claim tagged **(verified)** or **(unverified)**.

nixpkgs pins **`litellm` 1.102.1**; `main` on GitHub is ahead. Behaviour noted
below is for current versions; re-check against the packaged version if a
difference appears.

---

## 1. Config as code

### 1.1 Shape

`config.yaml` with five meaningful top-level keys:

```yaml
model_list: []          # deployments: public name -> backend
router_settings: {}     # retries, cooldowns, timeouts, fallbacks
litellm_settings: {}    # callbacks, cache, request_timeout
general_settings: {}    # master_key, health checks, (database_url)
environment_variables: {}  # note: plural
```

`proxy_settings` is **not** a config key (it is a filename in some docs).
**(verified)**

### 1.2 An OpenAI-compatible backend (llama-swap)

```yaml
model_list:
  - model_name: gemma-4-e4b
    litellm_params:
      model: openai/gemma-4-e4b
      api_base: http://127.0.0.1:39700/v1
      api_key: os.environ/BRYS_LLAMA_KEY
    model_info:
      id: brys-gemma
      mode: chat
```

- `model: openai/<name>` marks it OpenAI-compatible. **(verified)**
- `api_base` must end in `/v1` or you get Not Found. **(verified)**
- The `openai/` path requires *a* key (llama-swap accepts any) — pass it via
  `os.environ/`. **(verified)**
- `model_info.mode` selects the health probe endpoint (chat → `/chat/completions`).
  **(verified)**

### 1.3 No database

| feature | needs Postgres? |
| --- | --- |
| model_list, router/litellm/general settings | no |
| master_key (single shared bearer) | no |
| per-client virtual keys `sk-...` | **yes** |
| teams, users, budgets, spend logs | **yes** |

With `DATABASE_URL` unset, `setup_prisma_client(None)` returns `None` and the
proxy runs file-only; it **does not refuse to start**. Auth = one shared
`LITELLM_MASTER_KEY`. Budget enforcement is silently disabled. **(verified)**

**No YAML-declared static virtual-key list was found** in current LiteLLM — so
DB-less means a single shared bearer key, no per-client keys. **(unverified that
such a feature does not exist under another name; searched and not found.)**

### 1.4 Master key is mandatory

Current versions **refuse to start** if `master_key` is unset/empty/a known
default (`master_key_boot_check.py`). Supply it via
`master_key: os.environ/LITELLM_MASTER_KEY` + systemd `EnvironmentFile`.
**(verified on main; check 1.102.1.)**

---

## 2. Unreachable backend behaviour

### 2.1 Request flow on failure

pick deployment → call fails → retry up to `num_retries` (re-picking siblings in
the same `model_name` group) → record failure → cool down after `allowed_fails`
within `cooldown_time` → try `fallbacks` → else return the error. **(verified)**

### 2.2 Router settings that matter

| key | default | meaning |
| --- | ---: | --- |
| `num_retries` | 2 | retries per request |
| `timeout` | **6000 s** (via `request_timeout`) | per request — **must clamp** |
| `cooldown_time` | 5 s | how long a cooled deployment is skipped |
| `allowed_fails` | null → rate rule (>50% fails in 1 min, min 5 req) | fails before cooldown |
| `fallbacks` | [] | cross-model failover on any error |
| `context_window_fallbacks` | [] | failover on context overflow |
| `default_fallbacks` | null | fallback when a group has none |
| `enable_pre_call_checks` | false | pre-send context/vision checks |
| `enable_health_check_routing` | false | route away from unhealthy deployments |
| `disable_cooldowns` | false | disable cooldowns entirely |

**(verified)**

### 2.3 Status codes

- **All deployments for a model down/cooling → HTTP 429** with `retry-after`
  header, on the inference path (`RouterRateLimitError`). **(verified in source)**
- **503 "no healthy deployment" appears only on `/health?model=...`**, not on
  chat/inference. **(verified)**
- A single dead backend with a connect-refused fails fast; a *hung* backend blocks
  until `timeout` — hence the need to clamp it. **(verified)**

### 2.4 Health checks

- `general_settings.background_health_checks: true`, `health_check_interval: 300`,
  `health_check_details: true`.
- Probes derive their URL from `model` + `mode`; **there is no custom health URL
  key**, so they hit llama-swap's `/chat/completions`, not `/v1/models` or
  `/health`. Avoid the token cost with `disable_background_health_check` per
  model and rely on cooldowns. **(unverified that no custom URL exists — none
  found.)**
- `/health/liveliness` (no auth) and `/health/readiness` are the liveness/startup
  probes.

---

## 3. Prometheus

- Endpoint `GET /metrics`, **enabled by flag**: `litellm_settings.callbacks:
  [prometheus]`. **(verified)**
- **`litellm_deployment_state`** gauge, labels `litellm_model_name`, `model_id`,
  `api_base`: 0 healthy, 1 partial, 2 complete outage → **alert on `> 0`**.
  **(verified)**
- Also `litellm_deployment_cooled_down`, success/failure counters, latency
  histograms.
- `prometheus_client` is already in the nixpkgs closure. Multi-worker needs a
  writable `PROMETHEUS_MULTIPROC_DIR`. **(verified)**

---

## 4. Packaging / runtime

- nixpkgs has `litellm` (1.102.1), `mainProgram = litellm`; **no `services.litellm`
  NixOS module** was confirmed — run it under our own systemd/container wiring.
  **(unverified that no module exists.)**
- Runs under uvicorn by default: `litellm --config <path>`.
- **No mandatory persistent state** DB-less; losing the container loses only
  cooldown counters. Optional local cache only if enabled.
- Memory footprint not measured; measure in the container.

---

## 5. Conclusion for our deployment

- No DB. `config.yaml` in the repo, `master_key` from sops env.
- Clamp `timeout` to ~60 s, `num_retries: 1`, `cooldown_time: 30`,
  `allowed_fails: 2`, and wire `fallbacks` so a dead host degrades to another.
- Enable `prometheus` and alert on `litellm_deployment_state > 0`.
- Health checks: rely on cooldowns + the deployment-state metric rather than
  paying for background inference probes against every backend.
