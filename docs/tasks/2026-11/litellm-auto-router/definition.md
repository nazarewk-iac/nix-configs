---
type: Task
description: Evaluate LiteLLM's auto/complexity router and semantic/tag routing against the pi-orchestrator's hand-maintained intent-alias picker, and decide whether to adopt, complement, or skip it.
status: research-done
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
