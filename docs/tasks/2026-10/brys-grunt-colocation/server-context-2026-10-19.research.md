---
type: Research
description: Server-driven context deployment and full brys model sweep (2026-10-19). Proves `/v1/models` carries each model's real context via `context_length`, that the discovery plugin applies it for every id, and that all 34 brys-hosted ids answer through the compat-proxy.
task: definition.md
authored_by: agent
timestamp: 2026-10-19T16:20:00+02:00
---

# Server-driven context + all-model sweep (2026-10-19)

## What changed

Two commits on top of the llama-swap migration:

1. **Server-driven context.** llama-swap renders a model's `capabilities.context`
   into the top-level `context_length` field of `/v1/models`, for every id and
   alias. The `llm` aspect emits `capabilities.context` from each model's
   `perf.contextSize`; the generated discovery plugin reads it back and sets
   `limit.context` per id. The client (oams) configures **discovery only**; it
   carries no hand-written `models` overlay.

2. **No context tiers.** llama-swap has no per-alias context, and the unified KV
   pool is usage-proportional, so a model cannot be bounded per client. Each
   request runs at the model's real maximum (DS4 320K, Qwen 1M). The oams
   subagents are now one per (model, thinking level) — `ds4-{off,low,medium,high}`
   and `qwen-{off,low,medium,high}`. The `<n>k` tier aliases are removed from
   brys; the served id count drops from 56 to 34.

## Deployment

Activated on brys, into the swapping specialisation `llms-frontier` (a
`switch --specialisation`, in place; no reboot). `llama-swap` active,
`llama-cpp` inactive.

## Server contract

`GET /v1/models` now carries, for all 34 ids:

```json
{ "id": "deepseek-v4-flash", "context_length": 327680, "meta": { "llamaswap": { "aliases": ["frontier"] } } }
```

Counts: **34 ids, all 34 with `context_length`**. Aliases (`frontier`, `qwen`,
`grunt`) inherit their base model's context, which is now the model's real
maximum — correct, because aliases are not bound per context.

## Discovery plugin (live)

The generated plugin was run end-to-end against the live server. It produced 34
model entries, **0 without `limit.context`**:

| id | `limit.context` | `limit.output` |
|---|---|---|
| `deepseek-v4-flash` | 327680 | 8192 |
| `qwen3.8-flash-next` | 1048576 | 8192 |
| `frontier` | 327680 | 8192 |
| `qwen` | 1048576 | 8192 |
| `grunt` / `qwen3.5-4b` | 16384 | 4096 |
| `tmax-2b` | 16384 | 4096 |
| `qwen3.5-0.8b-cpu` | 8192 | 2048 |
| `gemma-4-31b` | 8192 | 2048 |

## Full model sweep

Every id in `/v1/models` was called with a one-line prompt
(`max_tokens 8`, `temperature 0`). **34/34 returned HTTP 200, 0 failures.**

Wall time per id is dominated by cold-load; small models are 1-8 s, the large
dense/MoE surveyed models 30-50 s, and the two frontier models ~120 s on a cold
start (DS4 124 s, Qwen 123 s). `deepseek-v4-flash`/`qwen3.8-flash-next` and the
`*-reasoning` models returned an empty `content` because their output went to the
reasoning field — expected, not a failure.

## Notes

- The `aliasContexts` mechanism was implemented and then removed: it could
  publish a per-alias window, but the server does not enforce it, so it only
  advertised a bound that any client could exceed by sending more tokens. Sticking
  to each model's real maximum is the honest contract.
- `standalone-aspects` fails on `kdn.llm.local.swap.enable` at the parent commit
  too — a pre-existing check issue, not introduced here.
