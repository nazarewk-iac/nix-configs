---
type: Task
description: Decide whether a LiteLLM proxy in front of llama-swap earns its place, for request retries on interrupted or stalled queries, per-request logging into a worklog, fallbacks and timeouts, and an importable request/response record.
status: open
authored_by: agent
timestamp: 2026-10-27T21:15:00+01:00
---

# A proxy in front of the swapper: what litellm would and would not buy

## Context

The local stack today has three layers:

```
opencode → compat proxy (opencode-compat-proxy)  → llama-swap → llama-server children
           rewrites DSML/XML tool calls to OpenAI tool_calls
```

(`modules/den/aspects/llm-proxy.nix` — one FastAPI process per upstream, one
`systemd` unit each.)

Two pain points the owner wants to solve, and neither is in that proxy today:

1. **A query dies or stalls and nothing retries it.** The realistic causes are a
   model swap (90–120 s, longer under load), a model that got evicted by another
   request's matrix set, a child that crashed on load, or a client timeout. Today
   the caller sees a failure and an agent wastes a whole turn.
2. **No record of what was asked and answered.** The fleet evaluation
   ([../gaz-den-workstation/003-fleet-evaluation/definition.md](../gaz-den-workstation/003-fleet-evaluation/definition.md))
  needs per-call data: alias, prompt size, latency, outcome. Today that is manual
  note-taking, which is why it is unreliable.

## What litellm is, before deciding anything

- Available: `pkgs.litellm` **1.102.1** in the pinned nixpkgs, with a NixOS
  module (`services.litellm`) that takes a free-form `settings` with
  `model_list`, `router_settings`, `litellm_settings`, `general_settings`.
- It is a **proxy**. It routes to deployments that are already running. It does
  **not** start, stop, load or evict a model. That was decided in
  [../brys-grunt-colocation/llama-router-scheduler.research.md](../brys-grunt-colocation/llama-router-scheduler.research.md)
  ("LiteLLM proxy … No fit — routing only"), and it still holds: **litellm cannot
  fix the concurrency ceiling** ([../llama-swap-concurrency/definition.md](../llama-swap-concurrency/definition.md)).
  It can only improve what happens *around* a request.

So the honest framing: this task is not "litellm or a scheduler". It is "is
litellm the cheapest way to get retries and request logs, or is it a second
moving part that duplicates what we already run?"

## What it would add

| Capability | Where it lives in litellm | Why we want it |
|---|---|---|
| Retry on a failed request | `litellm_settings.num_retries`, `request_timeout`; `router_settings.retry_policy` | a swap or a cold load stops costing a whole agent turn |
| Fallback to another model or alias | `router_settings.fallbacks`, `context_window_fallbacks` | a dead `chat-std-fast` falls back to `chat-std-mid` instead of failing |
| Cooldown after repeated fails | `router_settings.allowed_fails`, `cooldown_time` | stops hammering a model that is OOM-ing |
| Timeouts per model | `request_timeout`, per-deployment | a 20-minute stalled stream is cut and retried |
| Request/response logging | `litellm_settings.callbacks`, custom callbacks, `jsonl` logging | the worklog the evaluation needs, written automatically |
| Spend and token accounting | callback to a local DB | token cost per alias, per session |
| A stable OpenAI-shaped surface | proxy | the fleet keeps one base URL |

## Design questions that decide it

1. **Does a retry help, or does it double the load?** A retry fired while
   llama-swap is still loading the model queues a second request behind the same
   load. The retry must be on **connection/5xx/timeout**, after a delay, never on
   a slow-but-live stream.
2. **What is retried safely?** A chat completion that streamed 900 tokens and
   then died cannot be retried transparently: the client already saw tokens. So
   retry is only safe for a request that produced no output. That is a
   correctness constraint, not a preference.
3. **Layer order: opencode -> litellm -> compat-proxy -> swap, or the reverse?**
   The compat proxy rewrites DSML into `tool_calls`. litellm must not be the
   layer that loses that, so the proxy stays **closest to the model**. Retry
   belongs outside it.
4. **Does a second proxy add latency to every streaming token?** Measure. If a
   pass-through hop costs measurable TTFT, that is a real cost against the
   evaluation.
5. **Where do "worklogs" live?** A per-session JSONL under the harness's
   git-ignored path, or the task's `.worklog.md`. Streamed request/response
   bodies can carry user data, so the same privacy rules as screenshots apply.

## The alternatives, which must be priced first

| Option | Effort | What it gives |
|---|---|---|
| **Client-side retry/timeout** in the opencode provider config | a config line | most interrupted-query cases, no new service |
| Retry inside the **existing compat proxy** (`opencode-compat-proxy` is already ours) | a small patch | retries plus logging, no new daemon, no new auth tier |
| litellm as a new service | a new unit, a config, a database for spend | retries, fallbacks, logging, spend, a well-known config format |
| Do nothing, and let the orchestrator retry | none | honest, but the overseer then burns turns noticing |

The task must pick one of these with numbers, not vibes.

## Acceptance

- A written decision with a reason, and the rejected options stated.
- If litellm is adopted: it runs as a NixOS unit, it is in front of the swap, the
  DSML translation still works (a streamed tool call is proven end to end), a
  forced eviction produces a retry that succeeds, and a per-request log line
  lands somewhere durable.
- If litellm is rejected: the cheaper option is implemented instead, or the
  reason is recorded.
- The token-usage pass-through that keeps OpenCode's counter working is not
  broken. `docs/local-llms.md` explains why that chunk matters.

## Risks

| Risk | Mitigation |
|---|---|
| A retry loop doubles load on a box already swapping | retry only on connection error, with a backoff and a cap |
| litellm breaks the DSML tool-call path silently | test a streamed tool call end to end before adopting |
| A second proxy adds latency to every token | measure TTFT before and after; reject on regression |
| Request logs capture secrets or personal text | treat them as user data: `/tmp/opencode` or a git-ignored path |
| A second auth layer confuses the fleet | one master key, injected by the existing wrapper environment, never in the repo |
