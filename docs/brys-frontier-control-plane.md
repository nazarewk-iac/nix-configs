---
type: Reference
description: How brys serves one frontier engine behind one card — the components, the profile-switch protocol, the drain that keeps `qfn` requests alive, the event journal, and the failures that shaped it.
timestamp: 2026-11-20T02:10:00+01:00
---

# The brys frontier control plane

One GPU, one inference engine, and a small control plane that decides which engine configuration is
running. The point of the design is that an agent never has to know: it asks for `qfn` and keeps
working while somebody else changes the engine underneath it.

Operating commands live in [hosts-den/brys/README.md](../hosts-den/brys/README.md#local-llm-serving);
measured numbers in
[docs/tasks/2026-11/brys-r9700-model-fit/measurements.md](tasks/2026-11/brys-r9700-model-fit/measurements.md);
the agent-facing rules in [.agents/skills/kdn-llms/SKILL.md](../.agents/skills/kdn-llms/SKILL.md).

## The shape

```
 harness (OpenCode, Pi, curl)
        |
        |  OpenAI /v1, model = qfn | qfn-max | qfn-fast-colo | qfn-max-colo | qwen3-omni
        v
 LiteLLM gateway (etra)  .............  optional; the four names are static there
        |
        v
 llama-swap :39700  .................  one entry per model name
        |
        |  spawns the entry's command
        v
 strata-select  <profile> --alias <name> --port N
        |      asks POST /select, then serves the proxy in-process
        v
 proxy :N  ..........................  one lease per request; waits while draining
        |
        |  HTTP/1.1, Connection: close
        v
 strata-manager :8181  ...............  owns the engine, drains, reloads, journals
        |
        |  supervises one child
        v
 strata serve :8080  .................  the frontier (QFN), up to 1M context   [the only engine]
 qwen3-omni llama.cpp :N  ............  the companion, inside the VRAM reserve, on demand
```

Nothing above `strata-manager` knows what a profile is. Nothing below llama-swap knows what a
harness is.

## The names

| name             | entry command              | what happens                                |
| ---------------- | -------------------------- | ------------------------------------------- |
| `qfn`            | `strata-select auto`       | keeps the current profile; **no reload**    |
| `qfn-max-multi`  | `strata-select max-multi`  | 512k × 5, the resting profile               |
| `qfn-max-swarm`  | `strata-select max-swarm`  | 256k × 8                                    |
| `qfn-max`        | `strata-select max-long`   | 1M × 2 (UD-IQ4_XS)                          |
| `qfn-max-long`   | `strata-select max-long`   | the same profile under its own name         |
| `qfn-max-single` | `strata-select max-single` | 1M × 1, the fastest single stream           |
| `qfn-fast-swarm` | `strata-select fast-swarm` | IQ2_XS, 384k × 8                            |
| `qfn-max-colo`   | `strata-select omni-max`   | UD-IQ4_XS plus the 21.5 GB reserve          |
| `qfn-fast-colo`  | `strata-select omni-fast`  | IQ2_XS plus the 21.5 GB reserve             |
| `qwen3-omni`     | plain llama.cpp model      | loads inside the reserve, beside the engine |

The manager accepts the same words as profile names (`qfn` → `auto`, `qfn-max` → `max-long`,
`qfn-fast-colo` → `omni-fast`), so a person and a harness share one vocabulary; the alias map is
derived from `data/llm.nix`, so a profile name is never typed twice.

`qfn` is the name a harness should use. A profile change is a full engine reload — 50–70 s, and it
destroys the engine's KV cache — so the design moves the decision out of the model name and into a
deliberate API call.

## The switch protocol

A switch is deliberately not "kill and start". `select(profile)` runs five steps, in this order:

1. **Mark draining.** `/status` reports `draining: true`; `/lease` answers `wait` instead of a
   lease. Requests that arrive now are delayed, never refused.
2. **Wait for the leases that are already out.** `strata-proxy` takes one lease per request before
   it forwards, and releases it when the response has been relayed. The switch waits until every
   lease is released (1200 s ceiling, then it proceeds anyway and journals `drain_timeout`; the
   ceiling was 300 s until a Wan VACE edit measured 1039 s, and a drain shorter than the longest
   request cuts it).
3. **Unload the companion.** Only models that are _not_ frontier entries: `qwen3-omni` holds about
   20 GiB of VRAM (19.1 GiB of weights plus a 1.5 GiB K/V reserve) and 129 MiB of RAM that the
   incoming engine wants. The frontier proxies stay loaded — they point at the same port, so they
   remain valid across the switch.
4. **Stop, drop the page cache, start.** The cache drop is a root oneshot (`sync; echo 3 >
/proc/sys/vm/drop_caches`) reached through one NUL-free sudoers line. A model load is a ~95 GiB
   allocation burst on a 125 GiB host with no swap; without the drop the kernel OOM-kills the
   engine mid-load (measured four times).
5. **Clear draining** and journal the switch. Requests that waited now get a lease and are served
   by the new engine.

The proxy also answers llama-swap's `GET /health` **locally while draining**. A failed probe would
make llama-swap kill the process that is holding the delayed requests, which is the one outcome the
design exists to prevent.

### What that buys, measured

| level                          | in-flight request     | switch            | result   |
| ------------------------------ | --------------------- | ----------------- | -------- |
| brys proxy, streaming          | 602 chunks in 6.7 s   | 73 s, drain 6.3 s | complete |
| gateway on etra                | 502 chunks in 6.2 s   | 72.5 s            | complete |
| Pi harness through the gateway | counted 1…400, exit 0 | 66 s              | complete |

A request that arrives during the switch waits for the new engine and is served by it. `qfn-max`
and `qfn-fast-colo` get the same treatment, but they are the ones that _ask_ for the reload, so a caller
of those can still be interrupted by another selection.

## The event journal

`strata-manager` appends one JSON line per event to `events.jsonl` and aggregates it at `GET /stats`:

| event                             | fields                       | meaning                                       |
| --------------------------------- | ---------------------------- | --------------------------------------------- |
| `switch`                          | from, to, seconds, cause, ok | a completed profile change                    |
| `engine_load`                     | profile, seconds, ok         | the reload itself                             |
| `engine_stop`                     | seconds                      | draining the child                            |
| `cache_drop`                      | seconds, ok                  | the root oneshot                              |
| `drain`                           | seconds, clean               | how long the switch waited for in-flight work |
| `drain_timeout`                   | running                      | the ceiling was hit with requests still out   |
| `request`                         | seconds                      | one forwarded request's lifetime              |
| `companion_up` / `companion_down` | model, seconds (observed)    | llama-swap's view, polled every 3 s           |

The point is not dashboards. It is that a switching skill can quote a measured cost instead of a
guess, and that a regression shows up as a drifting median.

## Failure modes this design carries scars from

| symptom                                           | cause                                                                                                     | fix in place                                  |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| HTTP 500 ten milliseconds into a start            | the manager unloaded **all** models before a reload, killing the child whose request asked for the switch | unload companions only                        |
| engine OOM-killed mid-load, `free` at zero        | a ~95 GiB burst with the pack still in page cache                                                         | drop the cache before every load              |
| `/status` silent, no revert                       | a TTL revert ran inside the manager and held its lock                                                     | the revert is an external `systemd-run` timer |
| gateway `Invalid API key` from OpenCode           | `opencode run` delegates to a background service with a stale environment                                 | `opencode run --standalone`                   |
| `Model unavailable` for a name the gateway serves | OpenCode validates against the static catalog, not the discovery plugin                                   | the four names are declared statically        |

## Deliberate non-goals

- **No live VRAM change.** `POST /v1/vram` needs `--vram-elastic` and that flag is NVIDIA-only; the
  check is in the backend, not the flag. A reserve change is a reload, by hardware.
- **No per-request routing.** A profile choice is global, stateful and expensive; a router that
  flips per request would thrash the engine. LiteLLM's auto-router is a poor fit here for exactly
  that reason — it belongs where swaps are cheap (the grunt tier, 4B models).
- **No second engine.** One card, one process: co-residence is the reserve plus the companion, not
  two frontiers.
- **No overdrive.** `hardware.amdgpu.overdrive` raises the ceiling above 300 W; it does not lower the
  210 W floor, so it buys nothing for power saving.

## Code map

| file                                 | role                                                                                                                                                                                  |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/kdn-inference-helpers/`    | the control plane in Go: `select`, `manager`, `proxy`, `admit`, `status`; `/select`, `/status`, `/stats`, `/events`, `/lease`, `/release`, `/unload`; owns the engine child; journals |
| `hosts-den/brys/strata-serve.sh`     | materialises a profile config and execs `strata serve` (used by the unit fallback)                                                                                                    |
| `hosts-den/brys/strata-profiles.nix` | the account, the units, the sudoers line, the cache-drop oneshot — and the writer of the derived `config.json`, never a profile table                                                 |
| `data/llm.nix`                       | the fleet catalogue; each frontier model's `hosts.<host>.serving` block is the one place its profile knobs and measured facts are written                                             |
| `lib/llm.nix`                        | `strata`: the projection that derives the manager's `config.json`, the llama-swap entry command, the policy's fact rows and the engine argv from those blocks                         |
| `hack/brys-frontier.sh`              | the human entry point: `up`, `up --profile X --ttl 2h`, `down`, `status`                                                                                                              |
| `hack/probe-drain*.py`               | the proofs: in-flight at the proxy, through the gateway, under a harness                                                                                                              |
