---
type: Status
description: The research/decision (COMPLEMENT) and the chat-fast + fastest_fit prototype are done and deployed; the "default cheap sub-tasks to chat-fast" policy is the remaining piece.
task: definition.md
authored_by: agent
timestamp: 2026-11-14T05:09:42+01:00
---

## Done so far

- **Research + decision**: COMPLEMENT, do not replace. Keep the pi-orchestrator as the
  intent -> alias picker (deterministic, modality-aware, per-host); adopt LiteLLM tag routing for
  the quality/intent axis; use `routing_groups` to latency-balance the shared small models. The
  cost-savings rationale does not transfer to a self-hosted fleet.
- **Prototype, deployed on etra** `hosts/etra/litellm_fastest.py` (`fastest.fastest_fit`, a
  `pre_call` callback): for a request to a `chat-fast` group it drops deployments that cannot fit
  (context window, vision) and keeps the single fastest by measured tps (prefill rate for large
  prompts, else decode rate).
- **Verified**: a `chat-fast` request returns the 116.8 t/s model — the fastest, not a slow default.

## Remaining

- **Policy change** (the durable win): make cheap sub-tasks default to `chat-fast` rather than the
  slow primary. That is an orchestrator / `data/llm.nix` policy change, not a gateway change.
- **Fit is only context + vision** today; tool/function-calling fit is not filtered (add
  `supports_function_calling` when the data carries it).
- **Pool is small (16k) models only** to keep the background checks cheap; a big-context model would
  let the selector escalate on long prompts.

## Next directions

1. Scope the "default cheap sub-tasks to `chat-fast`" policy change as its own task (or fold it into
   the pi-orchestrator default policy), then implement it in `data/llm.nix` / the orchestrator.
2. When the policy lands and the fit gaps are closed, flip to `done` with a `done.md` and delete
   this `status.md`.
