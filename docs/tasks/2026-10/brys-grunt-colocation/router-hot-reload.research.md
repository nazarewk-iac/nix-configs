---
type: Research
description: Hot configuration reload without dropping in-flight requests — a survey of llama-swap, llama.cpp router mode, and generic proxies (Caddy, HAProxy, nginx, Envoy), with a recommendation for the brys router.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T07:00:00+02:00
---

# Hot reload of the router configuration — research

The brys router must accept configuration changes — add, remove or edit model
definitions and routes — with **zero dropped in-flight requests** and ideally
**zero model eviction**. This document records the verified behaviour of every
candidate and the smallest artefact that reaches the goal.

**Verification legend:** `[V]` verified against the cited URL; `[I]` inferred from
documented mechanisms.

## 1. Requirement

| Constraint | Meaning |
|---|---|
| Hot reload | a config change takes effect without a restart of the listener |
| Zero dropped requests | no in-flight request is cut; no queued request is failed, for a reload that keeps the affected models resident |
| Zero model eviction (ideal) | an edit to one model does not unload the other models |

## 2. llama-swap — watches config, but reload is stop-the-world `[V]`

llama-swap does watch its config: `-watch-config` is a **2 s `os.Stat` poll**, and it
also honours `SIGHUP`. The reload, however, is **stop-the-world**:

- it throws away the running proxy and builds a new one,
- it calls `old.Shutdown`, which **stops every upstream process**,
- it **cuts in-flight requests** and **fails queued** requests,
- **unrelated models reload from disk** (minutes for a large MoE).

There is **no `/api/config/reload` endpoint**, and **differential reload is not
implemented**. Source: `github.com/mostlygeek/llama-swap` issue **#1202** (confirmed
by the maintainer) and PR **#685**.

**Consequence:** never reload llama-swap in production with tasks in flight.

## 3. llama-server (llama.cpp) router mode — per-router preset reload `[V]`

`llama-server` router mode can reload its model preset at runtime via
`GET /models?reload=1`. On reload:

- a **changed or removed model IS unloaded**,
- **unchanged models are untouched**.

There is **no SIGHUP handler**. Feature request **#21823** was closed as a duplicate
of **#21779**. See `github.com/ggml-org/llama.cpp` PR #21779 and
`tools/server/README.md`.

**Consequence:** a per-router reload evicts only the edited model. brys already splits
routers, so a small-set edit does not touch the frontier.

## 4. Generic proxies — hitless reload, but no model management `[V]`

| Proxy | Reload mechanism | In-flight behaviour | Model processes |
|---|---|---|---|
| **Caddy** | `caddy reload` / `POST /load` / `SIGUSR1` | provisions the new config **in-process**, keeps listeners; SSE (used by OpenCode) is **not** closed, only WebSockets (unless `stream_close_delay`) | none |
| **HAProxy** | `-sf <pid> -x <sock>` with `bind ... expose-fd listeners` | the **only** tool with a published zero-drop measurement (**0 failed / 2000**) | none |
| **nginx** | `SIGHUP` | **drains** old workers | none |
| **Envoy** | hot restart | **drains**, but does **not** transfer connections | none |

Sources: `caddyserver.com/docs/command-line`,
`haproxy.com/blog/truly-seamless-reloads-with-haproxy-no-more-hacks`,
`nginx.org/en/docs/control.html`, Envoy hot-restart docs.

These proxies reload the **routing layer** hitlessly, but they do **not** manage
model processes, so they cannot by themselves add or remove a resident model.

## 5. The gap `[V]`

**No free / self-hosted tool does the full triple today:**

1. hot reload, **and**
2. no dropped requests, **and**
3. no model eviction.

llama-swap has the model lifecycle but reloads stop-the-world; the generic proxies
reload hitlessly but own no models.

## 6. Recommendation

1. **Never reload llama-swap in production.** Its reload stops every upstream and
   drops requests (§2).
2. **Put the model→port routing in a layer that reloads hitlessly** — **Caddy**
   (already deployed) or **HAProxy** with FD transfer (§4). This layer changes
   routes with zero dropped requests.
3. **Reload individual router presets** via `llama-server /models?reload=1` only
   when that router's model is idle (§3). Only the edited model is evicted.
4. **If zero compromise is required**, the smallest artefact is a **~250-line
   Go/Python proxy** (§7) whose route table is an `atomic.Pointer` reloaded on
   `SIGHUP`/`fsnotify`, while the listener and the `llama-server` children stay up.

## 7. Design sketch — smallest zero-drop, zero-evict proxy

```
        +-------------------------------------------+
config --->( SIGHUP / fsnotify watcher )             |
        |        |                                  |
        |        v                                  |
        |   parse + validate new route table        |
        |        |  (model -> (host, port, backend)) |
        |        v                                  |
        |   atomic.Pointer[RouteTable].Store(new)   |  <-- single atomic swap
        +-------------------------------------------+
                 ^
   request --> listener (never closed) --> lookup atomic.Pointer --> proxy to
                 |                                                  llama-server child
                 v
        backend registry: children are started/stopped ONLY on an explicit
        add/remove of that model; an edit of a route leaves the child untouched
```

Properties:

- The **listener is never closed**; only the pointer value swaps. A request that
  reads the pointer before or after the swap sees a complete, valid table.
- A model **edit** changes the pointer but leaves the `llama-server` child (and its
  in-flight requests) running → zero eviction for unrelated models.
- A model **removal** is applied only after its in-flight count reaches zero (a
  drain counter per backend).
- Zero external dependencies beyond the JSON/YAML parser and `fsnotify`.

This is the only listed option that reaches the full triple, and it is small enough
to own.

## 8. Verification ledger

**`[V]`:** llama-swap `-watch-config` (2 s `os.Stat` poll) / `SIGHUP` and
stop-the-world reload (`old.Shutdown` stops all upstreams, cuts in-flight, fails
queued, unrelated models reload from disk), no `/api/config/reload`, no differential
reload — `github.com/mostlygeek/llama-swap` issue #1202 and PR #685.
`llama-server` router reload via `GET /models?reload=1` (changed/removed model
unloaded, unchanged untouched; no SIGHUP; #21823 closed as duplicate of #21779) —
`github.com/ggml-org/llama.cpp` `tools/server/README.md`.
Caddy `reload`/`POST /load`/`SIGUSR1` in-process, SSE not closed —
`caddyserver.com/docs/command-line`. HAProxy `-sf`/`-x`/`expose-fd listeners`,
0 failed / 2000 —
`haproxy.com/blog/truly-seamless-reloads-with-haproxy-no-more-hacks`.
nginx SIGHUP worker drain — `nginx.org/en/docs/control.html`. Envoy hot restart
drains without transferring connections — Envoy docs.

**`[I]`:** the ~250-line proxy line count and the exact `atomic.Pointer` +
drain-counter implementation; that Caddy already fronts the brys routers; the
per-router idle check for step 3.
