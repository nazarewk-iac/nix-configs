---
type: Task
description: Give llama-server a disk-backed, session-keyed prompt-cache store, so 10-20+ local LLM sessions survive a server restart and resume without a full re-prefill.
status: open
authored_by: agent
timestamp: 2026-10-09T21:15:00+02:00
---

# Persist llama-server session KV caches to disk

## Context

The Qwen prompt cache is RAM only. `--cache-ram` sizes the in-memory
`server_prompt_cache`; a restart, a model reload, or an eviction drops every
entry. A long session on `qwen3.8-flash-next` holds a prompt-cache entry of
about **5.7 GiB** (see
[../llm-prompt-cache-ram/done.md](../llm-prompt-cache-ram/done.md)), and a cold
re-prefill of that context costs tens of seconds.

The upstream `llama-server` has a manual disk primitive:
`--slot-save-path` plus `POST /slots/{id_slot}?action=save|restore`. A client
must call it. There is no automatic save and no session key.

Upstream is moving to exactly the wanted behaviour. Issue
[ggml-org/llama.cpp#29678](https://github.com/ggml-org/llama.cpp/issues/29678)
asks for automatic save/restore keyed by a client session id. PR
[#29738](https://github.com/ggml-org/llama.cpp/pull/29738) implements it and is
**open** as of 2026-10-09.

## Goal

Keep 10-20+ named sessions of KV state on disk, so a continuation reuses the
saved prefix and a server restart does not throw the sessions away.

## Proposed approach (not decided)

1. **Measure** the real save-file size per session on `llm-qwen`, with and
   without context checkpoints.
2. **Pick the mechanism**:
   - a manual CLI wrapper over `/slots` on the pinned build (works today, no
     checkpoint reuse), or
   - a `master`-based llama.cpp build that carries checkpoint persistence
     ([#26004](https://github.com/ggml-org/llama.cpp/pull/26004)) plus PR
     #29738 applied as a patch (the repo already carries open-PR patches), or
   - wait for #29738 to merge, then bump the pin.
3. **Wire the slot** with `slot-save-path` and the session flag, and add a
   storage directory under the persistent `usr/data` dataset.
4. **Drive it from OpenCode** with a session id header, if OpenCode can supply
   one per conversation (a plugin can inject headers; see the research).

## Acceptance criteria

- The chosen build starts with the session store enabled and no router error.
- A session survives a `llama-server` restart: the second request reports a
  cache hit (`timings.cache_n`) and does not re-prefill the full prompt.
- At least 10 sessions coexist on disk; the oldest are removed past the cap.
- Disk use stays inside the budget for the `usr/data` dataset.
- No prompt or KV data leaves the host; the save directory is not
  world-readable.

## References

- [research.md](research.md) — full findings: mechanism, file format, size,
  upstream status, integration options, open questions.
- `modules/slots/llm/default.nix`, `modules/den/aspects/llm.nix` — the slot and
  aspect that would carry the new options.
- `hosts/brys/llm.nix`, `hosts/brys/llm-qwen.nix` — the Qwen wiring.
- [docs/local-llms.md](../../../local-llms.md) — RAM levers and the prompt
  cache.
