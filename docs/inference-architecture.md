---
type: Reference
description: The whole inference stack end to end — which pieces are daemons, which are one-shot commands, which process owns which child, and the exact sequence of events for a first request, a switch, a companion request and an idle eviction.
timestamp: 2026-11-20T14:30:00+01:00
---

# Inference architecture, end to end

Two hosts and one card. **brys** runs the models; **etra** runs the gateway that the agent hosts talk
to; **oams** (and every other client) is a harness. This page is the map: processes, commands, and
when each one does something. The design rationale is in
[brys-frontier-control-plane.md](brys-frontier-control-plane.md), the llama-swap split in
[tasks/2026-11/inference-runtime-boundary](tasks/2026-11/inference-runtime-boundary/definition.md).

## The path of one request

```
  harness (OpenCode / Pi / curl)  on oams, anji, …
        │  OpenAI /v1, model = qfn | qfn-max | qfn-max-colo | qfn-fast-colo | qwen3-omni
        ▼
  LiteLLM gateway            etra, container@litellm.service, HTTPS        [daemon]
        │  relays to brys:39704
        ▼
  llama-swap                 brys :39700, User=llm-server                  [daemon]
        │  picks the entry, starts its child on first use, health-checks it
        ▼
  entry child                one per loaded model, on llama-swap's ${PORT}
        │   ├── qfn*  →  `kdn-inference-helpers select <profile> --port N`   [proxy, long-lived]
        │   └── omni  →  `kdn-inference-helpers omni -- llama-server …`      [gate + model]
        ▼
  strata-manager             brys :8181, User=llm-server                   [daemon]
        │  /select /status /stats /events /lease /release /unload
        │  owns exactly one child and one set of leases
        ▼
  strata serve               brys :8080                                    [child of the manager]
        └── qwen3-omni llama-server   ${PORT}+1000                         [child of the gate]
```

## What is a daemon and what is a command

| piece | kind | lifetime | owner |
| --- | --- | --- | --- |
| `llama-swap.service` | **daemon** | boot to shutdown | systemd, `llm-server` |
| `strata-manager.service` | **daemon** | boot to shutdown | systemd, `llm-server` |
| `kdn-inference-helpers select …` | **daemon** (per entry) | while llama-swap keeps that model loaded | llama-swap |
| `kdn-inference-helpers omni -- llama-server …` | **daemon** (per entry) + child | while llama-swap keeps the companion loaded | llama-swap (gate), gate (model) |
| `llama-server` (grunt/surveyed models) | **daemon** (per entry) | while loaded | llama-swap |
| `strata serve` | **daemon** (one) | while a profile is selected | the manager |
| `llama-server` for the companion | **daemon** (one) | while the gate runs | the gate |
| `kdn-inference-helpers ctl up\|down\|status\|stats\|unload` | **command** | seconds | a human or an agent |
| `kdn-inference-helpers serve <profile> --port N` | **command** (execs the engine) | becomes the engine | the `strata-frontier` fallback unit |
| `strata-drop-cache.service` | **oneshot**, root | ~4 s, triggered per switch | the manager, through one sudoers line |
| `strata-revert.service` | **transient timer** | armed for `--ttl`, fires once | `ctl up --ttl` |
| `r9700-power-cap.service` (+ `-resume`) | **oneshot**, root | boot and resume | systemd |
| `strata-frontier.service` | **disabled fallback** | only when started by hand | nobody by default |
| `container@litellm.service`, `litellm-brys-egress.service` | **daemons** | boot to shutdown | systemd on etra |
| `hack/probe-drain*.py`, `hack/probe-power-*.py` | **commands** | minutes | a human, as acceptance tests |

The rule of thumb: a process that must stay attached to a port is a daemon; a process that asks for
something and prints the answer is a command. The wrappers `strata-manager`, `strata-select`,
`strata-proxy` and `strata-serve` are one-line shims that keep the historical names pointing at the
Go binary.

## Ports

| port | thing | notes |
| --- | --- | --- |
| 39700 | llama-swap | the fleet's OpenAI front door on brys |
| 8080 | Strata engine | one per card, owned by the manager |
| 8181 | manager | `/select`, `/status`, `/stats`, `/events`, `/lease`, `/release`, `/unload` |
| `${PORT}` | one per llama-swap entry | assigned by llama-swap, e.g. 10009 |
| `${PORT}+1000` | companion model | the gate listens on `${PORT}`, the model behind it |
| 39704 | etra → brys relay | used by the gateway container |

## Files the runtime owns

| path | who writes | what |
| --- | --- | --- |
| `/etc/kdn-inference-helpers/config.json` | NixOS | ports, aliases, frontier ids, cache-drop hook, log paths |
| `<data>/strata/manager-state.json` | manager | the selected profile |
| `<data>/strata/events.jsonl` | manager | one JSON line per switch, load, stop, drain, companion event |
| `<data>/strata/engine.log` | manager | the engine child's stdout and stderr |
| `<data>/strata/companion.log` | gate | the companion's stdout and stderr |
| `<data>/strata/profiles/strata-<profile>.json` | adapter | the materialised engine config |
| `<data>/strata/install/strata-<pack>.json` | the Strata Terminal | the base config each profile patches |

## When things happen

**Boot.** `r9700-power-cap` writes 210 W. The manager starts, reads the state file and **restores**
that profile if the engine does not answer (a cold `max` is ~70 s). llama-swap starts with no entry
loaded. Nothing is on the card until the first request.

**A first `qfn` request.** llama-swap starts the `qfn` entry → `select qfn --port N` → `POST /select
{"profile":"qfn"}`. The manager resolves `qfn` to `auto`: with nothing loaded it starts `max`
(~70 s), then answers. The proxy on `N` forwards, holding one **lease** for the request. Later `qfn`
requests see a running engine and are answered in milliseconds without touching it.

**A request while somebody switches.** The manager's switch starts with `BeginDrain`: new leases are
refused, the granted ones are waited for (300 s ceiling), and then the engine is unloaded, the page
cache dropped, and the new profile started. A request that arrives during the switch polls `/lease`
and is served by the new engine — delayed, never cut.

**A switch asked for by API** (`ctl up --profile max`, or `POST /select`): same sequence, one reload,
~50–76 s measured. `--ttl` additionally arms `strata-revert`, which posts `{"profile":"qfn-max"}`
after the duration so the card returns to the whole-card profile.

**An omni request with no reserve.** llama-swap starts the `omni` **gate** (fast, no model). The gate
sees the profile is `max`, reads the body, and answers `409` with
`confirm.field = kdn_switch_to`, the alternatives and the ~70 s cost. No model is started.

**An omni request with `kdn_switch_to`.** The gate asks the manager to switch to the named colo
profile with `keep_companions: true` (otherwise the switch would unload the gate that is waiting on
the call), waits, starts llama-server on `${PORT}+1000`, and forwards the same body. Measured: 200 in
133 s, profile `omni-max`.

**Omni idle for an hour.** llama-swap's `ttl: 3600` on the entry unloads the gate (killing the model
with it). The manager's companion watcher notices the last companion gone and reverts the engine to
`max` by itself — one reload, drained. Same path for an explicit `ctl unload` or
`POST /unload {"model":"qwen3-omni"}`.

## Who owns which child (restart semantics)

| if this restarts | what dies with it | what survives |
| --- | --- | --- |
| `strata-manager` | the engine (its child); the manager restores the profile on start | llama-swap and its entry proxies — they reconnect to the same port |
| `llama-swap` | every entry child: the QFN proxies and the companion gate + its model | the engine, because the manager owns it; the next request re-attaches in ms |
| the `select` proxy for an entry | that entry's port only; llama-swap restarts it on the next request | the engine and the other entries |
| the `omni` gate | the companion model with it | the engine; the journal already recorded the unload |
| `strata serve` | in-flight requests on the engine (the manager retries a restore) | the manager, which journals the failure and clears the profile |

## What is deliberately not in this picture

- **No second engine.** One card, one engine; co-residence is a VRAM reserve plus the companion.
- **No per-request routing between profiles.** A profile is global and expensive; the four names make
  the choice explicit.
- **No llama-swap fork.** The one thing it cannot express (a start decision that depends on the
  request body) lives in the gate, with an exit condition recorded in the boundary task.
