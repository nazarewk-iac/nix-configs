---
type: Task
description: Evaluate LiteLLM's auto/complexity router and semantic/tag routing against the pi-orchestrator's hand-maintained intent-alias picker, and decide whether to adopt, complement, or skip it.
status: in-progress
authored_by: agent
timestamp: 2026-11-07T04:30:00+01:00
---

# LiteLLM auto-router vs the pi-orchestrator model picker

## Context

The gateway (`docs/tasks/2026-11/litellm-gateway/`) exposes the fleet behind
intent aliases (`chat-std-mid`, `tools-std-fast`, `vision-std-fast`,
`chat-deep-slow`, ...) that the `pi-orchestrator` picks per subagent task. LiteLLM
also ships an "Auto Router" (complexity router) and a semantic/tag router that
choose a model per request. This task asks whether one replaces or complements the
other.

## Findings (source-verified, 2026-11-07)

**Two features, both in the box:**
- **Complexity router** (`model: auto_router/complexity_router`,
  `complexity_router_config.tiers {SIMPLE,MEDIUM,COMPLEX,REASONING}`) — current
  (v1.94.0+). Default classifier is a **heuristic scorer** (sub-ms, no API call)
  over token count / code presence / reasoning markers / technical terms; optional
  `llm`/`jev`/`custom` classifiers. Overrides: `keyword_tier_rules`,
  `escalation_keywords`, `semantic_keyword_matching` (needs an embedding model),
  `enable_context_window_escalation` (routes >X-token prompts to a bigger-context
  tier), `modality_routing` (text-only vs vision). `session_affinity` pins a
  conversation to one tier (important for slow prefill).
- **Semantic auto router** (`model: auto_router/<name>`, `router.json` with
  `routes[].utterances` + `score_threshold`) — **deprecated**; embedding
  similarity to example utterances; ~100-500 ms per request.

**DB:** the complexity router needs **no DB** (config-only, DB-less). Savings
accounting needs a DB; we do not use it.

**Tag routing is the strongest fit for "client says intent, gateway picks":**
`router_settings.enable_tag_filtering: true` + `litellm_params.tags`; a client
sends `tags`/`x-litellm-tags` (`&tag` require, `!tag` exclude, plain = prefer,
`default` pool). `routing_groups` binds model_names to a strategy callable as a
model. Both documented and DB-free.

**Overhead / observability:** heuristic router is free and sub-ms; the LLM
classifier adds a call per request; `cause=`/`routed_model=` log lines exist, but a
first-class "tier chosen" Prometheus metric does **not** (only `model_id`/
`model_group` on spend metrics).

## Recommendation

**COMPLEMENT, do not replace.**

1. **Keep pi-orchestrator** as the intent→alias picker. It is deterministic,
   modality-aware (vision/audio/embed/rerank), and picks per-host — none of which
   the complexity router models (audio routing NOT FOUND; vision is only a
   text-vs-capable filter; no per-host placement).
2. **Adopt tag routing** for the quality/intent axis: replace hand-maintained
   per-intent aliases with **tagged pools** (`tiny`, `mid`, `deep`, `tools`,
   `vision`), and let the orchestrator (or a client) send `tags: ["tools:fast",
   "!host:oams"]`. Biggest concrete win, DB-free.
3. **Use `routing_groups`** to latency-balance the overlapping small models
   (brys+oams) per group, and pin the deep/slow model.
4. **Optional single complexity alias** for text-only auto-tiering *if* wanted:
   `classifier_type: heuristic`, `session_affinity: true`,
   `enable_context_window_escalation: true` (with declared `max_input_tokens`).
   Do NOT add an LLM classifier on a local fleet (extra call, nondeterminism).
5. The router's cost-savings rationale (cloud-token pricing) does **not** transfer
   to a self-hosted fleet where marginal token cost is ~electricity; the value
   here is context-fit/quality matching, not cost.

## Status

Research complete; **no implementation yet**. Recommended next step if adopted:
add `enable_tag_filtering` + `litellm_params.tags` derived from the existing
intent aliases (a `tags` field in `data/llm.nix`), and a couple of `routing_groups`
for the shared small models. The complexity router is optional and off.

## Reframe: latency / task-fit, not cost (2026-11-07)

The operator clarified the goal: not cost savings, but **automatically picking the
fastest model that FITS the task**, because the primary `qwen3.8-flash-next` is
notoriously slow. `capabilities.rates` (decode/prefill tps) now exist in
`data/llm.nix`, so "fastest" is a measured, client-side-known quantity.

"Fastest fit" is two decisions: (1) **fit** = which capability class (cheap chat
vs code vs deep vs vision/tools, plus context size), (2) **speed** = among models
that fit, which is fastest right now. LiteLLM splits them poorly: the complexity
router models *fit* crudely (quality tiers, no tps knowledge); `latency-based-routing`
only choose among deployments of the SAME model name (can't cross model sizes);
tag routing is the fit lever. The orchestrator is the right home for *fit* (it has
task context); the gateway is the right home for *speed*.

## Prototype: `chat-fast` pool + `fastest.fastest_fit` (2026-11-07)

Implemented and deployed on etra:

- A model GROUP `chat-fast` in `hosts/etra/litellm.nix` = several fast GPU chat
  models (`qwen3.5-2b`, `granite-4.2-3b`, `qwen3.5-4b`,
  `ministral-3-3b-reasoning`), each deployment carrying `tokens_per_second`,
  `prefill_tokens_per_second`, `max_input_tokens`, `supports_vision` in
  `model_info` (read from the raw `data.models` entry, NOT the member view, which
  throws on `.vision`).
- A selector plugin `hosts/etra/litellm_fastest.py` (`fastest.fastest_fit`),
  callback #3 beside `prometheus` and `probe.host_probe`. For a request to a group
  in `KDN_FASTEST_GROUPS` (default `chat-fast`) it drops deployments that cannot
  FIT (context window, vision) and keeps the single fastest by measured tps
  (prefill rate for prompts > `KDN_FASTEST_LARGE_PROMPT`, else decode rate).

Verified: a `chat-fast` request returns `x-litellm-model-id:
brys-chat-fast-qwen3.5-2b` — the 116.8 t/s model, i.e. the fastest, not a slow
default.

### Caveats / next steps
- **Fit is only context+vision today.** Tool/function-calling fit and per-task
  capability are not filtered; add `supports_function_calling` etc. when the data
  carries it.
- **Pool is small (16k) models only** to keep the 30 s background health checks
  cheap. Adding a big-context model would let the same selector **escalate** on
  long prompts (fastest small one below ~16k, big-context model above).
- The selector returns exactly the single fastest deployment; failover relies on
  the upstream health/cooldown filtering. Consider returning top-2 with weights if
  failover proves fragile.
- **This is speed; the orchestrator still owns fit.** The durable win is also a
  policy change so cheap sub-tasks default to `chat-fast` rather than the slow
  primary.
