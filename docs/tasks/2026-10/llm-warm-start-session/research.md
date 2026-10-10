---
type: Research
description: Warm-start feasibility — the mechanism works (a fresh session on a warm slot reuses the base prefix), but session-keyed requests bypass LCP slot selection, so all slots must be warmed.
task: definition.md
authored_by: agent
timestamp: 2026-10-10T14:10:00+02:00
---

# Warm-start: feasibility and the session-isolation constraint

Measured on brys, `llms-frontier`, the `llama-cpp-sessions` build.

## The base prompt is ~12K tokens

Captured one real OpenCode request (a mock upstream logs the body): a
**20,103-character system message + 10 tool schemas**. Templated by
llama-server that is **12,087 tokens** — so a cold start prefills ~12K tokens at
~29 tok/s, about **7 minutes** before the first generated token.

## The mechanism works

Warm the base into a slot, then a fresh session that lands on that slot reuses
it:

| Request | session id | result |
|---|---|---|
| warm (prefill base) | `warmstart` | `prompt_n 12087, cache_n 0` |
| fresh pinned to the warm slot | `freshpin`, `id_slot 1` | `prompt_n 16, cache_n 12075` |
| restore the saved base into a slot | `warmstart`, `id_slot 1` | `prompt_n 4, cache_n 12087` |

So a fresh session reuses the whole base when it runs on a slot that already
holds the base, and a saved base file restores into a slot in ~150 ms (no
re-prefill).

## The constraint: session-keyed requests skip LCP selection

In the fork, `get_available_slot` (`server-context.cpp:2021`) handles a request
with a session id **before** the prompt-similarity path:

```cpp
// session-tagged requests: the slot is chosen by session identity, not by prompt similarity
if (!task.session_id.empty() && (COMPLETION || INFILL)) {
    ... return &slot;   // or pick_idle_slot + restore/stamp, then return
}
// prompt-similarity (LCP) selection only runs when session_id is empty
```

Consequences:

- A session-keyed request either finds **its own** session's slot, or takes an
  idle victim (`pick_idle_slot`, LRU) and restores **its own** file / starts
  fresh. It never consults the RAM prompt cache and never does LCP slot
  selection.
- A fresh session (new id) therefore does **not** find the warm slot by prefix.
  It lands on the LRU victim. It reuses the base only if that victim already
  holds the base prefix (the completion's own prefix match inside the slot).

This is why the naive "warm one session, everything reuses it" does not happen:
the OpenCode plugin sends `x-session-id`, so every request is session-keyed.

## Design that works

Warm **all** slots with the base, so whatever LRU victim a fresh session takes
is warm:

1. Prefill the base once under a fixed id; the server saves it to
   `llama-session-warmstart.bin` (eviction/shutdown).
2. On model load, restore the base into every slot: copy the file to
   `llama-session-warm<N>.bin` and send one request per slot
   (`session_id: warm<N>`, `id_slot: N`). Each restore is ~150 ms.
3. It self-sustains: every session's tokens start with the base prefix, so once
   the warm slots are replaced by real sessions, the LRU victim still holds the
   base prefix and a fresh session reuses it.

Cost: one base prefill (~7 min) at setup, then 4 restores (~1 s) per model load.

## Open questions

- **Capture.** The base prompt is repo- and agent-specific (system prompt +
  tools + `AGENTS.md`). The capture used a mock upstream that logs the request
  body; a production flow needs a stable capture (a saved request body, or the
  server's prompt logging).
- **Per-agent.** Each OpenCode agent has its own prompt; a single warm base
  covers only the shared part. The sub-agents share the tool schemas and most of
  the system prompt.
- **Trigger.** A systemd oneshot after `llama-cpp` that restores the base into
  all slots. With `--models-max 1`, warm only the resident model.
- **Cost vs. benefit.** ~7 min once, then fresh sessions start warm. Without it,
  the first session of the day pays ~7 min and later sessions reuse the base
  from the slot/prompt cache.
