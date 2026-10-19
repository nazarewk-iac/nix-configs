---
type: Reference
description: Local LLM serving via the den `llm` aspect (llama-server router mode + Caddy TLS reverse proxy) — full option synopsis, architecture, and the brys host as a concrete deployment example.
timestamp: 2026-08-31T00:00:00+02:00
---

# Local LLM serving

How the `kdn.llm.local` den aspect serves local LLMs on a NixOS host.
This document covers the concept, the global download behaviour, and a
concrete example single-host deployment on **brys**.

Reference docs: [the den `llm` aspect](../modules/den/aspects/llm.nix). The
universal `modules/slots/llm` server slot was removed once brys moved to the
aspect; the `client` and `proxy` subslots stay for now.

> See [llama-swap mode](#llama-swap-mode) for the alternative lifecycle owner
> that replaces the per-router `llama-server` units.

## Concept

`kdn.llm.local` runs one or more llama-server processes (from llama.cpp) in
**router mode**: each owns an OpenAI-compatible HTTP API on loopback that
loads/unloads individual GGUFs on demand (`--models-max 1`, exactly one model
resident at a time in that router). The primary **frontier** router
(`services.llama-cpp`, `:39703`) holds the default "main" model set; any number
of optional extra routers (`kdn.llm.local.routers.<name>`) host smaller
freely-swapping sets. A self-signed-certificate **Caddy** reverse proxy exposes
the endpoint on the LAN over HTTPS. Between Caddy and the servers sits one
OpenCode DSML compat-proxy that both translates DSML/XML tool calls and routes
each request's `model=` field to the router that owns it (unknown models fall
back to the frontier), merging all routers' `/v1/models`. A single instance
fronts the whole N-router topology.

```
LAN client ──HTTPS──▶ Caddy (:80/:443) ──▶ compat-proxy (:9530) ─┬─▶ llama-server "main" (:39703, --api-key-file)
                                                                  └─▶ llama-server "small" (:39704, --api-key-file)
                                                                  └─▶ ... any further `routers.<name>` ...
```

## llama-swap mode

`kdn.llm.local.swap.enable = true` replaces every per-router `llama-server`
unit with one [llama-swap](https://github.com/mostlygeek/llama-swap) process.
llama-swap owns every model child: it starts a `llama-server` per model on
demand, answers to every model id and alias itself, and evicts a running child
when a queued request needs its slot. The topology becomes:

```
LAN client ──HTTPS──▶ Caddy (:80/:443) ──▶ compat-proxy (:9530) ──▶ llama-swap (:39700, /v1/models)
                                                                        └─▶ child llama-server (one per model, on demand)
```

The compat-proxy no longer fans out to per-router upstreams: it points its
`UPSTREAM_URL` at the llama-swap port (`swap.port`, default `39700`), and
llama-swap answers to every id, so no `ROUTER_<NAME>_*` table appears. The child
`llama-server` processes inherit the llama-swap unit's systemd namespace.

**Auth.** The swap children get `--api-key-file /var/cache/llama-swap/api-keys`,
because the router path's `llama-cpp.preStart` no longer runs. A llama-swap
`preStart` assembles the per-key files under `apiKeyDir` into that one file in
llama-swap's own `CacheDirectory` (its DynamicUser can write there); the
compat-proxy forwards the bearer it receives. Each child validates the same
bearer the router path validated.

The swap-mode options (all inert until `swap.enable` is set):

| Option | Meaning |
|---|---|
| `swap.enable` | Turn llama-swap into the single model-lifecycle owner. |
| `swap.port` | Loopback port llama-swap listens on (default `39700`); the compat-proxy targets it. |
| `swap.healthCheckTimeout` | Seconds llama-swap waits for a new child to answer before it fails the request (default `900`, so a cold frontier load of ~90-120 s fits). |
| `swap.routerEngine` | `"matrix"` (evict-cost policy, chosen on brys) or `"group"` (one group per router). |
| `swap.persistentModels` | Model ids llama-swap must never evict for another model. |
| `swap.packageOverrides` | Per-model llama.cpp build, so one child can differ from `kdn.llm.local.package`. |
| `swap.vulkanDeviceSelect` | Value of `MESA_VK_DEVICE_SELECT` for the llama-swap unit (replaces the router-mode pin on `llama-cpp`). |

### Matrix routing on brys

With `swap.routerEngine = "matrix"` brys sets two persistent models,
`deepseek-v4-flash` and `qwen3.8-flash-next`. The engine gives each model an
`evict_costs` entry — **1000** for a persistent (frontier) model, **1** for a
grunt — and groups models into `sets`. A request for a model evicts every
running model that is **not** in the same set, and a set that keeps a frontier
beats one that drops it. The rendered sets are:

```
main           = (deepseek-v4-flash | qwen3.8-flash-next)   # frontier models swap among themselves
with_grunt     = (qwen3.5-4b) & (deepseek-v4-flash | qwen3.8-flash-next)
with_surveyed  = (<28 surveyed grunts>) & (deepseek-v4-flash | qwen3.8-flash-next)
```

So the two frontier models swap among themselves (`main` holds them with `|`),
while a grunt runs **alongside** a frontier model (`with_grunt`/`with_surveyed`
AND it with the frontier set) and never evicts it: a grunt request evicts the
other grunt, not the frontier. Every surveyed model is cost 1, so it is always
the model that loses a slot. This is the mechanism that lets the four boot
specialisations collapse to one config; see
[single-specialisation.design.md](tasks/2026-10/brys-grunt-colocation/single-specialisation.design.md).

Only brys's swapping entries use swap mode: the main `brys` profile
(`hosts/brys/default.nix`), `llms-frontier` and `llm-qwen` all set
`withSwap = true`. `llm-ds4` and `llm-small` still use router mode (per-router
`llama-server` units), so their output stays unchanged.

### `--load-mode` (v0.6.0 build)

The v0.6.0 build dropped `--mmap`/`--no-mmap`; it accepts only `--load-mode`.
The swap `cmd` therefore emits `--load-mode mmap|none` (the router-mode INI key
`mmap = on|off` maps onto that), and a model that sets `perf.loadMode` uses that
value directly. See "The MTP builds dropped `--mmap`" in
[Qwen3.8-Flash-Next on brys](#qwen38-flash-next-on-brys-2026-10-06).

### Hot reload

llama-swap's config watch (`-watch-config`, a 2 s `os.Stat` poll; also `SIGHUP`)
is **stop-the-world**: it stops every upstream child, cuts in-flight requests
and fails queued ones (llama-swap issue #1202). The mitigation is to **never
reload in place**: run with `-watch-config=false`, regenerate the config at
activation, and keep the hitless route layer (Caddy/proxy) in front. The full
survey is [router-hot-reload.research.md](tasks/2026-10/brys-grunt-colocation/router-hot-reload.research.md);
the migration is [llama-swap-migration.design.md](tasks/2026-10/brys-grunt-colocation/llama-swap-migration.design.md).

### Observability and stats

llama-swap is **stateless**: one Go binary, no database, no history. Verified on
brys — `--help` shows only config/listen/TLS/watch flags; `/var/cache/llama-swap`
holds only `api-keys` and the GPU shader caches; the unit is `DynamicUser` with
`CacheDirectory = "llama-swap"`. No config key persists model statistics across
a restart.

What is available, live only:

| Source | What it gives | Persisted? |
|---|---|---|
| llama-swap `/metrics` | System-level Prometheus: `llamaswap_cpu_util_percent{core}`, `memory_{free,total,used}_bytes`, `swap_{total,used}_bytes`, `load_average`, `network_bytes_total`. **No per-model or token/tps metric.** | No (scrape-only) |
| llama-server child response | Per-response `timings`: `prompt_per_second`, `predicted_per_second`, `predicted_n`, etc. This is what the benchmark tables read. | No |
| llama-swap `/ui` (:39700) | Live per-model token metrics and request inspection in the browser. | No |
| `/logs`, `/logs/stream/:model` | In-memory log ring buffer, per model. | No |
| `/running` | The currently loaded models. | No |

**Per-model tps history needs an external store.** Scrape llama-swap `/metrics`
(system) plus each child's metrics into Prometheus/VictoriaMetrics and graph with
Grafana. Note two gaps today: the swap children are **not** started with
`llama-server --metrics`, so the child token counters are not exposed; and
llama-swap has no per-model `--metrics` toggle. `perf.extraFlags` (see the model
table) is the hook that would add `--metrics` per model if that is ever wanted.
This document records the status only; nothing is wired.

## N-router topology and routing

The compat-proxy maps each request's `model` (a name or an alias) through its
`ROUTE` table to the owning router's base URL; anything unrouted (including
`None`) goes to the frontier `UPSTREAM_URL`. `GET /v1/models` walks every
configured router and merges the listings, deduped by model id. Each router
runs `--models-max 1`, so model load/unload on that router is an on-demand swap
within the router only — the frontier's resident model is untouched.

Why split at all? A single `models-max=1` router thrashes DeepSeek V4 Flash's
(DS4) ~77 GB weight page-cache whenever a second model loads (see the measured
per-model table in
[hosts/brys/performance.md](../hosts/brys/performance.md): any 45 G+ MoE fully
evicts DS4's resident weights, see `qwen3-coder-next` 65.6 G,
`qwen3-next-80b` 80 G, `gpt-oss-120b` ~100 G, `qwen3-235b` ~100 G). Splitting
lets DS4 stay resident/hot on the frontier router (its ~92 GB working set held
against page-cache pressure) while the small set swaps freely on its own
router; only `phi-4` (17.7 G) or `qwen3-30b-a3b` (44.4 G but evicting ~45 G of
DS4 cache) ever risk touching the frontier's cache in a single-router layout.
  Facts only — no extrapolation beyond the measured footprints in
  [hosts/brys/performance.md](../hosts/brys/performance.md).

### Token usage in streams

OpenCode forces `stream_options.include_usage: true` on its OpenAI-compatible
providers, and llama-server answers with a final SSE chunk that has an empty
`choices` array plus a `usage` (and `timings`) object. The compat-proxy must pass
that chunk through, or the OpenCode token counter stays at zero for every
self-hosted model. The proxy keeps it on both the plain-text and the DSML
tool-call streaming paths (the non-streaming path always carried `usage`). The
proxy source is the
[`nazarewk-iac/opencode_compat_proxy`](https://github.com/nazarewk-iac/opencode_compat_proxy)
fork, a `flake = false` input; its `main` aggregates the three patches and its
`stream-usage` branch holds the usage fix alone. See
[tasks/2026-10/opencode-self-hosted-token-stats/done.md](tasks/2026-10/opencode-self-hosted-token-stats/done.md).

### Option contract

All of this is configured through `kdn.llm.local` in a host's `mkSlots` block:

- `kdn.llm.local.routers.<name>` (`attrsOf`) — each entry enables an extra
  llama-server router with `enable`, `port`, `threads`, `apiKeyDir`. Router
  **names must be lowercase alphanumeric** (e.g. `small`, `coder`) so the
  proxy's env key `ROUTER_<NAME>_*` round-trips through its hyphenated slug
  back to the on-disk section name.
- `kdn.llm.local.models.<name>.mainRouter` — which router owns the model
  (`"main"` = the frontier/default server; any other value the equally-named
  `routers.<name>`). A model lands in exactly one router's preset INI.
- `kdn.llm.local.models.<name>.aliases` — extra names routed to that model's
  router too.

The compat-proxy honors, per router: `ROUTER_<NAME>_URL`
(`http://127.0.0.1:<port>`) + `ROUTER_<NAME>_MODELS` (`m1,m2,...`, names +
aliases). The legacy `SMALL_UPSTREAM_URL` + `SMALL_MODELS` pair is sugar for a
router named `small`; the slot now emits the general `ROUTER_<NAME>_*` form for
every enabled router (including `small`). A future host adds a third router by
declaring `routers.<name>` + pointing the relevant models' `mainRouter` at it —
the slot generates its env vars automatically. See the `router` branch of the
[`nazarewk-iac/opencode_compat_proxy`](https://github.com/nazarewk-iac/opencode_compat_proxy)
fork for the proxy contract.

To enable on any NixOS host, inside its `mkSlots` block:

```nix
kdn.llm.local.enable = true;
kdn.llm.local.modelsDir = "/var/lib/kdn/llms/models";    # required, no default
kdn.llm.local.domain = "brys.lan.etra.net.int.kdn.im";     # required, LAN hostname
kdn.llm.local.certs.certFile = "/run/configs/.../public.key";   # required
kdn.llm.local.certs.keyFile = "/run/configs/.../private.key";   # required
kdn.llm.local.apiKeyDir = "/run/configs/llms/llama-server/api-keys";   # optional
kdn.llm.local.download.mode = "slow";                    # global: slow | fast-polite
# ... per-model `kdn.llm.local.models.<name>` entries ...
```

Full option reference: [the den `llm` aspect](../modules/den/aspects/llm.nix).

## All models (unified table)

Every numeric column is measured on brys on 2026-10-18 except
`params`/`license`/`ctx`, which come from the 2026 model survey. `RssAnon` and
`VmRSS` are MiB; decode and prefill are tok/s. `ctx (served)` is the context the
run used: 16384 for every measured run, or the registered served context for a
model with no measurement. A dash means not applicable.

| model | class | params (active) | license | file GB | ctx (served) | RssAnon | VmRSS | decode t/s | prefill t/s | mode | registered in |
|---|---|---|---|---|---|---|---|---|---|---|---|
| qwen3.8-flash-next | frontier | — | — | 93.7 | 1048576 | — | — | — | — | — | swap main |
| deepseek-v4-flash | frontier | ~180B MoE | custom | 103 | 327680 | — | — | — | — | — | swap main |
| qwen3.5-4b | grunt | 4B dense (hybrid Gated-DeltaNet) | Apache-2.0 | 2.6 | 16384 | 114 | 643 | 60.8 | 158.0 | GPU | swap with_grunt (:39705) |
| qwen3.5-4b | grunt | 4B dense (hybrid Gated-DeltaNet) | Apache-2.0 | 2.6 | 16384 | 2118 | 4733 | 13.0 | 68.7 | CPU | swap with_grunt (:39705) |
| qwen3.5-9b | grunt | 9B dense (hybrid) | Apache-2.0 | 5.3 | 16384 | 3437 | 8855 | 5.6 | 40.8 | CPU | swap with_grunt (:39705, disabled) |
| phi-4 | small-cpu | — | — | 9 | 16384 | — | — | — | — | — | router small (:39704, llm-small) |
| qwen3-30b-a3b | small-cpu | — | — | 18 | 131072 | — | — | — | — | — | router small (:39704, llm-small) |
| qwen3-next-80b | small-cpu | — | — | 48 | 131072 | — | — | — | — | — | router small (:39704, llm-small) |
| qwen3-coder-next | small-cpu | — | — | 48 | 131072 | — | — | — | — | — | router small (:39704, llm-small) |
| gpt-oss-120b | small-cpu | — | — | 65 | — | — | — | — | — | — | router small (:39704, llm-small) |
| qwen3-235b | small-cpu | — | — | 77 | 65536 | — | — | — | — | — | router small (:39704, llm-small) |
| qwen3.5-0.8b | surveyed-gpu | 0.8B dense | Apache-2.0 | 0.5 | 16384 | 114 | 348 | 163.4 | 63.8 | GPU | swap with_surveyed (:39706, GPU) |
| qwen3.5-0.8b | surveyed-gpu | 0.8B dense | Apache-2.0 | 0.5 | 16384 | 535 | 1043 | 55.8 | 43.0 | CPU | swap with_surveyed (:39706, GPU) |
| qwen3.5-2b | surveyed-gpu | 2B dense (hybrid) | Apache-2.0 | 1.2 | 16384 | 114 | 544 | 116.8 | 273.5 | GPU | swap with_surveyed (:39706, GPU) |
| qwen3.5-2b | surveyed-gpu | 2B dense (hybrid) | Apache-2.0 | 1.2 | 16384 | 864 | 2085 | 20.1 | 118.5 | CPU | swap with_surveyed (:39706, GPU) |
| tmax-2b | surveyed-gpu | 2B dense | Apache-2.0 | 1.27 | 16384 | 117 | 557 | 110.7 | 311 | GPU | swap with_surveyed (:39706, GPU) |
| tmax-2b | surveyed-gpu | 2B dense | Apache-2.0 | 1.27 | 16384 | 385 | 1650 | 28.6 | 79.7 | CPU | swap with_surveyed (:39706, GPU) |
| granite-4.2-3b | surveyed-gpu | 3B dense | Apache-2.0 | 2.1 | 16384 | 59 | 232 | 83.9 | 223.6 | GPU | swap with_surveyed (:39706, GPU) |
| granite-4.2-3b | surveyed-gpu | 3B dense | Apache-2.0 | 2.1 | 16384 | 2770 | 4906 | 19.8 | 174.0 | CPU | swap with_surveyed (:39706, GPU) |
| ministral-3-3b-instruct | surveyed-gpu | — | — | 2.15 | 16384 | 74 | 429 | 79.3 | 1369 | GPU | swap with_surveyed (:39706, GPU) |
| ministral-3-3b-instruct | surveyed-gpu | — | — | 2.15 | 16384 | 1778 | 3898 | 17.4 | 480 | CPU | swap with_surveyed (:39706, GPU) |
| ministral-3-3b-reasoning | surveyed-gpu | — | — | 2.15 | 16384 | 74 | 429 | 80.9 | 933 | GPU | swap with_surveyed (:39706, GPU) |
| ministral-3-3b-reasoning | surveyed-gpu | — | — | 2.15 | 16384 | 1778 | 3898 | 18.9 | 202 | CPU | swap with_surveyed (:39706, GPU) |
| gemma-4-e2b | surveyed-gpu | — | — | 3.11 | 16384 | 133 | 1967 | 83.5 | 38.8 | GPU | swap with_surveyed (:39706, GPU) |
| gemma-4-e2b | surveyed-gpu | — | — | 3.11 | 16384 | 263 | 3315 | 23.8 | 37.8 | CPU | swap with_surveyed (:39706, GPU) |
| olmo-3-7b-instruct | surveyed-gpu | — | — | 4.47 | 16384 | 62 | 323 | 40.4 | 136 | GPU | swap with_surveyed (:39706, GPU) |
| olmo-3-7b-instruct | surveyed-gpu | — | — | 4.47 | 16384 | 11445 | 15819 | 9.83 | 25.9 | CPU | swap with_surveyed (:39706, GPU) |
| gemma-4-e4b | surveyed-gpu | 4.5B eff (8B w/ embeddings) | Apache-2.0 | 4.8 | 16384 | 170 | 2936 | 56.6 | 46.6 | GPU | swap with_surveyed (:39706, GPU) |
| gemma-4-e4b | surveyed-gpu | 4.5B eff (8B w/ embeddings) | Apache-2.0 | 4.8 | 16384 | 2600 | 7512 | 9.6 | 50.5 | CPU | swap with_surveyed (:39706, GPU) |
| granite-4.2-8b | surveyed-gpu | 8B dense | Apache-2.0 | 5.0 | 16384 | 46 | 298 | 38.6 | 146.0 | GPU | swap with_surveyed (:39706, GPU) |
| granite-4.2-8b | surveyed-gpu | 8B dense | Apache-2.0 | 5.0 | 16384 | 6270 | 11349 | 8.2 | 71.1 | CPU | swap with_surveyed (:39706, GPU) |
| ministral-3-8b-instruct | surveyed-gpu | — | — | 5.2 | 16384 | 74 | 402 | 38.4 | 576 | GPU | swap with_surveyed (:39706, GPU) |
| ministral-3-8b-instruct | surveyed-gpu | — | — | 5.2 | 16384 | 2303 | 7403 | 8.1 | 244 | CPU | swap with_surveyed (:39706, GPU) |
| ministral-3-8b-reasoning | surveyed-gpu | — | — | 5.2 | 16384 | 74 | 402 | 38.9 | 458 | GPU | swap with_surveyed (:39706, GPU) |
| ministral-3-8b-reasoning | surveyed-gpu | — | — | 5.2 | 16384 | 2303 | 7403 | 8.5 | 56 | CPU | swap with_surveyed (:39706, GPU) |
| mimo-v2.6-qwen-9b | surveyed-gpu | 9B dense | Apache-2.0 | 5.5 | 16384 | 3754 | 9325 | 5.7 | 28.1 | CPU | swap with_surveyed (:39706, GPU) |
| tmax-9b | surveyed-gpu | 9B dense | Apache-2.0 | 5.63 | 16384 | 117 | 708 | 36.9 | 121 | GPU | swap with_surveyed (:39706, GPU) |
| tmax-9b | surveyed-gpu | 9B dense | Apache-2.0 | 5.63 | 16384 | 839 | 6358 | 7.18 | 20.7 | CPU | swap with_surveyed (:39706, GPU) |
| qwen3.5-0.8b-cpu | surveyed-cpu | 0.8B dense | Apache-2.0 | 0.5 | 16384 | 535 | 1043 | 55.8 | 43.0 | CPU | swap with_surveyed (:39706, CPU) |
| qwen3.5-2b-cpu | surveyed-cpu | 2B dense (hybrid) | Apache-2.0 | 1.2 | 16384 | 864 | 2085 | 20.1 | 118.5 | CPU | swap with_surveyed (:39706, CPU) |
| tmax-2b-cpu | surveyed-cpu | 2B dense | Apache-2.0 | 1.27 | 16384 | 385 | 1650 | 28.6 | 79.7 | CPU | swap with_surveyed (:39706, CPU) |
| gemma-4-12b | surveyed-cpu | 11.95B dense | Apache-2.0 | 7.12 | 16384 | 1871 | 8842 | 5.76 | 10.4 | CPU | swap with_surveyed (:39706, CPU) |
| gemma-4-26b-a4b | surveyed-cpu | 25.2B / 3.8B (MoE) | Apache-2.0 | 14 | 16384 | 14482 | 28248 | 14.5 | 67.7 | CPU | swap with_surveyed (:39706, CPU) |
| qwen3.6-27b | surveyed-cpu | 27B dense | Apache-2.0 | 16 | 16384 | 11759 | 27798 | 1.8 | 10.1 | CPU | swap with_surveyed (:39706, CPU) |
| granite-4.2-30b | surveyed-cpu | 30B dense | Apache-2.0 | 17 | 16384 | 17029 | 33865 | 2.1 | 17.1 | CPU | swap with_surveyed (:39706, CPU) |
| gemma-4-31b | surveyed-cpu | 31B dense | Apache-2.0 | 18 | 16384 | 19319 | 36790 | 1.7 | 9.3 | CPU | swap with_surveyed (:39706, CPU) |
| glm-4.7-flash | surveyed-cpu | 30B / ~3B (MoE) | MIT | 18 | 16384 | 13886 | 31352 | 11.5 | 46.5 | CPU | swap with_surveyed (:39706, CPU) |
| olmo-3.1-32b | surveyed-cpu | 32B | Apache-2.0 | 19 | 16384 | 18361 | 36951 | 2.3 | 17.6 | CPU | swap with_surveyed (:39706, CPU) |
| seed-oss-36b | surveyed-cpu | 36B dense | Apache-2.0 | 20 | 16384 | 20178 | 40937 | 2.0 | 12.0 | CPU | swap with_surveyed (:39706, CPU) |
| qwen3.5-35b-a3b | surveyed-cpu | 35B / 3B (MoE) | Apache-2.0 | 21 | 16384 | 12210 | 33206 | 9.2 | 45.9 | CPU | swap with_surveyed (:39706, CPU) |
| qwen3.6-35b-a3b | surveyed-cpu | 35B / ~3B (MoE) | Apache-2.0 | 21 | 16384 | 12210 | 33320 | 10.9 | 49.7 | CPU | swap with_surveyed (:39706, CPU) |
| nemotron-3.5-lightning-30b | surveyed-cpu | 30B / 3B (Mamba-2 + MoE hybrid) | OpenMDW-1.1 | 24 | 16384 | 363 | 23527 | 12.9 | 44.0 | CPU | swap with_surveyed (:39706, CPU) |
| nemotron-3.5-bolt-74b | bench-only | 74B / 9B | OpenMDW-1.1 | 21 | — | — | — | — | — | — | — (bench only) |

Source research files: [coresidency-measured.research.md](tasks/2026-10/brys-grunt-colocation/coresidency-measured.research.md)
(all measured columns), [models-2026.research.md](tasks/2026-10/brys-grunt-colocation/models-2026.research.md)
and [models-2026-mid-large.research.md](tasks/2026-10/brys-grunt-colocation/models-2026-mid-large.research.md)
(`params`/`license`), [single-specialisation.design.md](tasks/2026-10/brys-grunt-colocation/single-specialisation.design.md)
(the `sets`/`evict_costs`), `hosts/brys/llm-routers.nix` and
`hosts/brys/{default,llm-qwen,llms-frontier,llm-ds4,llm-small}.nix` (registration).

### Coverage gaps

- **KV cache** is measured only at the served context length (16384 for the
  survey runs). It scales with context, so the footprint of a long-context model
  (Qwen at 1M, DS4 at 320K) is understated here.
- **Prompt / reuse cache is not in the table at all.** The only prompt-cache
  measurement is warm-start prefix reuse in
  [llm-warm-start-session/measurements-2026-10-18.research.md](tasks/2026-10/llm-warm-start-session/measurements-2026-10-18.research.md)
  (0.44 s vs 76.1 s, ~174x) for two models.
- **Registered but unmeasured:** `deepseek-v4-flash`, `qwen3.8-flash-next`, and
  the six `small-cpu` set members.
- **Measured but not registered:** only `nemotron-3.5-bolt-74b` (it fails to
  load; deliberately omitted from the swap config).

## Global download behaviour

Applies to all models equally (not per model):

- **`download.mode`** — how aggressively to transfer:
  - `"slow"` (default): Xet disabled, regular HTTP. Gentlest.
  - `"fast-polite"`: Xet enabled, low pinned concurrency (Tier 1 mitigation).
    Faster than `"slow"` while staying gentle on a shared link.
  how aggressive Xet is.
- **`download.tokenFile`** — optional HF token path, loaded via systemd
  `LoadCredential`.

The download service (`kdn-llm-download`) walks all enabled models one at a
time, logs a status line after each, and skips files already present.

## Example deployment: brys

The **brys** host (Ryzen 5950X, 128 GB DDR4, CPU-only with an effectively
unusable 8 GB AMD GPU for this workload) is the primary deployment of this
slot.

### Serving endpoint

- The standard boot (main host) and the `llms-frontier` specialisation serve
  **both frontier models** — DeepSeek V4 Flash and Qwen3.8-Flash-Next — from one
  llama-server router on loopback. The `llm-ds4` specialisation serves DeepSeek
  alone and `llm-qwen` Qwen alone:
  - **`main`** (frontier): `127.0.0.1:39703`, threads 16. Holds
    `deepseek-v4-flash` (alias `frontier`) and `qwen3.8-flash-next` (alias
    `qwen`); `--models-max 1` keeps only one resident, so a request for the
    other swaps it in (~90-120 s). **Four slots share one unified KV pool**
    (`parallel=4`, `kv-unified=on`), so a second request no longer queues behind
    the first request's full prefill. There is no per-slot cap; `ctx-size` is
    327680 on the specialisations and 131072 on the main profile.
  - **Measured concurrency (2026-10-06):** a short request returned in **3.7 s**
    while a 256-token request was in flight (121.8 s) — neither waited for the
    other. Prefill ran at 7.9–15.9 tok/s; DS4 stayed resident (`RssFile`
    92.6 GB, **0 idle major faults**, no OOM); DSpark acceptance 0.44 at
    `parallel 4`. See the benchmark log below.
- One loopback compat-proxy `:9530` in front of it, with `routerProxyEnv`
  emitting `ROUTER_SMALL_URL` + `ROUTER_SMALL_MODELS` only on the `llm-small`
  boot entry.
- LAN endpoint over HTTPS: `https://brys.lan.etra.net.int.kdn.im/v1`, pinned to
  a self-signed cert and API-key protected. `POST /v1/chat/completions` with the
  `model` field set to a model name or alias; the compat-proxy routes it to the
  owning router (unknown → frontier), which loads/swaps the GGUF automatically.
  Auth: `Authorization: Bearer <key>`
  (`llama-server/api-keys/default` in the sops tree).

### Boot specialisations: one model family per boot

The frontier model and the small set no longer share a boot. All entries are
`inheritParentConfig = false` boot specialisations, selected from the bootloader
(never activated in place), and all share the appliance body in
`hosts/brys/llm-appliance.nix`:

- **`llm-ds4`** (`hosts/brys/llm-ds4.nix`) — DeepSeek V4 Flash alone.
  `withFrontier = true; withSmall = false`. 320K shared KV pool, 4 slots,
  DSpark draft. The main `brys` profile serves the same model at 128K, unpinned.
- **`llm-small`** (`hosts/brys/llm-small.nix`) — the small-model set alone.
  `withFrontier = false; withSmall = true`. `kdn.llm.local.routers.small`
  (`:39704`, threads 8) is a **set router**: `--models-max 2` keeps up to two
  confirmed-coexistable small models resident together, and the primary
  `:39703` router holds no model.
- **`llm-qwen`** (`hosts/brys/llm-qwen.nix`) — Qwen3.8-Flash-Next alone.
  `withFrontier = false; withSmall = false; withQwen = true`. 1M context
  (YaRN x4), batch/ubatch 4096, F16 KV, and the MTP draft head + the main model
  + KV all on the CPU. The W6600 is **not** used (it hard-hangs; see
  [GPU draft head](#gpu-draft-head-llm-qwen-2026-10-07--disabled-2026-10-09)).
  **Four slots share one unified
  KV pool** (`parallel=4`, `kv-unified=on`, `ctx-size=1048576`), so a second
  request no longer queues behind the first. The earlier CPU-only entry and the
  separate `llm-qwen-gpu` entry were folded into this one.

**Multimodal (vision).** Qwen is `image-text-to-text`, so it accepts image and
video input once its projector loads. The `qwenVision` argument in
`hosts/brys/llm.nix` (default false) adds the `mmproj-F16.gguf` projector to the
Qwen model; the **main `brys` profile sets it true**, so image and video input
work on the normal host. Flip it false to serve text-only. The `llm-qwen` and
`llms-frontier` boot entries keep the default (text-only). The projector
downloads with the model. See
[docs/tasks/2026-10/qwen-3.8-flash-next-multimodal/](tasks/2026-10/qwen-3.8-flash-next-multimodal/definition.md).

The choice lives in `hosts/brys/llm.nix`'s `withFrontier` / `withSmall` /
`withQwen` arguments, so a host pulls in only the model family it needs.

**Why the split (measured, Phase 3):** on the ~40 GB/s bandwidth-bound box any
resident small model contends for the same memory bandwidth. Even an
*idle-but-resident* small model (phi-4, 8 GB) halves DS4 (~6.7 → ~3 t/s); an
*actively generating* small model drops DS4 to ~1.75–2.2 t/s (67–74% hit) and a
65 GB+ MoE (qwen3-coder-next) crushes it to ~0.9–1.1 t/s and evicts DS4's weight
cache (RSS 67→15 GB). Best co-tenant by far is `qwen3-30b-a3b` (fast, low
bandwidth, ~2.2 t/s DS4 hit, cache intact), but a router's
`--sleep-idle-seconds -1` pins its last resident model, so DS4 is never truly
"alone" once the small set has been touched. The only robust answer is a
separate boot entry.

### Models (all enabled on brys)

| Name | Alias | hfRepo / file | Size |
|---|---|---|---|
| `qwen3-30b-a3b` | `fast` | `Qwen/Qwen3-30B-A3B-GGUF` / `Qwen3-30B-A3B-Q4_K_M.gguf` | ~18 GB |
| `qwen3-next-80b` | `balanced` | `unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF` / `...-Q4_K_M.gguf` | ~48 GB |
| `deepseek-v4-flash` | `frontier` | `unsloth/DeepSeek-V4-Flash-GGUF` / `UD-IQ3_XXS/...-00001-of-00004.gguf` | ~103 GB (multi-shard) |
| `qwen3.8-flash-next` | `qwen`/`frontier` | `unsloth/Qwen3.8-Flash-Next-GGUF` / `UD-IQ4_XS/...-00001-of-00003.gguf` | ~94 GB (3 shards) |
| `qwen3-235b` | — | `mradermacher/Qwen3-235B-A22B-i1-GGUF` / `...IQ2_M.gguf.part1of2` | ~77 GB |
| `qwen3-coder-next` | — | `Qwen/Qwen3-Coder-Next-GGUF` / `...-Q4_K_M-00001-of-00004.gguf` | ~48 GB |
| `gpt-oss-120b` | — | `unsloth/gpt-oss-120b-GGUF` / `gpt-oss-120b-F16.gguf` | ~65 GB |
| `phi-4` | — | `microsoft/phi-4-gguf` / `phi-4-Q4_K.gguf` | ~9 GB |

Serving runs the main model on the CPU. The W6600 is unusable for the dense
weights, and its use for the Qwen MTP draft head is disabled (see below).
Per-model serving knobs on brys: `threads=16` (physical cores, SMT is counter
productive for memory-bound inference), `flash-attn=on`, `mmap=on`, and
`reasoning` (both `auto` with default effort `low`). DeepSeek
V4 Flash and Qwen3.8-Flash-Next both add `parallel=4` + `kv-unified=on`; the
other models keep `parallel=1`. Context sizes:

| Model | ctx-size | Notes |
|---|---|---|
| `deepseek-v4-flash` | 327680 (320K) | MLA; the specialisation runs 320K. See "ZFS ARC quirk" below — the old ">192K oscillates" rule was ARC churn, not the context |
| `qwen3-30b-a3b` | 131072 | |
| `qwen3-next-80b` | 131072 | |
| `qwen3-coder-next` | 131072 | |
| `qwen3-235b` | 65536 | 128K KV would exceed RAM (141 GB) |
| `phi-4` | 16384 | hard architectural ceiling |

The **main `brys` profile** uses a smaller DeepSeek context (131072) and leaves
its threads unpinned: it shares the box with the desktop. The specialisation
gets the whole machine, so it takes 320K. Both draw the rest of their config
from the shared `hosts/brys/llm.nix` (which deliberately sets no CPU affinity —
see "Prefill tuning" below).

### Client context tiers and the thinking matrix (oams)

Both brys model families are tiered **on the client side only** in
`hosts/oams/devenv.nix`. Unified KV makes the server pool usage-proportional, so
a small request is already cheap without any server flag; there is deliberately
no `--kv-unified-per-slot` cap. Instead the file declares the same model at
several practical context budgets, and one opencode subagent per (model, tier,
thinking level).

**Thinking matrix.** The common levels are `off`, `low`, `medium` and `high`.
Each level maps to that model's own `chat_template_kwargs`. Both server presets
default to `reasoning = auto` (thinking on; the template decides) with
`reasoning-effort = low`, so a request that sets no kwargs still thinks at low
effort (for DS4, whose template honours only `max`, that is thinking-on at the
template default). A client overrides both per request: opencode passes an
agent's `options` object **verbatim** into the chat-completions body (verified
with an echo server). The model entry also carries `reasoning = true`, which
tells opencode to parse the thinking output.

On the client the matrix is exposed as **model variants**
(`hosts/oams/devenv.nix`): each context tier is a `brys` model and
`off`/`low`/`medium`/`high` are its variants. The model's default is `low`, so
the tier alone thinks at low effort; in the TUI pick the tier as the model and
cycle the variant (the `variant_cycle` keybind) for another level. The same
matrix is also one opencode subagent per (tier, level), for task delegation.

| level | DS4 `deepseek-v4-flash` | Qwen `qwen3.8-flash-next` |
|---|---|---|
| `off` | `enable_thinking=false` | `enable_thinking=false` |
| `low` | `enable_thinking=true` | `enable_thinking=true`, `reasoning_effort="low"` |
| `medium` | `enable_thinking=true` | `enable_thinking=true`, `reasoning_effort="medium"` |
| `high` | `enable_thinking=true`, `reasoning_effort="max"` | `enable_thinking=true`, `reasoning_effort="xhigh"` |

DS4's template honours only `reasoning_effort = "max"`, so its `low` and
`medium` are equivalent thinking-on. Qwen's template accepts `xhigh`, `medium`
and `low` (there is no `none`), so `high` maps to `xhigh`.

**Agent naming scheme.** One subagent per (model, tier, level), named
`<prefix>-<tier>-<level>`, for example `ds4-320k-off`, `ds4-128k-high`,
`qwen-1m-off`, `qwen-256k-medium`. The prefix is `ds4` or `qwen`; every agent is
`mode = "subagent"` and names `brys/<tier-id>`. The tier is the DS4 label
(`320k`, `256k`, … `16k`) or the Qwen label (`1m`, `256k`, … `16k`).

**Provider model ids and tiers:**

| family | base model id | tier ids | contexts |
|---|---|---|---|
| DS4 | `deepseek-v4-flash` (320K) | `deepseek-v4-flash`, `deepseek-v4-flash-<n>k` | 327680, 262144, 196608, 131072, 98304, 65536, 32768, 16384 |
| Qwen | `qwen3.8-flash-next` (1M) | `qwen3.8-flash-next`, `qwen3.8-flash-next-<n>k` | 1048576, 262144, 131072, 65536, 32768, 16384 |

`output` scales with the tier (`min(8192, context/4)`) so input + output fit the
window. **16K is the smallest useful subagent tier:** opencode sends an
8.6K–10.2K-token system prompt plus tool schemas, so an 8K window cannot fit and
the request stalls (observed 2026-10-06). A 16K subagent read a file and returned
the right answer; 16K is tight, 32K is comfortable.

Every id hits the same model on brys and the same shared pool; the tier only
bounds what the client sends. The base id (320K DS4 / 1M Qwen) and the `frontier`
alias stay the default choice for a main agent.

> **The tier ids are server aliases, not a proxy fallback.** The compat-proxy
> routes an id it does not know to the frontier *upstream*, but it does not
> rewrite the id, and llama-server then rejects an unknown id with HTTP 400
> (`model '...' not found`). So a purely client-side tier cannot be routed:
> every `deepseek-v4-flash-<n>k` and `qwen3.8-flash-next-<n>k` id must be listed
> in `hosts/brys/llm.nix` as an alias of its base model. They add no KV cap and
> no memory. Thinking needs no alias at all: it is selected per request.

### ZFS ARC quirk (required for large contexts)

The model GGUFs live on ZFS (`usr/data`). ZFS's ARC is a *second* cache beside
the Linux page cache that backs the `mmap`'d weights, and its default `c_max`
is about half of RAM. On brys it grew to ~65 GB and the kernel then evicted the
mmap'd ~103 GB DeepSeek weights to make room — every request re-read them from
disk. Measured before the cap: prefill **0.18 tok/s**, 6.3M major faults,
271 GB read, and the single server slot blocked all queued requests. The
storage-side detail (the mirror, the measured NVMe throughput, and why the ARC
competes with the weights) is in
[hosts/brys/performance.md](../hosts/brys/performance.md).

`hosts/brys/llm.nix` therefore caps it, shared by both boot entries:

```nix
boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];  # 8 GiB
```

The cap is a kernel module parameter, so it only applies on a **cold boot**
(reboot into the entry; a `switch` does not apply it). To apply it live without
a reboot: `echo 8589934592 | sudo tee /sys/module/zfs/parameters/zfs_arc_max`.

With the cap the weights stay fully resident and the context is no longer the
constraint. Measured on brys, 8 GiB ARC, warm (DSpark acceptance in parens):

| ctx | DS4 RSS | RssAnon (KV) | idle major faults |
|---|---|---|---|
| 192K (old, uncapped) | ~92 GB | ~14 GB | 138/s (ARC thrash) |
| 256K | 115.7 GB | 14.6 GB | 0/s |
| 320K | 110.6 GB | 15.0 GB | 0/s |

KV is cheap for this MLA model (~0.4–1.4 GB per 64K), so RSS is dominated by
the ~101 GB of weights. Decode throughput is draft-acceptance bound: ~4.8 tok/s
at ~48% acceptance, ~8.6 tok/s at ~70%. Headroom stays ~1 GB free / ~101 GB
reclaimable, so a co-resident small-router model or a build can still evict the
weights.

#### Prefill (prompt processing) tuning

Two faults made long prompts appear hung. Both are now fixed in
`hosts/brys/llm.nix` + the slot.

1. **`--cpu-range`/`--cpu-strict` stall prefill on llama-cpp 0.4.0 (build
   10809).** In this build the affinity applies with the wrong scope: a server
   started with `--cpu-range 1-12` (pinned or not strict) never emits a prompt
   timing line at any context — decode is pinned, the prompt threadpool is not
   placed correctly and spins. Unpinned, prefill runs. So the DeepSeek perf sets
   **no** `cpuRange`/`cpuStrict`; the scheduler places the threads on the
   isolated cores itself. (Decode was unaffected, which is why only long prompts
   exposed it.)
2. **The llama default `ubatch` is 512.** Prompt processing is bandwidth-bound
   on the activated MoE expert weights; a small physical batch reuses them over
   too few tokens. `--ubatch-size`/`--batch-size` of 4096 is the single biggest
   prefill lever. Measured on brys at 320K with the DSpark draft, warm,
   cache-miss prompt (1385 tokens):

   | ubatch | prefill | wall |
   |---|---|---|
   | 512 (default) | 7.2 tok/s | 194 s |
   | 1024 | 10.2 | 137 s |
   | 2048 | 13.8 | 103 s |
   | **4096** | **15.8** | 89 s |
   | 8192 | 17.1 @128K / regresses memory | — |

   Live through the router (threads 16, ctx 320K): **15.2–16.5 tok/s**. Threads
   above 12 did not help (15 threads: 13.2). The knobs live in the slot as
   `perf.batchSize`/`perf.ubatchSize` (asserted `ubatchSize <= batchSize`) and
   are set on `deepseek-v4-flash` only.

Identical repeat prompts hit llama's prefix cache and return in ~1–2 s, so
always benchmark with a fresh, cache-missing prompt.

### Freeing RAM when colocating a model with a workstation

The main `brys` profile shares the box with the desktop. The boot
specialisations (`llm-ds4`, `llm-qwen`, `llms-frontier`) do not: the selected
model owns the whole machine. A colocated model must return RAM to the desktop,
so it needs other defaults than a dedicated appliance. This section collects the
tested RAM levers.

The numbers are from brys with Qwen3.8-Flash-Next `UD-IQ4_XS` (93.7 GB), unless
a row says otherwise. **brys** means a measured brys experiment. **general**
means the effect follows from the mechanism and was not timed on brys.

| lever | effect on RAM | trade-off | source |
|---|---|---|---|
| `--lazy-mode auto` (default) | offloads the PLE / n-gram table and other large tensors to SSD; `off` → `auto` freed **~46 GB** (`RssFile` 92.2 → 46.0 GB) | none measured; decode rose slightly (11.14 → 12.26 t/s). `on` is identical to `auto` here | brys |
| context size | the direct KV-RAM knob; Qwen 1M → 512K F16 KV freed **~16 GB** (`RssAnon` 35.7 → 19.9 GB) | a shorter window; keep ≥512K for the current workload | brys |
| `-ctk q8_0 -ctv q8_0` | halves KV (1M: ~24 → ~12 GiB); at 512K `RssAnon` 19.9 → 13.1 GB | decode is slightly slower (~8.49 → ~7.9 t/s) | brys |
| `--cache-ram` (default 8192 MiB) | lower it to shrink the prompt cache; `1024` frees RAM. The Qwen entries raise it to **36864** (37 GiB) instead, to stop the constant evictions of the ~5.7 GiB entries | decode is slightly slower (~7.9 t/s at 512K q8_0); a full 37 GiB cache evicts weight pages | brys |
| `parallel` (slots) | `4` → `1` frees a few GB of per-slot state | loses concurrency; head-of-line blocking returns | brys |
| MTP draft on the GPU | moves the ~4–6 GB draft head to VRAM, off system RAM | needs a GPU; speeds decode | general |
| smaller quant | `UD-IQ3_XXS` (82 GB) vs `UD-IQ4_XS` (93.7 GB) frees **~12 GB** | a quality drop (85.4% vs 89.6% top-1) | brys |
| `mmap` + 8 GiB ZFS ARC cap | weights stay file-backed and reclaimable; the cap stops ZFS from holding a second copy | none for serving; see the [ZFS ARC quirk](#zfs-arc-quirk-required-for-large-contexts) | brys |

Notes on the table:

- **`--lazy-mode` is the biggest lever and is already the default.** Do not set
  `off` on a colocated host: it makes the large tensors resident and costs about
  46 GB for no throughput gain. The served behaviour already keeps them on SSD.
  The full table is in "`--lazy-mode` SSD offload (brys)" below.
- **Context and KV quantisation are the two direct controls.** Lower the context
  first; add `q8_0` KV only if the context is already at its floor.
- **The prompt cache is a separate ceiling, not the KV cache.** `--cache-ram`
  (default 8192 MiB) bounds the cross-request prompt cache; when it fills,
  llama-server evicts the oldest entry (the `making room for prompt cache
  entry` log line). One long Qwen prompt is ~5.7 GiB, so the default held
  barely one and evicted constantly. The Qwen entries (`llm-qwen`,
  `llms-frontier`) set `perf.cacheRam = 36864` (37 GiB). The cache grows on
  demand, so the value is a ceiling, not an allocation; a full one still leaves
  ~8 GiB `MemAvailable` on the 125 GiB box.
- **Keep `mmap`; do not use `--load-mode mlock`.** mlock pins the weights and
  defeats reclaim. With `mmap`, the kernel reclaims weight pages under memory
  pressure, so a colocated model slows down instead of OOM. The 8 GiB ZFS ARC cap
  stops ZFS from holding a second copy of the same data (see the
  [ZFS ARC quirk](#zfs-arc-quirk-required-for-large-contexts)).
- **`parallel 4` is cheap.** It adds only about 3 GB over `parallel 1`, because
  the pool is unified. Keep it when concurrency matters. See the
  [Concurrency](#concurrency-2026-10-07) section below.
- **The old `q8_0` warning does not hold here.** The claim that `q8_0` is buggy
  for `qwen4exp` does not reproduce on llama.cpp v0.6.0: no assertion and no
  loop.

**Tested and rejected.** `--no-mmap-prefetch` (upstream PR #29250) and a newer
master build gave no RAM or throughput win. `--load-mode none` OOMs the W6600.
See "The first-request stall" below. Expert streaming (`--moe-stream`, upstream
PR #25294) also loses: it cuts RSS to ~41 GiB but drops prefill by 65% and decode
by 34%, because the model is ~75% resident and O_DIRECT bypasses the page cache
that serves it. See "Expert-streaming experiments (negative)" in
[packages/llama-cpp/README.md](packages/llama-cpp/README.md).

**General principle.** For colocation, prefer `mmap` + `--lazy-mode auto` + a
modest context, and optionally `q8_0` KV. Accept a slower first token and a
slower decode under memory pressure: the kernel reclaims the file-backed weight
pages, so the model degrades instead of failing. For maximum speed, use a
dedicated boot specialisation, where the model owns the RAM.

Related work: [qwen-flash-next-quant](tasks/2026-10/qwen-flash-next-quant/),
[qwen-3.8-flash-next-multimodal](tasks/2026-10/qwen-3.8-flash-next-multimodal/),
[qwen-gpu-offload](tasks/2026-10/qwen-gpu-offload/), and
[llm-unified-kv-parallelism](tasks/2026-10/llm-unified-kv-parallelism/). The
hardware side is in [hosts/brys/performance.md](../hosts/brys/performance.md).

### Download configuration on brys

- **Service:** `kdn-llm-download` — sequential, one model at a time.
- **Mode:** `fast-polite` — Xet enabled with low pinned concurrency (Tier 1
  mitigation), so downloads are faster than `"slow"` while staying gentle on
  the shared link. Runs directly in the host network namespace.
- **Token:** `HF_TOKEN` via systemd `LoadCredential` from
  `/run/configs/llms/huggingface/token` (wired through sops-nix).

### Persistence

Model files live at `/var/lib/kdn/llms/models`, registered under
`kdn.disks.persist."usr/data"` (ZFS `usr/data` dataset) so they survive
reboots.

### Disk session cache (Qwen)

The Qwen specialisations keep each conversation's KV state on disk, keyed by a
client session id. A request that carries the id resumes from its saved state
instead of re-prefilling the whole prompt, and the state survives a server
restart. This needs the `llama-cpp-sessions` build
(`packages/llama-cpp`), which carries upstream #26004 (checkpoint persistence)
plus the rebased PR #29738 (session-keyed save/restore).

- **Store:** `/var/lib/kdn/llms/sessions`, persisted under
  `kdn.disks.persist."usr/cache"` with mode `0770` and group
  `llama-cpp-sessions`. The llama-cpp DynamicUser joins that group. The files
  hold plaintext prompt tokens and KV, so the directory must not be
  world-readable.
- **Server flags** (per model, emitted by the slot): `slot-save-path`,
  `slot-save-sessions = x-session-id`, `slot-save-sessions-max = 64`,
  `ctx-checkpoints = 32`, `checkpoint-min-step = 10500`.
- **Client:** the `kdn.llm.client` slot writes an opencode plugin
  (`.opencode/plugins/kdn-llm-session-id.ts`) that sends `x-session-id` for the
  LAN provider ids.
- **Prune:** the `kdn-llm-session-prune` timer (every 15 min) deletes files
  older than 24 h and, if the store is over 200 GB, the oldest first. Upstream
  `--slot-save-sessions-max` is a separate count bound applied at startup.
- **Sizes** (measured 2026-10-09): the GDN recurrent state is ~112 MiB, and a
  checkpoint is the recurrent state only, so each checkpoint is ~112 MiB. A
  65-token session file is 356 MB (~114 MB base + 2 checkpoints). For a long
  session the attention KV (24 KiB/token at F16) becomes the larger term.
  `ctx-checkpoints 32` bounds the checkpoint RAM at ~14 GiB over four slots,
  which is why `perf.cacheRam` is 16384 MiB, not 36864.

See [llm-session-cache-persistence](tasks/2026-10/llm-session-cache-persistence/)
for the full record.

### Model auto-discovery (client)

`kdn.llm.client.upstreams.<name>.discovery.enable = true` stops the aspect from
writing a hand-listed `models` block into the opencode provider. Instead the
aspect writes a local pinned plugin (`.opencode/plugins/kdn-models-discovery.ts`)
that runs the opencode `config` hook, fetches `<baseURL>/models` (the
OpenAI-compatible model list; `discovery.url` overrides the path) and merges
every discovered id into `provider.<name>.models`. A discovered id that is not
hand-listed gets a minimal entry (its id as the name); a hand-listed id keeps its
entry, so the configured `models` become a per-model **metadata overlay**
(context, output, reasoning, options, variants) applied on top of the discovered
list. A fetch failure leaves the static overlay in place, so the shell still
works offline.

The plugin is a local `.ts` file written into `.opencode/plugins/`, so it is
**pinned by this repo's commit** — no npm fetch, no `@latest`, no network at
startup for the plugin itself. A local plugin is needed because opencode 1.19.0
(the nixpkgs pin) has no native `/v1/models` discovery; that lives on the
unmerged 2.0 line. The `config` hook (`@opencode-ai/plugin`) is the verified
extension point. See [the `llm-client` aspect](../modules/den/aspects/llm-client.nix).

### Secrets

All LLM secrets live in one shared sops file (`llms.nonsensitive.sops.yaml`) and
are mounted at `/run/configs/llms` on both **brys** and **oams** via the same
`kdn.security.secrets.sops.files."llms"` entry (basePath `/run/configs/llms`,
no keyPrefix). The sops tree maps to files directly:

- `huggingface.token` → `/run/configs/llms/huggingface/token` (HF download token)
- `certs/public.key` → `/run/configs/llms/certs/public.key` (self-signed Caddy cert)
- `certs/private.key` → `/run/configs/llms/certs/private.key`
- `llama-server/api-keys/default` → `/run/configs/llms/llama-server/api-keys/default`
  (one API key; further keys are added the same way, each its own file)

The certificate is pre-generated once (openssl EC P-256, SAN
`brys.lan.etra.net.int.kdn.im`, 10 years) and stored in the sops file — there
is no cert-generation logic in the module system.

### Status / known state

- `qwen3-30b-a3b` and `qwen3-next-80b` were fully downloaded and verified on
  the 2026-08-29 smoke test.
- `deepseek-v4-flash` is fully downloaded (all four `UD-IQ3_XXS` shards
  present; `00001-of-00004` is legitimately ~5 MB — it is the split descriptor
  that llama mmap-links to the large shards `02/03/04` for the full ~103 GB
  weights). The model also uses the DSpark drafter
  (`dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf`, ~10.9 GB) for speculative
  decoding; both fetch through `kdn-llm-download`.
- Go-to status command: `kdn-llm-status`.

### Hardware and performance

The box hardware, the ZFS mirror and the ARC cap, the measured memory bandwidth,
and the per-model resident footprints are in
[hosts/brys/performance.md](../hosts/brys/performance.md).

### `--lazy-mode` SSD offload (brys)

The v0.6.0 Vulkan build has
`--lazy-mode {on,auto,off}`; the default is `auto` (on for tensors larger than
4 GiB). A manual server at ctx 524288 (YaRN x2), `parallel 4`, `kv-unified`,
F16 KV, threads 16, MTP `draft-mtp` n-max 5, `--load-mode mmap`, on the W6600:

| `--lazy-mode` | idle VmRSS | RssFile | RssAnon | prefill 1.7K tok | decode 128 tok warm |
|---|---|---|---|---|---|
| `off` | 111.2 GB | 92.2 GB | 19.1 GB | 19.70 t/s | 11.14 t/s |
| `auto` (default) | 65.0 GB | 46.0 GB | 19.1 GB | 19.20 t/s | 12.26 t/s |
| `on` | 65.0 GB | 46.0 GB | 19.1 GB | 19.19 t/s | 12.69 t/s |

`auto` and `on` are identical: the default already offloads the same tensors,
so the served behaviour already keeps the lazy tensors on SSD. Forcing
`--lazy-mode off` makes them resident and costs **about 46 GB of RAM** for no
throughput gain (prefill unchanged; decode flat to slightly lower). The
offloaded set is larger than the ~28.8 GB PLE / n-gram table estimate, so
`--lazy-mode` covers other large tensors too. Under load the `on` resident set
grows (idle 65.0 GB to 82.7 GB after a 1.7K prefill and 256 decode tokens),
still well below the 111 GB fully-resident case. This corrects the earlier note
that the n-gram table "stays resident (no `--lazy-mode`)".

**ngram verdict.** `--spec-type ngram-mod` alone hung `qwen4exp` (about 13
cores stuck for an hour, below 1 tok/s). Rejected. MTP (`draft-mtp`) stays the
speculative path.

**Server logs.** A manual one-off `llama-server` run should pass
`--log-file <path>`, so its output stays inspectable after the run. The running
service logs to journald: `journalctl -u llama-cpp`.

### Qwen3.8-Flash-Next on brys (2026-10-06)

`Qwen/Qwen3.8-Flash-Next` (`Qwen4ExpForConditionalGeneration`, `model_type
qwen4_exp`) is a very sparse hybrid model. It has 48 layers, but only every 4th
layer is full attention (12 of 48); the other layers use GDN linear attention.
It has 2 KV heads, `head_dim` 256, and 512 experts with 10 active per token plus
one shared expert. The weight shards also hold a 51B n-gram embedding table.

First served build: **llama.cpp 0.4.0 (build 10809, commit `5266f24`)**. The
build carries `llama_model_qwen4exp`, so the model loads. The build does **not**
carry the `qwen4exp` MTP graph (no `graph_mtp` symbol), so the Unsloth MTP draft
heads do not work here. The Unsloth MTP README states that stock mainline needs
PR #28243 or their fork.

**MTP build (2026-10-07):** the `llm-qwen` entry selects the in-repo
`pkgs.kdn.llama-cpp-v0_6_0` build (ggml-org v0.6.0, build 11429). That build
holds the `qwen4exp` MTP graph, so MTP is on: `spec-type = draft-mtp` with the
self-contained draft `MTP/mtp-Qwen3.8-Flash-Next-Q8_0.gguf` and
`spec-draft-n-max 2`. The Unsloth fork also holds the graph. v0.6.0 is the
deployed package because it carries the long-context QSA indexer memory and mask
fixes that the fork lacks. See
[packages/llama-cpp/README.md](../packages/llama-cpp/README.md) for the two
derivations and their update steps.

**MTP disabled (2026-10-11):** `qwenMtp` is off on brys. The 2026-10-07
benchmark ran warm at 128K with a 300-token decode and measured acceptance
1.000, so MTP gave +68% decode (5.65 -> 9.5 t/s). At the served long-context
config the draft head accepted only ~0.42 of drafts (mean len 3.11,
`--spec-draft-n-max 5`, observed over many turns on `llms-frontier`), so the
speculation overhead no longer repaid its cost. The implementation stays
(`qwenMtp`, `qwenSpecDraftNMax`/`PMin`/`Prio` and the `MTP/…-Q8_0.gguf` draft
entry in `hosts/brys/llm.nix`); only the switch is false. Re-enable by setting
`qwenMtp = true` in `hosts/brys/llm-qwen.nix` and `hosts/brys/llms-frontier.nix`.

A session file written under MTP-on cannot be restored under MTP-off: the
server logs `state_read_data: incompatible key rotation (0 instead of 256)` and
`failed to restore kv cache`, then starts that session fresh. This is one-time
per stale file; the next save under MTP-off is compatible.

The MTP builds dropped `--mmap`. They have only `--load-mode`, and the router
rejects the `mmap` preset key at startup. `hosts/brys/llm.nix` therefore sets
`perf.mmap = null` for Qwen, which omits the key. The default load mode is mmap,
so the served behaviour does not change.

Chosen quant: **`unsloth/Qwen3.8-Flash-Next-GGUF` `UD-IQ4_XS`**, 3 shards,
93.7 GB total (10,946,624 + 49,835,229,856 + 43,836,407,744 bytes). The shards
keep the n-gram table inside the weights. The download took ~22 min. The hybrid
attention makes KV tiny for this model, so IQ4_XS fits under the 8 GiB ARC cap
with room to spare. `UD-Q4_K_XL` is ~10 GB bigger and tight.

Deployed config (`hosts/brys/llm-qwen.nix`): ctx-size 1048576 (1M), YaRN x4
(`rope-scale` 4.0, `rope-freq-base` 10000000, `yarn-orig-ctx` 262144),
batch-size 4096, ubatch-size 4096, parallel 4 with unified KV, threads 16,
flash-attn on, reasoning auto (effort low), KV type F16. Aliases `qwen` and
`frontier`. The
MTP builds need `perf.mmap = null` (see the MTP build paragraph above).
The server reports `n_slots = 4`, `n_ctx_slot = 1048576`, `kv_unified = 'true'`,
and a 16-thread pool.

The slot gained the long-context options that this config uses:
`perf.ropeScaling` (none/linear/yarn), `perf.ropeScale`, `perf.ropeFreqBase`,
`perf.yarnOrigCtx`, and the KV-quantisation fallback `perf.cacheTypeK` /
`perf.cacheTypeV`. `hosts/brys/llm.nix` exposes them as the `qwenRopeScaling`,
`qwenRopeScale`, `qwenRopeFreqBase`, `qwenYarnOrigCtx` and `qwenCacheTypeK` /
`qwenCacheTypeV` arguments.

### Concurrency (2026-10-07)

The deployed `llm-qwen` entry runs **4 slots on one unified KV pool**
(`parallel = 4`, `kvUnified = true`), the same shape as DS4. The server logs
`n_slots = 4, n_ctx_slot = 1048576, kv_unified = 'true'`.

The old Kagi-thread claim that the QSA indexer cache is single-slot only is
**false** for the pinned llama.cpp v0.6.0 (commit `d812350`). The QSA indexer
cache is a per-slot side buffer over the attention cells, built with the same
`n_seq_max` / `unified` / `kv_size` as the cells:
`src/llama-memory-hybrid-idx.h:14-15`,
`src/llama-memory-hybrid-idx.cpp:70-73`, and
`src/llama-model.cpp:2481-2493` (`n_seq_max = cparams.n_seq_max`, no cap). The
MTP draft is multi-sequence too (`common/speculative.cpp`).

With `--kv-unified`, `src/llama-context.cpp:294-297` sets `n_ctx_seq = n_ctx`,
so the total cell count is `n_ctx` regardless of `parallel`. `parallel` never
multiplies KV RAM.

**Measured:** a short request returned in **2.4-4.6 s** while a 400-token
request was in flight. At `parallel = 1` the same short request **waited 51.5 s**
(serialised). Concurrency now matches DS4.

**Single-request throughput is unchanged:** counting-300 decode 14.16 t/s at
`parallel 4` vs 13.44 at `parallel 1`; prose-300 4.97 t/s (acceptance-bound);
prefill ~22.4 vs 18.0 t/s. Memory: `VmRSS` ~101 GB, `RssAnon` ~37.5 GB (only
~3 GB more than `parallel 1` — the shared pool), `VmSwap` 0, no OOM.

#### Parallelism ceiling (2026-10-07)

Both entries keep `parallel = 4`. A sweep on brys, same harness, warm, shows that
higher parallelism does not help either model. Both are bandwidth-bound sparse
MoE: concurrent sequences widen the activated-expert union, so aggregate
throughput stays near the single-request ceiling.

Qwen3.8-Flash-Next (`llm-qwen`, 1M ctx, YaRN x4, MTP on the W6600, unified KV):

| p | single decode t/s | agg t/s C=4 | agg t/s C=8 | VmRSS / RssAnon / RssFile | errors |
|---|---|---|---|---|---|
| 4 | 9.29-9.35 | 2.01 | 1.65 | ~98-101 / ~37-39 / ~60-61 GB | none |
| 8 | 7.84 | 1.34 | pathological (>40 min, 0.05 t/s) | 81 / 42.9 / 38.1 GB | none |
| 16 | 4.24 | timeout 180 s | timeout | 98.8 / 44.8 / 54.0 GB | none |
| 32 | — | — | — | — | `ggml_abort` at load, HTTP 500 |

DS4 (`llm-ds4`, 320K, DSpark draft on the CPU, unified KV):

| p | single decode t/s | agg t/s C=4 | agg t/s C=8 | VmRSS / RssAnon / RssFile |
|---|---|---|---|---|
| 4 | 5.10 | 2.80 | 2.11 | 119 / 24.3 / 94.9 GB |
| 8 | 4.17 | 2.21 | timeout 900 s | 118.8 / 36.5 / 82.4 GB (3971 faults/5 s) |

Findings:

- `parallel = 4` is the sweet spot for both. Higher values hurt.
- Qwen scales worse than DS4 (aggregate/single 0.21 vs 0.55). At 1M context only
  about 60 GB of the 94 GB weights stays resident, and each extra slot's
  anonymous state evicts more weights (`RssFile` 60 to 38 GB at p=8). DS4 keeps
  94.9 of 103 GB resident.
- The Qwen `parallel = 4` aggregate is flat across concurrency: C=1 6.4, C=2 3.9,
  C=3 6.15, C=4 6.08 t/s.
- **Multi-sequence prefill is pathological on this build.** At Qwen p=4, C=4, a
  22-token prefill took 75.8 s against 3.1 s at C=2. Staggering the starts
  restored the aggregate to about 6.08 t/s, near the single-request rate. A
  single long prompt is fine: 6,211 tokens at 29.87 t/s under the shared 1M pool.
- No config change resulted. Both entries stay at `parallel = 4`.

### GPU draft head (`llm-qwen`, 2026-10-07) — DISABLED 2026-10-09

> ⚠️ **The W6600 Vulkan draft head is disabled on brys.** It hard-hangs under the
> Qwen workload: at ~40.6K tokens of context the amdgpu compute ring
> (`comp_1.2.0`) times out and the kernel resets it ("device wedged, but
> recovered through reset"), but the radv Vulkan context is lost, so every later
> decode fails instantly with `vk::Queue::submit: ErrorDeviceLost`. llama-server
> sends an error mid-stream and OpenCode closes the turn with an empty assistant
> message — the session "stops without answering" until the server is restarted.
> The gain was only ~18% decode (10.82 vs ~9.1 t/s), so both Qwen specialisations
> set `qwenVulkan = false` and run the MTP draft head on the CPU (`qwenGpu = true`
> still selects the MTP-capable v0.6.0 build). Do not re-enable without a
> driver/firmware fix. The history below is kept for the record.

The `llm-qwen` entry ran the Qwen shape on the Vulkan build
(`pkgs.kdn.llama-cpp-v0_6_0-vulkan`) with the MTP draft head on the Radeon Pro
W6600. `hardware.graphics.enable = true` + `hardware.graphics.extraPackages =
[ pkgs.mesa ]` expose the RADV ICD, and `MESA_VK_DEVICE_SELECT=1002:73e3!` (plus
the preset key `device = Vulkan0`) pin the W6600 and never the 4 GB Lexa.

This started as a separate `llm-qwen-gpu` boot entry beside a CPU-only
`llm-qwen`; once the GPU draft head proved the only winning variant, the two
were folded into the single canonical `llm-qwen` entry (the CPU-only entry
dropped).

The intended dense-layer offload (`-ngl 99 -cmoe -nkvo`) is **slower**: at 1M
context the 24 GiB F16 KV must stay on the CPU, so every attention step crosses
PCIe and decode falls to 2.0 t/s. Partial `-ngl` (8/20/40) is also slower than
the CPU (5.0-5.9 t/s). The only win is offloading the ~6 GB draft head: the main
model and KV stay in RAM, decode rises to **10.82 t/s** (from 9.13 on the same
prompt). See [docs/tasks/2026-10/qwen-gpu-offload/done.md](tasks/2026-10/qwen-gpu-offload/done.md).

The slot and den aspect gained the knobs `perf.nGpuLayers`, `perf.cpuMoe`,
`perf.noKvOffload`, `perf.draftNGpuLayers` and `perf.device`; `hosts/brys/llm.nix`
exposes them as `qwenNGpuLayers`, `qwenCpuMoe`, `qwenNoKvOffload`,
`qwenDraftNGpuLayers` and `qwenDevice`.

### MTP draft tuning (2026-10-07)

MTP draft depth is the `spec-draft-n-max` value (the maximum draft tokens per
step). The first MTP build used `n-max 2`. A sweep at 1M context (v0.6.0, MTP on,
F16 KV, parallel 1 pre-concurrency, threads 16, two prompts, 300 tokens, temp 0,
warm second run) shows that deeper drafts help until acceptance falls.
"Realistic" is a Python merge-function prompt; "control" is a plain count from
1 to 300.

| n-max | realistic decode t/s | realistic accept / mean len | control decode t/s | control accept |
|---|---|---|---|---|
| 1 | 8.13 | 0.980 / 1.98 | 8.15 | 1.000 |
| 2 (old default) | 8.90 | 0.919 / 2.84 | 9.28 | 1.000 |
| 3 | 10.42 | 0.893 / 3.68 | 11.38 | 1.000 |
| **5 (chosen)** | **11.18** | 0.858 / 5.25 | 12.92 | 1.000 |
| 8 | 8.86 | 0.711 / 6.64 | 13.72 | 1.000 |

`n-max 5` is the best realistic decode (11.18 t/s). `n-max 8` raises control
throughput (13.72 t/s) but regresses the realistic prompt: acceptance falls to
0.711, so the draft overhead dominates. The chosen value is
`qwenSpecDraftNMax = 5`.

Two more knobs were tested and kept null:

- `spec-draft-prio = 2` made no difference (11.09 vs 11.18 t/s, noise).
- `spec-draft-p-min` 0.5/0.8 raised acceptance (0.886/0.908) but lowered the mean
  accepted length (5.16/4.95), so net throughput was flat or worse.

**Bug fix.** `modules/slots/llm/default.nix` emitted `spec-draft-p-min` without
`toString`, so a float value failed Nix evaluation (`cannot coerce a float to a
string`). It now reads `${toString perf.specDraftPMin}`.
`modules/den/aspects/llm.nix` already had the `toString`, so it did not change.

The new `hosts/brys/llm.nix` arguments are `qwenSpecDraftNMax`,
`qwenSpecDraftPMin` and `qwenSpecDraftPrio`. `hosts/brys/llm-qwen.nix` sets
`qwenSpecDraftNMax = 5`; p-min and prio stay null.

### Long-context ladder (2026-10-07)

The model GGUF declares `n_ctx_train = 262144` (256K) and no rope scaling, so a
context above 256K needs the YaRN flags. Measured on brys with MTP on, parallel
1 pre-concurrency, threads 16, F16 KV, ZFS ARC 8 GiB:

| ctx | rope | KV | RssFile | RssAnon | RSS | free available | idle maj_fault/s | prefill t/s | decode t/s | coherence | OOM |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 262144 | none | F16 | 59.7 GiB | 31.8 GiB | 91.4 GiB | 81 GB | 0 | 30.6 | 7.51 | 17*23=391, Paris OK | no |
| 524288 | yarn x2 | F16 | 59.7 GiB | 40.0 GiB | 99.7 GiB | 73 GB | 0 | 29.3 | 7.58 | OK | no |
| 1048576 | yarn x4 | F16 | 59.7 GiB | 56.4 GiB | 116.0 GiB | 60 GB | 0 | 30.8 | 9.3 steady | 391, Paris, bat+ball=$0.10 OK | no |

KV is 24 KiB/token at F16 (12 full-attention layers x 2 KV heads x 256 head_dim
x 2 x 2 bytes), so 6/12/24 GiB at 256K/512K/1M. F16 KV fits at 1M, so the q8_0
fallback (`perf.cacheTypeK`/`perf.cacheTypeV`) stays untested. 1M leaves only
about 1-2 GiB free (about 60 GB reclaimable page cache). The KV is pre-allocated
at load, so idle serving is stable. A large concurrent allocation, for example a
nix build, can evict the mmap'd weights. Static YaRN did not degrade the
short-context probes.

### 128K baseline (2026-10-06)

Measured on brys, cold-booted into `llm-qwen`, model warm, before the long-context
work:

- cold model load ~90 s.
- prefill: 20.1 tok/s at ubatch 1024 (964 tokens / 47.9 s); **39.9 tok/s** at
  ubatch 4096 (run 1: 3425 tok / 85.7 s = 39.95; run 2: 3430 tok / 85.9 s =
  39.91). The ubatch lever gives the same ~2x gain as on DeepSeek.
- decode: 300 tokens at 4.75 tok/s (predicted_ms 62985). Earlier short samples
  read 3.3-5.5 tok/s (36 tokens).
- warm prefix-cache repeat: ~1-6.6 s wall.
- residency: `VmRSS` ~86 GB (`RssFile` ~58 GB, `RssAnon` ~28 GB), `VmSwap` 0,
  `free -g` available ~87 GB, **0 idle major faults/s**, no OOM in the kernel
  log.

**MTP result (2026-10-07, warm, 300-token decode):** the MTP draft raised decode
from **5.65 to about 9.5 tok/s (+68%)**, at a mean accepted length of 2.99 and
an acceptance of 1.000. The upstream v0.6.0 build and the Unsloth fork are
within about 1-4% of each other, which is noise. v0.6.0 without MTP is within
noise of the 0.4.0 baseline. The full table is in
[docs/tasks/2026-10/llama-cpp-latest-package/definition.md](tasks/2026-10/llama-cpp-latest-package/definition.md).

For reference, DeepSeek V4 Flash does 15.2-16.5 tok/s prefill and ~5-8.6 tok/s
decode. So Qwen prefill is ~2.4x DeepSeek, and Qwen decode is slightly lower.
The Kagi thread gives a 128K-200K context range; brys now serves 1M with YaRN x4
(see the long-context ladder above).

On **warm long coding tasks** (1500-2000-token generations) the decode order
reverses: **Qwen is ~2.5-3x faster than DS4**. See "Warm long-task decode (Qwen
vs DS4)" in [hosts/brys/performance.md](../hosts/brys/performance.md).

### Benchmark result log (append-only)

Each row records a config tweak, the resulting server-side `print_timing`
eval tok/s on DS4 (warm), and the model load time. New results are appended
at the bottom.

| timestamp | tweak | server eval tok/s | ms/tok | vs prev | client tok/s | load time | note |
|---|---|---|---|---|---|---|---|
| 2026-09-05 19:41 | baseline (isolcpus=1-15, threads=16, no cpu-range) | 2.28 | 439 | — | 0.30 | ~1:40 | page-cache cold/churned |
| 2026-09-05 20:03 | `cpu-range=1-15` + `cpu-strict=1` + `threads=15` | 2.33 | 428 | 0.05 (==) | 0.31 | 1:45 (19:53:20 → 19:55:05) | still cold |
| 2026-09-05 20:07 | cpu-range same config, run 1 | 3.92 | 255 | ↑ | 0.53 | warm | page cache recovering |
| 2026-09-05 20:08 | cpu-range same config, run 2 | **5.75** | 174 | ↑ | 0.78 | warm | fully warm → matches 6.5-6.7 baseline |
| 2026-09-05 20:21 | `transparent_hugepage=always` (reboot), run 1 | 5.03 | 199 | — | 0.34 | cold | still warming |
| 2026-09-05 20:22 | `transparent_hugepage=always`, run 2 (warm) | 6.37 | 157 | ≈ | 0.82 | warm | no change vs madvise (THP no-op on file mmaps) |
| 2026-09-05 20:39 | `cpu-range` + `specDraftNMax=4` + `specDraftPrio=2`, run 1 | 3.21 | 312 | ↓ | 0.44 | warm | mean len↑3.95 but still warming |
| 2026-09-05 20:41 | cpu-range + n_max=4 + prio=2, run 2 (warm) | **4.39** | 228 | **↓ regression** | 0.58 | warm | draft mean len 3.62, acceptance 0.66; HIGHER n_max slower on CPU (matches rohitraj) → REVERT |
| 2026-09-05 20:50 | revert: cpu-range, DSpark defaults + madvise (reboot), run 1 | 6.21 | 161 | ↑ | 0.41 | cold→warm | confirms revert |
| 2026-09-05 20:51 | revert confirmed, run 2 (warm) | **6.91** | 145 | ↑↑ NEW BEST | 0.89 | warm | ~86% of ~8 t/s ceiling; DSpark n_max+prio was the regression |
| 2026-09-06 00:15 | session control (loopback router, threads=15, re-warm) | 6.41 | 156 | ≈ | 6.39 | warm | harness validated; client==server tok/s |
| 2026-09-06 00:2x | EXPERIMENT 1: `load-mode=mlock` + LimitMEMLOCK=inf (reboot) run a | 7.20 | 139 | ≈ NEW warm peak | 7.17 | warm | mlock DID NOT materialize: 0 bytes locked (ENOMEM on 101 GB; mmap conflict) → effectively control |
| 2026-09-06 00:2x | EXPERIMENT 1 (mlock), run b | 7.04 | 142 | ≈ | 7.01 | warm | confirms mlock null; \~90% of \~8 t/s ceiling |
| 2026-09-06 01:0x | EXPERIMENT 2: threads 15→12, cpu-range 1-12 (reboot) r1/2/3 | 6.89/6.88/6.91 | 145 | == | 6.86/6.84/6.88 | warm | dead-flat; bandwidth already saturated at ≤12 cores → no change |
| 2026-09-06 01:1x | EXPERIMENT 3: `--poll 100` + `--spec-draft-prio 2` (manual server) | (5.79-5.93 client) | — | — | 5.79/5.93 | warm | INCONCLUSIVE: manual harness unreliable/thrashing on loaded box; not attributed |
| 2026-09-06 01:3x | EXPERIMENT 4: `vm.vfs_cache_pressure` 50→10 (runtime) | 3.11 | 319 | ↓/worse | 3.11 | warm-ish | cache stayed ~50 GB → weights NOT resident; physical RAM capacity is the binding constraint, not reclaim policy |
| 2026-09-06 02:0x | EXPERIMENT A: ctx 262144→131072 (reboot), warm runs 1-4 / converged | 6.65/6.61/6.68/6.85 → **6.78** | 147 | ≈ (stable) | 7.05/6.62/6.58/6.85 | warm | weights resident throughout (buff/cache ~103-104 GB stable, no 2-4 collapse); halving KV freed headroom → ROBUSTNESS, not higher peak |
| 2026-09-06 02:3x | EXPERIMENT B: memcg-v2 cap (runtime, competing allocator) — unprotected | 5.28 | 189 | ↓ | 5.27 | warm | default-cgroup `stress-ng --vm-bytes 18G` evicted ~18 GB weights (buff/cache 103→85) → collapse |
| 2026-09-06 02:3x | EXPERIMENT B: memcg-v2 cap (runtime) — same allocator under `MemoryMax=4G` scope | **6.49** | 154 | ↑ PROTECTED | 6.49 | warm | competitor memcg-OOM-killed in its own scope; weights stayed resident; serving stayed fast → cgroup cap IS the robustness mechanism |
| 2026-09-06 03:0x | EXPERIMENT C: ik_llama.cpp fork swap | — | — | SKIP | — | — | not drop-in (no router mode, no `--cpu-range`); bandwidth-bound → no peak upside; DSpark syntax differs. Packaging easy (own flake) but moot. Kept upstream llama.cpp |
| 2026-10-06 12:4x | unified KV: `parallel 4` + `kv-unified on`, ctx 327680 (cold boot `llm-ds4` gen 652) | 2.22 | 451 | — | — | ~3:16 (first load) | **concurrency confirmed**: a short request (8 tok) returned in **3.7 s** while a 256-token request was in flight (121.8 s) — no head-of-line blocking; server logged `n_slots = 4, n_ctx_slot = 327680, kv_unified = 'true'`; DS4 `RssFile` 92.6 GB, **0 idle major faults**, no OOM; DSpark acceptance 0.44 at `parallel 4` (draft still works) |
| 2026-10-06 | **Qwen3.8-Flash-Next** UD-IQ4_XS, ubatch/batch 1024 (baseline) | 20.1 (prefill) | — | — | — | ~90 s (cold) | model warm on `llm-qwen`; 964 tok / 47.9 s; this row is Qwen, not DS4 |
| 2026-10-06 | **Qwen3.8-Flash-Next** UD-IQ4_XS, ubatch/batch 4096 | **39.9 (prefill)** | — | ~2x | — | ~90 s (cold) | run 1: 3425 tok / 85.7 s = 39.95; run 2: 3430 tok / 85.9 s = 39.91; decode 300 tok at 4.75 t/s; VmRSS ~86 GB, 0 idle major faults; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen3.8-Flash-Next** + llama.cpp **0.4.0 b10809** (control), no MTP | 5.65 | — | — | — | warm | decode 300 tok; prefill 36.6 t/s; RSS 82.3 GiB; 0 idle major faults; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen3.8-Flash-Next** + llama.cpp **0.6.0 b11429** (config A), no MTP | 5.81 | — | vs 0.4.0 ≈ | — | warm | decode 300 tok; prefill 37.7 t/s; RSS 81.3 GiB; 0 idle major faults; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen3.8-Flash-Next** + llama.cpp **0.6.0 b11429** (config B), MTP on | **9.50** | — | +68% | — | warm | decode 300 tok; prefill 35.2 t/s; MTP acceptance 1.000, mean len 2.99; RSS 87.8 GiB; 0 idle major faults; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen3.8-Flash-Next** + llama.cpp **unsloth b11098** (config C), MTP on | **9.56** | — | +69% (≈ B) | — | warm | decode 300 tok; prefill 36.8 t/s; MTP acceptance 1.000, mean len 2.99; RSS 86.6 GiB; 0 idle major faults; short-context fork result, not deployed; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen3.8-Flash-Next** + v0.6.0 b11429, MTP on, ctx 262144 (ladder) | 30.6 (prefill) | — | — | — | warm | decode 7.51 t/s; RssFile 59.7 GiB, RssAnon 31.8 GiB, RSS 91.4 GiB, free available 81 GB; 0 idle major faults; no OOM; coherence 17*23=391, Paris OK; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen3.8-Flash-Next** + v0.6.0 b11429, MTP on, ctx 524288, YaRN x2 | 29.3 (prefill) | — | — | — | warm | decode 7.58 t/s; RssFile 59.7 GiB, RssAnon 40.0 GiB, RSS 99.7 GiB, free available 73 GB; 0 idle major faults; no OOM; coherence OK; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen3.8-Flash-Next** + v0.6.0 b11429, MTP on, ctx 1048576, YaRN x4 (parallel 1, pre-concurrency) | 30.8 (prefill) | — | — | — | warm | decode 9.3 t/s steady; RssFile 59.7 GiB, RssAnon 56.4 GiB, RSS 116.0 GiB, free available 60 GB; 0 idle major faults; no OOM; coherence 391, Paris, bat+ball=$0.10 OK; F16 KV; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen MTP** sweep: v0.6.0 b11429, MTP on, ctx 1048576, `spec-draft-n-max 1` | 8.13 | — | — | — | warm | Qwen MTP sweep: realistic decode 8.13 t/s, accept 0.980, mean len 1.98; control decode 8.15 t/s, accept 1.000; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen MTP** sweep: `spec-draft-n-max 2` (old default) | 8.90 | — | — | — | warm | Qwen MTP sweep: realistic decode 8.90 t/s, accept 0.919, mean len 2.84; control decode 9.28 t/s, accept 1.000; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen MTP** sweep: `spec-draft-n-max 3` | 10.42 | — | — | — | warm | Qwen MTP sweep: realistic decode 10.42 t/s, accept 0.893, mean len 3.68; control decode 11.38 t/s, accept 1.000; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen MTP** sweep: `spec-draft-n-max 5` (**chosen**) | **11.18** | — | — | — | warm | Qwen MTP sweep: realistic decode 11.18 t/s, accept 0.858, mean len 5.25; control decode 12.92 t/s, accept 1.000; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen MTP** sweep: `spec-draft-n-max 8` | 8.86 | — | — | — | warm | Qwen MTP sweep: realistic decode 8.86 t/s, accept 0.711, mean len 6.64; control decode 13.72 t/s, accept 1.000; regresses the realistic prompt; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen MTP** knobs: `spec-draft-prio 2`, and `spec-draft-p-min` 0.5/0.8 | — | — | — | — | warm | prio 2: 11.09 vs 11.18 t/s (noise); p-min 0.5/0.8: accept 0.886/0.908 but mean len 5.16/4.95, net flat or worse; both kept null; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen GPU** `llm-qwen-gpu`: Vulkan build, `-ngl 99 -cmoe -nkvo` | 2.01 | — | — | — | warm | decode 2.01 t/s (vs 9.13 CPU same prompt); prefill 44.7 t/s; accept 0.708; VRAM 7.30 GiB; GPU busy 11%/75%; the 24 GiB CPU KV makes every attention step cross PCIe; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen GPU** partial `-ngl 8` / `-ngl 20` (no `-cmoe`) | 5.89 / 5.04 | — | — | — | warm | decode 5.89/5.04 t/s; prefill 14.4/14.6 t/s; VRAM ~7.9 GiB; still slower than CPU; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen GPU** `llm-qwen-gpu` final: `n-gpu-layers-draft 99` + `device Vulkan0` | **10.82** | — | — | — | warm | decode 10.82 t/s (**+18.5%** vs 9.13 CPU same prompt); prefill 16.9 t/s; accept 0.731, mean len 4.55; RSS 95.3 GB, VRAM 6.40 GiB, GPU busy 12%/99%; 0 idle major faults, no OOM; MTP draft head on the W6600, main model + KV on CPU; this row is Qwen, not DS4 |
| 2026-10-07 | **Qwen3.8-Flash-Next** + v0.6.0 b11429, MTP on, ctx 1048576, `parallel 4` + `kv-unified on` (**deployed**) | 14.16 | — | vs `parallel 1` ≈ | — | warm | **concurrency**: short request returned in **2.4-4.6 s** while a 400-token request was in flight; at `parallel 1` the same short request waited **51.5 s** (serialised); server logged `n_slots = 4, n_ctx_slot = 1048576, kv_unified = 'true'`; counting-300 decode 14.16 t/s vs 13.44 at `parallel 1`; prose-300 4.97 t/s (acceptance-bound); prefill ~22.4 vs 18.0 t/s; VmRSS ~101 GB, RssAnon ~37.5 GB, VmSwap 0, no OOM; QSA indexer cache is a per-slot side buffer, so the Kagi single-slot claim is false; this row is Qwen, not DS4 |

**Key mechanism finding (2026-09-05 ~20:10):** the DS4 weights are `mmap`-backed and go
fully resident as **file-backed page cache** (~77 GB `RssFile` on the worker), plus ~14 GB
anonymous (`RssAnon`) → ~92 GB RSS on a 128 GB host. It does NOT re-read on demand *after the
first warm pass*, BUT if anything pressures page cache (a nix build/copy, a stream bench, erm:
essentially any large alloc), the kernel evicts those file pages and llama re-reads them from
disk on next decode → throughput collapses to disk-bound (~2-3 t/s, even 0.9). Once warm and
undisturbed it holds ~5.75-6.7 t/s. **Thus the 2.28/0.9 "regressions" were page-cache churn,
not isolation or cpu affinity.** Always: warm fully, keep the box otherwise idle, then bench;
record RSS/residency with the result. A big lever is keeping the ~92 GB resident without churn.

**Caveat (2026-09-05 ~20:06):** the 19:41 "baseline" (and the handover 0.9) were likely
artefacts of page-cache churn, not isolation. The SAME process (3064, isolation unchanged)
read 6.51 and 6.69 t/s at 19:14/19:16, then 2.28 at 19:41 right after nix-daemon build/copy
disk reads began. The mmap'd ~103 GB GGUF re-reads from disk if page cache is evicted
→ disk-bound. Treat any single bench that follows a build/copy as invalid; re-warm and re-run.

**Root cause refined (2026-09-06, follow-up session):** the recurring *active-serving* oscillation
(2.9→4.5→4.8→6.9 t/s on the router as `buff/cache` cycles 48→75→62→50 GB) is a **physical RAM
capacity** problem, not a VM-policy one. The ~90 GB working set (77 GB file weights + ~14 GB KV/anon
+ OS) on 128 GB leaves only ~1-3 GB free; during generation the KV/anon allocations force the kernel
to reclaim weight file pages because there is no headroom. Verified NULL levers: `--load-mode mlock`
(ENOMEM locking ~101 GB + `mmap` conflict), `vm.vfs_cache_pressure` 50→10 (no help, weights still
not resident), threads 15→12 (identical), `--poll`/`--spec-draft-prio` (inconclusive / unreliable
manual harness). Practical warm peak is **~6.9-7.2 t/s ≈ 87-90 % of the ~8 t/s bandwidth ceiling**;
the only remaining lever flagged for a future session is **memory cgroup v2 isolation** of the
serving unit (so spiky allocs fail in their own cgroup and cannot reclaim the weights), or shrinking
the working set via a smaller `contextSize`.

**Resolved (2026-10-02):** the "physical RAM capacity" framing above was incomplete. The missing
allocator was the **ZFS ARC** (default `c_max` ≈ half of RAM), which grew to ~65 GB and competed for
the same physical RAM as the `mmap`'d weights. Capping it (`zfs_arc_max=8589934592`, 8 GiB) keeps
the weights resident with **zero idle major faults**, and the 192K ceiling disappears — 256K and
320K both hold. `contextSize` was never the binding constraint; the ARC was. See "ZFS ARC quirk"
above for the figures. The mlock/cgroup ideas above are moot for this cause.

### The first-request stall: master and `--no-mmap-prefetch` (brys, 2026-10-08)

Hypothesis: the `MADV_WILLNEED` prefetch that llama.cpp issues at load reads the
whole ~94 GB file and thrashes the 125 GB box, which causes the first-request
stall. Upstream PR #29250 adds `--no-mmap-prefetch` to skip that prefetch. The
PR is **open, not merged** as of 2026-10-08; master head `9c2e0e4` (build 11490)
has no such flag, and v0.6.0 (build 11429) has no such flag. Both support
`--load-mode none`, which drops mmap (and therefore the prefetch).

Two new builds were added to [packages/llama-cpp](packages/llama-cpp/README.md):
`llama-cpp-master-vulkan` and `llama-cpp-master-noprefetch-vulkan` (master plus
PR #29250). All builds were made on brys (32 threads), each in about 2 min 5 s.

Benchmark: a manual `llama-server` with the served `llm-qwen` shape (Vulkan MTP
draft head on the W6600, 1M ctx YaRN x4, F16 KV, batch/ubatch 4096, threads 16,
`parallel 4 --kv-unified`, MTP `draft-mtp` n-max 5). The page cache was dropped
before each run, so every run starts cold. `first` is a fresh 201-token prompt
right after load; `steady` is a 300-token decode, temp 0; `prefill` is 1821
tokens.

| build / flag | load | first request | steady decode | prefill 1.8K |
|---|---|---|---|---|
| v0.6.0 (default) | 140.2 s | 141.8 s (1.42 t/s) | 4.20 t/s | 19.6 t/s |
| master (default) | 140.3 s | 143.5 s (1.40 t/s) | 4.20 t/s | 19.9 t/s |
| master + `--no-mmap-prefetch` | 84.0 s | 191.7 s (1.05 t/s) | 2.36 t/s | 15.6 t/s |
| master + `--load-mode none` | — | crashed (W6600 OOM) | — | — |

Verdict: **neither a newer master nor `--no-mmap-prefetch` removes the stall.**
The stall is cold-read bound, not prefetch bound. The load-time prefetch warms
the page cache, so it *helps* the first request; skipping it moves the cost from
load into the first request and lowers steady decode. The total time to the first
token is about the same either way (v0.6.0 282 s, noprefetch 276 s).
`--load-mode none` fails: the W6600 reports `amdgpu: Not enough memory for
command submission` and the context fails to initialise. No host selects either
build; the served config is unchanged.

### The BLAS backend stall: small fresh prompts (brys, 2026-10-08)

The `llama-cpp-v0_6_0-vulkan` build sets `GGML_BLAS=true` and links OpenBLAS.
The BLAS backend (`ggml_backend_blas_mul_mat`) dequantizes a quantized `src0`
to F32 and calls `cblas_sgemm`. On brys this stalls fresh prompt processing.
This test A/Bs a no-BLAS build (`llama-cpp-v0_6_0-vulkan-noblas`,
`GGML_BLAS=false`, no `bin/libggml-blas.so`) against the served build.

Method: a manual `llama-server` with the served `llm-qwen` shape (Qwen3.8-
Flash-Next UD-IQ4_XS, 1M ctx YaRN x4, F16 KV, batch/ubatch 4096, threads 16,
`parallel 4 --kv-unified`, MTP `draft-mtp` n-max 5 on the W6600). Warm, no
cache drops. `fresh` is a cache-miss prompt (`cache_prompt=false`); `decode` is
300 tokens at temp 0 with `ignore_eos`. Both builds were run in the same
session; `bin/libggml-blas.so` is the only difference.

Qwen3.8-Flash-Next, manual server:

| fresh prefill | BLAS | no-BLAS | ratio |
|---|---|---|---|
| 124 tok (first after load) | 1.03 t/s | 8.0-10.3 t/s | ~10x |
| 124 tok (second) | 1.10 t/s | 16.6-17.7 t/s | ~16x |
| 1762 tok | 19.35 t/s | 26.1-30.8 t/s | ~1.6x |
| 14047 tok | 32.69 t/s | 38.15 t/s | ~1.2x |
| decode 300 tok | 4.35 t/s | 5.66 t/s | ~1.3x |

Load was 82 s (BLAS) and 77-80 s (no-BLAS). The earlier inconsistency is
resolved: **the catastrophic stall is specific to small fresh prompts.** A
~120-token prefill is 10-16x slower with BLAS, but the cost is amortized at 2K
and 16K. BLAS is still slower at every size, and decode is about 30% slower.

DeepSeek V4 Flash (IQ3_XXS, DSpark draft, 327680 ctx), manual server, warm:

| fresh prefill | BLAS | no-BLAS |
|---|---|---|
| 127 tok | 0.58 t/s | 1.91 t/s |
| 1807 tok | 13.92 t/s | 31.26 t/s |
| decode 300 tok | 4.97 t/s | 4.84 t/s |

The same small-prompt stall appears on DS4 (3.3x), the 2K prefill is 2.2x
faster, and decode is unchanged.

**Verdict: no-BLAS wins.** The build is adopted. `qwenGpu` in
[hosts/brys/llm.nix](../hosts/brys/llm.nix) now defaults `llamaPackage` to
`llama-cpp-v0_6_0-vulkan-noblas`, so `llm-qwen` and `llms-frontier` use it (the
combined entry serves DS4 through the same build).

Served `llms-frontier` (no-BLAS), measured after a cold boot (generation 693):

| metric | value |
|---|---|
| first request (cold boot) | 169 s wall = ~141 s cold model load + 27.7 s first prefill (123 tok, 4.43 t/s) |
| warm fresh 124-tok prefill | 7.0 s (17.45 t/s) |
| warm fresh 1761-tok prefill | 65.4 s (26.92 t/s) |
| warm decode 300 tok | 4.22 t/s |

Before, the served first request after a load was ~130 s, dominated by the BLAS
prefill stall (a 124-token prefill at 1.03 t/s). The warm first-request prefill
is now 7.0 s. The cold-boot total is dominated by the ~141 s cold disk read of
the ~94 GB file, which is build-independent; a BLAS build under the same cold
boot would add the ~120 s stall.
