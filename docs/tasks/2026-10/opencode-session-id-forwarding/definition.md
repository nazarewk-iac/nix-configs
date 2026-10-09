---
type: Task
description: OpenCode sends x-session-id but llama-server never sees it, so every turn re-prefills; the compat-proxy drops the header on the streaming path and the plugin read the wrong provider field.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-10T10:30:00+02:00
---

# Forward x-session-id end to end

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

The Qwen disk session cache depends on the request carrying a session id, so
llama-server can save/restore the conversation's KV state. After the cache was
deployed (2026-10-09), the `ee324` session still re-prefilled every turn, and
`GET /slots` showed `session_id: ""` for every busy slot.

Two independent defects:

1. The generated OpenCode plugin read `input.provider.info.id`, which is
   `undefined`, so the `chat.headers` hook threw
   (`undefined is not an object (evaluating 'input.provider.info.id')`). The
   provider id is `input.model.providerID`.
2. The compat-proxy's **streaming** path built a fresh header set and forwarded
   only `Authorization`, dropping every other client header including
   `x-session-id`. The non-streaming path forwards all headers.

## References

- `modules/den/aspects/llm-client.nix`, `modules/slots/llm/client/default.nix`
  — the generated plugin.
- `~/dev/github.com/nazarewk-iac/opencode_compat_proxy` (`proxy.py`) — the
  streaming header set.
- [research.md](research.md) — the full diagnosis and the reproduction.
