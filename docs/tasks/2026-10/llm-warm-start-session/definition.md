---
type: Task
description: Pre-compute the shared base-prompt KV/session once (right after the model loads) under a fixed session id, so a fresh OpenCode session or sub-agent resumes from a warm in-RAM prefix instead of re-prefilling the ~30K-token system prompt.
status: open
authored_by: agent
timestamp: 2026-10-10T11:00:00+02:00
---

# Warm-start session for fresh OpenCode sessions and sub-agents

## Context

Every new OpenCode session and every sub-agent (the `ds4-*` / `qwen-*` agents in
`hosts/oams/devenv.nix`, and the per-agent system prompt + tool schemas, roughly
a few thousand tokens each; the base system prompt plus all tool schemas is on
the order of tens of thousands of tokens) begins with an almost identical
prefix. The RAM prompt cache (`--cache-ram`) reuses that prefix only while it
stays resident, and the disk session store is keyed per session, so a brand-new
session starts cold and re-prefills the whole base prompt.

On brys this is expensive: prefill runs ~19-27 tok/s, so a 30K-token base prompt
costs ~20 minutes before the first generated token.

## Goal

After the model loads, prefill the shared base prompt once, keep it in RAM, and
let a fresh session or sub-agent **resume from it** rather than re-prefill it.
The warm start must survive the usual per-session differences by reusing at
least the common prefix.

## Proposed approach

1. **Produce the canonical prefix.** The shared system prompt and the tool
   schemas of the default agent. Capture it once (an OpenCode request body, or a
   scripted `/completion` with the exact token prefix).
2. **Prefill it under a fixed session id on startup.** Two routes:
   - **#29738 session store**: on model load, send one request with
     `session_id: "warmstart"` (or the agent-specific ids) and the base prompt,
     then keep it. A fresh session cannot reuse a *different* session's file,
     so this needs the **body `session_id` to be the caller's** unless we add
     server support to seed a session from another.
   - **RAM prompt cache**: rely on `--cache-ram` holding the base-prompt entry.
     A new session's first request with the same prefix then reuses it. This
     needs no new server code, only that the base prefix is (a) resident and
     (b) the longest matching prefix for typical requests.
3. **Decide the grouping.** One warm entry (the pure system prompt), or one per
   agent variant (`ds4-320k` … `qwen-128k`), since each agent has its own
   prompt/schema prefix.
4. **Trigger.** A systemd oneshot after `llama-cpp` is active and the model is
   loaded (the router loads a model on first request, so the warm trigger must
   itself be the first request), or a small wrapper that loads the model then
   warms it.

## Open questions

- **Does a new session actually reuse a warm prefix?** It depends on
  `--slot-prompt-similarity` and on the RAM cache holding the entry. Verify that
  a cold OpenCode session's first request reports `cache_n > 0` when the base
  prefix is resident.
- **Router model load.** With `--models-max 1`, warming DS4 evicts Qwen and
  vice versa. Warm only the resident model, or warm on load.
- **Per-agent prefixes.** The sub-agents differ; a single warm entry may only
  cover the pure system prompt. Measure how much of each agent's prefix is
  shared.
- **Persistence.** A warm state in RAM is lost on reload. A disk warm-start file
  under a fixed id, restored on load, would survive restarts (needs either the
  body-`session_id` (OpenCode plugin) or a server "seed from file" feature).
- **Cost.** One warm prefill (~20 min once) versus many cold ones.

## Acceptance criteria

- After the model is loaded and warmed, a fresh OpenCode session's first request
  reports a large `cache_n` (the base prefix) and a small `prompt_n`.
- A sub-agent's first request reuses at least the shared part.
- The warm step is bounded and does not block serving beyond the one prefill.

## References

- [../opencode-session-id-forwarding/done.md](../opencode-session-id-forwarding/done.md)
  — the session id now reaches llama-server.
- [../llm-session-cache-persistence/done.md](../llm-session-cache-persistence/done.md)
  — the disk session store and `--cache-ram`.
- `hosts/oams/devenv.nix` — the per-agent prompts and models.
- `hosts/brys/llm.nix` — `qwenCacheRam`, `sessionHeaders`, checkpoints.
