---
type: Task
description: Record the boundary between llama-swap and the inference runtime, the one behaviour llama-swap cannot express, and the conditions under which forking llama-swap is cheaper than the gate that implements it today.
status: open
authored_by: agent
timestamp: 2026-11-20T13:40:00+01:00
---

# The llama-swap / inference-runtime boundary

## Context

Two programs share the serving role on brys, and the split must stay deliberate:

| capability                                                                            | owner                                 |
| ------------------------------------------------------------------------------------- | ------------------------------------- |
| `:39700` front door, `/v1/models` catalog, aliases                                    | llama-swap                            |
| matrix sets and `evict_costs` (which model evicts which)                              | llama-swap                            |
| per-model `ttl`, idle unload                                                          | llama-swap                            |
| health checks, log ring buffer, captures, metrics                                     | llama-swap                            |
| supervision of the ~40 grunt/surveyed models                                          | llama-swap                            |
| the frontier engine (`strata serve`), profile selection, the drain, the event journal | `kdn-inference-helpers` (`manager`)   |
| the per-entry listener for the four QFN names                                         | `kdn-inference-helpers` (`select`)    |
| **the companion's llama-server child**: start, health, port, the 409 guard            | `kdn-inference-helpers` (`omni` gate) |

The third row is the one exception: for `qwen3-omni`, our binary owns a process that llama-swap used
to own. This task records why, what it costs, and when to stop doing it.

## The gap

llama-swap starts a model's `cmd` **before** it has a request in hand, so it cannot refuse a request
based on its body. What we need is exactly that:

> `qwen3-omni` must not load while the engine holds the whole card. The refusal must be readable and
> must name its own remedy: repeat the request with `kdn_switch_to: "<colo profile>"`, which switches
> the engine and then serves.

Three ways to get it, and only one keeps the message readable:

1. **Client preflight** (agent asks `/status`, then `/select`): no enforcement for a forgetful client.
2. **Gate that exits non-zero**: llama-swap reports "model failed to start"; the remedy never reaches
   the client.
3. **Gate that owns the child** (implemented): the 409 and the switch are both possible, and the same
   process starts the server after the switch.

## What the gate does now

- Answers `/health` **200 always**, so llama-swap never kills the process that is holding a request.
- No reserve (profile `max`): reads the body; without `kdn_switch_to` answers
  `409` with `{error, current_profile, requires, confirm{field,value}, alternatives, reload_seconds, note}`.
- With `kdn_switch_to` naming a **colo** profile (`qfn-max-colo` → `omni-max`, `qfn-fast-colo` →
  `omni-fast`): asks the manager to switch with `keep_companions: true` (without it the switch unloads
  the gate process that is waiting on the call — measured, it cancelled the switch), waits, starts
  llama-server on `${PORT}+1000`, forwards the body unchanged.
- With a reserve already (`omni-max`/`omni-fast`): forwards immediately, no switch, no prompt.
- Switching uses `context.WithoutCancel`: a client that gives up must not cancel a reload that has
  already stopped the engine.

## The two rules that complete the loop

- **`qfn` never switches a running model.** With nothing loaded it starts `max`; with anything loaded
  it keeps it. This is what makes the stable name safe to hand to an agent.
- **The last companion unload returns the engine to `max`.** The manager's companion watcher sees the
  model disappear and switches back on its own (~72 s, drained). llama-swap's `ttl: 3600` on the omni
  entry is what triggers it when nobody unloads explicitly.

## Measured live (2026-11-20, Go runtime)

| step                                    | result                                                                 |
| --------------------------------------- | ---------------------------------------------------------------------- |
| omni without a reserve, no field        | `409`, `confirm.field = kdn_switch_to`                                 |
| omni with `kdn_switch_to: qfn-max-colo` | `200` in **133 s** (switch ~70 s + model load), profile `omni-max`     |
| explicit unload of omni                 | profile back to `max` within **72 s**, journaled as `companion_revert` |
| `qfn` with a profile already running    | no switch (Go test, and the live restore path)                         |

## Options for the next round, ranked

1. **Keep the gate** (current). ~150 lines, universal enforcement (a client that talks straight to
   `:39700` is still guarded), no fork.
2. **Move the guard into etra's LiteLLM pre-call hook.** Deletes the `omni` subcommand; the guard then
   only covers traffic through the gateway. Smaller, but scoped.
3. **Fork llama-swap with a generic per-model `preStart` hook** that sees the request and may deny with
   a structured error. Roughly 100–200 lines in llama-swap plus config plumbing, and it is
   upstreamable as a generic feature. Worth it only if a second body-aware rule appears, or if
   upstream accepts the hook.
4. **Replace llama-swap with the helper.** ~1.5k lines to reach parity for our usage (front door,
   catalog, aliases, matrix eviction, ttl, health, N-model supervision, unload API, metrics) plus a
   permanent parity chase. Not worth it.

## Decision

Stay on option 1. **No fork is needed for a perfectly usable state**: every behaviour the user asked
for works today, and the fork would only remove the gate, not add capability.

## Exit condition

Revisit the fork when either of these becomes true:

- a **second** body-aware rule appears (the gate would need to grow a policy engine, which is where a
  fork becomes cheaper); or
- upstream accepts a generic `preStart` hook (then the gate collapses into it and the helper stops
  owning any model process).

The fork, if it happens, must carry a **generic** hook, never `kdn_switch_to` in llama-swap's code, so
it stays upstreamable and our vocabulary stays ours.

## Verification

```sh
# the refusal
curl -s -X POST :39700/v1/chat/completions -d '{"model":"qwen3-omni",…}' | jq .confirm
# the switch and the answer
curl -s -X POST :39700/v1/chat/completions -d '{"model":"qwen3-omni","kdn_switch_to":"qfn-max-colo",…}'
# the revert (after an explicit unload, or after the 1 h ttl)
curl -s :8181/status | jq .profile      # back to "max"
```

`go test -race ./...` in `packages/kdn-inference-helpers` covers the gate (409 shape, colo target
validation, reserve pass-through, `keep_companions`), the `qfn`-never-switches rule, and the
companion revert.
